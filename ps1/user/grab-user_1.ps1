$ExportPath = 'c:\adusers_list.csv’
Get-ADUser -Filter * -Properties PasswordExpired, Name, UserPrincipalName, SamAccountName, EmailAddress| Export-Csv -NoType $ExportPath