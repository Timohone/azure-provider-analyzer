# Get-AzProviderReport.ps1
# Generates a comprehensive HTML report of all Azure providers with baseline recommendations

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "./reports",
    
    [Parameter(Mandatory=$false)]
    [string]$ReportTitle = "Azure Provider Analysis Report",
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeNotRegistered
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   AZURE PROVIDER ANALYSIS - HTML REPORT GENERATOR         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Microsoft Official Enterprise-Scale Azure Landing Zone Provider Requirements
$microsoftALZ = @{
    # Required for ALZ Deployment (Empty Subscriptions)
    Required = @(
        "Microsoft.Insights",
        "Microsoft.AlertsManagement",
        "Microsoft.OperationalInsights",
        "Microsoft.OperationsManagement",
        "Microsoft.Automation",
        "Microsoft.Security",
        "Microsoft.Network",
        "Microsoft.EventGrid",
        "Microsoft.ManagedIdentity",
        "Microsoft.GuestConfiguration",
        "Microsoft.Advisor",
        "Microsoft.PolicyInsights"
    )
    
    # Additional Recommended for Common Resources
    Recommended = @(
        "Microsoft.Compute",
        "Microsoft.Storage",
        "Microsoft.ResourceHealth",
        "Microsoft.KeyVault",
        "Microsoft.Sql",
        "Microsoft.Capacity",
        "Microsoft.ManagedServices",
        "Microsoft.Management",
        "Microsoft.SecurityInsights",
        "Microsoft.Blueprint",
        "Microsoft.Cache",
        "Microsoft.RecoveryServices"
    )
}

# Static Provider Categories (Known Facts)
$staticCategories = @{
    # Auto-Registered by Azure (no manual registration needed)
    AutoRegistered = @(
        "Microsoft.Authorization",
        "Microsoft.Resources",
        "Microsoft.Consumption",
        "Microsoft.Billing",
        "Microsoft.Portal",
        "Microsoft.ResourceGraph",
        "Microsoft.ResourceNotifications",
        "Microsoft.SerialConsole",
        "Microsoft.Advisor",
        "Microsoft.Security",
        "Microsoft.CostManagement",
        "Microsoft.Monitor",
        "Microsoft.MarketplaceOrdering",
        "Microsoft.PolicyInsights",
        "microsoft.support",
        "Microsoft.Features",
        "Microsoft.ResourceHealth"
    )
    
    # Deprecated Classic Providers (should be removed)
    Deprecated = @(
        "Microsoft.ClassicStorage",
        "Microsoft.ClassicNetwork",
        "Microsoft.ClassicCompute",
        "Microsoft.ClassicSubscription",
        "Microsoft.ClassicInfrastructureMigrate"
    )
}

# Verbindung prüfen
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not connected to Azure. Connecting..." -ForegroundColor Yellow
        Connect-AzAccount
    }
    Write-Host "✓ Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "✓ Tenant: $($context.Tenant.Id)" -ForegroundColor Green
    $tenantId = $context.Tenant.Id
    $userName = $context.Account.Id
} catch {
    Write-Host "✗ Failed to connect to Azure: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Output-Verzeichnis erstellen
if (-not (Test-Path -Path $OutputPath)) {
    Write-Host "Creating output directory: $OutputPath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "✓ Directory created" -ForegroundColor Green
}

# Alle Subscriptions abrufen
$subscriptions = Get-AzSubscription
Write-Host "Found $($subscriptions.Count) subscriptions in tenant" -ForegroundColor Green
Write-Host ""

# Datenstrukturen
$allProvidersData = @()
$providerUsageMatrix = @{}
$subscriptionSummary = @()

$currentSub = 0

foreach ($sub in $subscriptions) {
    $currentSub++
    $percentComplete = [math]::Round(($currentSub / $subscriptions.Count) * 100, 1)
    
    Write-Progress -Activity "Analyzing Subscriptions" -Status "Processing $($sub.Name)" -PercentComplete $percentComplete
    Write-Host "[$currentSub/$($subscriptions.Count)] $($sub.Name)" -ForegroundColor Yellow
    
    try {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
        
        $allProviders = Get-AzResourceProvider -ListAvailable
        $resources = Get-AzResource
        $resourceCount = $resources.Count
        
        $providersWithResources = @{}
        if ($resourceCount -gt 0) {
            foreach ($resource in $resources) {
                $providerNamespace = $resource.ResourceType.Split('/')[0]
                if ($providersWithResources.ContainsKey($providerNamespace)) {
                    $providersWithResources[$providerNamespace]++
                } else {
                    $providersWithResources[$providerNamespace] = 1
                }
            }
        }
        
        foreach ($provider in $allProviders) {
            $hasResources = $providersWithResources.ContainsKey($provider.ProviderNamespace)
            $resourceCountForProvider = if ($hasResources) { $providersWithResources[$provider.ProviderNamespace] } else { 0 }
            
            if ($provider.RegistrationState -eq "Registered" -or $IncludeNotRegistered) {
                $allProvidersData += [PSCustomObject]@{
                    Subscription = $sub.Name
                    SubscriptionId = $sub.Id
                    ProviderNamespace = $provider.ProviderNamespace
                    RegistrationState = $provider.RegistrationState
                    HasResources = $hasResources
                    ResourceCount = $resourceCountForProvider
                }
            }
            
            if ($provider.RegistrationState -eq "Registered") {
                if (-not $providerUsageMatrix.ContainsKey($provider.ProviderNamespace)) {
                    $providerUsageMatrix[$provider.ProviderNamespace] = @{
                        Count = 0
                        Subscriptions = @()
                        WithResources = 0
                        TotalResources = 0
                    }
                }
                $providerUsageMatrix[$provider.ProviderNamespace].Count++
                $providerUsageMatrix[$provider.ProviderNamespace].Subscriptions += $sub.Name
                if ($hasResources) {
                    $providerUsageMatrix[$provider.ProviderNamespace].WithResources++
                    $providerUsageMatrix[$provider.ProviderNamespace].TotalResources += $resourceCountForProvider
                }
            }
        }
        
        $registeredCount = ($allProviders | Where-Object { $_.RegistrationState -eq "Registered" }).Count
        $providersWithResourcesCount = $providersWithResources.Keys.Count
        
        $registeredProviders = ($allProviders | Where-Object { $_.RegistrationState -eq "Registered" } | Select-Object -ExpandProperty ProviderNamespace | Sort-Object) -join '|'
        
        $subscriptionSummary += [PSCustomObject]@{
            Subscription = $sub.Name
            SubscriptionId = $sub.Id
            RegisteredProviders = $registeredCount
            ProvidersWithResources = $providersWithResourcesCount
            TotalResources = $resourceCount
            RegisteredProvidersList = $registeredProviders
        }
        
        Write-Host "  ✓ Registered: $registeredCount | With Resources: $providersWithResourcesCount | Resources: $resourceCount" -ForegroundColor Green
        
    } catch {
        Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Progress -Activity "Analyzing Subscriptions" -Completed
Write-Host ""
Write-Host "Analyzing provider usage patterns..." -ForegroundColor Cyan

# Provider Usage Summary mit dynamischer Kategorisierung
$providerUsageSummary = $providerUsageMatrix.GetEnumerator() | ForEach-Object {
    $providerName = $_.Key
    $percentage = [math]::Round(($_.Value.Count / $subscriptions.Count) * 100, 2)
    
    # Dynamische Kategorisierung basierend auf tatsächlicher Verwendung
    $categories = @()
    
    # Static Categories
    if ($staticCategories.AutoRegistered -contains $providerName) {
        $categories += "Auto-Registered"
    }
    if ($staticCategories.Deprecated -contains $providerName) {
        $categories += "Deprecated"
    }
    
    # Microsoft ALZ
    if ($microsoftALZ.Required -contains $providerName) {
        $categories += "ALZ-Required"
    }
    if ($microsoftALZ.Recommended -contains $providerName) {
        $categories += "ALZ-Recommended"
    }
    
    # Dynamic Categories basierend auf Usage
    if ($percentage -ge 80) {
        $categories += "Widely-Used"
    }
    elseif ($percentage -ge 50) {
        $categories += "Common"
    }
    elseif ($percentage -ge 20) {
        $categories += "Moderate"
    }
    else {
        $categories += "Specialized"
    }
    
    # Control Plane vs Data Plane
    $isControlPlane = $_.Value.WithResources -eq 0
    if ($isControlPlane) {
        $categories += "Control-Plane"
    } else {
        $categories += "Data-Plane"
    }
    
    [PSCustomObject]@{
        Provider = $providerName
        RegisteredInSubscriptions = $_.Value.Count
        TotalSubscriptions = $subscriptions.Count
        Percentage = $percentage
        SubscriptionsWithResources = $_.Value.WithResources
        TotalResourcesAcrossAllSubs = $_.Value.TotalResources
        IsControlPlane = $isControlPlane
        Categories = $categories
        IsAutoRegistered = $staticCategories.AutoRegistered -contains $providerName
        IsDeprecated = $staticCategories.Deprecated -contains $providerName
        IsALZRequired = $microsoftALZ.Required -contains $providerName
        IsALZRecommended = $microsoftALZ.Recommended -contains $providerName
        IsWidelyUsed = $percentage -ge 80
        IsCommon = $percentage -ge 50 -and $percentage -lt 80
    }
} | Sort-Object RegisteredInSubscriptions -Descending

# Statistiken
$totalProviders = $providerUsageSummary.Count
$controlPlaneCount = ($providerUsageSummary | Where-Object { $_.IsControlPlane }).Count
$dataPlaneCount = $totalProviders - $controlPlaneCount
$widelyUsedProviders = $providerUsageSummary | Where-Object { $_.IsWidelyUsed }
$totalResources = ($subscriptionSummary | Measure-Object -Property TotalResources -Sum).Sum
$deprecatedCount = ($providerUsageSummary | Where-Object { $_.IsDeprecated }).Count

# ALZ Compliance Check
$alzRequiredRegistered = $providerUsageSummary | Where-Object { $_.IsALZRequired }
$alzRequiredMissing = $microsoftALZ.Required | Where-Object { $_ -notin $alzRequiredRegistered.Provider }
$alzCompliancePercentage = [math]::Round(($alzRequiredRegistered.Count / $microsoftALZ.Required.Count) * 100, 1)

Write-Host "Generating HTML report..." -ForegroundColor Cyan

# HTML generieren
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$ReportTitle</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: #f5f5f5;
            padding: 20px;
            color: #1a1a1a;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 4px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .header {
            background: #0078d4;
            color: white;
            padding: 40px 30px;
        }
        
        .header h1 { font-size: 28px; font-weight: 500; margin-bottom: 8px; }
        .header .meta { font-size: 13px; opacity: 0.9; font-weight: 300; }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 1px;
            background: #e0e0e0;
            border-bottom: 1px solid #e0e0e0;
        }
        
        .stat-card {
            background: white;
            padding: 24px;
            text-align: center;
        }
        
        .stat-card .label {
            font-size: 11px;
            text-transform: uppercase;
            color: #666;
            margin-bottom: 8px;
            font-weight: 500;
            letter-spacing: 0.5px;
        }
        
        .stat-card .value {
            font-size: 32px;
            font-weight: 300;
            color: #0078d4;
        }
        
        .stat-card.warning .value { color: #d83b01; }
        .stat-card.success .value { color: #107c10; }
        
        .section {
            padding: 40px 30px;
            border-bottom: 1px solid #e0e0e0;
        }
        
        .section:last-child { border-bottom: none; }
        
        .section h2 {
            font-size: 20px;
            margin-bottom: 24px;
            color: #1a1a1a;
            font-weight: 500;
        }
        
        .baseline-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        
        .baseline-card {
            background: #fafafa;
            border: 1px solid #e0e0e0;
            border-radius: 4px;
            padding: 20px;
        }
        
        .baseline-card.highlight {
            border: 2px solid #0078d4;
            background: #f0f8ff;
        }
        
        .baseline-card h4 {
            color: #1a1a1a;
            margin-bottom: 8px;
            font-size: 14px;
            font-weight: 500;
        }
        
        .baseline-card .description {
            font-size: 12px;
            color: #666;
            margin-bottom: 12px;
        }
        
        .baseline-card .count {
            font-size: 11px;
            color: #0078d4;
            font-weight: 500;
            margin-bottom: 8px;
        }
        
        .baseline-card .provider-list {
            list-style: none;
            padding: 0;
        }
        
        .baseline-card .provider-list li {
            padding: 6px 0;
            font-size: 13px;
            color: #333;
            font-family: 'Courier New', monospace;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 16px;
            font-size: 13px;
        }
        
        table thead {
            background: #fafafa;
            border-bottom: 2px solid #e0e0e0;
        }
        
        table th {
            padding: 12px;
            text-align: left;
            font-weight: 500;
            cursor: pointer;
            user-select: none;
            color: #666;
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        table th:hover { background: #f0f0f0; }
        table tbody tr { border-bottom: 1px solid #f0f0f0; }
        table tbody tr:hover { background: #fafafa; }
        table td { padding: 12px; color: #333; }
        
        .badge {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 3px;
            font-size: 10px;
            font-weight: 500;
            text-transform: uppercase;
            margin-right: 4px;
            letter-spacing: 0.3px;
        }
        
        .badge-control { background: #e3f2fd; color: #1976d2; }
        .badge-data { background: #e8f5e9; color: #388e3c; }
        .badge-auto { background: #f3e5f5; color: #7b1fa2; }
        .badge-deprecated { background: #ffebee; color: #c62828; }
        .badge-alz { background: #fff3e0; color: #f57c00; }
        .badge-widely { background: #e8f5e9; color: #2e7d32; }
        .badge-common { background: #e0f2f1; color: #00695c; }
        
        .progress-bar {
            width: 100%;
            height: 6px;
            background: #e0e0e0;
            border-radius: 3px;
            overflow: hidden;
            margin-top: 4px;
        }
        
        .progress-fill {
            height: 100%;
            background: #0078d4;
            transition: width 0.3s ease;
        }
        
        .search-box {
            padding: 10px 12px;
            width: 100%;
            max-width: 300px;
            border: 1px solid #e0e0e0;
            border-radius: 4px;
            font-size: 13px;
            margin-bottom: 16px;
        }
        
        .search-box:focus {
            outline: none;
            border-color: #0078d4;
        }
        
        .warning-box {
            background: #fff3cd;
            border-left: 3px solid #ffc107;
            padding: 12px 16px;
            margin: 16px 0;
            border-radius: 4px;
            font-size: 13px;
        }
        
        .info-box {
            background: #e7f3ff;
            border-left: 3px solid #0078d4;
            padding: 12px 16px;
            margin: 16px 0;
            border-radius: 4px;
            font-size: 13px;
        }
        
        .success-box {
            background: #dff6dd;
            border-left: 3px solid #107c10;
            padding: 12px 16px;
            margin: 16px 0;
            border-radius: 4px;
            font-size: 13px;
        }
        
        .footer {
            background: #fafafa;
            padding: 20px;
            text-align: center;
            font-size: 12px;
            color: #666;
        }
        
        .clickable-row {
            cursor: pointer;
        }
        
        .clickable-row:hover {
            background: #f5f5f5 !important;
        }
        
        .provider-details {
            display: none;
            background: #fafafa;
            padding: 16px;
            border-top: 1px solid #e0e0e0;
        }
        
        .provider-details.show {
            display: block;
        }
        
        .provider-details h4 {
            font-size: 13px;
            margin-bottom: 12px;
            color: #666;
            font-weight: 500;
        }
        
        .provider-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
            gap: 8px;
            font-size: 12px;
            font-family: 'Courier New', monospace;
        }
        
        .provider-item {
            padding: 6px 8px;
            background: white;
            border: 1px solid #e0e0e0;
            border-radius: 3px;
            color: #333;
        }
        
        @media print {
            body { background: white; padding: 0; }
            .container { box-shadow: none; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>$ReportTitle</h1>
            <div class="meta">
                Generated $reportDate | Tenant $tenantId | $userName | $($subscriptions.Count) Subscriptions
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="label">Subscriptions</div>
                <div class="value">$($subscriptions.Count)</div>
            </div>
            <div class="stat-card">
                <div class="label">Providers</div>
                <div class="value">$totalProviders</div>
            </div>
            <div class="stat-card">
                <div class="label">Widely Used</div>
                <div class="value">$($widelyUsedProviders.Count)</div>
            </div>
            <div class="stat-card $(if($alzCompliancePercentage -lt 100){'warning'}else{'success'})">
                <div class="label">ALZ Compliance</div>
                <div class="value">$alzCompliancePercentage%</div>
            </div>
            <div class="stat-card">
                <div class="label">Control Plane</div>
                <div class="value">$controlPlaneCount</div>
            </div>
            <div class="stat-card">
                <div class="label">Resources</div>
                <div class="value">$totalResources</div>
            </div>
        </div>
        
        <div class="section">
            <h2>Enterprise-Scale Azure Landing Zone Compliance</h2>
"@

if ($alzRequiredMissing.Count -gt 0) {
    $html += @"
            <div class="warning-box">
                <strong>ALZ Compliance Gap:</strong> $($alzRequiredMissing.Count) required providers are missing or not widely registered. These are needed for Enterprise-Scale ALZ deployment.
            </div>
"@
} else {
    $html += @"
            <div class="success-box">
                <strong>ALZ Compliant:</strong> All required Enterprise-Scale ALZ providers are registered across your subscriptions.
            </div>
"@
}

if ($deprecatedCount -gt 0) {
    $html += @"
            <div class="warning-box">
                <strong>Deprecated Providers:</strong> $deprecatedCount Classic providers detected. Consider removing these in a modernization effort.
            </div>
"@
}

$html += @"
            <div class="info-box">
                <strong>Analysis Method:</strong> Provider categories are determined dynamically based on actual usage patterns in your tenant (Widely Used ≥80%, Common ≥50%) combined with Microsoft best practices.
            </div>
            
            <div class="baseline-grid">
                <div class="baseline-card highlight">
                    <h4>Microsoft ALZ Required</h4>
                    <div class="description">Required for Enterprise-Scale with predefined template (empty subscriptions)</div>
                    <div class="count">$($microsoftALZ.Required.Count) providers - $($alzRequiredRegistered.Count) found in tenant</div>
                    <ul class="provider-list">
"@

foreach ($provider in $microsoftALZ.Required) {
    $isRegistered = $alzRequiredRegistered.Provider -contains $provider
    $marker = if ($isRegistered) { "✓" } else { "✗" }
    $style = if ($isRegistered) { "color: #107c10;" } else { "color: #d83b01;" }
    $html += "<li style='$style'>$marker $provider</li>"
}

$html += @"
                    </ul>
                </div>
                
                <div class="baseline-card">
                    <h4>Microsoft ALZ Recommended</h4>
                    <div class="description">Additional recommended providers for common resources</div>
                    <div class="count">$($microsoftALZ.Recommended.Count) providers</div>
                    <ul class="provider-list">
"@

foreach ($provider in $microsoftALZ.Recommended) {
    $html += "<li>$provider</li>"
}

$html += @"
                    </ul>
                </div>
                
                <div class="baseline-card">
                    <h4>Widely Used in Tenant</h4>
                    <div class="description">Registered in ≥80% of subscriptions (proven usage pattern)</div>
                    <div class="count">$($widelyUsedProviders.Count) providers</div>
                    <ul class="provider-list">
"@

foreach ($provider in $widelyUsedProviders | Select-Object -First 12) {
    $html += "<li>$($provider.Provider) ($($provider.Percentage)%)</li>"
}

$html += @"
                    </ul>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>All Providers Summary</h2>
            <input type="text" id="providerSearch" class="search-box" placeholder="Search providers..." onkeyup="filterTable('allProvidersTable', 'providerSearch')">
            <table id="allProvidersTable">
                <thead>
                    <tr>
                        <th onclick="sortTable('allProvidersTable', 0)">Provider</th>
                        <th onclick="sortTable('allProvidersTable', 1)">Subscriptions</th>
                        <th onclick="sortTable('allProvidersTable', 2)">Percentage</th>
                        <th onclick="sortTable('allProvidersTable', 3)">Category</th>
                        <th onclick="sortTable('allProvidersTable', 4)">Resources</th>
                    </tr>
                </thead>
                <tbody>
"@

foreach ($provider in $providerUsageSummary) {
    $badges = ""
    
    if ($provider.IsALZRequired) {
        $badges += '<span class="badge badge-alz">ALZ-Required</span>'
    }
    if ($provider.IsWidelyUsed) {
        $badges += '<span class="badge badge-widely">Widely-Used</span>'
    }
    if ($provider.IsCommon) {
        $badges += '<span class="badge badge-common">Common</span>'
    }
    if ($provider.IsAutoRegistered) {
        $badges += '<span class="badge badge-auto">Auto</span>'
    }
    if ($provider.IsDeprecated) {
        $badges += '<span class="badge badge-deprecated">Deprecated</span>'
    }
    if ($provider.IsControlPlane) {
        $badges += '<span class="badge badge-control">Control</span>'
    } else {
        $badges += '<span class="badge badge-data">Data</span>'
    }
    
    $html += @"
                    <tr>
                        <td><strong>$($provider.Provider)</strong><br>$badges</td>
                        <td>$($provider.RegisteredInSubscriptions) / $($provider.TotalSubscriptions)</td>
                        <td>
                            <div style="font-size: 12px; color: #666; margin-bottom: 4px;">$($provider.Percentage)%</div>
                            <div class="progress-bar">
                                <div class="progress-fill" style="width: $($provider.Percentage)%"></div>
                            </div>
                        </td>
                        <td style="font-size: 11px; color: #666;">$($provider.Categories -join ', ')</td>
                        <td>$($provider.TotalResourcesAcrossAllSubs)</td>
                    </tr>
"@
}

$html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Subscription Summary</h2>
            <p style="font-size: 13px; color: #666; margin-bottom: 16px;">Click on a subscription to view all registered providers</p>
            <table id="subscriptionTable">
                <thead>
                    <tr>
                        <th onclick="sortTable('subscriptionTable', 0)">Subscription</th>
                        <th onclick="sortTable('subscriptionTable', 1)">Registered</th>
                        <th onclick="sortTable('subscriptionTable', 2)">With Resources</th>
                        <th onclick="sortTable('subscriptionTable', 3)">Resources</th>
                    </tr>
                </thead>
                <tbody>
"@

$rowIndex = 0
foreach ($sub in $subscriptionSummary) {
    $providers = $sub.RegisteredProvidersList -split '\|'
    
    $html += @"
                    <tr class="clickable-row" onclick="toggleProviders($rowIndex)">
                        <td><strong>$($sub.Subscription)</strong><br><small style="color: #999;">$($sub.SubscriptionId)</small></td>
                        <td>$($sub.RegisteredProviders)</td>
                        <td>$($sub.ProvidersWithResources)</td>
                        <td>$($sub.TotalResources)</td>
                    </tr>
                    <tr>
                        <td colspan="4" style="padding: 0;">
                            <div id="providers-$rowIndex" class="provider-details">
                                <h4>Registered Providers ($($sub.RegisteredProviders))</h4>
                                <div class="provider-grid">
"@
    
    foreach ($provider in $providers) {
        $html += "<div class='provider-item'>$provider</div>"
    }
    
    $html += @"
                                </div>
                            </div>
                        </td>
                    </tr>
"@
    $rowIndex++
}

$html += @"
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            Azure Provider Analysis Report | Generated by Get-AzProviderReport.ps1 | $reportDate
        </div>
    </div>
    
    <script>
        function sortTable(tableId, columnIndex) {
            var table = document.getElementById(tableId);
            var rows = Array.from(table.querySelectorAll('tbody tr:not(:has(.provider-details))'));
            var isAscending = table.dataset.sortOrder === 'asc';
            
            rows.sort(function(a, b) {
                var aValue = a.cells[columnIndex].innerText.trim();
                var bValue = b.cells[columnIndex].innerText.trim();
                
                var aNum = parseFloat(aValue.replace(/[^0-9.-]/g, ''));
                var bNum = parseFloat(bValue.replace(/[^0-9.-]/g, ''));
                
                if (!isNaN(aNum) && !isNaN(bNum)) {
                    return isAscending ? aNum - bNum : bNum - aNum;
                }
                
                return isAscending ? 
                    aValue.localeCompare(bValue) : 
                    bValue.localeCompare(aValue);
            });
            
            var tbody = table.querySelector('tbody');
            rows.forEach(function(row) {
                var detailsRow = row.nextElementSibling;
                tbody.appendChild(row);
                if (detailsRow && detailsRow.querySelector('.provider-details')) {
                    tbody.appendChild(detailsRow);
                }
            });
            
            table.dataset.sortOrder = isAscending ? 'desc' : 'asc';
        }
        
        function filterTable(tableId, searchId) {
            var input = document.getElementById(searchId);
            var filter = input.value.toUpperCase();
            var table = document.getElementById(tableId);
            var rows = table.querySelectorAll('tbody tr');
            
            rows.forEach(function(row) {
                var text = row.innerText.toUpperCase();
                row.style.display = text.indexOf(filter) > -1 ? '' : 'none';
            });
        }
        
        function toggleProviders(index) {
            var details = document.getElementById('providers-' + index);
            if (details.classList.contains('show')) {
                details.classList.remove('show');
            } else {
                document.querySelectorAll('.provider-details.show').forEach(function(el) {
                    el.classList.remove('show');
                });
                details.classList.add('show');
            }
        }
    </script>
</body>
</html>
"@

$htmlFile = Join-Path $OutputPath "azure-provider-report-$timestamp.html"
$html | Out-File -FilePath $htmlFile -Encoding UTF8

$absolutePath = (Resolve-Path $htmlFile).Path

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                   REPORT GENERATED                         ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Report saved to:" -ForegroundColor Yellow
Write-Host $absolutePath -ForegroundColor Cyan
Write-Host ""
Write-Host "ALZ Compliance: $alzCompliancePercentage% ($($alzRequiredRegistered.Count)/$($microsoftALZ.Required.Count) required providers)" -ForegroundColor $(if($alzCompliancePercentage -eq 100){'Green'}else{'Yellow'})
if ($alzRequiredMissing.Count -gt 0) {
    Write-Host "Missing ALZ Providers: $($alzRequiredMissing -join ', ')" -ForegroundColor Red
}
Write-Host ""
Write-Host "Opening in default browser..." -ForegroundColor Yellow
Start-Process $htmlFile

Write-Host ""
Write-Host "✓ Complete!" -ForegroundColor Green