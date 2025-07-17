# Define SMTP server details (internal relay / Exchange Server)
$smtpServer = "mail.yourdomain.local"  # Ganti dengan SMTP server internal Anda
$smtpPort = 25  # Biasanya 25 jika tanpa SSL/TLS
$toAddress = "recipient@yourdomain.com"
$fromAddress = "it-ops@yourdomain.com"

# Create the static email body for failure
$emailBody = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; color: #333; }
        h1 { color: #FF0000; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; text-align: left; padding: 8px; }
        th { background-color: #FF0000; color: white; }
    </style>
</head>
<body>
    <h1>Backup Failed</h1>
    <p>Hello,</p>
    <p>The backup failed for the system on the following date:</p>
    <table>
        <tr><th>Backup Status</th><td>Failed</td></tr>
        <tr><th>Backup Location</th><td>E:\WindowsImageBackup\LABAD01</td></tr>
        <tr><th>Reason</th><td>Backup process could not be completed or backup file is not available.</td></tr>
    </table>
    <p>Please investigate the issue.<br>IT Operations Team</p>
</body>
</html>
"@

# Set the email subject for failure
$emailSubject = "Backup Failure Notification"

# Send the email using Send-MailMessage (no credentials)
try {
    Send-MailMessage -From $fromAddress `
                     -To $toAddress `
                     -Subject $emailSubject `
                     -Body $emailBody `
                     -SmtpServer $smtpServer `
                     -Port $smtpPort `
                     -BodyAsHtml
    Write-Host "Backup failure notification email sent successfully."
} catch {
    Write-Host "Error sending email: $_"
}
