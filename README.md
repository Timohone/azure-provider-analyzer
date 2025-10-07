# Azure Provider Analyzer

PowerShell tool that analyzes Azure Resource Providers across all subscriptions in your tenant and generates an interactive HTML report with baseline recommendations for Landing Zone deployments.

## What It Does

- Scans all subscriptions in your Azure tenant
- Identifies which providers are registered and actively used
- Detects "invisible" control plane providers (Authorization, Consumption, etc.)
- Generates baseline recommendations for new subscriptions
- Creates an interactive HTML report with provider details per subscription

## Prerequisites

- PowerShell 5.1+ (PowerShell 7+ recommended)
- Azure PowerShell Module: `Install-Module -Name Az`
- Reader permissions on all subscriptions

## Installation

```bash
git clone https://github.com/yourusername/azure-provider-analyzer.git
cd azure-provider-analyzer
```

## Usage

```powershell
# Connect to Azure
Connect-AzAccount

# Run analysis (saves to ./reports folder)
.\Get-AzProviderReport.ps1

# Custom report title
.\Get-AzProviderReport.ps1 -ReportTitle "Q4 2025 Provider Audit"

# Custom output directory
.\Get-AzProviderReport.ps1 -OutputPath "C:\Reports"
```

## Output

Generates `azure-provider-report-YYYYMMDD-HHMMSS.html` containing:

- **Statistics Dashboard**: Key metrics at a glance
- **Baseline Recommendations**: Provider sets for different subscription types
  - Minimal Baseline (all subscriptions)
  - Governance Baseline
  - Landing Zone (Public/Hybrid)
  - Platform (Connectivity/Identity/Management/Security)
- **Provider Summary**: Complete list with usage statistics and categories
- **Subscription Details**: Click any subscription to view all registered providers

## Provider Categories

The tool automatically categorizes providers:

- **Auto-Registered**: Already available (Authorization, Resources, Consumption)
- **Deprecated**: Classic providers that should be removed
- **Minimal Baseline**: Essential 3 providers for every subscription
- **Governance Baseline**: Recommended additional providers
- **Control Plane**: Providers without visible resources
- **Data Plane**: Providers that create resources

## Example Baseline

**Minimal Baseline** (Tier 1 - all subscriptions):
```
Microsoft.Insights
Microsoft.Storage  
Microsoft.KeyVault
```

**Governance Baseline** (Tier 2 - recommended):
```
Microsoft.OperationalInsights
Microsoft.ManagedIdentity
Microsoft.AlertsManagement
```

## Why Use This?

- **Landing Zone Planning**: Know which providers to pre-register
- **Governance**: Ensure consistency across subscriptions
- **Cost Optimization**: Identify unused registered providers
- **Security**: Detect missing security providers (KeyVault, ManagedIdentity)
- **Compliance**: Document provider usage for audits

## License

MIT License