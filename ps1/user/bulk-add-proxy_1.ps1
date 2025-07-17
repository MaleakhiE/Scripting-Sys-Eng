# Define CSV file path
$csvPath = "C:\Path\To\Your\File.csv"

# Import Active Directory module
Import-Module ActiveDirectory

# Read the CSV file
$users = Import-Csv -Path $csvPath

foreach ($user in $users) {
    $samAccountName = $user.samAccountName
    $proxyAddress = $user.'STP Email'
    $primaryEmail = $user."Email Protelindo/Iforte"

    # Get the user from Active Directory
    $adUser = Get-ADUser -Filter {SamAccountName -eq $samAccountName} -Properties ProxyAddresses

    if ($adUser) {
        # Get existing proxy addresses
        $currentProxies = $adUser.ProxyAddresses

        # Define new proxy address as lowercase smtp:
        $newProxy = "smtp:$proxyAddress"

        # Add primary email as uppercase SMTP: (Primary Address)
        if ($primaryEmail -and -not ($currentProxies -match "SMTP:$primaryEmail")) {
            $currentProxies += "SMTP:$primaryEmail"
        }

        # Add new proxy address if not already present
        if ($proxyAddress -and -not ($currentProxies -match [regex]::Escape($newProxy))) {
            $currentProxies += $newProxy
        }

        # Update AD user with new proxy addresses
        Set-ADUser -Identity $samAccountName -Replace @{ProxyAddresses = $currentProxies}

        Write-Host "Done - Updated ProxyAddresses for: $samAccountName"
    } else {
        Write-Host "Error - User not found in AD: $samAccountName" -ForegroundColor Red
    }
}

Write-Host "Done - Bulk update completed!" -ForegroundColor Green
