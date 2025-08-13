# Azure Key Vault Network Rules Update Script
# This script downloads Azure service tags and updates Key Vault firewall rules

param(
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$ServiceTag,
    
    [Parameter(Mandatory=$false)]
    [string]$ServiceTagVersion = "20250804",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

Write-Host "Azure Key Vault Network Rules Update Script" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green

# Define the base filename and URL pattern
$baseFileName = "ServiceTags_Public_$ServiceTagVersion.json"
$jsonFilePath = Join-Path $PSScriptRoot $baseFileName
$jsonUrl = "https://download.microsoft.com/download/7/1/d/71d86715-5596-4529-9b13-da13a5de5b63/$baseFileName"

# Download the latest JSON file only if it does not exist
Write-Host "Checking for Azure Service Tags file..." -ForegroundColor Yellow
if (-not (Test-Path $jsonFilePath)) {
    Write-Host "Downloading Azure Service Tags file: $baseFileName" -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $jsonUrl -OutFile $jsonFilePath
        Write-Host "Downloaded successfully!" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download service tags file: $($_.Exception.Message)"
        exit 1
    }
}
else {
    Write-Host "Service Tags file already exists: $jsonFilePath" -ForegroundColor Green
}

# Parse for the specified service tag
$serviceTags = Get-Content $jsonFilePath | ConvertFrom-Json

Write-Host "Looking for service tag: $ServiceTag" -ForegroundColor Yellow

$ipRanges = $serviceTags.values |
            Where-Object { $_.name -eq $ServiceTag } |
            Select-Object -ExpandProperty properties |
            Select-Object -ExpandProperty addressPrefixes |
            Select-Object -Unique

if (-not $ipRanges) {
    Write-Error "No IP ranges found for service tag: $ServiceTag"
    Write-Host "Available service tags (showing first 20):" -ForegroundColor Yellow
    $serviceTags.values | Select-Object -ExpandProperty name | Sort-Object | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    Write-Host "  ..." -ForegroundColor Gray
    Write-Host "Total available tags: $($serviceTags.values.Count)" -ForegroundColor Gray
    Write-Host "`nCommon examples:" -ForegroundColor Yellow
    @("AzureCloud.WestEurope", "AzureCloud.EastUS", "Storage.WestEurope", "Sql.WestEurope", "AzureActiveDirectory") | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    exit 1
}

Write-Host "Found $($ipRanges.Count) IP ranges for service tag: $ServiceTag" -ForegroundColor Green

# Validate region compatibility for regional service tags
if ($ServiceTag -match '^(.+)\.(.+)$') {
    $servicePattern = $Matches[1]
    $serviceTagRegion = $Matches[2]
    
    Write-Host "Detected regional service tag - validating region compatibility..." -ForegroundColor Yellow
    Write-Host "Service: $servicePattern, Tag Region: $serviceTagRegion" -ForegroundColor Gray
    
    # Get Key Vault information for region validation
    Write-Host "Getting Key Vault region information..." -ForegroundColor Yellow
    try {
        if ($ResourceGroupName) {
            $kvInfo = az keyvault show --name $KeyVaultName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
        } else {
            $kvInfo = az keyvault show --name $KeyVaultName --output json | ConvertFrom-Json
            if ($kvInfo) {
                $ResourceGroupName = $kvInfo.resourceGroup
            }
        }
        
        if (-not $kvInfo) {
            throw "Key Vault not found"
        }
        
        Write-Host "Key Vault found: $($kvInfo.name)" -ForegroundColor Green
        Write-Host "Key Vault location: $($kvInfo.location)" -ForegroundColor Green
        
        # Convert Key Vault location to service tag format for comparison
        $kvRegionForTag = switch ($kvInfo.location.ToLower()) {
            "westeurope" { "WestEurope" }
            "eastus" { "EastUS" }
            "eastus2" { "EastUS2" }
            "westus" { "WestUS" }
            "westus2" { "WestUS2" }
            "westus3" { "WestUS3" }
            "centralus" { "CentralUS" }
            "northeurope" { "NorthEurope" }
            "southeastasia" { "SoutheastAsia" }
            "eastasia" { "EastAsia" }
            "australiaeast" { "AustraliaEast" }
            "australiasoutheast" { "AustraliaSoutheast" }
            "brazilsouth" { "BrazilSouth" }
            "canadacentral" { "CanadaCentral" }
            "canadaeast" { "CanadaEast" }
            "chinaeast" { "ChinaEast" }
            "chinanorth" { "ChinaNorth" }
            "francecentral" { "FranceCentral" }
            "germanywestcentral" { "GermanyWestCentral" }
            "japaneast" { "JapanEast" }
            "japanwest" { "JapanWest" }
            "koreacentral" { "KoreaCentral" }
            "koreasouth" { "KoreaSouth" }
            "southafricanorth" { "SouthAfricaNorth" }
            "southcentralus" { "SouthCentralUS" }
            "northcentralus" { "NorthCentralUS" }
            "ukwest" { "UKWest" }
            "uksouth" { "UKSouth" }
            "westcentralus" { "WestCentralUS" }
            default { 
                # Attempt to convert to title case as fallback
                (Get-Culture).TextInfo.ToTitleCase($kvInfo.location.ToLower()) -replace '\s', ''
            }
        }
        
        Write-Host "Key Vault region (for service tags): $kvRegionForTag" -ForegroundColor Green
        
        # Check if regions match
        if ($serviceTagRegion -ne $kvRegionForTag) {
            Write-Error "REGION MISMATCH: Cannot add service tag from different region!"
            Write-Host "Key Vault region: $kvRegionForTag (location: $($kvInfo.location))" -ForegroundColor Red
            Write-Host "Service tag region: $serviceTagRegion" -ForegroundColor Red
            Write-Host "`nAzure Key Vault network rules do not allow cross-region IP ranges." -ForegroundColor Yellow
            Write-Host "Suggested alternatives:" -ForegroundColor Yellow
            Write-Host "  $servicePattern.$kvRegionForTag" -ForegroundColor Cyan
            
            # Check if the suggested alternative exists
            $suggestedTag = "$servicePattern.$kvRegionForTag"
            $suggestedExists = $serviceTags.values | Where-Object { $_.name -eq $suggestedTag }
            if ($suggestedExists) {
                Write-Host "`nThe suggested service tag '$suggestedTag' is available!" -ForegroundColor Green
                Write-Host "Run the script with: -ServiceTag '$suggestedTag'" -ForegroundColor Cyan
            } else {
                Write-Host "`nAlternative service tags for your region ($kvRegionForTag):" -ForegroundColor Yellow
                $regionalTags = $serviceTags.values | Where-Object { $_.name -like "*.$kvRegionForTag" } | Select-Object -ExpandProperty name | Sort-Object
                if ($regionalTags) {
                    $regionalTags | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
                } else {
                    Write-Host "  No regional service tags found for $kvRegionForTag" -ForegroundColor Red
                }
            }
            exit 1
        } else {
            Write-Host "✓ Region validation passed: Service tag region matches Key Vault region" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to validate region compatibility: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "Global service tag detected - no region validation needed" -ForegroundColor Green
    # Still get Key Vault info for later use
    try {
        if ($ResourceGroupName) {
            $kvInfo = az keyvault show --name $KeyVaultName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
        } else {
            $kvInfo = az keyvault show --name $KeyVaultName --output json | ConvertFrom-Json
            if ($kvInfo) {
                $ResourceGroupName = $kvInfo.resourceGroup
            }
        }
        
        if (-not $kvInfo) {
            throw "Key Vault not found"
        }
        
        Write-Host "Key Vault found: $($kvInfo.name)" -ForegroundColor Green
        Write-Host "Resource Group: $($kvInfo.resourceGroup)" -ForegroundColor Green
        Write-Host "Location: $($kvInfo.location)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to find Key Vault '$KeyVaultName': $($_.Exception.Message)"
        exit 1
    }
}

# Check if Azure CLI is available
Write-Host "Checking Azure CLI availability..." -ForegroundColor Yellow
try {
    $azVersion = az version --output tsv 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Azure CLI is available" -ForegroundColor Green
    }
    else {
        throw "Azure CLI not found"
    }
}
catch {
    Write-Error "Azure CLI is not installed or not available in PATH"
    Write-Host "Please install Azure CLI from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" -ForegroundColor Yellow
    exit 1
}

# Check if user is logged in to Azure
Write-Host "Checking Azure login status..." -ForegroundColor Yellow
try {
    $accountInfo = az account show --output json 2>$null | ConvertFrom-Json
    if ($accountInfo) {
        Write-Host "Logged in as: $($accountInfo.user.name)" -ForegroundColor Green
        Write-Host "Subscription: $($accountInfo.name) ($($accountInfo.id))" -ForegroundColor Green
    }
    else {
        throw "Not logged in"
    }
}
catch {
    Write-Error "Not logged in to Azure. Please run 'az login' first."
    exit 1
}

# Get current network rules (Key Vault info already retrieved during region validation)
Write-Host "Getting current Key Vault network rules..." -ForegroundColor Yellow
try {
    $currentRules = az keyvault network-rule list --name $KeyVaultName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    Write-Host "Current IP rules count: $($currentRules.ipRules.Count)" -ForegroundColor Green
    Write-Host "Current virtual network rules count: $($currentRules.virtualNetworkRules.Count)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to get current network rules: $($_.Exception.Message)"
    exit 1
}

# Identify existing custom IP rules (non-Azure ranges) to preserve
$existingCustomRules = @()
$existingAzureRules = @()

if ($currentRules.ipRules.Count -gt 0) {
    Write-Host "Analyzing existing IP rules..." -ForegroundColor Yellow
    
    foreach ($rule in $currentRules.ipRules) {
        $isAzureRange = $false
        
        # Check if this rule matches any of the new Azure ranges
        foreach ($azureRange in $ipRanges) {
            if ($rule.addressRange -eq $azureRange) {
                $isAzureRange = $true
                break
            }
        }
        
        if ($isAzureRange) {
            $existingAzureRules += $rule
            Write-Host "Found existing Azure range: $($rule.addressRange)" -ForegroundColor Gray
        }
        else {
            $existingCustomRules += $rule
            Write-Host "Found custom IP rule to preserve: $($rule.addressRange)" -ForegroundColor Green
        }
    }
    
    Write-Host "Custom rules to preserve: $($existingCustomRules.Count)" -ForegroundColor Green
    Write-Host "Existing Azure rules: $($existingAzureRules.Count)" -ForegroundColor Yellow
}

if ($WhatIf) {
    Write-Host "`nWHAT-IF MODE: The following changes would be made:" -ForegroundColor Cyan
    Write-Host "- Existing custom IP rules will be PRESERVED" -ForegroundColor Green
    Write-Host "- Service tag '$ServiceTag' ranges will be updated/replaced" -ForegroundColor Yellow
    Write-Host "- $($ipRanges.Count) IP ranges from '$ServiceTag' will be added/updated" -ForegroundColor Cyan
    
    if ($existingCustomRules.Count -gt 0) {
        Write-Host "`nCustom IP rules that will be preserved:" -ForegroundColor Green
        $existingCustomRules | ForEach-Object { Write-Host "  $($_.addressRange)" -ForegroundColor Green }
    }
    
    Write-Host "`nFirst 10 IP ranges from '$ServiceTag' that would be added:" -ForegroundColor Cyan
    $ipRanges | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    if ($ipRanges.Count -gt 10) {
        Write-Host "  ... and $($ipRanges.Count - 10) more" -ForegroundColor Cyan
    }
    Write-Host "`nTo apply these changes, run the script without the -WhatIf parameter" -ForegroundColor Yellow
    exit 0
}

# Confirm before making changes
Write-Host "`nThis will add/update $($ipRanges.Count) IP ranges from service tag: $ServiceTag" -ForegroundColor Yellow
if ($existingCustomRules.Count -gt 0) {
    Write-Host "Your $($existingCustomRules.Count) custom IP rule(s) will be PRESERVED." -ForegroundColor Green
}
if ($existingAzureRules.Count -gt 0) {
    Write-Host "Existing $($existingAzureRules.Count) rule(s) from '$ServiceTag' will be updated." -ForegroundColor Yellow
}
$confirmation = Read-Host "Do you want to continue? (y/N)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "Operation cancelled" -ForegroundColor Yellow
    exit 0
}

# Remove only existing service tag IP rules (preserve custom rules)
if ($existingAzureRules.Count -gt 0) {
    Write-Host "Removing outdated '$ServiceTag' IP rules..." -ForegroundColor Yellow
    $removeCount = 0
    $removeFailed = 0
    
    foreach ($rule in $existingAzureRules) {
        try {
            $result = az keyvault network-rule remove --name $KeyVaultName --resource-group $ResourceGroupName --ip-address $rule.addressRange --output none 2>$null
            if ($LASTEXITCODE -eq 0) {
                $removeCount++
            } else {
                $removeFailed++
            }
        }
        catch {
            $removeFailed++
        }
    }
    
    Write-Host "Removed $removeCount rules successfully" -ForegroundColor Green
    if ($removeFailed -gt 0) {
        Write-Host "Failed to remove $removeFailed rules" -ForegroundColor Yellow
    }
}
else {
    Write-Host "No existing '$ServiceTag' rules to remove" -ForegroundColor Green
}

# Add new IP rules in optimized batches
Write-Host "Adding new IP rules..." -ForegroundColor Yellow

$batchSize = 100  # Optimized batch size for best performance
$totalBatches = [math]::Ceiling($ipRanges.Count / $batchSize)
$currentBatch = 0
$successCount = 0
$failureCount = 0

Write-Host "Processing $($ipRanges.Count) IP ranges in $totalBatches batches of up to $batchSize rules each..." -ForegroundColor Yellow

for ($i = 0; $i -lt $ipRanges.Count; $i += $batchSize) {
    $currentBatch++
    $batch = $ipRanges[$i..([math]::Min($i + $batchSize - 1, $ipRanges.Count - 1))]
    
    # Process current batch
    foreach ($ipRange in $batch) {
        try {
            $result = az keyvault network-rule add --name $KeyVaultName --resource-group $ResourceGroupName --ip-address $ipRange --output none 2>$null
            if ($LASTEXITCODE -eq 0) {
                $successCount++
            } else {
                $failureCount++
            }
        }
        catch {
            $failureCount++
        }
    }
    
    # Show progress every 5 batches or on completion
    if ($currentBatch % 5 -eq 0 -or $currentBatch -eq $totalBatches) {
        $processedSoFar = [math]::Min($i + $batchSize, $ipRanges.Count)
        $percentComplete = [math]::Round(($processedSoFar / $ipRanges.Count) * 100, 1)
        Write-Host "Processed $processedSoFar/$($ipRanges.Count) ($percentComplete%)" -ForegroundColor Cyan
    }
}

Write-Host "`nBatch processing completed!" -ForegroundColor Green
Write-Host "Successfully added: $successCount rules" -ForegroundColor Green
if ($failureCount -gt 0) {
    Write-Host "Failed to add: $failureCount rules" -ForegroundColor Yellow
}

# Verify the update
Write-Host "Verifying updated network rules..." -ForegroundColor Yellow
try {
    $updatedRules = az keyvault network-rule list --name $KeyVaultName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    Write-Host "Updated IP rules count: $($updatedRules.ipRules.Count)" -ForegroundColor Green
    
    $expectedTotal = $ipRanges.Count + $existingCustomRules.Count
    if ($updatedRules.ipRules.Count -eq $expectedTotal) {
        Write-Host "`nSUCCESS: Key Vault network rules updated successfully!" -ForegroundColor Green
        Write-Host "Total rules: $($updatedRules.ipRules.Count) (Service tag '$ServiceTag': $($ipRanges.Count), Custom: $($existingCustomRules.Count))" -ForegroundColor Green
    }
    else {
        Write-Warning "WARNING: Expected $expectedTotal rules but found $($updatedRules.ipRules.Count)"
        Write-Host "Expected: $($ipRanges.Count) from '$ServiceTag' + $($existingCustomRules.Count) Custom = $expectedTotal" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Failed to verify updated rules: $($_.Exception.Message)"
}

Write-Host "`nKey Vault network rules update completed!" -ForegroundColor Green
