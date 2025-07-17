Import-Module ActiveDirectory

$csvPath = "Delinea Users_2025-1-8.csv"

$users = Import-Csv -Path $csvPath -Delimiter ";"

foreach ($user in $users) {
    $userPrincipalName = $user.userPrincipalName

    $samAccountName = $userPrincipalName.Split("@")[0]

    Set-ADUser -Identity $samAccountName `
               -Replace @{platformUserMembershipType="vendor"}

    Write-Host "Updated user: $samAccountName with platformUserMembershipType=vendor"
}
