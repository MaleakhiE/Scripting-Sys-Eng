# Import Active Directory module
Import-Module ActiveDirectory

# Define CSV file path
$csvFile = "C:\Path\To\Users.csv"

# Read users from CSV
$users = Import-Csv -Path $csvFile

foreach ($user in $users) {
    $samAccountName = $user.samAccountName
    $oldPrimarySMTP = $user.UPN
    $primarySMTP = $user."STP Email"
    $newPrimarySMTP = $primarySMTP -replace '(@)', '.old$1'
    
    # Get user from Active Directory
    $adUser = Get-ADUser -Filter {SamAccountName -eq $samAccountName} -Properties ProxyAddresses, UserPrincipalName

    if ($adUser) {
        Write-Host "Processing user: $samAccountName"

        # Move old primary SMTP to proxy addresses
        $proxyAddresses = $adUser.ProxyAddresses
        if ($proxyAddresses -notcontains "smtp:$oldPrimarySMTP") {
            $proxyAddresses += "smtp:$oldPrimarySMTP"
            Write-Host "Done -  Added Proxy Address: smtp:$oldPrimarySMTP"
        }

        # Set new primary SMTP address
        Set-ADUser -Identity $samAccountName -EmailAddress $newPrimarySMTP -Replace @{ProxyAddresses = $proxyAddresses; UserPrincipalName = $newPrimarySMTP}

        Write-Host "Done - Updated Primary SMTP: SMTP:$newPrimarySMTP"
    } else {
        Write-Host "Error - User not found: $samAccountName"
    }
}

Write-Host "Done -  Bulk update completed successfully!"
