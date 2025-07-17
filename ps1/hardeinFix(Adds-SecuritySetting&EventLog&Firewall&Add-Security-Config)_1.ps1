# Script to Backup, Apply Policies, and Generate Policy Report

# Define Paths
$timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$backupPath = "C:\Temp\$timestamp\secpol_backup_$timestamp.inf"
$currentPolicyPath = "C:\Temp\$timestamp\secpol_$timestamp.cfg"
$reportPath = "C:\Temp\$timestamp\PolicyReport_$timestamp.html"

# Create directory for storing backups and reports
if (-not (Test-Path "C:\Temp\$timestamp")) {
    New-Item -Path "C:\Temp\$timestamp" -ItemType Directory | Out-Null
}

# Step 1: Export existing policies
Write-Output "Exporting existing policies..."
secedit /export /cfg $backupPath /quiet

# Step 2: Backup current policies
if (Test-Path $backupPath) {
    Copy-Item $backupPath $currentPolicyPath -Force
    Write-Output "Backup of existing policies saved to $backupPath"
} else {
    Write-Error "Failed to export existing policies. Exiting script."
    exit
}

# Step 3: Modify Internet Communication Policies
$policyUpdates = @(
    @{Parameter = 'Turn off downloading of print drivers over HTTP'; Key = "DisableHTTPPrinting"; Value = "1"},
    @{Parameter = 'Turn off the "Publish to Web" task for files and folders'; Key = "NoPublishingWizard"; Value = "1"},
    @{Parameter = 'Turn off Internet download for Web publishing and online ordering wizards'; Key = "NoOnlineOrdering"; Value = "1"},
    @{Parameter = 'Turn off printing over HTTP'; Key = "DisableHTTPPrinting"; Value = "1"},
    @{Parameter = 'Turn off Search Companion content file updates'; Key = "DisableContentUpdates"; Value = "1"},
    @{Parameter = 'Turn off the Windows Messenger Customer Experience Improvement Program'; Key = "CEIP"; Value = "1"},
    @{Parameter = 'Turn off Windows Customer Experience Improvement Program'; Key = "CEIPEnable"; Value = "0"},

    # Additional Security Settings
    @{Parameter = 'Registry policy processing'; Value = 'Enabled';},
    @{Parameter = 'Configure Offer Remote Assistance'; Value = 'Disabled';},
    @{Parameter = 'Configure Solicited Remote Assistance'; Value = 'Disabled';},
    @{Parameter = 'Turn off Autoplay'; Value = 'Enabled: All drives';},
    @{Parameter = 'Require trusted path for credential entry'; Value = 'Enabled';},
    @{Parameter = 'Disable remote Desktop Sharing'; Value = 'Enabled';},
    @{Parameter = 'Always use classic logon'; Value = 'Enabled';},
    @{Parameter = 'Prompt for password on resume from hibernate/suspend'; Value = 'Enabled';},
    @{Parameter = 'Screen Saver'; Value = 'Enabled';},
    @{Parameter = 'Screen Saver executable name'; Value = 'logon.scr';},
    @{Parameter = 'Password protect the screen saver'; Value = 'Enabled';},
    @{Parameter = 'Screen Saver timeout'; Value = '600 seconds or fewer';},

    # Additional Event Log settings
    @{Parameter = 'Application: Maximum Log File Size (KB)'; Value = '32768 KB or greater';},
    @{Parameter = 'Application: Retain old events'; Value = 'Disabled';},
    @{Parameter = 'Security: Maximum Log Size (KB)'; Value = '81920 KB or greater';},
    @{Parameter = 'Security: Retain old events'; Value = 'Disabled';},
    @{Parameter = 'System: Maximum Log Size (KB)'; Value = '32768 KB or greater';},
    @{Parameter = 'System: Retain old events'; Value = 'Disabled';},

    # Firewall settings
    @{Parameter = 'Windows Firewall: Firewall state (Public)'; Value = 'Off';},
    @{Parameter = 'Windows Firewall: Protect all network connections (Domain)'; Value = 'Off';},
    @{Parameter = 'Windows Firewall: Protect all network connections (Standard)'; Value = 'Off';},

    # Additional Security Configuration
    @{Parameter = 'Disable USB storage'; Value = 'Enabled';}
)

$existingPolicies = Get-Content $currentPolicyPath
$policyReport = @()

foreach ($policy in $policyUpdates) {
    $key = $policy.Key
    $value = $policy.Value
    $parameter = $policy.Parameter

    # Attempt to find the policy line
    $matchedLine = ($existingPolicies | Where-Object { $_ -match "^$key\s*=" }) -join ""

    if ($matchedLine) {
        $oldValue = $matchedLine.Split('=')[-1].Trim()
        if ($oldValue -ne $value) {
            # Update policy if the value is different
            $existingPolicies = $existingPolicies -replace "^$key\s*=.+", "$key = $value"
            $policyReport += @{
                Parameter = $parameter
                OldValue = $oldValue
                NewValue = $value
                Status = "Updated"
            }
        } else {
            $policyReport += @{
                Parameter = $parameter
                OldValue = $oldValue
                NewValue = $value
                Status = "Unchanged"
            }
        }
    } else {
        # If not found, log as "Not Defined"
        $policyReport += @{
            Parameter = $parameter
            OldValue = "Not Defined"
            NewValue = $value
            Status = "Added"
        }
        $existingPolicies += "$key = $value"
    }
}

# Save updated policies
Set-Content $currentPolicyPath $existingPolicies
Write-Output "Internet communication policies updated."

# Step 4: Apply the new policies
secedit /configure /db secedit_$timestamp.sdb /cfg $currentPolicyPath /quiet
Write-Output "New policies applied successfully."

# Step 5: Generate HTML Report
$reportContent = @"
<html>
<head>
    <title>Policy Update Report</title>
    <style>
        body { font-family: Arial; background-color: #f9f9f9; color: #333; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { border: 1px solid #ccc; padding: 10px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
    </style>
</head>
<body>
    <h1>Policy Update Report</h1>
    <table>
        <tr>
            <th>Policy</th>
            <th>Old Value</th>
            <th>New Value</th>
            <th>Status</th>
        </tr>
"@

foreach ($policy in $policyReport) {
    $reportContent += @"
        <tr>
            <td>$($policy.Parameter)</td>
            <td>$($policy.OldValue)</td>
            <td>$($policy.NewValue)</td>
            <td>$($policy.Status)</td>
        </tr>
"@
}

$reportContent += "</table></body></html>"
Set-Content $reportPath $reportContent
Write-Output "Policy report generated at $reportPath."

Write-Output "Script completed successfully."
