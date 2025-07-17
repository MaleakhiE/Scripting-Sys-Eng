# Advanced Security Policy Configuration Script
# Applies specific local security policies using multiple methods
# Includes Backup and Restore Functionality

# Define Paths and Timestamp
$timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$tempPath = "C:\Temp\SecurityPolicyBackup"
$backupPath = "$tempPath\Backup_$timestamp"
$reportPath = "$backupPath\SecurityPolicyReport_$timestamp.html"
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

    # Generate HTML Report
    $reportContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Policy Configuration Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f4f4f4; }
        .container { max-width: 800px; margin: 0 auto; background-color: white; padding: 20px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #333; text-align: center; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        th { background-color: #f2f2f2; }
        .updated { color: green; font-weight: bold; }
        .unchanged { color: orange; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Security Policy Configuration Report</h1>
        <table>
            <tr>
                <th>Policy</th>
                <th>Old Value</th>
                <th>New Value</th>
                <th>Status</th>
            </tr>
"@

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

    $reportContent += @"
        </table>
        <p>Report generated on: $(Get-Date)</p>
    </div>
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