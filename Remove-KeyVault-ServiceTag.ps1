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
    [switch]$WhatIf
)

# Script to remove Azure Service Tag IP ranges from Key Vault network rules
# This script preserves custom IP rules and only removes service tag ranges

Write-Host "Azure Key Vault Service Tag Removal Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Validate Azure CLI is available
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI is not installed or not in PATH. Please install Azure CLI and try again."
    exit 1
}

# Check if logged in to Azure
try {
    $null = az account show 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    }
}
catch {
    Write-Error "Failed to check Azure login status. Please run 'az login' first."
    exit 1
}

Write-Host "Checking Azure login status..." -ForegroundColor Yellow
$azAccount = az account show --output json | ConvertFrom-Json
Write-Host "Logged in as: $($azAccount.user.name)" -ForegroundColor Green
Write-Host "Subscription: $($azAccount.name) ($($azAccount.id))" -ForegroundColor Green
Write-Host ""

# Auto-detect resource group if not provided
if (-not $ResourceGroupName) {
    Write-Host "Auto-detecting resource group for Key Vault '$KeyVaultName'..." -ForegroundColor Yellow
    try {
        $kvInfo = az keyvault show --name $KeyVaultName --output json 2>$null | ConvertFrom-Json
        if ($LASTEXITCODE -eq 0) {
            $ResourceGroupName = $kvInfo.resourceGroup
            Write-Host "Found Key Vault in resource group: $ResourceGroupName" -ForegroundColor Green
        } else {
            Write-Error "Key Vault '$KeyVaultName' not found or access denied."
            exit 1
        }
    }
    catch {
        Write-Error "Failed to find Key Vault '$KeyVaultName'. Please check the name or specify -ResourceGroupName."
        exit 1
    }
}

# Validate Key Vault exists and is accessible
Write-Host "Validating Key Vault access..." -ForegroundColor Yellow
try {
    $kvDetails = az keyvault show --name $KeyVaultName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    Write-Host "Key Vault found: $($kvDetails.name)" -ForegroundColor Green
    Write-Host "Location: $($kvDetails.location)" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Error "Cannot access Key Vault '$KeyVaultName' in resource group '$ResourceGroupName'"
    exit 1
}

# Download Azure Service Tags JSON
$serviceTagsUrl = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519"
$jsonFileName = "ServiceTags_Public_$ServiceTagVersion.json"
$jsonFilePath = Join-Path $PSScriptRoot $jsonFileName

Write-Host "Downloading Azure Service Tags (version: $ServiceTagVersion)..." -ForegroundColor Yellow

if (Test-Path $jsonFilePath) {
    Write-Host "Using existing Service Tags file: $jsonFileName" -ForegroundColor Green
} else {
    try {
        # Download the JSON file directly
        $downloadUrl = "https://download.microsoft.com/download/7/1/D/71D86715-5596-4529-9B13-DA13A5DE5B63/ServiceTags_Public_$ServiceTagVersion.json"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $jsonFilePath -UseBasicParsing
        Write-Host "Downloaded: $jsonFileName" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download Service Tags file. Please check your internet connection and try again."
        Write-Host "You can manually download from: $serviceTagsUrl" -ForegroundColor Yellow
        exit 1
    }
}

# Parse the JSON file
Write-Host "Parsing Azure Service Tags..." -ForegroundColor Yellow
try {
    $serviceTags = Get-Content $jsonFilePath -Raw | ConvertFrom-Json
    Write-Host "Service Tags loaded successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to parse Service Tags JSON file"
    exit 1
}

# Find the specified service tag
$targetServiceTag = $serviceTags.values | Where-Object { $_.name -eq $ServiceTag }
if (-not $targetServiceTag) {
    Write-Error "Service tag '$ServiceTag' not found in the downloaded data."
    Write-Host ""
    Write-Host "Available service tags (showing PowerBI examples):" -ForegroundColor Yellow
    $powerBITags = $serviceTags.values | Where-Object { $_.name -like "PowerBI*" } | Select-Object -First 10
    foreach ($tag in $powerBITags) {
        Write-Host "  - $($tag.name)" -ForegroundColor Cyan
    }
    Write-Host "Use the exact service tag name (case-sensitive)" -ForegroundColor Yellow
    exit 1
}

# Extract IP ranges from the service tag
$ipRanges = $targetServiceTag.properties.addressPrefixes
Write-Host "Found $($ipRanges.Count) IP ranges for service tag '$ServiceTag'" -ForegroundColor Green

# Get current Key Vault network rules
Write-Host "Retrieving current Key Vault network rules..." -ForegroundColor Yellow
try {
    $currentRules = az keyvault network-rule list --name $KeyVaultName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    Write-Host "Current IP rules count: $($currentRules.ipRules.Count)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve Key Vault network rules"
    exit 1
}

# Identify which existing rules match the service tag IP ranges
$existingServiceTagRules = @()
$existingCustomRules = @()

foreach ($rule in $currentRules.ipRules) {
    if ($rule.addressRange -in $ipRanges) {
        $existingServiceTagRules += $rule
    } else {
        $existingCustomRules += $rule
    }
}

Write-Host ""
Write-Host "Analysis Results:" -ForegroundColor Cyan
Write-Host "=================" -ForegroundColor Cyan
Write-Host "Service tag '$ServiceTag' rules to remove: $($existingServiceTagRules.Count)" -ForegroundColor Yellow
Write-Host "Custom rules to preserve: $($existingCustomRules.Count)" -ForegroundColor Green
Write-Host "Total current rules: $($currentRules.ipRules.Count)" -ForegroundColor Cyan

if ($existingServiceTagRules.Count -eq 0) {
    Write-Host ""
    Write-Host "No rules found for service tag '$ServiceTag' to remove." -ForegroundColor Green
    Write-Host "The Key Vault already doesn't have any rules from this service tag." -ForegroundColor Green
    exit 0
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "WHAT-IF MODE: The following changes would be made:" -ForegroundColor Magenta
    Write-Host "=================================================" -ForegroundColor Magenta
    Write-Host "Rules to be REMOVED ($($existingServiceTagRules.Count)):" -ForegroundColor Red
    
    $counter = 0
    foreach ($rule in $existingServiceTagRules) {
        $counter++
        Write-Host "  $counter. $($rule.addressRange)" -ForegroundColor Red
        if ($counter -ge 10 -and $existingServiceTagRules.Count -gt 10) {
            Write-Host "  ... and $($existingServiceTagRules.Count - 10) more rules" -ForegroundColor Red
            break
        }
    }
    
    Write-Host ""
    Write-Host "Custom rules to be PRESERVED ($($existingCustomRules.Count)):" -ForegroundColor Green
    foreach ($rule in $existingCustomRules) {
        Write-Host "  ✓ $($rule.addressRange)" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Final result would be: $($existingCustomRules.Count) total rules" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To apply these changes, run the script without -WhatIf" -ForegroundColor Yellow
    exit 0
}

# Confirm before making changes
Write-Host ""
Write-Host "This will remove $($existingServiceTagRules.Count) rules for service tag '$ServiceTag'" -ForegroundColor Yellow
Write-Host "Custom rules ($($existingCustomRules.Count)) will be preserved" -ForegroundColor Green
$confirmation = Read-Host "Do you want to continue? (y/N)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "Operation cancelled" -ForegroundColor Yellow
    exit 0
}

# Remove service tag IP rules
Write-Host ""
Write-Host "Removing '$ServiceTag' IP rules..." -ForegroundColor Yellow

$removeCount = 0
$failedCount = 0
$batchSize = 100
$totalBatches = [Math]::Ceiling($existingServiceTagRules.Count / $batchSize)

for ($i = 0; $i -lt $existingServiceTagRules.Count; $i += $batchSize) {
    $currentBatch = $i / $batchSize + 1
    $batchEnd = [Math]::Min($i + $batchSize - 1, $existingServiceTagRules.Count - 1)
    $batchRules = $existingServiceTagRules[$i..$batchEnd]
    
    foreach ($rule in $batchRules) {
        try {
            $result = az keyvault network-rule remove --name $KeyVaultName --resource-group $ResourceGroupName --ip-address $rule.addressRange --output none 2>$null
            if ($LASTEXITCODE -eq 0) {
                $removeCount++
            } else {
                $failedCount++
            }
        }
        catch {
            $failedCount++
        }
    }
    
    # Show progress every 5 batches or on completion
    if ($currentBatch % 5 -eq 0 -or $currentBatch -eq $totalBatches) {
        $processedSoFar = [Math]::Min($i + $batchSize, $existingServiceTagRules.Count)
        $percentComplete = [Math]::Round(($processedSoFar / $existingServiceTagRules.Count) * 100, 1)
        Write-Host "Processed $processedSoFar/$($existingServiceTagRules.Count) ($percentComplete%)" -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "Removal completed!" -ForegroundColor Green
Write-Host "Successfully removed: $removeCount rules" -ForegroundColor Green
if ($failedCount -gt 0) {
    Write-Host "Failed to remove: $failedCount rules" -ForegroundColor Yellow
}

# Verify the removal
Write-Host ""
Write-Host "Verifying updated network rules..." -ForegroundColor Yellow
try {
    $updatedRules = az keyvault network-rule list --name $KeyVaultName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    Write-Host "Updated IP rules count: $($updatedRules.ipRules.Count)" -ForegroundColor Green
    
    if ($updatedRules.ipRules.Count -eq $existingCustomRules.Count) {
        Write-Host ""
        Write-Host "SUCCESS: Service tag '$ServiceTag' rules removed successfully!" -ForegroundColor Green
        Write-Host "Remaining rules: $($updatedRules.ipRules.Count) (all custom rules preserved)" -ForegroundColor Green
    }
    else {
        Write-Warning "WARNING: Expected $($existingCustomRules.Count) rules but found $($updatedRules.ipRules.Count)"
    }
}
catch {
    Write-Error "Failed to verify updated rules: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Service tag removal completed!" -ForegroundColor Green
