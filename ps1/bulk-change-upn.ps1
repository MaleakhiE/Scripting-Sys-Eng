# Import Active Directory module
Import-Module ActiveDirectory

# Define CSV file path
$csvFile = "C:\Path\To\Users.csv"

# Read users from CSV
$users = Import-Csv -Path $csvFile

foreach ($user in $users) {
    $samAccountName = $user.samAccountName
    $oldUPN = $user.UPN
    $newUPN = $user."Email Protelindo/Iforte"

    # Get user from Active Directory
    $adUser = Get-ADUser -Filter {SamAccountName -eq $samAccountName} -Properties UserPrincipalName

    if ($adUser) {
        Write-Host "Processing user: $samAccountName"

        # Check if the current UPN matches the old primary SMTP address
        if ($adUser.UserPrincipalName -eq $oldUPN) {
            try {
                # Change the UPN to the new format
                Set-ADUser -Identity $samAccountName -UserPrincipalName $newUPN
                Write-Host "✅ UPN updated from $oldUPN to $newUPN"
            } catch {
                Write-Host "❌ Error updating UPN for $samAccountName : $_"
            }
        } else {
            Write-Host "⚠️ UPN does not match old SMTP for $samAccountName, skipping..."
        }
    } else {
        Write-Host "❌ User not found: $samAccountName"
    }
}

Write-Host "`n✅ Bulk UPN update completed successfully!"
