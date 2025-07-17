# Import the Active Directory module
Import-Module ActiveDirectory

$timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
# Define backup file path for later restore
$backupFilePath = "C:\Temp\AD_Disabled_Computers_Backup($timestamp).csv"

# Check if backup file already exists to prevent overwriting
if (Test-Path $backupFilePath) {
    Write-Host "Backup file exists. Please review before proceeding."
    $response = Read-Host "Do you want to overwrite the backup file? (Y/N)"
    if ($response -ne "Y") {
        Write-Host "Exiting without making changes."
        exit
    }
}

# Get all computers in the domain and filter for Windows Server 2016
$computers = Get-ADComputer -Filter * -Property OperatingSystem | Where-Object { $_.OperatingSystem -like "*Windows Server 2019*" }

# Prepare a list for backup data (Computer Name and Enabled Status)
$backupData = @()

# Loop through each computer to back up their state and disable the account
foreach ($computer in $computers) {
    # Back up current enabled status
    $backupData += [PSCustomObject]@{
        ComputerName    = $computer.Name
        DistinguishedName = $computer.DistinguishedName
        Enabled         = $computer.Enabled
    }

    # Disable the computer account if it's currently enabled
    if ($computer.Enabled) {
        Write-Host "Disabling computer account: $($computer.Name)"
        Disable-ADAccount -Identity $computer.DistinguishedName
    }
}

# Write backup data to a CSV file for future restoration
$backupData | Export-Csv -Path $backupFilePath -NoTypeInformation

Write-Host "All Windows Server 2016 machines have been disabled."
Write-Host "Backup data saved to: $backupFilePath"

# ================================
# Restore Section (for rollback)
# ================================
# Ask if user wants to restore disabled accounts
$responseRestore = Read-Host "Do you want to restore the disabled computers? (Y/N)"
if ($responseRestore -eq "Y") {
    # Check if backup file exists
    if (Test-Path $backupFilePath) {
        # Import the backup data
        $restoredData = Import-Csv -Path $backupFilePath
        
        # Loop through the restored data and enable the accounts that were disabled
        foreach ($entry in $restoredData) {
            if ($entry.Enabled -eq $false) {
                Write-Host "Restoring computer account: $($entry.ComputerName)"
                Enable-ADAccount -Identity $entry.DistinguishedName
            }
        }
        
        Write-Host "Restoration complete. All previously disabled accounts have been re-enabled."
    } else {
        Write-Host "Backup file not found. Cannot restore accounts."
    }
} else {
    Write-Host "No restore action taken."
}
