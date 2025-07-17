Import-Module ActiveDirectory

# Optional: Export results to a CSV
$output = @()

# Search all users in the domain
Get-ADUser -Filter * -Properties DistinguishedName | ForEach-Object {
    $dn = $_.DistinguishedName

    try {
        $directoryEntry = [ADSI]"LDAP://$dn"
        $security = $directoryEntry.ObjectSecurity

        # Check if inheritance is disabled
        if (-not $security.AreAccessRulesProtected) {
            # Inheritance is enabled; skip
            return
        }

        # Add to result
        $output += [PSCustomObject]@{
            SamAccountName   = $_.SamAccountName
            Name             = $_.Name
            DistinguishedName = $_.DistinguishedName
            Inheritance      = "Disabled"
        }
    }
    catch {
        Write-Warning "Failed to read permissions for $dn"
    }
}

# Output to console and export to CSV
$output | Format-Table -AutoSize
$output | Export-Csv -NoTypeInformation -Path "ADUsers-InheritanceDisabled.csv"

Write-Host "✅ Done. Exported to ADUsers-InheritanceDisabled.csv"

