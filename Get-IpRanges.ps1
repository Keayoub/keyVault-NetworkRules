# Define the base filename and URL pattern
$version = "20250804"
$baseFileName = "ServiceTags_Public_$version.json"
$jsonFilePath = Join-Path $PSScriptRoot $baseFileName
$jsonUrl = "https://download.microsoft.com/download/7/1/d/71d86715-5596-4529-9b13-da13a5de5b63/$baseFileName"

# Download the latest JSON file only if it does not exist
if (-not (Test-Path $jsonFilePath)) {
    Invoke-WebRequest -Uri $jsonUrl -OutFile $jsonFilePath
}

# Parse for the region tag
$serviceTags = Get-Content $jsonFilePath | ConvertFrom-Json
$regionTagName = "AzureCloud.WestEurope"  # use the correct regional tag
$ipRanges = $serviceTags.values |
            Where-Object { $_.name -eq $regionTagName } |
            Select-Object -ExpandProperty properties |
            Select-Object -ExpandProperty addressPrefixes |
            Select-Object -Unique

# Output the IP ranges to use them or verify the result
$ipRanges

# You can now use $ipRanges in your Key Vault firewall settings
