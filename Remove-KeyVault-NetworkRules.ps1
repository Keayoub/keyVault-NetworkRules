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

Write-Host "Azure Key Vault Service Tag Removal Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

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

# Get current rules
$currentRules = az keyvault network-rule list --name $KeyVaultName --resource-group $ResourceGroupName --output json | ConvertFrom-Json

$existingServiceTagRules = @()
$existingCustomRules = @()

foreach ($rule in $currentRules.ipRules) {
    if ($rule.addressRange -in $ipRanges) {
        $existingServiceTagRules += $rule
    } else {
        $existingCustomRules += $rule
    }
}

Write-Host "Service tag rules to remove: $($existingServiceTagRules.Count)" -ForegroundColor Yellow
Write-Host "Custom rules to preserve: $($existingCustomRules.Count)" -ForegroundColor Green

if ($existingServiceTagRules.Count -eq 0) {
    Write-Host "No rules found for service tag '$ServiceTag' to remove." -ForegroundColor Green
    exit 0
}

if ($WhatIf) {
    Write-Host "`nWHAT-IF MODE:" -ForegroundColor Magenta
    Write-Host "Would remove $($existingServiceTagRules.Count) rules for '$ServiceTag'" -ForegroundColor Red
    Write-Host "Would preserve $($existingCustomRules.Count) custom rules" -ForegroundColor Green
    exit 0
}

$confirmation = Read-Host "Remove $($existingServiceTagRules.Count) rules for '$ServiceTag'? (y/N)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "Operation cancelled" -ForegroundColor Yellow
    exit 0
}

# Remove rules
Write-Host "Removing rules..." -ForegroundColor Yellow
$removeCount = 0

foreach ($rule in $existingServiceTagRules) {
    try {
        az keyvault network-rule remove --name $KeyVaultName --resource-group $ResourceGroupName --ip-address $rule.addressRange --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            $removeCount++
        }
    }
    catch {
        # Ignore errors
    }
}

Write-Host "Successfully removed: $removeCount rules" -ForegroundColor Green
Write-Host "Service tag removal completed!" -ForegroundColor Green
