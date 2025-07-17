# Import Exchange Online module
Import-Module ExchangeOnlineManagement

# Connect to Exchange Online (Admin credentials required)
Connect-ExchangeOnline

# Define CSV file path
$csvPath = "/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Protelindo/Meeting/24 Maret 2025/test-forwarding.csv"

# Read CSV file
$users = Import-Csv -Path $csvPath

foreach ($user in $users) {
    $oldMailbox = $user.OldEmail
    $newMailbox = $user.NewEmail

    # Set mail forwarding
    
    # External forwarding
    # Set-Mailbox -Identity $oldMailbox -ForwardingSMTPAddress $newMailbox -DeliverToMailboxAndForward $true

    # Internal forwarding
    Set-Mailbox -Identity $oldMailbox -ForwardingAddress $newMailbox -DeliverToMailboxAndForward $true

    Write-Host "✅ Forwarding set from $oldMailbox to $newMailbox"
}

# Disconnect from Exchange Online
Disconnect-ExchangeOnline -Confirm:$false

Write-Host "🎉 Bulk forwarding completed!"
