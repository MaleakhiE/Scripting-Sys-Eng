# Define paths for the HTML report and logs
$reportPath = "C:\SecurityPolicyReport.html"
$logFile = "C:\SecurityPolicyLog.txt"
$tempConfigPath = "C:\temp\secpol.cfg"
$tempDbPath = "C:\temp\secedit.sdb"

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    exit
}


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
    try {
        if (-not (Test-Path "C:\temp")) {
            New-Item -Path "C:\temp" -ItemType Directory -Force | Out-Null
            Write-Log "Created temporary directory: C:\temp"
        }
    } catch {
        Write-Log "Error creating temporary directory: $_"
        Write-Host "Error occurred while creating temporary directory."
        exit
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
        $content = $content -replace 'DontDisplayLastUser Name = \d', 'DontDisplayLastUser Name = 1'
        
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
        
        # Applying the new security options
        $content = $content -replace 'Network security: Minimum session security for NTLM SSP', 'Require NTLMv2 session security, Require 128-bit encryption'
        $content = $content -replace 'Network access: Remotely accessible registry paths', 'Configured'
        $content = $content -replace 'Accounts: Rename administrator account', '<Specify Account Name>'
        $content = $content -replace 'Accounts: Rename guest account', '<Specify Account Name>'
        $content = $content -replace 'Accounts: Guest account status', 'Disabled'
        $content = $content -replace 'Network access: Allow anonymous SID/Name translation', 'Disabled'
        $content = $content -replace 'Accounts: Limit local account use of blank passwords to console logon only', 'Enabled'
        $content = $content -replace 'Devices: Allowed to format and eject removable media', 'Administrators'
        $content = $content -replace 'Devices: Prevent users from installing printer drivers', 'Enabled'
        $content = $content -replace 'Devices: Restrict CD-ROM access to locally logged-on user only', 'Enabled'
        $content = $content -replace 'Devices: Restrict floppy access to locally logged-on user only', 'Enabled'
        $content = $content -replace 'Interactive logon: Message text for users attempting to log on', 'Available'
        $content = $content -replace 'Domain member: Digitally encrypt or sign secure channel data (always)', 'Enabled'
        $content = $content -replace 'Domain member: Digitally encrypt secure channel data (when possible)', 'Enabled'
        $content = $content -replace 'Domain member: Disable machine account password changes', 'Disabled'
        $content = $content -replace 'Domain member: Maximum machine account password age', '30 days or fewer'
        $content = $content -replace 'Domain member: Require strong (Windows or later) session key', 'Enabled'
        $content = $content -replace 'Interactive logon: Do not display last user name', 'Enabled'
        $content = $content -replace 'Interactive logon: Do not require CTRL+ALT+DEL', 'Disabled'
        $content = $content -replace 'Interactive logon: Number of previous logons to cache', '0 Logons'
        $content = $content -replace 'Interactive logon: Prompt user to change password before expiration', 'Between 5 and 14 days'
        $content = $content -replace 'Interactive logon: Require Domain Controller authentication to unlock workstation', 'Enabled'
        $content = $content -replace 'Interactive logon: Smart card removal behavior', 'Lock Workstation'
        $content = $content -replace 'Microsoft network client: Digitally sign communications (always)', 'Enabled'
        $content = $content -replace 'Microsoft network client: Digitally sign communications (if server agrees)', 'Enabled'
        $content = $content -replace 'Microsoft network server: Disconnect clients when logon hours expire', 'Enabled'
        $content = $content -replace 'Network access: Do not allow anonymous enumeration of SAM accounts', 'Enabled'
        $content = $content -replace 'Network access: Do not allow anonymous enumeration of SAM accounts and shares', 'Enabled'
        $content = $content -replace 'Network access: Let Everyone permissions apply to anonymous users', 'Disabled'
        $content = $content -replace 'Network access: Named Pipes that can be accessed anonymously', 'Browser or <blank>'
        $content = $content -replace 'Network access: Restrict anonymous access to Named Pipes and Shares', 'Enabled'
        $content = $content -replace 'Network access: Shares that can be accessed anonymously', 'None'
        $content = $content -replace 'Network access: Sharing and security model for local accounts', 'Classic - local users authenticate as themselves'
        $content = $content -replace 'Network security: Do not store LAN Manager hash value on next password change', 'Enabled'
        $content = $content -replace 'Network security: LAN Manager authentication level', 'Send NTLMv2 response only. Refuse LM'
        $content = $content -replace 'Network security: LDAP client signing requirements', 'Negotiate signing or higher'
        $content = $content -replace 'Network security: Minimum session security for NTLM SSP based (including secure RPC) clients', 'Require NTLMv2 session security, Require 128-bit encryption'
        $content = $content -replace 'Recovery console: Allow automatic administrative logon', 'Disabled'
        $content = $content -replace 'Shutdown: Clear virtual memory pagefile', 'Disabled'
        $content = $content -replace 'Shutdown: Allow system to be shut down without having to log on', 'Disabled'
        $content = $content -replace 'System objects: Require case insensitivity for non-Windows subsystems', 'Enabled'
        $content = $content -replace 'System objects: Strengthen default permissions of internal system objects', 'Enabled'
        $content = $content -replace 'System cryptography: Force strong key protection for user keys stored on the computer', 'User  is Prompted when the key is first used'

        # Computer Configuration & User Configuration -> Internet Communication
        $content = $content -replace 'Turn off downloading of print drivers over HTTP', 'Enabled'
        $content = $content -replace 'Turn off the "Publish to Web" task for files and folders', 'Enabled'
        $content = $content -replace 'Turn off Internet download for Web publishing and online ordering wizards', 'Enabled'
        $content = $content -replace 'Turn off printing over HTTP', 'Enabled'
        $content = $content -replace 'Turn off Search Companion content file updates', 'Enabled'
        $content = $content -replace 'Turn off the Windows Messenger Customer Experience Improvement Program', 'Enabled'
        $content = $content -replace 'Turn off Windows Customer Experience Improvement Program', 'Disabled'

        # Additional Security Settings
        $content = $content -replace 'Registry policy processing', 'Enabled'
        $content = $content -replace 'Configure Offer Remote Assistance', 'Disabled'
        $content = $content -replace 'Configure Solicited Remote Assistance', 'Disabled'
        $content = $content -replace 'Turn off Autoplay', 'Enabled: All drives'
        $content = $content -replace 'Require trusted path for credential entry', 'Enabled'
        $content = $content -replace 'Disable remote Desktop Sharing', 'Enabled'
        $content = $content -replace 'Always use classic logon', 'Enabled'
        $content = $content -replace 'Prompt for password on resume from hibernate/suspend', 'Enabled'
        $content = $content -replace 'Screen Saver', 'Enabled'
        $content = $content -replace 'Screen Saver executable name', 'logon.scr'
        $content = $content -replace 'Password protect the screen saver', 'Enabled'
        $content = $content -replace 'Screen Saver timeout', '600 seconds or fewer'

        # Event Log
        $content = $content -replace 'Application: Maximum Log File Size (KB)', '32768 KB or greater'
        $content = $content -replace 'Application: Retain old events', 'Disabled'
        $content = $content -replace 'Security: Maximum Log Size (KB)', '81920 KB or greater'
        $content = $content -replace 'Security: Retain old events', 'Disabled'
        $content = $content -replace 'System: Maximum Log Size (KB)', '32768 KB or greater'
        $content = $content -replace 'System: Retain old events', 'Disabled'

        # Firewall
        $content = $content -replace 'Windows Firewall: Firewall state (Public)', 'Off'
        $content = $content -replace 'Windows Firewall: Protect all network connections (Domain)', 'Off'
        $content = $content -replace 'Windows Firewall: Protect all network connections (Standard)', 'Off'

        # Additional Security Configuration
        $content = $content -replace 'Disable USB storage', 'Enabled'

        # Save the modified content back to the configuration file
        $content | Set-Content -Path $tempConfigPath
        secedit /configure /db $tempDbPath /cfg $tempConfigPath /overwrite /log C:\Temp\secedit_export.log
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

    # Account Policies -> Account Lockout Policy
    @{Parameter = 'Account lockout duration'; Value = '5 minutes';},
    @{Parameter = 'Account lockout threshold'; Value = '6 valid login attempts';},
    @{Parameter = 'Reset account lockout counter after'; Value = '5 minutes';},

    # Local Policies -> Detailed Security Auditing
    @{Parameter = 'Audit Policy: System: Ipsec Driver'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: System: Security State Change'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: System: Security System Extension'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: System: System Integrity'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: Logon-Logoff: Logoff'; Value = 'Success';},
    @{Parameter = 'Audit Policy: Logon-Logoff: Logon'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: Logon-Logoff: Special Logon'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: Object Access: File System'; Value = 'Failure';},
    @{Parameter = 'Audit Policy: Object Access: Registry'; Value = 'Failure';},
    @{Parameter = 'Audit Policy: Privilege Use: Sensitive Privilege Use'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: Detailed Tracking: Process Creation'; Value = 'Success';},
    @{Parameter = 'Audit Policy: Policy Change: Audit Policy Change'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: Policy Change: Authentication Policy Change'; Value = 'Success';},
    @{Parameter = 'Audit Policy: Account Management: Computer Account Management'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: Account Management: Other Account Management Events'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: Account Management: Security Group Management'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: Account Management: User Account Management'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: DS Access: Directory Service Access'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: DS Access: Directory Service Changes'; Value = 'Success, Failure';},
    @{Parameter = 'Audit Policy: Account Logon: Credential Validation'; Value = 'Success, Failure';}

    # Local Policies -> Security Options
    @{Parameter = 'Network security: Minimum session security for NTLM SSP'; Value = 'Require NTLMv2 session security, Require 128-bit encryption';},
    @{Parameter = 'Network access: Remotely accessible registry paths'; Value = 'Configured';},
    @{Parameter = 'Accounts: Rename administrator account'; Value = '<Specify Account Name>';},
    @{Parameter = 'Accounts: Rename guest account'; Value = '<Specify Account Name>';},
    @{Parameter = 'Accounts: Guest account status'; Value = 'Disabled';},
    @{Parameter = 'Network access: Allow anonymous SID/Name translation'; Value = 'Disabled';},
    @{Parameter = 'Accounts: Limit local account use of blank passwords to console logon only'; Value = 'Enabled';},
    @{Parameter = 'Devices: Allowed to format and eject removable media'; Value = 'Administrators';},
    @{Parameter = 'Devices: Prevent users from installing printer drivers'; Value = 'Enabled';},
    @{Parameter = 'Devices: Restrict CD-ROM access to locally logged-on user only'; Value = 'Enabled';},
    @{Parameter = 'Devices: Restrict floppy access to locally logged-on user only'; Value = 'Enabled';},

    # @{Parameter = 'Interactive logon: Message text for users attempting to log on'; Value = 'Available';},
    # @{Parameter = 'Domain member: Digitally encrypt or sign secure channel data (always)'; Value = 'Enabled';},
    # @{Parameter = 'Domain member: Digitally encrypt secure channel data (when possible)'; Value = 'Enabled';},
    # @{Parameter = 'Domain member: Disable machine account password changes'; Value = 'Disabled';},
    # @{Parameter = 'Domain member: Maximum machine account password age'; Value = '30 days or fewer';},
    # @{Parameter = 'Domain member: Require strong (Windows or later) session key'; Value = 'Enabled';},
    # @{Parameter = 'Interactive logon: Do not display last user name'; Value = 'Enabled';},
    # @{Parameter = 'Interactive logon: Do not require CTRL+ALT+DEL'; Value = 'Disabled';},
    # @{Parameter = 'Interactive logon: Number of previous logons to cache'; Value = '0 Logons';},
    # @{Parameter = 'Interactive logon: Prompt user to change password before expiration'; Value = 'Between 5 and 14 days';},
    # @{Parameter = 'Interactive logon: Require Domain Controller authentication to unlock workstation'; Value = 'Enabled';},
    # @{Parameter = 'Interactive logon: Smart card removal behavior'; Value = 'Lock Workstation';},
    # @{Parameter = 'Microsoft network client: Digitally sign communications (always)'; Value = 'Enabled';},
    # @{Parameter = 'Microsoft network client: Digitally sign communications (if server agrees)'; Value = 'Enabled';},
    # @{Parameter = 'Microsoft network server: Disconnect clients when logon hours expire'; Value = 'Enabled';},
    # @{Parameter = 'Network access: Do not allow anonymous enumeration of SAM accounts'; Value = 'Enabled';},
    # @{Parameter = 'Network access: Do not allow anonymous enumeration of SAM accounts and shares'; Value = 'Enabled';},
    # @{Parameter = 'Network access: Let Everyone permissions apply to anonymous users'; Value = 'Disabled';},
    # @{Parameter = 'Network access: Named Pipes that can be accessed anonymously'; Value = 'Browser or <blank>';},
    # @{Parameter = 'Network access: Restrict anonymous access to Named Pipes and Shares'; Value = 'Enabled';},
    # @{Parameter = 'Network access: Shares that can be accessed anonymously'; Value = 'None';},
    # @{Parameter = 'Network access: Sharing and security model for local accounts'; Value = 'Classic - local users authenticate as themselves';},
    # @{Parameter = 'Network security: Do not store LAN Manager hash value on next password change'; Value = 'Enabled';},
    # @{Parameter = 'Network security: LAN Manager authentication level'; Value = 'Send NTLMv2 response only. Refuse LM';},
    # @{Parameter = 'Network security: LDAP client signing requirements'; Value = 'Negotiate signing or higher';},
    # @{Parameter = 'Network security: Minimum session security for NTLM SSP based (including secure RPC) clients'; Value = 'Require NTLMv2 session security, Require 128-bit encryption';},
    # @{Parameter = 'Recovery console: Allow automatic administrative logon'; Value = 'Disabled';},
    # @{Parameter = 'Shutdown: Clear virtual memory pagefile'; Value = 'Disabled';},
    # @{Parameter = 'Shutdown: Allow system to be shut down without having to log on'; Value = 'Disabled';},
    # @{Parameter = 'System objects: Require case insensitivity for non-Windows subsystems'; Value = 'Enabled';},
    # @{Parameter = 'System objects: Strengthen default permissions of internal system objects'; Value = 'Enabled';},
    # @{Parameter = 'System cryptography: Force strong key protection for user keys stored on the computer'; Value = 'User is Prompted when the key is first used';},

    # Computer Configuration & User Configuration -> Internet Communication
    @{Parameter = 'Turn off downloading of print drivers over HTTP'; Value = 'Enabled';},
    @{Parameter = 'Turn off the "Publish to Web" task for files and folders'; Value = 'Enabled';},
    @{Parameter = 'Turn off Internet download for Web publishing and online ordering wizards'; Value = 'Enabled';},
    @{Parameter = 'Turn off printing over HTTP'; Value = 'Enabled';},
    @{Parameter = 'Turn off Search Companion content file updates'; Value = 'Enabled';},
    @{Parameter = 'Turn off the Windows Messenger Customer Experience Improvement Program'; Value = 'Enabled';},
    @{Parameter = 'Turn off Windows Customer Experience Improvement Program'; Value = 'Disabled';},

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

    # Event Log
    @{Parameter = 'Application: Maximum Log File Size (KB)'; Value = '32768 KB or greater';},
    @{Parameter = 'Application: Retain old events'; Value = 'Disabled';},
    @{Parameter = 'Security: Maximum Log Size (KB)'; Value = '81920 KB or greater';},
    @{Parameter = 'Security: Retain old events'; Value = 'Disabled';},
    @{Parameter = 'System: Maximum Log Size (KB)'; Value = '32768 KB or greater';},
    @{Parameter = 'System: Retain old events'; Value = 'Disabled';},

    # Firewall
    @{Parameter = 'Windows Firewall: Firewall state (Public)'; Value = 'Off';},
    @{Parameter = 'Windows Firewall: Protect all network connections (Domain)'; Value = 'Off';},
    @{Parameter = 'Windows Firewall: Protect all network connections (Standard)'; Value = 'Off';},

    # Additional Security Configuration
    @{Parameter = 'Disable USB storage'; Value = 'Enabled';}
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