# Az## Files

- `Get-IpRanges.ps1` - Simple script to download and extract Azure IP ranges for a specific region
- `Update-KeyVault-NetworkRules.ps1` - Main script to add Azure service tag IP ranges to Key Vault
- `Remove-KeyVault-NetworkRules-Fast.ps1` - **Optimized removal script with parallel processing and ultra-fast rebuild mode**y Vault Network Rules Management

This repository contains PowerShell scripts to manage Azure Key Vault network access rules using Azure Service Tags.

## Files

- `Get-IpRanges.ps1` - Simple script to download and extract Azure IP ranges for a specific region
- `Update-KeyVault-NetworkRules.ps1` - Main script to add Azure service tag IP ranges to Key Vault
	- `Remove-ServiceTag-Working.ps1` - Script to remove Azure service tag IP ranges from Key Vault
- `Remove-KeyVault-NetworkRules-Fast.ps1` - **Optimized removal script with parallel processing and ultra-fast rebuild mode**
- `Update-KeyVault-NetworkRules-Complete.ps1` - Comprehensive script to update Key Vault firewall rules

## Prerequisites

1. **Azure CLI** - Install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
2. **PowerShell** - Windows PowerShell 5.1 or PowerShell Core 7+
3. **Azure Login** - Run `az login` before using the scripts
4. **Permissions** - You need Key Vault Contributor permissions or equivalent

## Usage

### Quick IP Range Retrieval

To quickly get the current Azure service IP ranges for West Europe:

```powershell
.\Get-IpRanges.ps1
```

### Complete Key Vault Update

To update your Key Vault network rules with a specific Azure service tag:

```powershell
# Test run (see what would change without making changes)
.\Update-KeyVault-NetworkRules.ps1 -KeyVaultName "your-key-vault-name" -ServiceTag "AzureCloud.WestEurope" -WhatIf

# Apply changes
.\Update-KeyVault-NetworkRules.ps1 -KeyVaultName "your-key-vault-name" -ServiceTag "AzureCloud.WestEurope"

# Specify resource group if needed
.\Update-KeyVault-NetworkRules.ps1 -KeyVaultName "your-key-vault-name" -ServiceTag "Storage.EastUS" -ResourceGroupName "your-rg-name"

# Use different service tags
.\Update-KeyVault-NetworkRules.ps1 -KeyVaultName "your-key-vault-name" -ServiceTag "Sql.WestEurope"
```

### Remove Service Tag Rules

To remove Azure service tag IP ranges from your Key Vault (preserves custom rules):

```powershell
# Test run (see what would be removed without making changes)
.\Remove-KeyVault-NetworkRules-Fast.ps1 -KeyVaultName "your-key-vault-name" -ServiceTag "PowerBI.EastUS2" -WhatIf

# Remove service tag rules (default parallel processing)
.\Remove-KeyVault-NetworkRules-Fast.ps1 -KeyVaultName "your-key-vault-name" -ServiceTag "PowerBI.EastUS2"
```

### Optimized Removal (Recommended - Default is Parallel Processing)

**⚠️ Important: Use the correct script name: `Remove-KeyVault-NetworkRules-Fast.ps1`**

For fast removal of service tags:

```powershell
# Default parallel processing mode (fast and safe for any number of IP ranges)
.\Remove-KeyVault-NetworkRules-Fast.ps1 -KeyVaultName "your-key-vault-name" -ServiceTag "AzureCloud.EastUS"

# Ultra-fast rebuild mode (maximum speed for 500+ IP ranges, brief downtime)
.\Remove-KeyVault-NetworkRules-Fast.ps1 -KeyVaultName "your-key-vault-name" -ServiceTag "AzureCloud.EastUS" -Rebuild

# Test first with WhatIf (recommended before actual removal)
.\Remove-KeyVault-NetworkRules-Fast.ps1 -KeyVaultName "your-key-vault-name" -ServiceTag "AzureCloud.EastUS" -WhatIf

# Specify resource group if needed
.\Remove-KeyVault-NetworkRules-Fast.ps1 -KeyVaultName "your-key-vault-name" -ServiceTag "Storage.EastUS" -ResourceGroupName "your-rg-name"
```

## Performance Optimization

The script is optimized for fast, efficient processing with the following features:

- **Optimized batch size**: 100 rules per batch for best performance
- **Minimal output**: Reduced console output for maximum speed  
- **No artificial delays**: Processes rules as fast as Azure API allows
- **Smart progress reporting**: Shows progress every 5 batches to avoid output overhead

**Typical performance**:
- **~200 IP ranges**: ~1 minute
- **~500 IP ranges**: ~2-3 minutes

## Removal Performance Comparison

For removing service tag rules, choose the best method based on the number of IP ranges:

| Method | 50 IPs | 200 IPs | 500 IPs | 1000+ IPs | Downtime |
|--------|---------|---------|---------|-----------|----------|
| **Standard Removal** | 30 sec | 2 min | 5 min | 10+ min | None |
| **Parallel Processing (Default)** | 10 sec | 30 sec | 1 min | 2-3 min | None |
| **Ultra-Fast Rebuild** | 5 sec | 5 sec | 10 sec | 15 sec | Brief* |

*Ultra-fast rebuild mode temporarily blocks all access while clearing and rebuilding rules

**Recommendations:**
- **Any number of IP ranges**: Use default parallel processing (`Remove-KeyVault-NetworkRules-Fast.ps1`)
- **500+ IP ranges with acceptable brief downtime**: Use ultra-fast rebuild mode (`-Rebuild` parameter)

## Parameters

### Update-KeyVault-NetworkRules.ps1

- **KeyVaultName** (Required) - Name of your Azure Key Vault
- **ServiceTag** (Required) - Exact Azure service tag to add (e.g., "AzureCloud.WestEurope", "Storage.EastUS")
- **ResourceGroupName** (Optional) - Resource group name (auto-detected if not provided)
- **ServiceTagVersion** (Optional) - Azure Service Tags version (default: "20250804")
- **WhatIf** (Optional) - Preview changes without applying them

### Remove-KeyVault-NetworkRules-Fast.ps1 (Recommended - Default Parallel Processing)

- **KeyVaultName** (Required) - Name of your Azure Key Vault
- **ServiceTag** (Required) - Exact Azure service tag to remove (e.g., "AzureCloud.EastUS", "Storage.EastUS")
- **ResourceGroupName** (Optional) - Resource group name (auto-detected if not provided)
- **ServiceTagVersion** (Optional) - Azure Service Tags version (default: "20250804")
- **WhatIf** (Optional) - Preview what would be removed without making changes
- **Rebuild** (Optional) - Use ultra-fast rebuild mode instead of default parallel processing

## Service Tag Examples

The script now requires you to specify the exact service tag you want to add:

```powershell
# Azure Cloud services for West Europe
-ServiceTag "AzureCloud.WestEurope"

# Storage services for East US
-ServiceTag "Storage.EastUS"

# SQL services for your region
-ServiceTag "Sql.WestEurope"

# Azure Active Directory (global)
-ServiceTag "AzureActiveDirectory"

# Application Insights (global)
-ServiceTag "ApplicationInsights"
```

## What the Script Does

1. Downloads the latest Azure Service Tags JSON file
2. Validates the specified service tag exists
3. **Validates region compatibility** (prevents cross-region issues)
4. Connects to your Key Vault using Azure CLI
5. **Analyzes existing rules to identify custom vs service tag ranges**
6. **Preserves your custom IP rules (non-service tag ranges)**
7. Removes only outdated service tag IP ranges
8. Adds current service tag IP ranges
9. Verifies the update was successful

## Region Validation

The script now includes intelligent region validation to prevent Azure cross-region restrictions:

- **Automatic detection**: Detects your Key Vault's region automatically
- **Cross-region prevention**: Blocks attempts to add service tags from different regions
- **Smart suggestions**: Suggests the correct service tag for your Key Vault's region
- **Global service support**: Allows global service tags (like AzureActiveDirectory)

### Example Region Validation

```powershell
# ❌ This will fail if your Key Vault is in West Europe
.\Update-KeyVault-NetworkRules.ps1 -KeyVaultName "my-kv" -ServiceTag "AzureCloud.EastUS"

# ✅ Script will suggest the correct tag
# Suggested alternatives:
#   AzureCloud.WestEurope

# ✅ Global tags work regardless of region
.\Update-KeyVault-NetworkRules.ps1 -KeyVaultName "my-kv" -ServiceTag "AzureActiveDirectory"
```

## Security Considerations

- **IMPORTANT**: The script preserves your custom IP rules and only updates Azure service ranges
- Existing custom IP addresses (your office, VPN, etc.) will be kept intact
- Only Azure Cloud IP ranges are replaced with current ones
- Always use `-WhatIf` first to preview changes
- The script requires confirmation before making changes

## Troubleshooting

### Script Not Found Error

If you get an error like "Remove-ServiceTag-Working.ps1 not found", make sure you're using the correct script names:

- ✅ **Correct**: `Remove-KeyVault-NetworkRules-Fast.ps1` (for removing service tags)
- ✅ **Correct**: `Update-KeyVault-NetworkRules.ps1` (for adding/updating service tags)
- ❌ **Incorrect**: `Remove-ServiceTag-Working.ps1` (old/deprecated name)

Current workspace files:
```powershell
# List files to verify script names
Get-ChildItem *.ps1
```

### Azure CLI Not Found
```bash
# Install Azure CLI
winget install Microsoft.AzureCLI
```

### Not Logged In
```bash
az login
```

### Key Vault Not Found
- Verify the Key Vault name is correct
- Ensure you have access permissions
- Check if you're in the correct subscription: `az account show`

### Too Many IP Rules
Azure Key Vault has limits on the number of network rules. The script processes rules in batches to handle this.

## Example Output

```
Azure Key Vault Network Rules Update Script
=============================================
Checking for Azure Service Tags file...
Service Tags file already exists: C:\...\ServiceTags_Public_20250804.json
Parsing Azure service tags for region: WestEurope
Found 156 IP ranges for AzureCloud.WestEurope
Checking Azure CLI availability...
Azure CLI is available
Checking Azure login status...
Logged in as: user@example.com
Subscription: My Subscription (12345678-1234-1234-1234-123456789abc)
Getting Key Vault information...
Key Vault found: my-keyvault
Resource Group: my-resource-group
Location: westeurope
Getting current Key Vault network rules...
Current IP rules count: 2
Current virtual network rules count: 0

This will replace current IP rules with 156 Azure service IP ranges.
Do you want to continue? (y/N): y
Removing existing IP rules...
Adding new IP rules...
Processing batch 1 of 16 (10 rules)...
...
SUCCESS: Key Vault network rules updated successfully!
```

## Notes

- The script uses the latest available Azure Service Tags
- IP ranges are region-specific
- Updates may take a few minutes depending on the number of rules
- Virtual network rules are preserved (only IP rules are modified)
