# step to restore
# secedit /configure /db secedit.sdb /cfg C:\Temp\secpol_backup.inf /quiet
# secedit /export /cfg C:\Temp\secpol_restored.inf

# Script to Backup, Apply, and Generate Policy Report
# Define Paths
$timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$backupPath = "C:\Temp\$timestamp\secpol_backup_$timestamp.inf"
$currentPolicyPath = "C:\Temp\$timestamp\secpol_$timestamp.cfg"
$reportPath = "C:\Temp\$timestamp\PolicyReport_$timestamp.html"

if (-not (Test-Path "C:\Temp\$timestamp")) {
    New-Item -Path "C:\Temp\$timestamp" -ItemType Directory | Out-Null
}


# Step 1: Export existing policies
Write-Output "Exporting existing policies..."
secedit /export /cfg $backupPath /quiet

# Step 2: Read and backup current policies
if (Test-Path $backupPath) {
    Copy-Item $backupPath $currentPolicyPath -Force
    Write-Output "Backup of existing policies saved to $backupPath"
} else {
    Write-Error "Failed to export existing policies. Exiting script."
    exit
}

# Step 3: Modify Password Policies
$accountPolicies = @()
$existingPolicies = Get-Content $currentPolicyPath

# Define changes to password policies
$passwordPolicies = @{
    'PasswordHistorySize'  = '13'
    'MaximumPasswordAge'   = '30'
    'MinimumPasswordAge'   = '0'
    'MinimumPasswordLength' = '8'
}

# Apply changes to policies
foreach ($key in $passwordPolicies.Keys) {
    $oldValue = ($existingPolicies -match "$key = .+").Split('=')[-1].Trim()
    $newValue = $passwordPolicies[$key]
    if ($oldValue -ne $newValue) {
        $existingPolicies = $existingPolicies -replace "$key = .+", "$key = $newValue"
        $accountPolicies += @{
            Policy = $key
            OldValue = $oldValue
            NewValue = $newValue
            Status = "Updated"
        }
    } else {
        $accountPolicies += @{
            Policy = $key
            OldValue = $oldValue
            NewValue = $newValue
            Status = "Unchanged"
        }
    }
}

# Save modified policies
Set-Content $currentPolicyPath $existingPolicies
Write-Output "Password policies updated."

# Step 4: Apply the new policies
secedit /configure /db secedit_$timestamp.sdb /cfg $currentPolicyPath /quiet
Write-Output "New policies applied successfully."

# Step 5: Apply Account Lockout Policies
Write-Output "Applying account lockout policies..."
net accounts /lockoutthreshold:6
net accounts /lockoutduration:5
net accounts /lockoutwindow:5

$accountPolicies += @{
    Policy = "Account lockout threshold"
    OldValue = "N/A"
    NewValue = "6 valid login attempts"
    Status = "Applied"
}
$accountPolicies += @{
    Policy = "Account lockout duration"
    OldValue = "N/A"
    NewValue = "5 minutes"
    Status = "Applied"
}
$accountPolicies += @{
    Policy = "Reset account lockout counter after"
    OldValue = "N/A"
    NewValue = "5 minutes"
    Status = "Applied"
}

# Step 6: Generate HTML Report
$reportContent = @"
<html>
<head>
    <title>Policy Report</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
            background-color: #f9f9f9;
            color: #333;
        }
        h1 {
            text-align: center;
            color: #4CAF50;
            margin-top: 20px;
        }
        table {
            width: 90%;
            margin: 20px auto;
            border-collapse: collapse;
            box-shadow: 0 2px 5px rgba(0, 0, 0, 0.2);
            background-color: #fff;
        }
        th, td {
            padding: 12px;
            text-align: left;
        }
        th {
            background-color: #4CAF50;
            color: white;
            font-weight: bold;
            border-bottom: 2px solid #ddd;
        }
        td {
            border-bottom: 1px solid #ddd;
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
        .status-unchanged {
            color: #FF9800;
            font-weight: bold;
        }
        .footer {
            text-align: center;
            margin: 20px 0;
            font-size: 14px;
            color: #888;
        }
    </style>
</head>
<body>
    <h1>Policy Report</h1>
    <table>
        <tr>
            <th>Policy</th>
            <th>Old Value</th>
            <th>New Value</th>
            <th>Status</th>
        </tr>
"@

foreach ($policy in $accountPolicies) {
    $reportContent += @"
        <tr>
            <td>$($policy.Policy)</td>
            <td>$($policy.OldValue)</td>
            <td>$($policy.NewValue)</td>
            <td>$($policy.Status)</td>
        </tr>
"@
}

$reportContent += @"
    </table>
    <div class="footer">
        Report generated on <span id="current-date"></span>
    </div>

    <script>
        // Insert current date into the footer
        document.getElementById('current-date').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
"@

Set-Content $reportPath $reportContent
Write-Output "Policy report generated at $reportPath."

Write-Output "Script completed successfully!"
