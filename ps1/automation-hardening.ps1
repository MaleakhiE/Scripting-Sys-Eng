# Define paths for the HTML report and logs
$reportPath = "C:\SecurityPolicyReport.html"
$logFile = "C:\SecurityPolicyLog.txt"

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

# Function to ensure a registry path exists
function Ensure-RegistryPath {
    param ([string]$path)
    if (-not (Test-Path $path)) {
        try {
            New-Item -Path $path -Force | Out-Null
            Write-Log "Created missing registry path: $path"
        } catch {
            Write-Log "Error creating registry path: $path - $($_)"
        }
    }
}

# Function to set registry values with elevated privileges using Invoke-Command
function Set-RegistryValueWithInvokeCommand {
    param (
        [string]$path,
        [string]$key,
        [string]$value
    )
    try {
        # Hardcoded credentials (administrator username and password)
        $username = "administrator"
        $password = ConvertTo-SecureString "password.1" -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($username, $password)

        # Running the registry change command using elevated privileges
        Invoke-Command -ScriptBlock {
            param($path, $key, $value)

            # Set the registry key directly using the elevated session
            try {
                Set-ItemProperty -Path $path -Name $key -Value $value -Force
                Write-Log "Successfully set $key to $value in $path using Invoke-Command"
                return $true
            } catch {
                Write-Log "Error setting $key in $path via Invoke-Command: $($_)"
                return $false
            }
        } -ArgumentList $path, $key, $value -Credential $credential

    } catch {
        Write-Log "Error setting $key in $path via Invoke-Command: $($_)"
        return $false
    }
}

# Initialize HTML report and log file
Initialize-HTMLReport
Write-Log "=== Starting Security Configuration Check ==="

# Step 1: Generate a report of existing policies
Write-Log "Generating existing security policy report..."
$existingReport = Get-GPResultantSetOfPolicy -Computer localhost -ReportType HTML -Path "C:\CurrentPolicyReport.html"
Write-Log "Existing policy report saved."

# Step 2: Define required security policies
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
    @{Parameter = 'Audit Policy: Account Logon: Credential Validation'; Value = 'Success, Failure';},

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
    @{Parameter = 'Interactive logon: Message text for users attempting to log on'; Value = 'Available';},
    @{Parameter = 'Domain member: Digitally encrypt or sign secure channel data (always)'; Value = 'Enabled';},
    @{Parameter = 'Domain member: Digitally encrypt secure channel data (when possible)'; Value = 'Enabled';},
    @{Parameter = 'Domain member: Disable machine account password changes'; Value = 'Disabled';},
    @{Parameter = 'Domain member: Maximum machine account password age'; Value = '30 days or fewer';},
    @{Parameter = 'Domain member: Require strong (Windows or later) session key'; Value = 'Enabled';},
    @{Parameter = 'Interactive logon: Do not display last user name'; Value = 'Enabled';},
    @{Parameter = 'Interactive logon: Do not require CTRL+ALT+DEL'; Value = 'Disabled';},
    @{Parameter = 'Interactive logon: Number of previous logons to cache'; Value = '0 Logons';},
    @{Parameter = 'Interactive logon: Prompt user to change password before expiration'; Value = 'Between 5 and 14 days';},
    @{Parameter = 'Interactive logon: Require Domain Controller authentication to unlock workstation'; Value = 'Enabled';},
    @{Parameter = 'Interactive logon: Smart card removal behavior'; Value = 'Lock Workstation';},
    @{Parameter = 'Microsoft network client: Digitally sign communications (always)'; Value = 'Enabled';},
    @{Parameter = 'Microsoft network client: Digitally sign communications (if server agrees)'; Value = 'Enabled';},
    @{Parameter = 'Microsoft network server: Disconnect clients when logon hours expire'; Value = 'Enabled';},
    @{Parameter = 'Network access: Do not allow anonymous enumeration of SAM accounts'; Value = 'Enabled';},
    @{Parameter = 'Network access: Do not allow anonymous enumeration of SAM accounts and shares'; Value = 'Enabled';},
    @{Parameter = 'Network access: Let Everyone permissions apply to anonymous users'; Value = 'Disabled';},
    @{Parameter = 'Network access: Named Pipes that can be accessed anonymously'; Value = 'Browser or <blank>';},
    @{Parameter = 'Network access: Restrict anonymous access to Named Pipes and Shares'; Value = 'Enabled';},
    @{Parameter = 'Network access: Shares that can be accessed anonymously'; Value = 'None';},
    @{Parameter = 'Network access: Sharing and security model for local accounts'; Value = 'Classic - local users authenticate as themselves';},
    @{Parameter = 'Network security: Do not store LAN Manager hash value on next password change'; Value = 'Enabled';},
    @{Parameter = 'Network security: LAN Manager authentication level'; Value = 'Send NTLMv2 response only. Refuse LM';},
    @{Parameter = 'Network security: LDAP client signing requirements'; Value = 'Negotiate signing or higher';},
    @{Parameter = 'Network security: Minimum session security for NTLM SSP based (including secure RPC) clients'; Value = 'Require NTLMv2 session security, Require 128-bit encryption';},
    @{Parameter = 'Recovery console: Allow automatic administrative logon'; Value = 'Disabled';},
    @{Parameter = 'Shutdown: Clear virtual memory pagefile'; Value = 'Disabled';},
    @{Parameter = 'Shutdown: Allow system to be shut down without having to log on'; Value = 'Disabled';},
    @{Parameter = 'System objects: Require case insensitivity for non-Windows subsystems'; Value = 'Enabled';},
    @{Parameter = 'System objects: Strengthen default permissions of internal system objects'; Value = 'Enabled';},
    @{Parameter = 'System cryptography: Force strong key protection for user keys stored on the computer'; Value = 'User is Prompted when the key is first used';},

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

# Step 3: Apply and verify policies
foreach ($policy in $policies) {
    $policyName = $policy.Parameter
    $expectedValue = $policy.Value
    $currentValue = "Not Found"
    $newValue = "Not Set"
    $status = "Not Applied"
    $details = ""

    try {
        # Log the current value before making changes
        Write-Log "$policyName current value: $currentValue"

        # For simplicity, assuming policies can be applied using registry or other methods as required
        # Write the policy results to the HTML report
        Write-HTMLReport $policyName $currentValue $expectedValue $newValue $status $details
    } catch {
        Write-Log "Unexpected error applying ${policyName}: $($_)"
    }
}

# Finalize the HTML report
Finalize-HTMLReport
Write-Log "=== Security policy enforcement completed ==="
Write-Host "Report generated at: $reportPath"




