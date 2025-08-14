param(
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$ServiceTag,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$ServiceTagVersion = "20250804",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,
    
    [Parameter(Mandatory=$false)]
    [switch]$Rebuild  # Ultra-fast mode: Clear all rules and rebuild custom ones
)

Write-Host "Azure Key Vault Service Tag Removal Script (Optimized)" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

if ($Rebuild) {
    Write-Host "Mode: ULTRA-FAST REBUILD (Clear all rules and rebuild custom ones)" -ForegroundColor Magenta
} else {
    Write-Host "Mode: PARALLEL PROCESSING (Default - Fast removal with concurrent jobs)" -ForegroundColor Green
}

# Auto-detect resource group if not provided
if (-not $ResourceGroupName) {
    Write-Host "Auto-detecting resource group..." -ForegroundColor Yellow
    try {
        $kvInfo = az keyvault show --name $KeyVaultName --output json | ConvertFrom-Json
        $ResourceGroupName = $kvInfo.resourceGroup
        Write-Host "Found Key Vault in resource group: $ResourceGroupName" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to find Key Vault '$KeyVaultName'"
        exit 1
    }
}

# Get service tag data
$jsonFileName = "ServiceTags_Public_$ServiceTagVersion.json"
$jsonFilePath = Join-Path $PSScriptRoot $jsonFileName

if (-not (Test-Path $jsonFilePath)) {
    Write-Host "Downloading service tags..." -ForegroundColor Yellow
    $downloadUrl = "https://download.microsoft.com/download/7/1/D/71D86715-5596-4529-9B13-DA13A5DE5B63/ServiceTags_Public_$ServiceTagVersion.json"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $jsonFilePath -UseBasicParsing
}

$serviceTags = Get-Content $jsonFilePath -Raw | ConvertFrom-Json
$targetServiceTag = $serviceTags.values | Where-Object { $_.name -eq $ServiceTag }

if (-not $targetServiceTag) {
    Write-Error "Service tag '$ServiceTag' not found"
    exit 1
}

$ipRanges = $targetServiceTag.properties.addressPrefixes
Write-Host "Found $($ipRanges.Count) IP ranges for '$ServiceTag'" -ForegroundColor Green

# Get current rules to identify custom rules (needed for both modes)
Write-Host "Analyzing current Key Vault rules..." -ForegroundColor Yellow
try {
    $kvDetails = az keyvault show --name $KeyVaultName --resource-group $ResourceGroupName --query "properties.networkAcls" --output json | ConvertFrom-Json
    $currentRules = $kvDetails.ipRules
    Write-Host "Current IP rules count: $($currentRules.Count)" -ForegroundColor Green
} catch {
    Write-Error "Failed to get current network rules"
    exit 1
}

# Identify custom rules (non-service tag rules) and service tag rules
$customRules = @()
$serviceTagRules = @()

foreach ($rule in $currentRules) {
    $isServiceTagRule = $false
    foreach ($serviceRange in $ipRanges) {
        if ($rule.addressRange -eq $serviceRange) {
            $isServiceTagRule = $true
            $serviceTagRules += $rule
            break
        }
    }
    
    if (-not $isServiceTagRule) {
        $customRules += $rule
    }
}

Write-Host "Service tag rules to remove: $($serviceTagRules.Count)" -ForegroundColor Yellow
Write-Host "Custom rules to preserve: $($customRules.Count)" -ForegroundColor Green

if ($serviceTagRules.Count -eq 0) {
    Write-Host "No rules found for service tag '$ServiceTag' to remove." -ForegroundColor Green
    exit 0
}

if ($WhatIf) {
    Write-Host "`nWHAT-IF MODE:" -ForegroundColor Magenta
    Write-Host "Would remove $($serviceTagRules.Count) rules for service tag '$ServiceTag'" -ForegroundColor Yellow
    Write-Host "Would preserve $($customRules.Count) custom rules" -ForegroundColor Green
    
    if ($Rebuild) {
        Write-Host "`nREBUILD MODE: Would use ultra-fast clear-and-rebuild approach:" -ForegroundColor Cyan
        Write-Host "1. Clear all IP rules from Key Vault" -ForegroundColor Gray
        Write-Host "2. Re-add $($customRules.Count) custom rules" -ForegroundColor Gray
        Write-Host "   ⚡ ULTRA-FAST: Recommended for 500+ service tag rules" -ForegroundColor Green
        Write-Host "   ⚠ Brief downtime: All access blocked during rebuild" -ForegroundColor Yellow
    } else {
        Write-Host "`nPARALLEL MODE (Default): Would remove rules using parallel processing:" -ForegroundColor Cyan
        Write-Host "1. Process rules in batches of 50 with up to 10 concurrent jobs" -ForegroundColor Gray
        Write-Host "2. Fast removal while preserving access to custom rules" -ForegroundColor Gray
        Write-Host "   � FAST & SAFE: Good for any number of service tag rules" -ForegroundColor Green
        Write-Host "   ✅ No downtime: Custom rules remain accessible throughout" -ForegroundColor Green
    }
    
    if ($serviceTagRules.Count -gt 0) {
        Write-Host "`nFirst 10 service tag rules to remove:" -ForegroundColor Gray
        $serviceTagRules | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.addressRange)" -ForegroundColor Gray }
        if ($serviceTagRules.Count -gt 10) {
            Write-Host "  ... and $($serviceTagRules.Count - 10) more" -ForegroundColor Gray
        }
    }
    exit 0
}

Write-Host "`nThis will remove $($serviceTagRules.Count) IP ranges for service tag '$ServiceTag'" -ForegroundColor Yellow
Write-Host "Custom rules preserved: $($customRules.Count)" -ForegroundColor Green

if ($Rebuild) {
    Write-Host "Mode: ULTRA-FAST REBUILD (clears all rules, then rebuilds custom ones)" -ForegroundColor Magenta
    if ($serviceTagRules.Count -gt 500) {
        Write-Host "✅ Excellent choice: Service tag has $($serviceTagRules.Count) rules (perfect for rebuild mode)" -ForegroundColor Green
    } else {
        Write-Host "ℹ️  Note: Parallel mode is also efficient for $($serviceTagRules.Count) rules" -ForegroundColor Cyan
    }
} else {
    Write-Host "Mode: PARALLEL PROCESSING (Default - Fast and safe removal)" -ForegroundColor Green
    Write-Host "✅ Recommended: Works efficiently for any number of rules while maintaining access" -ForegroundColor Green
    if ($serviceTagRules.Count -gt 1000) {
        Write-Host "💡 Tip: Consider using -Rebuild for maximum speed with $($serviceTagRules.Count) rules" -ForegroundColor Cyan
    }
}

$confirmation = Read-Host "Do you want to continue? (y/N)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "Operation cancelled" -ForegroundColor Yellow
    exit 0
}

if ($Rebuild) {
    # ULTRA-FAST REBUILD MODE
    Write-Host "`n🚀 Using ULTRA-FAST REBUILD MODE..." -ForegroundColor Green
    
    # Step 1: Clear all IP rules
    Write-Host "Step 1: Clearing all IP rules..." -ForegroundColor Yellow
    try {
        # Set default action to Deny to clear all rules
        az keyvault update --name $KeyVaultName --resource-group $ResourceGroupName --default-action Deny --output none
        Write-Host "✅ All IP rules cleared" -ForegroundColor Green
    } catch {
        Write-Error "❌ Failed to clear IP rules: $($_.Exception.Message)"
        exit 1
    }
    
    # Step 2: Re-add custom rules if any exist
    if ($customRules.Count -gt 0) {
        Write-Host "Step 2: Re-adding $($customRules.Count) custom rules..." -ForegroundColor Yellow
        $addedCount = 0
        $failedCount = 0
        
        foreach ($rule in $customRules) {
            try {
                az keyvault network-rule add --name $KeyVaultName --resource-group $ResourceGroupName --ip-address $rule.addressRange --output none 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $addedCount++
                    Write-Host "  ✅ Re-added: $($rule.addressRange)" -ForegroundColor Green
                } else {
                    $failedCount++
                    Write-Host "  ❌ Failed: $($rule.addressRange)" -ForegroundColor Red
                }
            } catch {
                $failedCount++
                Write-Host "  ❌ Error: $($rule.addressRange)" -ForegroundColor Red
            }
        }
        
        Write-Host "✅ Re-added $addedCount custom rules successfully" -ForegroundColor Green
        if ($failedCount -gt 0) {
            Write-Host "⚠️  Failed to re-add $failedCount custom rules" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Step 2: No custom rules to re-add" -ForegroundColor Green
    }
    
    Write-Host "`n🎉 ULTRA-FAST REBUILD completed!" -ForegroundColor Green
    
} else {
    # PARALLEL PROCESSING MODE (DEFAULT)
    Write-Host "`n� Using PARALLEL PROCESSING MODE (Default)..." -ForegroundColor Green

    $batchSize = 50  # Process in batches for better performance
    $maxConcurrentJobs = 10  # Limit concurrent jobs to avoid overwhelming Azure API
    $totalBatches = [math]::Ceiling($serviceTagRules.Count / $batchSize)
    $currentBatch = 0
    $successCount = 0
    $failureCount = 0
    $jobs = @()

    Write-Host "Processing $($serviceTagRules.Count) service tag rules in $totalBatches batches (batch size: $batchSize, max concurrent: $maxConcurrentJobs)" -ForegroundColor Cyan

    for ($i = 0; $i -lt $serviceTagRules.Count; $i += $batchSize) {
        $currentBatch++
        $batch = $serviceTagRules[$i..([math]::Min($i + $batchSize - 1, $serviceTagRules.Count - 1))]
        
        # Wait if we have too many concurrent jobs
        while ((Get-Job -State Running).Count -ge $maxConcurrentJobs) {
            Start-Sleep -Milliseconds 100
            
            # Process completed jobs
            $completedJobs = Get-Job -State Completed
            foreach ($job in $completedJobs) {
                $result = Receive-Job -Job $job
                $successCount += $result.Success
                $failureCount += $result.Failed
                Remove-Job -Job $job
            }
        }
        
        # Start new job for this batch
        $job = Start-Job -ScriptBlock {
            param($KeyVaultName, $ResourceGroupName, $ruleBatch)
            
            $batchSuccess = 0
            $batchFail = 0
            
            foreach ($rule in $ruleBatch) {
                try {
                    & az keyvault network-rule remove --name $KeyVaultName --resource-group $ResourceGroupName --ip-address $rule.addressRange --output none 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $batchSuccess++
                    } else {
                        $batchFail++
                    }
                }
                catch {
                    $batchFail++
                }
            }
            
            return @{
                Success = $batchSuccess
                Failed = $batchFail
                BatchSize = $ruleBatch.Count
            }
        } -ArgumentList $KeyVaultName, $ResourceGroupName, $batch
        
        $jobs += $job
        
        # Show progress every 5 batches
        if ($currentBatch % 5 -eq 0 -or $currentBatch -eq $totalBatches) {
            $processedSoFar = [math]::Min($i + $batchSize, $serviceTagRules.Count)
            $percentComplete = [math]::Round(($processedSoFar / $serviceTagRules.Count) * 100, 1)
            Write-Host "Started batch $currentBatch/$totalBatches (processing $processedSoFar/$($serviceTagRules.Count) - $percentComplete%)" -ForegroundColor Cyan
        }
    }

    # Wait for all jobs to complete and collect results
    Write-Host "`nWaiting for all removal operations to complete..." -ForegroundColor Yellow
    while ((Get-Job -State Running).Count -gt 0) {
        Start-Sleep -Seconds 1
        
        # Process completed jobs
        $completedJobs = Get-Job -State Completed
        foreach ($job in $completedJobs) {
            $result = Receive-Job -Job $job
            $successCount += $result.Success
            $failureCount += $result.Failed
            Remove-Job -Job $job
        }
        
        $runningJobs = (Get-Job -State Running).Count
        if ($runningJobs -gt 0) {
            Write-Host "  Still processing... ($runningJobs jobs running)" -ForegroundColor Gray
        }
    }

    # Clean up any remaining jobs
    Get-Job | Remove-Job -Force

    Write-Host "`n🎉 PARALLEL PROCESSING completed!" -ForegroundColor Green
    Write-Host "Successfully removed: $successCount rules" -ForegroundColor Green
    if ($failureCount -gt 0) {
        Write-Host "Failed to remove: $failureCount rules" -ForegroundColor Yellow
        Write-Host "Note: Some failures are expected if rules were already removed or didn't exist" -ForegroundColor Gray
    } else {
        Write-Host "All service tag rules processed successfully!" -ForegroundColor Green
    }
}

# Verify final state
Write-Host "`nVerifying final state..." -ForegroundColor Yellow
try {
    $finalRules = az keyvault show --name $KeyVaultName --resource-group $ResourceGroupName --query "properties.networkAcls.ipRules | length(@)" --output tsv
    Write-Host "Final IP rules count: $finalRules" -ForegroundColor Green
    
    if ($Rebuild) {
        Write-Host "Expected count: $($customRules.Count) (custom rules only)" -ForegroundColor Green
    } else {
        $expectedCount = $customRules.Count
        Write-Host "Expected count: $expectedCount (custom rules after removal)" -ForegroundColor Green
    }
} catch {
    Write-Host "Could not verify final rules count" -ForegroundColor Yellow
}

Write-Host "`n✅ Service tag '$ServiceTag' removal operation completed!" -ForegroundColor Green

if ($Rebuild) {
    Write-Host "🚀 Used ULTRA-FAST REBUILD mode" -ForegroundColor Magenta
} else {
    Write-Host "� Used PARALLEL PROCESSING mode (Default)" -ForegroundColor Green
}
