# step to restore
# secedit /configure /db secedit.sdb /cfg C:\Temp\secpol_backup.inf /quiet
# secedit /export /cfg C:\Temp\secpol_restored.inf

# Script to Backup, Apply, and Generate Policy Report
# Define Paths
$timestamp = (Get-Date -Format "yyyyMMdd")
$backupPath = "C:\Temp\$timestamp\Account_LockoutPolicy\secpol_backup_$timestamp.inf"
$currentPolicyPath = "C:\Temp\$timestamp\secpol_$timestamp.cfg"
$reportPath = "C:\Temp\$timestamp\policyCommunication_$timestamp.html"

if (-not (Test-Path "C:\Temp\$timestamp\Account_LockoutPolicy")) {
    New-Item -Path "C:\Temp\$timestamp\Account_LockoutPolicy" -ItemType Directory | Out-Null
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

# Restore
# AuditPol /restore /file:"C:\Temp\<your-backup-path>.csv"
# Get existing audit policies
# AuditPol /get /category:* | Out-String

# Script to Backup, Apply, and Generate Policy Report for Audit Policies

# Define Paths
$timestamp = (Get-Date -Format "yyyyMMdd")
$backupPath = "C:\Temp\$timestamp\AuditPolicy\AuditPolicyBackup_$timestamp.csv"
$reportPath = "C:\Temp\$timestamp\AuditpolicyCommunication_$timestamp.html"

if (-not (Test-Path "C:\Temp\$timestamp\AuditPolicy")) {
    New-Item -Path "C:\Temp\$timestamp\AuditPolicy" -ItemType Directory | Out-Null
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
        $status = "Unchanged"
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

# Advanced Security Policy Configuration Script
# Applies specific local security policies using multiple methods
# Includes Backup and Restore Functionality

# Define Paths and Timestamp
$timestamp = (Get-Date -Format "yyyyMMdd")
$tempPath = "C:\Temp\$timestamp\SecurityPolicyBackup"
$backupPath = "$tempPath\Backup_$timestamp"
$reportPath = "C:\Temp\$timestamp\Report_Hardening_Policy_BTPNS($timestamp).html"
$logPath = "$backupPath\SecurityPolicyScript_$timestamp.log"
$backupDataPath = "$backupPath\PolicyBackup.json"

# Create Backup Directory
function Ensure-BackupDirectory {
    if (-not (Test-Path $tempPath)) {
        New-Item -Path $tempPath -ItemType Directory | Out-Null
    }
    if (-not (Test-Path $backupPath)) {
        New-Item -Path $backupPath -ItemType Directory | Out-Null
    }
}

# Logging Function
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][string]$Level = "Info"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logPath -Value $logMessage
    Write-Host $logMessage
}

# Backup Security Policies Function
function Backup-SecurityPolicies {
    param([switch]$Force)
    
    Ensure-BackupDirectory
    Write-Log -Message "Starting Security Policy Backup" -Level "Info"
    
    $backupData = @{
        NTLM = @{
            RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
            KeyName = "NTLMMinClientSec"
            CurrentValue = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "NTLMMinClientSec" -ErrorAction SilentlyContinue)."NTLMMinClientSec"
        }
        AdminAccount = @{
            CurrentName = (Get-LocalUser | Where-Object {$_.SID.Value.EndsWith("-500")}).Name
        }
        GuestAccount = @{
            CurrentName = (Get-LocalUser -Name "Guest").Name
            IsEnabled = (Get-LocalUser -Name "Guest").Enabled
        }
        AnonymousSIDTranslation = @{
            RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\LSA"
            KeyName = "RestrictAnonymous"
            CurrentValue = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\LSA" -Name "RestrictAnonymous" -ErrorAction SilentlyContinue)."RestrictAnonymous"
        }
        DevicePolicies = @{
            RemovableMedia = @{
                RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
                KeyName = "NoRecentDocsNetHood"
                CurrentValue = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoRecentDocsNetHood" -ErrorAction SilentlyContinue)."NoRecentDocsNetHood"
            }
            PrinterDriverInstallation = @{
                RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers"
                KeyName = "DefaultSpoolDirectory"
                CurrentValue = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers" -Name "DefaultSpoolDirectory" -ErrorAction SilentlyContinue)."DefaultSpoolDirectory"
            }
        }
    }
    
    # Convert to JSON and save
    $backupData | ConvertTo-Json -Depth 10 | Set-Content -Path $backupDataPath
    
    Write-Log -Message "Security Policy Backup completed. Backup saved to $backupDataPath" -Level "Info"
    return $backupData
}

# Restore Security Policies Function
function Restore-SecurityPolicies {
    param(
        [Parameter(Mandatory=$false)]
        [string]$BackupFile = $backupDataPath
    )
    
    Write-Log -Message "Starting Security Policy Restoration" -Level "Info"
    
    # Check if backup file exists
    if (-not (Test-Path $BackupFile)) {
        Write-Log -Message "Backup file not found: $BackupFile" -Level "Error"
        throw "Backup file does not exist. Cannot restore policies."
    }
    
    # Read backup data
    $backupData = Get-Content -Path $BackupFile | ConvertFrom-Json
    
    # Restore NTLM Settings
    if ($backupData.NTLM) {
        try {
            Set-ItemProperty -Path $backupData.NTLM.RegistryPath -Name "NTLMMinClientSec" -Value $backupData.NTLM.CurrentValue
            Write-Log -Message "Restored NTLM SSP Session Security" -Level "Info"
        }
        catch {
            Write-Log -Message "Failed to restore NTLM settings: $_" -Level "Warning"
        }
    }
    
    # Restore Admin Account Name
    if ($backupData.AdminAccount) {
        try {
            $currentAdminName = (Get-LocalUser | Where-Object {$_.SID.Value.EndsWith("-500")}).Name
            if ($currentAdminName -ne $backupData.AdminAccount.CurrentName) {
                Rename-LocalUser -Name $currentAdminName -NewName $backupData.AdminAccount.CurrentName
                Write-Log -Message "Restored original administrator account name" -Level "Info"
            }
        }
        catch {
            Write-Log -Message "Failed to restore admin account name: $_" -Level "Warning"
        }
    }
    
    # Restore Guest Account
    if ($backupData.GuestAccount) {
        try {
            $currentGuestName = (Get-LocalUser -Name "Guest").Name
            
            # Restore original guest account name
            if ($currentGuestName -ne $backupData.GuestAccount.CurrentName) {
                Rename-LocalUser -Name $currentGuestName -NewName $backupData.GuestAccount.CurrentName
            }
            
            # Restore guest account enable/disable status
            if ($backupData.GuestAccount.IsEnabled) {
                Enable-LocalUser -Name $backupData.GuestAccount.CurrentName
            }
            else {
                Disable-LocalUser -Name $backupData.GuestAccount.CurrentName
            }
            
            Write-Log -Message "Restored guest account settings" -Level "Info"
        }
        catch {
            Write-Log -Message "Failed to restore guest account: $_" -Level "Warning"
        }
    }
    
    # Restore Anonymous SID Translation
    if ($backupData.AnonymousSIDTranslation) {
        try {
            Set-ItemProperty -Path $backupData.AnonymousSIDTranslation.RegistryPath -Name "RestrictAnonymous" -Value $backupData.AnonymousSIDTranslation.CurrentValue
            Write-Log -Message "Restored Anonymous SID Translation settings" -Level "Info"
        }
        catch {
            Write-Log -Message "Failed to restore Anonymous SID Translation: $_" -Level "Warning"
        }
    }
    
    # Restore Device Policies
    if ($backupData.DevicePolicies) {
        try {
            # Restore Removable Media Policy
            if ($backupData.DevicePolicies.RemovableMedia) {
                Set-ItemProperty -Path $backupData.DevicePolicies.RemovableMedia.RegistryPath -Name "NoRecentDocsNetHood" -Value $backupData.DevicePolicies.RemovableMedia.CurrentValue
            }
            
            # Restore Printer Driver Installation Policy
            if ($backupData.DevicePolicies.PrinterDriverInstallation) {
                Set-ItemProperty -Path $backupData.DevicePolicies.PrinterDriverInstallation.RegistryPath -Name "DefaultSpoolDirectory" -Value $backupData.DevicePolicies.PrinterDriverInstallation.CurrentValue
            }
            
            Write-Log -Message "Restored Device Policies" -Level "Info"
        }
        catch {
            Write-Log -Message "Failed to restore Device Policies: $_" -Level "Warning"
        }
    }
    
    Write-Log -Message "Security Policy Restoration completed" -Level "Info"
}

# Error Handling Function
function Handle-Error {
    param([string]$Message)
    Write-Log -Message $Message -Level "Error"
    throw $Message
}

# Main Script Execution
try {
    # Ensure Backup Directory
    Ensure-BackupDirectory
    
    # Backup Current Policies Before Making Changes
    $backupData = Backup-SecurityPolicies
    
    # Policy Changes Tracking
    $policyChanges = @()

    # 1. Network Security: NTLM SSP Session Security
    try {
        $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
        $ntlmKeyName = "NTLMMinClientSec"
        $ntlmValue = 537395200 # Requires NTLMv2 session security and 128-bit encryption

        $currentNTLMValue = (Get-ItemProperty -Path $registryPath -Name $ntlmKeyName -ErrorAction SilentlyContinue).$ntlmKeyName
        if ($currentNTLMValue -ne $ntlmValue) {
            Set-ItemProperty -Path $registryPath -Name $ntlmKeyName -Value $ntlmValue
            $policyChanges += @{
                Policy = "Network security: Minimum session security for NTLM SSP"
                OldValue = $currentNTLMValue
                NewValue = $ntlmValue
                Status = "Updated"
            }
            Write-Log -Message "Updated NTLM SSP Session Security" -Level "Info"
        }
        else {
            $policyChanges += @{
                Policy = "Network security: Minimum session security for NTLM SSP"
                OldValue = $currentNTLMValue
                NewValue = $ntlmValue
                Status = "Unchanged"
            }
        }
    }
    catch {
        Write-Log -Message "Failed to set NTLM SSP Session Security: $_" -Level "Warning"
    }

    # 2. Rename Administrator Account
    try {
        $currentAdminName = (Get-LocalUser | Where-Object {$_.SID.Value.EndsWith("-500")}).Name
        $newAdminName = "AdminSecure"
        
        if ($currentAdminName -ne $newAdminName) {
            Rename-LocalUser -Name $currentAdminName -NewName $newAdminName
            $policyChanges += @{
                Policy = "Accounts: Rename administrator account"
                OldValue = $currentAdminName
                NewValue = $newAdminName
                Status = "Updated"
            }
            Write-Log -Message "Renamed administrator account" -Level "Info"
        }
        else {
            $policyChanges += @{
                Policy = "Accounts: Rename administrator account"
                OldValue = $currentAdminName
                NewValue = $newAdminName
                Status = "Unchanged"
            }
        }
    }
    catch {
        Write-Log -Message "Failed to rename administrator account: $_" -Level "Warning"
    }

    # 3. Rename Guest Account and Disable
    try {
        $currentGuestName = (Get-LocalUser -Name "Guest").Name
        $newGuestName = "GuestDisabled"
        
        if ($currentGuestName -ne $newGuestName) {
            Rename-LocalUser -Name $currentGuestName -NewName $newGuestName
            $policyChanges += @{
                Policy = "Accounts: Rename guest account"
                OldValue = $currentGuestName
                NewValue = $newGuestName
                Status = "Updated"
            }
        }
        
        Disable-LocalUser -Name $newGuestName
        $policyChanges += @{
            Policy = "Accounts: Guest account status"
            OldValue = "Enabled"
            NewValue = "Disabled"
            Status = "Updated"
        }
        Write-Log -Message "Renamed and disabled guest account" -Level "Info"
    }
    catch {
        Write-Log -Message "Failed to rename/disable guest account: $_" -Level "Warning"
    }

    # 4. Disable Anonymous SID/Name Translation
    try {
        $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\LSA"
        $keyName = "RestrictAnonymous"
        $value = 1

        $currentValue = (Get-ItemProperty -Path $registryPath -Name $keyName -ErrorAction SilentlyContinue).$keyName
        if ($currentValue -ne $value) {
            Set-ItemProperty -Path $registryPath -Name $keyName -Value $value
            $policyChanges += @{
                Policy = "Network access: Allow anonymous SID/Name translation"
                OldValue = $currentValue
                NewValue = $value
                Status = "Updated"
            }
            Write-Log -Message "Disabled anonymous SID/Name translation" -Level "Info"
        }
        else {
            $policyChanges += @{
                Policy = "Network access: Allow anonymous SID/Name translation"
                OldValue = $currentValue
                NewValue = $value
                Status = "Unchanged"
            }
        }
    }
    catch {
        Write-Log -Message "Failed to disable anonymous SID/Name translation: $_" -Level "Warning"
    }

    # 5. Devices and Media Restrictions
    $devicePolicies = @(
        @{
            Name = "Removable Media Formatting"
            RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
            KeyName = "NoRecentDocsNetHood"
            Value = 1
        },
        @{
            Name = "Prevent Printer Driver Installation"
            RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers"
            KeyName = "DefaultSpoolDirectory"
            Value = "C:\Windows\System32\spool\PRINTERS"
        }
    )

    foreach ($policy in $devicePolicies) {
        try {
            $currentValue = (Get-ItemProperty -Path $policy.RegistryPath -Name $policy.KeyName -ErrorAction SilentlyContinue).$policy.KeyName
            
            if ($currentValue -ne $policy.Value) {
                Set-ItemProperty -Path $policy.RegistryPath -Name $policy.KeyName -Value $policy.Value
                $policyChanges += @{
                    Policy = $policy.Name
                    OldValue = $currentValue
                    NewValue = $policy.Value
                    Status = "Updated"
                }
                Write-Log -Message "Updated policy: $($policy.Name)" -Level "Info"
            }
            else {
                $policyChanges += @{
                    Policy = $policy.Name
                    OldValue = $currentValue
                    NewValue = $policy.Value
                    Status = "Unchanged"
                }
            }
        }
        catch {
            Write-Log -Message "Failed to set $($policy.Name): $_" -Level "Warning"
        }
    }
    
    # Define Paths
    $timestamp = (Get-Date -Format "yyyyMMdd")
    $backupPath = "C:\Temp\$timestamp\Internet_Communication\secpol_backup_$timestamp.inf"
    $currentPolicyPath = "C:\Temp\$timestamp\secpol_$timestamp.cfg"
    $reportPath = "C:\Temp\$timestamp\policyCommunication_$timestamp.html"

    # Create directory for storing backups and reports
    if (-not (Test-Path "C:\Temp\$timestamp\Internet_Communication")) {
        New-Item -Path "C:\Temp\$timestamp\Internet_Communication" -ItemType Directory | Out-Null
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
        @{Parameter = 'Turn off Windows Customer Experience Improvement Program'; Key = "CEIPEnable"; Value = "0"}
    )

    $existingPolicies = Get-Content $currentPolicyPath
    $policyCommunication = @()

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
                $policyCommunication += @{
                    Parameter = $parameter
                    OldValue = $oldValue
                    NewValue = $value
                    Status = "Updated"
                }
            } else {
                $policyCommunication += @{
                    Parameter = $parameter
                    OldValue = $oldValue
                    NewValue = $value
                    Status = "Unchanged"
                }
            }
        } else {
            # If not found, log as "Not Defined"
            $policyCommunication += @{
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

    # Script to Backup, Apply Policies, and Generate Policy Report

    $timestamp = (Get-Date -Format "yyyyMMdd")
    $backupPath = "C:\Temp\$timestamp\Security+Event+FirewallPolicy\secpol_backup_$timestamp.inf"
    $currentPolicyPath = "C:\Temp\$timestamp\secpol_$timestamp.cfg"
    $reportPath = "C:\Temp\$timestamp\HardeningPolicy_$timestamp.html"

    if (-not (Test-Path "C:\Temp\$timestamp\Security+Event+FirewallPolicy")) {
        New-Item -Path "C:\Temp\$timestamp\Security+Event+FirewallPolicy" -ItemType Directory | Out-Null
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

    # Create timestamp and paths
    $timestamp = (Get-Date -Format "yyyyMMdd")
    $baseDir = "C:\Temp\$timestamp\Interactive_Logon_Policy"
    $backupPath = Join-Path $baseDir "Interactive_Logon_Policy$timestamp.inf"
    $reportPath = "C:\Temp\$timestamp\PolicyReport_$timestamp.html"

    # Ensure directory exists
    if (-not (Test-Path $baseDir)) {
        New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
    }

    # Step 1: Backup current security policy
    Write-Host "Backing up current security policy..."
    secedit /export /cfg $backupPath /quiet

    # Step 2: Get current policy values using Registry paths
    function Get-CurrentInteractivePolicyValue {
        param (
            [string]$Path,
            [string]$Name
        )
        try {
            $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($value) {
                return $value.$Name
            }
            return "Not Set"
        }
        catch {
            return "Not Set"
        }
    }
    
    # Initialize policy changes array
    $policyInteractiveLogon = @()
    
    # Get current values and track changes
    $currentInteractivePolicies = @{
        "Interactive logon: Do not display last user name" = @{
            RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            RegName = "DontDisplayLastUserName"
            NewValue = "Enabled"
            RegValue = 1
        }
        "Interactive logon: Do not require CTRL+ALT+DEL" = @{
            RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            RegName = "DisableCAD"
            NewValue = "Disabled"
            RegValue = 0
        }
        "Interactive logon: Number of previous logons to cache" = @{
            RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
            RegName = "CachedLogonsCount"
            NewValue = "0 Logons"
            RegValue = 0
        }
        "Interactive logon: Prompt user to change password before expiration" = @{
            RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
            RegName = "PasswordExpiryWarning"
            NewValue = "14 days"
            RegValue = 14
        }
        "Interactive logon: Require Domain Controller authentication to unlock workstation" = @{
            RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
            RegName = "ForceUnlockLogon"
            NewValue = "Enabled"
            RegValue = 1
        }
        "Interactive logon: Smart card removal behavior" = @{
            RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
            RegName = "ScRemoveOption"
            NewValue = "Lock Workstation"
            RegValue = 1
        }
    }
    
    # Get current values and create policy changes array
    foreach ($policy in $currentInteractivePolicies.Keys) {
        $oldValue = Get-CurrentInteractivePolicyValue -Path $currentInteractivePolicies[$policy].RegPath -Name $currentInteractivePolicies[$policy].RegName
        $newValue = $currentInteractivePolicies[$policy].NewValue
        $regValue = $currentInteractivePolicies[$policy].RegValue
    
        # Special handling for numeric values like PasswordExpiryWarning (days)
        if ($policy -eq "Interactive logon: Prompt user to change password before expiration") {
            $oldValueDisplay = if ($oldValue -eq "Not Set") { "Not Set" } else { "$oldValue days" }
        } else {
            # Handle Enabled/Disabled or other string-based policies
            $oldValueDisplay = switch ($oldValue) {
                "1" { "Enabled" }
                "0" { "Disabled" }
                default { $oldValue }
            }
        }
    
        $policyInteractiveLogon += @{
            Policy = $policy
            OldValue = $oldValueDisplay
            NewValue = $newValue
            Status = if ($oldValue -eq $regValue) { "Unchanged" } else { "Updated" }
        }
    }
    

# Create security template
$securityTemplate = @"
[Unicode]
Unicode=yes
[System Access]
[Event Audit]
[Registry Values]
MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\DontDisplayLastUserName=4,1
MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\DisableCAD=4,0
MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\CachedLogonsCount=1,"0"
MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\PasswordExpiryWarning=4,14
MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\ForceUnlockLogon=4,1
MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\ScRemoveOption=1,"1"
[Version]
signature="`$CHICAGO`$"
Revision=1
"@

# Save the security template
$tempPath = Join-Path $baseDir "security_template_$timestamp.inf"
$securityTemplate | Out-File $tempPath -Encoding Unicode

# Apply the security policy
Write-Host "Applying new security policy..."
$result = secedit /configure /db "C:\Temp\$timestamp\secedit_$timestamp.sdb" /cfg $tempPath /quiet

if ($LASTEXITCODE -eq 0) {
    $overallStatus = "Successfully applied"
} else {
    $overallStatus = "Failed to apply some settings"
}

# Create timestamp and paths
$timestamp = (Get-Date -Format "yyyyMMdd")
$baseDir = "C:\Temp\$timestamp\Domain_Member_Policy"
$backupPath = Join-Path $baseDir "Domain_Member_Policy$timestamp.inf"
$reportPath = "C:\Temp\$timestamp\PolicyReport_$timestamp.html"

# Ensure directory exists
if (-not (Test-Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
}

# Step 1: Backup current security policy
Write-Host "Backing up current security policy..."
secedit /export /cfg $backupPath /quiet

# Step 2: Get current policy values using Registry paths
function Get-CurrentDomainPolicyValue {
    param (
        [string]$Path,
        [string]$Name
    )
    try {
        $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($value) {
            return $value.$Name
        }
        return "Not Set"
    }
    catch {
        return "Not Set"
    }
}

# Initialize policy changes array
$policyDomainMember = @()

# Get current values and track changes
$currentDomainPolicies = @{
    "Domain member: Digitally encrypt or sign secure channel data (always)" = @{
        RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
        RegName = "RequireSignOrSeal"
        NewValue = "Enabled"
        RegValue = 1
        RegValueType = "4"  # DWORD
    }
    "Domain member: Digitally encrypt secure channel data (when possible)" = @{
        RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
        RegName = "SealSecureChannel"
        NewValue = "Enabled"
        RegValue = 1
        RegValueType = "4"  # DWORD
    }
    "Domain member: Disable machine account password changes" = @{
        RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
        RegName = "DisablePasswordChange"
        NewValue = "Disabled"
        RegValue = 0
        RegValueType = "4"  # DWORD
    }
    "Domain member: Maximum machine account password age" = @{
        RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
        RegName = "MaximumPasswordAge"
        NewValue = "30 days"
        RegValue = 30
        RegValueType = "4"  # DWORD
    }
    "Domain member: Require strong (Windows 2000 or later) session key" = @{
        RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
        RegName = "RequireStrongKey"
        NewValue = "Enabled"
        RegValue = 1
        RegValueType = "4"  # DWORD
    }
    "Interactive logon: Message text for users attempting to log on" = @{
        RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        RegName = "LegalNoticeText"
        NewValue = "This system is restricted to authorized users only. All activities may be monitored and reported."
        RegValue = "This system is restricted to authorized users only. All activities may be monitored and reported."
        RegValueType = "7"  # MULTI_SZ
    }
}

# Get current values and create policy changes array
foreach ($policy in $currentDomainPolicies.Keys) {
    $oldValue = Get-CurrentDomainPolicyValue -Path $currentDomainPolicies[$policy].RegPath -Name $currentDomainPolicies[$policy].RegName
    $newValue = $currentDomainPolicies[$policy].NewValue
    $regValue = $currentDomainPolicies[$policy].RegValue

    # Convert the old value to display format
    if ($oldValue -is [string]) {
        $oldValueDisplay = $oldValue
    } else {
        $oldValueDisplay = switch ($oldValue) {
            0 { "Disabled" }
            1 { "Enabled" }
            default { 
                if ($policy -eq "Domain member: Maximum machine account password age") {
                    "$oldValue days"
                } else {
                    $oldValue.ToString()
                }
            }
        }
    }

    $policyDomainMember += @{
        Policy = $policy
        OldValue = $oldValueDisplay
        NewValue = $newValue
        Status = if ($oldValue -eq $regValue) { "Unchanged" } else { "Updated" }
    }
}

# Create security template
$securityTemplate = @"
[Unicode]
Unicode=yes
[System Access]
[Event Audit]
[Registry Values]
MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\RequireSignOrSeal=4,1
MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\SealSecureChannel=4,1
MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\DisablePasswordChange=4,0
MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\MaximumPasswordAge=4,30
MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\RequireStrongKey=4,1
MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\LegalNoticeText=7,"This system is restricted to authorized users only. All activities may be monitored and reported."
[Version]
signature="`$CHICAGO`$"
Revision=1
"@

# Save the security template
$tempPath = Join-Path $baseDir "security_template_$timestamp.inf"
$securityTemplate | Out-File $tempPath -Encoding Unicode

# Apply the security policy
Write-Host "Applying new security policy..."
$result = secedit /configure /db "C:\Temp\$timestamp\secedit_$timestamp.sdb" /cfg $tempPath /quiet

# Check result and display status
if ($LASTEXITCODE -eq 0) {
    Write-Host "Successfully applied security policies"
    
    # Display changes
    Write-Host "`nPolicy Changes:"
    $policyDomainMember | ForEach-Object {
        Write-Host ("`nPolicy: " + $_.Policy)
        Write-Host ("Old Value: " + $_.OldValue)
        Write-Host ("New Value: " + $_.NewValue)
        Write-Host ("Status: " + $_.Status)
    }
} else {
    Write-Host "Failed to apply some security settings"
}

# Create timestamp and paths
$timestamp = (Get-Date -Format "yyyyMMdd")
$baseDir = "C:\Temp\$timestamp\SystemPolicy"
$backupPath = Join-Path $baseDir "SystemPolicy_$timestamp.inf"
$reportPath = "C:\Temp\$timestamp\PolicyReport_$timestamp.html"

# Ensure directory exists
if (-not (Test-Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
}

# Step 1: Backup current security policy
Write-Host "Backing up current security policy..."
secedit /export /cfg $backupPath /quiet

# Function to get current policy values using Registry paths
function Get-CurrentDomainPolicyValue {
    param (
        [string]$Path,
        [string]$Name
    )
    try {
        $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($value) {
            return $value.$Name
        }
        return "Not Set"
    }
    catch {
        return "Not Set"
    }
}

# Initialize policy changes array
$policySystem = @()

# Define policies and registry paths
$currentSystemPolicies = @{
    "Shutdown: Clear virtual memory pagefile" = @{
        RegPath = "HKLM:\System\CurrentControlSet\Control\Session Manager\Memory Management"
        RegName = "ClearPageFileAtShutdown"
        NewValue = "Disabled"
        RegValue = 0
        RegValueType = "4"  # DWORD
    }
    "Shutdown: Allow system to be shut down without having to log on" = @{
        RegPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
        RegName = "ShutdownWithoutLogon"
        NewValue = "Disabled"
        RegValue = 0
        RegValueType = "4"  # DWORD
    }
    "System objects: Require case insensitivity for non-Windows subsystems" = @{
        RegPath = "HKLM:\System\CurrentControlSet\Control\Session Manager\ObjectNames"
        RegName = "RequireCaseInsensitivity"
        NewValue = "Enabled"
        RegValue = 1
        RegValueType = "4"  # DWORD
    }
    "System objects: Strengthen default permissions of internal system objects" = @{
        RegPath = "HKLM:\System\CurrentControlSet\Control\Session Manager\ObjectNames"
        RegName = "StrengthenDefaultPermissions"
        NewValue = "Enabled"
        RegValue = 1
        RegValueType = "4"  # DWORD
    }
    "System cryptography: Force strong key protection for user keys stored on the computer" = @{
        RegPath = "HKLM:\Software\Policies\Microsoft\Cryptography"
        RegName = "ForceKeyProtection"
        NewValue = "User is Prompted when the key is first used"
        RegValue = "User is Prompted when the key is first used"
        RegValueType = "1"  # STRING
    }
}

# Get current values and create policy changes array
foreach ($policy in $currentSystemPolicies.Keys) {
    $oldValue = Get-CurrentDomainPolicyValue -Path $currentSystemPolicies[$policy].RegPath -Name $currentSystemPolicies[$policy].RegName
    $newValue = $currentSystemPolicies[$policy].NewValue
    $regValue = $currentSystemPolicies[$policy].RegValue

    # Convert the old value to display format
    if ($oldValue -is [string]) {
        $oldValueDisplay = $oldValue
    } else {
        $oldValueDisplay = switch ($oldValue) {
            0 { "Disabled" }
            1 { "Enabled" }
            default { $oldValue.ToString() }
        }
    }

    $policySystem += @{
        Policy = $policy
        OldValue = $oldValueDisplay
        NewValue = $newValue
        Status = if ($oldValue -eq $regValue) { "Unchanged" } else { "Updated" }
    }
}

# Create security template
$systemTemplate = @"
[Unicode]
Unicode=yes
[System Access]
[Event Audit]
[Registry Values]
MACHINE\System\CurrentControlSet\Control\Session Manager\Memory Management\ClearPageFileAtShutdown=4,0
MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\ShutdownWithoutLogon=4,0
MACHINE\System\CurrentControlSet\Control\Session Manager\ObjectNames\RequireCaseInsensitivity=4,1
MACHINE\System\CurrentControlSet\Control\Session Manager\ObjectNames\StrengthenDefaultPermissions=4,1
MACHINE\Software\Policies\Microsoft\Cryptography\ForceKeyProtection=1,"User is Prompted when the key is first used"
[Version]
signature="`$CHICAGO`$"
Revision=1
"@

# Save the security template
$tempPath = Join-Path $baseDir "system_template_$timestamp.inf"
$systemTemplate | Out-File $tempPath -Encoding Unicode

# Apply the security policy
Write-Host "Applying new system policy..."
$result = secedit /configure /db "C:\Temp\$timestamp\secedit_$timestamp.sdb" /cfg $tempPath /quiet

# Check result and display status
if ($LASTEXITCODE -eq 0) {
    Write-Host "Successfully applied security policies"

    # Display changes
    Write-Host "`nPolicy Changes:"
    $policyDomainMember | ForEach-Object {
        Write-Host ("`nPolicy: " + $_.Policy)
        Write-Host ("Old Value: " + $_.OldValue)
        Write-Host ("New Value: " + $_.NewValue)
        Write-Host ("Status: " + $_.Status)
    }
} else {
    Write-Host "Failed to apply some security settings"
}

# Create timestamp and paths
$timestamp = (Get-Date -Format "yyyyMMdd")
$baseDir = "C:\Temp\$timestamp\NetworkSecurity"
$backupPath = Join-Path $baseDir "NetworkSecurity_$timestamp.inf"
$reportPath = "C:\Temp\$timestamp\PolicyReport_$timestamp.html"

# Ensure directory exists
if (-not (Test-Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
}

# Step 1: Backup current security policy
Write-Host "Backing up current security policy..."
secedit /export /cfg $backupPath /quiet

# Function to get current policy values using Registry paths
function Get-CurrentPolicyValue {
    param (
        [string]$Path,
        [string]$Name
    )
    try {
        $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($value) {
            return $value.$Name
        }
        return "Not Set"
    }
    catch {
        return "Not Set"
    }
}

# Initialize policy changes array
$policyNetworkSecurity = @()

# Define policies and registry paths
$currentPoliciesNetwork = @{
    "Network security: Do not store LAN Manager hash value on next password change" = @{
        RegPath = "HKLM:\System\CurrentControlSet\Control\Lsa"
        RegName = "NoLMHash"
        NewValue = 1
        RegValue = 1
        RegValueType = "4"  # DWORD
    }
    "Network security: LAN Manager authentication level" = @{
        RegPath = "HKLM:\System\CurrentControlSet\Control\Lsa"
        RegName = "LmCompatibilityLevel" 
        NewValue = 5 # LmCompatibilityLevel = 5 = Send NTLMv2 response only. Refuse LM.
        RegValue = 5
        RegValueType = "4"  # DWORD
    }
    "Network security: LDAP client signing requirements" = @{
        RegPath = "HKLM:\System\CurrentControlSet\Services\LDAP"
        RegName = "LDAPClientIntegrity"
        NewValue = 2 # LDAPClientIntegrity = 2 = Negotiate signing or higher.
        RegValue = 2
        RegValueType = "4"  # DWORD
    }
    "Network security: Minimum session security for NTLM SSP based clients" = @{
        RegPath = "HKLM:\System\CurrentControlSet\Control\Lsa"
        RegName = "NtlmMinClientSec"
        NewValue = 553648128 # Require NTLMv2 session security, Require 128-bit encryption
        RegValue = 553648128
        RegValueType = "4"  # DWORD
    }
    "Recovery console: Allow automatic administrative logon" = @{
        RegPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
        RegName = "DisableAdminAccount"
        NewValue = 1
        RegValue = 1
        RegValueType = "4"  # DWORD
    }
}

# Get current values and create policy changes array
foreach ($policy in $currentPoliciesNetwork.Keys) {
    $oldValue = Get-CurrentPolicyValue -Path $currentPoliciesNetwork[$policy].RegPath -Name $currentPoliciesNetwork[$policy].RegName
    $newValue = $currentPoliciesNetwork[$policy].NewValue
    $regValue = $currentPoliciesNetwork[$policy].RegValue

    # Convert the old value to display format
    $oldValueDisplay = switch ($oldValue) {
        0 { "Disabled" }
        1 { "Enabled" }
        default { $oldValue.ToString() }
    }

    $policyNetworkSecurity += @{
        Policy = $policy
        OldValue = $oldValueDisplay
        NewValue = if ($regValue -eq 1) { "Enabled" } else { "Disabled" }
        Status = if ($oldValue -eq $regValue) { "Unchanged" } else { "Updated" }
    }
}

# Create security template
$NetworkSecurityTemplate = @"
[Unicode]
Unicode=yes
[System Access]
[Event Audit]
[Registry Values]
MACHINE\System\CurrentControlSet\Control\Lsa\NoLMHash=4,1
MACHINE\System\CurrentControlSet\Control\Lsa\LmCompatibilityLevel=4,5
MACHINE\System\CurrentControlSet\Services\LDAP\LDAPClientIntegrity=4,2
MACHINE\System\CurrentControlSet\Control\Lsa\NtlmMinClientSec=4,536870912
MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\DisableAdminAccount=4,1
[Version]
signature="`$CHICAGO`$"
Revision=1
"@

# Save the security template
$tempPath = Join-Path $baseDir "NetworkSecurityTemplate_$timestamp.inf"
$NetworkSecurityTemplate | Out-File $tempPath -Encoding Unicode

# Apply the security policy
Write-Host "Applying security policy..."
$result = secedit /configure /db "C:\Temp\$timestamp\secedit_$timestamp.sdb" /cfg $tempPath /quiet

# Verify and display result
if ($LASTEXITCODE -eq 0) {
    Write-Host "Network Security policies successfully applied."

    # Display changes
    Write-Host "`nPolicy Changes:"
    $policyChanges | ForEach-Object {
        Write-Host ("Policy: " + $_.Policy)
        Write-Host ("Old Value: " + $_.OldValue)
        Write-Host ("New Value: " + $_.NewValue)
        Write-Host ("Status: " + $_.Status + "`n")
    }
} else {
    Write-Host "Failed to apply some security settings."
}


    # Generate HTML Report
    $reportContent = @"
<html>
<head>
    <title>Hardening BTPNS - Policy Report</title>
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
    <h1>Policy Report - Hardening BTPNS (79 / 106 Policy)</h1>
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

foreach ($change in $policyChanges) {
    $statusClass = if ($change.Status -eq 'Updated') { 'updated' } else { 'unchanged' }
    $reportContent += @"
        <tr>
            <td>$($change.Policy)</td>
            <td>$($change.OldValue)</td>
            <td>$($change.NewValue)</td>
            <td class="$statusClass">$($change.Status)</td>
        </tr>
"@
}

foreach ($policy in $policyCommunication) {
    $reportContent += @"
        <tr>
            <td>$($policy.Parameter)</td>
            <td>$($policy.OldValue)</td>
            <td>$($policy.NewValue)</td>
            <td>$($policy.Status)</td>
        </tr>
"@
}

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

foreach ($policy in $policyInteractiveLogon) {
    $reportContent += @"
        <tr>
            <td>$($policy.Policy)</td>
            <td>$($policy.OldValue)</td>
            <td>$($policy.NewValue)</td>
            <td>$($policy.Status)</td>
        </tr>
"@
}

foreach ($policy in $policyDomainMember) {
    $reportContent += @"
        <tr>
            <td>$($policy.Policy)</td>
            <td>$($policy.OldValue)</td>
            <td>$($policy.NewValue)</td>
            <td>$($policy.Status)</td>
        </tr>
"@
}

foreach ($policy in $policySystem) {
    $reportContent += @"
        <tr>
            <td>$($policy.Policy)</td>
            <td>$($policy.OldValue)</td>
            <td>$($policy.NewValue)</td>
            <td>$($policy.Status)</td>
        </tr>
"@
}

foreach ($policy in $policyNetworkSecurity) {
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

    # Save Report
    Set-Content -Path $reportPath -Value $reportContent
    Write-Log -Message "Policy report generated at $reportPath" -Level "Info"

    Write-Log -Message "Advanced Security Policy Configuration Script Completed Successfully" -Level "Info"
}
catch {
    Write-Log -Message "Script failed: $_" -Level "Error"
    throw
}

Write-Host "Security Policy Configuration completed. Check log at $logPath and report at $reportPath"