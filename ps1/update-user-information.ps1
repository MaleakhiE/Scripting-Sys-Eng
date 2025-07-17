# Import the Active Directory module
Import-Module ActiveDirectory

# Path to the CSV file containing user information
$csvFilePath = "C:\Path\To\Your\File.csv"

# Read CSV file
$userData = Import-Csv $csvFilePath

# Iterate through each row in the CSV
foreach ($user in $userData) {
    # Retrieve user information from CSV
    $username = $user.UserPrincipalName
    $emailAddress = $user.EmailAddress
    $mail = $user.mail
    $mailNickname = $user.mailnickname
    $targetAddress = $user.targetaddress
    $proxyAddresses = $user.proxyaddresses

    # Update user information in Active Directory
    Set-ADUser -Identity $username -UserPrincipalName $username -EmailAddress $emailAddress -Title $title -mail $mail -mailNickname $mailNickname -OtherAttributes @{targetAddress=$targetAddress; proxyAddresses=$proxyAddresses}

    if ($?) {
        Write-Host "User information updated for $username"
    } else {
        Write-Host "Failed to update user information for $username. Check the input and try again."
    }
}
