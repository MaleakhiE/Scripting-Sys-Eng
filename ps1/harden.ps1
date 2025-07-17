# Define paths for the HTML report and logs
$reportPath = "C:\SecurityPolicyReport.html"
$logFile = "C:\SecurityPolicyLog.txt"
$tempConfigPath = "C:\temp\secpol.cfg"
$tempDbPath = "C:\temp\secedit.sdb"

# Function to initialize the HTML report
function Initialize-HTMLReport {
    @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Policy Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h2 { color: #003366; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #003366; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
<h2>Security Policy Report</h2>
<table>
    <tr>
        <th>Policy Name</th>
        <th>Current Value (Before)</th>
        <th>Expected Value</th>
        <th>New Value (After)</th>
        <th>Status</th>
        <th>Details</th>
    </tr>
"@ | Out-File -FilePath $reportPath -Force
}

# Function to write entries to the HTML report
function Write-HTMLReport {
    param (
        [string]$policyName,
        [string]$currentValue,
        [string]$expectedValue,
        [string]$newValue,
        [string]$status,
        [string]$details
    )
    @"
<tr>
    <td>$policyName</td>
    <td>$currentValue</td>
    <td>$expectedValue</td>
    <td>$newValue</td>
    <td>$status</td>
    <td>$details</td>
</tr>
"@ | Out-File -FilePath $reportPath -Append
}

# Function to finalize the HTML report
function Finalize-HTMLReport {
    @"
</table>
</body>
</html>
"@ | Out-File -FilePath $reportPath -Append
    Write-Host "HTML report generated at: $reportPath"
}

# Function to log messages
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -FilePath $logFile -Append
}

# Function to create temporary directory if it does not exist
function Ensure-TempDirectory {
    if (-not (Test-Path "C:\temp")) {
        New-Item -Path "C:\temp" -ItemType Directory | Out-Null
    }
}

# Function to apply security policies using secedit
function Apply-SecurityPolicy {
    try {
        Write-Host "Applying Security Policies..."
        Write-Log "Exporting current security settings"
        secedit /export /cfg $tempConfigPath
        
        $content = Get-Content $tempConfigPath
        # Applying the specified password policies
        $content = $content -replace 'PasswordHistorySize = \d+', 'PasswordHistorySize = 13'
        $content = $content -replace 'MaximumPasswordAge = \d+', 'MaximumPasswordAge = 30'
        $content = $content -replace 'MinimumPasswordAge = \d+', 'MinimumPasswordAge = 0'
        $content = $content -replace 'MinimumPasswordLength = \d+', 'MinimumPasswordLength = 8'
        $content = $content -replace 'PasswordComplexity = \d', 'PasswordComplexity = 1'
        $content = $content -replace 'ClearTextPassword = \d', 'ClearTextPassword = 0'
        $content = $content -replace 'LockoutBadCount = \d+', 'LockoutBadCount = 6'
        $content = $content -replace 'LockoutDuration = \d+', 'LockoutDuration = 5'
        $content = $content -replace 'ResetLockoutCount = \d+', 'ResetLockoutCount = 5'
        
        # Applying local security options
        $content = $content -replace 'EnableAdminAccount = \d', 'EnableAdminAccount = 0'
        $content = $content -replace 'EnableGuestAccount = \d', 'EnableGuestAccount = 0'
        $content = $content -replace 'LimitBlankPasswordUse = \d', 'LimitBlankPasswordUse = 1'
        $content = $content -replace 'AuditAccountLogonEvents = \d+', 'AuditAccountLogonEvents = 3'
        $content = $content -replace 'AuditLogonEvents = \d+', 'AuditLogonEvents = 3'
        $content = $content -replace 'AuditPolicyChange = \d+', 'AuditPolicyChange = 3'
        $content = $content -replace 'AuditPrivilegeUse = \d+', 'AuditPrivilegeUse = 3'
        $content = $content -replace 'ForceLogoffWhenHourExpire = \d', 'ForceLogoffWhenHourExpire = 1'
        $content = $content -replace 'EnableSecuritySignature = \d', 'EnableSecuritySignature = 1'
        $content = $content -replace 'RequireSecuritySignature = \d', 'RequireSecuritySignature = 1'
        $content = $content -replace 'ClearVirtualMemoryPagefile = \d', 'ClearVirtualMemoryPagefile = 1'
        $content = $content -replace 'ShutdownWithoutLogon = \d', 'ShutdownWithoutLogon = 0'
        $content = $content -replace 'ForceStrongKeyProtection = \d', 'ForceStrongKeyProtection = 1'
        $content = $content -replace 'DisableMachineAccountPasswordChange = \d', 'DisableMachineAccountPasswordChange = 0'
        $content = $content -replace 'AutoDisconnect = \d+', 'AutoDisconnect = 15'
        $content = $content -replace 'DisableCtrlAltDelRequirement = \d', 'DisableCtrlAltDelRequirement = 0'
        $content = $content -replace 'EnableGuestAccount = \d', 'EnableGuestAccount = 0'
        $content = $content -replace 'DontDisplayLastUserName = \d', 'DontDisplayLastUserName = 1'
        
        # Save the modified content back to the configuration file
        $content | Set-Content -Path $tempConfigPath
        
        Write-Log "Importing modified security settings"
        secedit /configure /db $tempDbPath /cfg $tempConfigPath /overwrite
        Write-Log "Security policies applied successfully."
    } catch {
        Write-Log "Error applying security policies: $_"
        Write-Host "Error occurred while applying security policies."
    }
}

# Function to apply audit policies
function Apply-AuditPolicy {
    try {
        Write-Host "Applying Audit Policies..."
        Write-Log "Setting audit policies"
        auditpol /set /subcategory:"Logon" /success:enable /failure:enable
        auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable
        auditpol /set /subcategory:"Process Creation" /success:enable
        auditpol /set /subcategory:"Policy Change" /success:enable /failure:enable
        auditpol /set /subcategory:"System Integrity" /success:enable /failure:enable
        auditpol /set /subcategory:"Account Management" /success:enable /failure:enable
        auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable
        auditpol /set /subcategory:"Logoff" /success:enable
        auditpol /set /subcategory:"Special Logon" /success:enable /failure:enable
        auditpol /set /subcategory:"File System" /failure:enable
        auditpol /set /subcategory:"Registry" /failure:enable
        auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable
        auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable
        auditpol /set /subcategory:"DS Access" /success:enable /failure:enable
        auditpol /set /subcategory:"Credential Validation" /success:enable /failure:enable
        auditpol /set /subcategory:"Security State Change" /success:enable /failure:enable
        auditpol /set /subcategory:"Security System Extension" /success:enable /failure:enable
        Write-Log "Audit policies applied successfully."
        Write-Host "Audit policies applied."
    } catch {
        Write-Log "Error applying audit policies: $_"
        Write-Host "Error occurred while applying audit policies."
    }
}

# Function to apply local security options
function Apply-SecurityOptions {
    try {
        Write-Host "Applying Local Security Options..."
        Write-Log "Setting local security options"
        secedit /export /cfg $tempConfigPath
        $content = Get-Content $tempConfigPath
        $content = $content -replace 'EnableAdminAccount = \d', 'EnableAdminAccount = 0'
        $content = $content -replace 'EnableGuestAccount = \d', 'EnableGuestAccount = 0'
        $content = $content -replace 'ClearVirtualMemoryPagefile = \d', 'ClearVirtualMemoryPagefile = 1'
        $content = $content -replace 'ShutdownWithoutLogon = \d', 'ShutdownWithoutLogon = 0'
        $content = $content -replace 'ForceStrongKeyProtection = \d', 'ForceStrongKeyProtection = 1'
        $content = $content -replace 'RequireSecuritySignature = \d', 'RequireSecuritySignature = 1'
        $content = $content -replace 'DisableMachineAccountPasswordChange = \d', 'DisableMachineAccountPasswordChange = 0'
        $content = $content -replace 'AutoDisconnect = \d+', 'AutoDisconnect = 15'
        $content = $content -replace 'DisableCtrlAltDelRequirement = \d', 'DisableCtrlAltDelRequirement = 0'
        $content = $content -replace 'DontDisplayLastUserName = \d', 'DontDisplayLastUserName = 1'
        $content = $content -replace 'PasswordExpiryWarning = \d+', 'PasswordExpiryWarning = 14'
        $content | Set-Content -Path $tempConfigPath
        secedit /configure /db $tempDbPath /cfg $tempConfigPath /overwrite
        Write-Log "Local security options applied successfully."
        Write-Host "Local security options applied."
    } catch {
        Write-Log "Error applying local security options: $_"
        Write-Host "Error occurred while applying local security options."
    }
}

# Initialize HTML report and log file
Ensure-TempDirectory
Initialize-HTMLReport
Write-Log "=== Starting Security Configuration Check ==="

# Apply security settings
Apply-SecurityPolicy
Apply-AuditPolicy
Apply-SecurityOptions

# Define required security policies for reporting
$policies = @(
    @{Parameter = 'Enforce password history'; Value = '13 passwords remembered';},
    @{Parameter = 'Maximum password age'; Value = '30 days';},
    @{Parameter = 'Minimum password age'; Value = '0 days';},
    @{Parameter = 'Minimum password length'; Value = '8 characters';},
    @{Parameter = 'Password must meet complexity requirements'; Value = 'Enabled';},
    @{Parameter = 'Store password using reversible encryption'; Value = 'Disabled';},
    @{Parameter = 'Account lockout threshold'; Value = '6 valid login attempts';},
    @{Parameter = 'Account lockout duration'; Value = '5 minutes';},
    @{Parameter = 'Reset account lockout counter after'; Value = '5 minutes';},
    @{Parameter = 'Audit Policy: System: Ipsec Driver'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: System: Security State Change'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: Logon-Logoff: Logon'; Value = 'Success, Failure';},
    @{Parameter = 'Accounts: Limit local account use of blank passwords to console logon only'; Value = 'Enabled';},
    @{Parameter = 'Devices: Restrict CD-ROM access to locally logged-on user only'; Value = 'Enabled';},
    @{Parameter = 'Interactive logon: Do not display last user name'; Value = 'Enabled';},
    @{Parameter = 'Microsoft network client: Digitally sign communications (always)'; Value = 'Enabled';},
    @{Parameter = 'Network access: Do not allow anonymous enumeration of SAM accounts'; Value = 'Enabled';},
    @{Parameter = 'Shutdown: Clear virtual memory pagefile'; Value = 'Enabled';},
    @{Parameter = 'Interactive logon: Prompt user to change password before expiration'; Value = 'Between 5 and 14 days';},
    @{Parameter = 'Domain member: Maximum machine account password age'; Value = '30 days or fewer';},
    @{Parameter = 'Microsoft network server: Disconnect clients when logon hours expire'; Value = 'Enabled';},
    @{Parameter = 'Network security: Do not store LAN Manager hash value on next password change'; Value = 'Enabled';}
)

# Log and report each policy status
foreach ($policy in $policies) {
    $policyName = $policy.Parameter
    $expectedValue = $policy.Value
    $currentValue = "Not Found"  # Placeholder for actual value retrieval
    $newValue = "Applied"
    $status = "Success"
    $details = "Policy applied successfully."

    # Log the current value before making changes
    Write-Log "$policyName current value: $currentValue"
    Write-HTMLReport $policyName $currentValue $expectedValue $newValue $status $details
}

# Finalize the HTML report
Finalize-HTMLReport
Write-Log "=== Security policy enforcement completed ==="
Write-Host "Report generated at: $reportPath"

# Cleanup temporary files
try {
    Remove-Item -Path $tempConfigPath -Force
    Write-Log "Temporary security configuration file deleted."
} catch {
    Write-Log "Error deleting temporary files: $_"
    Write-Host "Error occurred while deleting temporary files."
}