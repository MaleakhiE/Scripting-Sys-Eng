$databases = Get-MailboxDatabase | Where-Object { $_.Name -like "DB1-*" }

foreach ($db in $databases) {
    $dbName = $db.Name
    $copies = Get-MailboxDatabaseCopyStatus -Identity $dbName

    $pvCopy = $copies | Where-Object { $_.MailboxServer -eq "PVEXCH01WBD25WP" }
    $rvCopy = $copies | Where-Object { $_.MailboxServer -eq "RVEXCH01WBD25WP" }

    if ($pvCopy -and $rvCopy) {
        Write-Host "Setting ActivationPreference for $dbName"
        Set-MailboxDatabaseCopy -Identity "$dbName\PVEXCH01WBD25WP" -ActivationPreference 1
        Set-MailboxDatabaseCopy -Identity "$dbName\RVEXCH01WBD25WP" -ActivationPreference 2
    } else {
        Write-Warning "$dbName does not have both PVEXCH01WBD25WP and RVEXCH01WBD25WP copies"
    }
}

