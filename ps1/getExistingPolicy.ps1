# Script to collect and report on existing security policy values
# This script will not make any changes to the system
# Output will be saved as an HTML report


# Function to get date in a formatted string
function Get-FormattedDate {
    return Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

# Function to get computer info
function Get-ComputerInformation {
    $computerInfo = Get-ComputerInfo | Select-Object CsName, CsDomain, OsName, OsVersion, OsBuildNumber
    return $computerInfo
}

# Function to get Group Policy settings from Computer Configuration
function Get-ComputerConfigurationPolicies {
    Write-Host "Collecting Computer Configuration policies..."
    
    # Get computer security settings from registry
    $policies = @()
    
    # Security Options
    $policies += Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" | 
                 Select-Object @{Name="Category"; Expression={"Security Options"}},
                               @{Name="Policy"; Expression={"LSA Settings"}},
                               @{Name="Value"; Expression={($_ | Format-List | Out-String).Trim()}}
    
    # Audit Policies
    $auditPolicies = auditpol /get /category:* /r | ConvertFrom-Csv
    foreach ($policy in $auditPolicies) {
        $policies += [PSCustomObject]@{
            Category = "Audit Policy"
            Policy = $policy.'Subcategory'
            Value = $policy.'Inclusion Setting'
        }
    }
    
    # Windows Firewall
    $firewallProfiles = Get-NetFirewallProfile
    foreach ($profile in $firewallProfiles) {
        $policies += [PSCustomObject]@{
            Category = "Windows Firewall"
            Policy = $profile.Name + " Profile"
            Value = "Enabled: " + $profile.Enabled + ", DefaultInboundAction: " + $profile.DefaultInboundAction + ", DefaultOutboundAction: " + $profile.DefaultOutboundAction
        }
    }
    
    # Windows Updates
    try {
        $updateSettings = (New-Object -ComObject "Microsoft.Update.AutoUpdate").Settings
        $policies += [PSCustomObject]@{
            Category = "Windows Updates"
            Policy = "Automatic Updates"
            Value = "NotificationLevel: " + $updateSettings.NotificationLevel
        }
    }
    catch {
        $policies += [PSCustomObject]@{
            Category = "Windows Updates"
            Policy = "Automatic Updates"
            Value = "Unable to retrieve (Error: $($_.Exception.Message))"
        }
    }
    
    # User Account Control Settings
    $uacSettings = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $policies += [PSCustomObject]@{
        Category = "User Account Control"
        Policy = "UAC Settings"
        Value = "EnableLUA: $($uacSettings.EnableLUA), ConsentPromptBehaviorAdmin: $($uacSettings.ConsentPromptBehaviorAdmin)"
    }
    
    return $policies
}

# Function to get Group Policy settings from User Configuration
function Get-UserConfigurationPolicies {
    Write-Host "Collecting User Configuration policies..."
    
    $policies = @()
    
    # User rights assignment - requires LGPO.exe to get complete info
    # Adding placeholder for demonstration
    $policies += [PSCustomObject]@{
        Category = "User Configuration"
        Policy = "User Rights Assignment"
        Value = "See detailed report for individual rights"
    }
    
    # Password Policy
    $netAccounts = net accounts | Out-String
    $policies += [PSCustomObject]@{
        Category = "Password Policy"
        Policy = "Password Settings"
        Value = $netAccounts.Trim()
    }
    
    # User folder redirection
    $policies += [PSCustomObject]@{
        Category = "User Folder Redirection"
        Policy = "Folder Redirection Status"
        Value = "Check Group Policy Editor for details"
    }
    
    return $policies
}

# Function to get local security policies using secedit
function Get-LocalSecurityPolicies {
    Write-Host "Collecting Local Security Policies..."
    
    $tempFile = "$env:TEMP\secpol.cfg"
    $command = "secedit /export /cfg '$tempFile' /quiet"
    Invoke-Expression -Command $command
    
    $content = Get-Content -Path $tempFile -Raw
    Remove-Item -Path $tempFile -Force
    
    $policies = @()
    $sections = $content -split '\[.*\]'
    
    foreach ($i in 1..($sections.Count - 1)) {
        $sectionName = [regex]::Match($content, '\[(.*?)\]').Groups[1].Value
        $sectionContent = $sections[$i]
        
        $lines = $sectionContent -split "`r`n" | Where-Object { $_ -match '=' }
        foreach ($line in $lines) {
            $parts = $line -split '='
            if ($parts.Count -ge 2) {
                $policyName = $parts[0].Trim()
                $policyValue = $parts[1].Trim()
                
                $policies += [PSCustomObject]@{
                    Category = $sectionName
                    Policy = $policyName
                    Value = $policyValue
                }
            }
        }
    }
    
    return $policies
}

# Function to generate HTML report
function Generate-HTMLReport {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ReportPath,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$ComputerInfo,
        
        [Parameter(Mandatory=$true)]
        [array]$AllPolicies
    )
    
    $reportDate = Get-FormattedDate
    
    $htmlHeader = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>[BTPNS] Existing Policy</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            color: #333;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        h1, h2, h3 {
            color: #0066cc;
        }
        .header {
            background-color: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
            border-left: 5px solid #0066cc;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
        }
        th, td {
            padding: 12px 15px;
            border: 1px solid #ddd;
            text-align: left;
        }
        th {
            background-color: #0066cc;
            color: white;
        }
        tr:nth-child(even) {
            background-color: #f2f2f2;
        }
        .footer {
            margin-top: 30px;
            font-size: 0.8em;
            color: #666;
            text-align: center;
        }
        .section {
            margin-bottom: 30px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Existing Policy BTPNS</h1>
            <p>This report captures the current security policy settings before any hardening measures are applied.</p>
            <p><strong>Report Generated:</strong> $reportDate</p>
        </div>
        
        <div class="section">
            <h2>System Information</h2>
            <table>
                <tr>
                    <th>Computer Name</th>
                    <td>$($ComputerInfo.CsName)</td>
                </tr>
                <tr>
                    <th>Domain</th>
                    <td>$($ComputerInfo.CsDomain)</td>
                </tr>
                <tr>
                    <th>Operating System</th>
                    <td>$($ComputerInfo.OsName)</td>
                </tr>
                <tr>
                    <th>OS Version</th>
                    <td>$($ComputerInfo.OsVersion)</td>
                </tr>
                <tr>
                    <th>Build Number</th>
                    <td>$($ComputerInfo.OsBuildNumber)</td>
                </tr>
            </table>
        </div>
"@

    $htmlBody = ""
    
    # Group policies by category
    $groupedPolicies = $AllPolicies | Group-Object -Property Category
    
    foreach ($group in $groupedPolicies) {
        $htmlBody += @"
        <div class="section">
            <h2>$($group.Name)</h2>
            <table>
                <tr>
                    <th>Policy</th>
                    <th>Current Value</th>
                </tr>
"@
        
        foreach ($policy in $group.Group) {
            $htmlBody += @"
                <tr>
                    <td>$($policy.Policy)</td>
                    <td>$($policy.Value)</td>
                </tr>
"@
        }
        
        $htmlBody += @"
            </table>
        </div>
"@
    }
    
    $htmlFooter = @"
        <div class="footer">
            <p>This report is for informational purposes only. Review security settings with your security team before making changes.</p>
        </div>
    </div>
</body>
</html>
"@
    
    $fullHtml = $htmlHeader + $htmlBody + $htmlFooter
    $fullHtml | Out-File -FilePath $ReportPath -Encoding UTF8
    
    Write-Host "HTML report saved to: $ReportPath"
}

# Main script execution
try {
    $scriptStart = Get-Date
    Write-Host "Security Policy Audit started at $(Get-FormattedDate)"
    
    # Create report directory if it doesn't exist
    $reportDir = "C:\Temp\Reports"
    if (-not (Test-Path -Path $reportDir)) {
        New-Item -Path $reportDir -ItemType Directory | Out-Null
    }
    
    $reportPath = "$reportDir\Existing_Policy-$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    
    # Get system information
    Write-Host "Collecting system information..."
    $computerInfo = Get-ComputerInformation
    
    # Get policy settings
    $computerPolicies = Get-ComputerConfigurationPolicies
    $userPolicies = Get-UserConfigurationPolicies
    $localSecurityPolicies = Get-LocalSecurityPolicies
    
    # Combine all policies
    $allPolicies = $computerPolicies + $userPolicies + $localSecurityPolicies
    
    # Generate HTML report
    Write-Host "Generating HTML report..."
    Generate-HTMLReport -ReportPath $reportPath -ComputerInfo $computerInfo -AllPolicies $allPolicies
    
    $scriptEnd = Get-Date
    $duration = $scriptEnd - $scriptStart
    Write-Host "Security Policy Audit completed at $(Get-FormattedDate)"
    Write-Host "Duration: $($duration.TotalSeconds) seconds"
    Write-Host "Report saved to: $reportPath"
    
    # Open the report
    Start-Process $reportPath
}
catch {
    Write-Error "An error occurred during the security policy audit: $_"
    exit 1
}