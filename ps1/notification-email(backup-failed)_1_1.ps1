# Define SMTP server details
$smtpServer = ""
$smtpPort = 587
$smtpUser = ""   # Replace with your Gmail address
$smtpPass = ""     # Replace with your Gmail app password (not your main Gmail password)
$toAddress = ""   # Replace with your recipient's email address
$fromAddress = ""  # Your email address

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
        <tr>
            <th>Backup Status</th>
            <td>Failed</td>
        </tr>
        <tr>
            <th>Backup Location</th>
            <td>E:\WindowsImageBackup\LABAD01</td>
        </tr>
        <tr>
            <th>Reason</th>
            <td>Backup process could not be completed or backup file is not available.</td>
        </tr>
    </table>
    <p>Please investigate the issue.<br>IT Operations Team</p>
</body>
</html>
"@

# Set the email subject for failure
$emailSubject = "Backup Failure Notification"

# Create a MailMessage object
$mailMessage = New-Object system.net.mail.mailmessage
$mailMessage.From = $fromAddress
$mailMessage.To.Add($toAddress)
$mailMessage.Subject = $emailSubject
$mailMessage.Body = $emailBody
$mailMessage.IsBodyHtml = $true

# Create the SMTP client and send the email
$smtpClient = New-Object Net.Mail.SmtpClient($smtpServer, $smtpPort)
$smtpClient.EnableSsl = $true
$smtpClient.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $smtpPass)

# Send the email
try {
    $smtpClient.Send($mailMessage)
    Write-Host "Backup failure notification email sent successfully."
} catch {
    Write-Host "Error sending email: $_"
}
