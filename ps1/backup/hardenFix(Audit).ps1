# Restore
# AuditPol /restore /file:"C:\Temp\<your-backup-path>.csv"
# Get existing audit policies
# AuditPol /get /category:* | Out-String

# Script to Backup, Apply, and Generate Policy Report for Audit Policies

# Define Paths
$timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$backupPath = "C:\Temp\$timestamp\AuditPolicyBackup_$timestamp.csv"
$reportPath = "C:\Temp\$timestamp\AuditPolicyReport_$timestamp.html"

if (-not (Test-Path "C:\Temp\$timestamp")) {
    New-Item -Path "C:\Temp\$timestamp" -ItemType Directory | Out-Null
}

# Function to Log Messages
function Write-Log {
    param ([string]$Message)
    Write-Output "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $Message"
}

# Step 1: Backup Existing Audit Policies (in restorable format)
Write-Log "Backing up existing audit policies..."
AuditPol /backup /file:$backupPath
if (Test-Path $backupPath) {
    Write-Log "Backup created at $backupPath."
} else {
    Write-Log "Failed to create backup."
    exit 1
}

# Step 2: Retrieve Existing Audit Policies for Comparison
function Get-ExistingAuditPolicies {
    Write-Log "Retrieving existing audit policies..."
    $output = AuditPol /get /category:* | Out-String
    $existingPolicies = @()
    $currentCategory = ""

    foreach ($line in $output -split "`n") {
        if ($line -match "^\s*([^\s].*):$") {
            # Match Category header (e.g., "System")
            $currentCategory = $matches[1]
        } elseif ($line -match "^\s{2}(.+?)\s{2,}(.+)$") {
            # Match Subcategory and Setting (e.g., "Logon - Success and Fail")
            $subcategory = $matches[1].Trim()
            $setting = $matches[2].Trim()
            $existingPolicies += @{
                Category = $currentCategory
                Subcategory = $subcategory
                Setting = $setting
            }
        }
    }

    Write-Log "Existing audit policies retrieved."
    return $existingPolicies
}

$existingPolicies = Get-ExistingAuditPolicies

# Step 3: Apply Advanced Audit Policies
Write-Log "Applying advanced audit policies..."
$auditPoliciesApplied = @()

$desiredPolicies = @(
    @{Subcategory = "IPsec Driver"; Setting = "Success and Failure"},
    @{Subcategory = "Security State Change"; Setting = "Success and Failure"},
    @{Subcategory = "Security System Extension"; Setting = "Success and Failure"},
    @{Subcategory = "System Integrity"; Setting = "Success and Failure"},
    @{Subcategory = "Logoff"; Setting = "Success"},
    @{Subcategory = "Logon"; Setting = "Success and Failure"},
    @{Subcategory = "Special Logon"; Setting = "Success and Failure"},
    @{Subcategory = "File System"; Setting = "Failure"},
    @{Subcategory = "Registry"; Setting = "Failure"},
    @{Subcategory = "Sensitive Privilege Use"; Setting = "Success and Failure"},
    @{Subcategory = "Process Creation"; Setting = "Success"},
    @{Subcategory = "Audit Policy Change"; Setting = "Success and Failure"},
    @{Subcategory = "Authentication Policy Change"; Setting = "Success"},
    @{Subcategory = "Computer Account Management"; Setting = "Success and Failure"},
    @{Subcategory = "Other Account Management Events"; Setting = "Success and Failure"},
    @{Subcategory = "Security Group Management"; Setting = "Success and Failure"},
    @{Subcategory = "User Account Management"; Setting = "Success and Failure"},
    @{Subcategory = "Directory Service Access"; Setting = "Success and Failure"},
    @{Subcategory = "Directory Service Changes"; Setting = "Success and Failure"},
    @{Subcategory = "Credential Validation"; Setting = "Success and Failure"}
)

foreach ($policy in $desiredPolicies) {
    $existing = $existingPolicies | Where-Object { $_.Subcategory -eq $policy.Subcategory }
    $oldSetting = if ($existing) { $existing.Setting } else { "Not Configured" }
    $newSetting = $policy.Setting
    $status = ""

    if ($existing -and $oldSetting -eq $newSetting) {
        $status = "Already Applied"
    } else {
        $success = "Disable"
        $failure = "Disable"
        if ($newSetting -match "Success") { $success = "Enable" }
        if ($newSetting -match "Failure") { $failure = "Enable" }
        AuditPol /set /subcategory:"$($policy.Subcategory)" /success:$success /failure:$failure
        $status = "Applied"
    }

    $auditPoliciesApplied += @{
        Category = if ($existing) { $existing.Category } else { "Unknown" }
        Subcategory = $policy.Subcategory
        OldSetting = $oldSetting
        NewSetting = $newSetting
        Status = $status
    }
}

# Step 4: Generate HTML Report
Write-Log "Generating HTML report..."

$reportContent = @"
<html>
<head>
    <title>Audit Policy Report</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background-color: #f9f9f9;
            color: #333;
        }
        h1 {
            text-align: center;
            color: #4CAF50;
        }
        table {
            width: 90%;
            margin: 20px auto;
            border-collapse: collapse;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border: 1px solid #ddd;
        }
        th {
            background-color: #4CAF50;
            color: white;
        }
        tr:nth-child(even) {
            background-color: #f2f2f2;
        }
        tr:hover {
            background-color: #f1f1f1;
        }
        .status-applied {
            color: #4CAF50;
            font-weight: bold;
        }
        .status-already-applied {
            color: #FF9800;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <h1>Audit Policy Report</h1>
    <h2>Before and After Comparison</h2>
    <table>
        <tr>
            <th>Subcategory</th>
            <th>Old Setting</th>
            <th>New Setting</th>
            <th>Status</th>
        </tr>
"@

foreach ($policy in $auditPoliciesApplied) {
    $statusClass = if ($policy.Status -eq "Applied") { "status-applied" } else { "status-already-applied" }

    $reportContent += @"
        <tr>
            <td>$($policy.Subcategory)</td>
            <td>$($policy.OldSetting)</td>
            <td>$($policy.NewSetting)</td>
            <td class='$statusClass'>$($policy.Status)</td>
        </tr>
"@
}

$reportContent += @"
    </table>
</body>
</html>
"@

Set-Content $reportPath $reportContent
Write-Log "Report generated at $reportPath."

Write-Log "Script completed successfully!"
