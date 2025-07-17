# Ensure Active Directory module is imported
Import-Module ActiveDirectory

# Output CSV file path
$OutputFile = "C:\Users\Public\AD_Users_PasswordExpiry.csv"

# Get AD domain password policy (to calculate expiration dates)
$MaxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge

# Get all AD users with necessary properties
$Users = Get-ADUser -Filter * -Properties DisplayName, UserPrincipalName, PasswordNeverExpires, msDS-UserPasswordExpiryTimeComputed | 
ForEach-Object {
    # Convert expiry time from LDAP format to readable date
    $ExpiryDate = if ($_.PasswordNeverExpires -eq $true) {
        "Never Expires"
    } elseif ($_.'msDS-UserPasswordExpiryTimeComputed') {
        [datetime]::FromFileTime($_.'msDS-UserPasswordExpiryTimeComputed')
    } else {
        "Unknown"
    }

    # Output user details
    [PSCustomObject]@{
        SamAccountName  = $_.SamAccountName
        DisplayName     = $_.DisplayName
        UserPrincipalName = $_.UserPrincipalName
        PasswordExpires = $ExpiryDate
    }
}

# Export results to a CSV file with semicolon delimiter
$Users | ConvertTo-Csv -NoTypeInformation -Delimiter ";" | Out-File -Encoding UTF8 $OutputFile

Write-Host "AD users' password expiry details saved to: $OutputFile"

# Import-Csv “/Users/eki/Documents/UPN.csv” | ForEach-Object{                                                                                                                                                                    
# $UserPrincipalName = $_.UserPrincipalName                                                 
# Update-MgUser -UserId $UserPrincipalName -PasswordPolicies DisablePasswordExpiration }