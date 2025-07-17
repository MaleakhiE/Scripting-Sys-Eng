# Define SMTP server details
$smtpServer = "smtp.gmail.com"
$smtpPort = 587
$smtpUser = ""   # Replace with your Gmail address
$smtpPass = ""      # Replace with your Gmail app password (not your main Gmail password)
$toAddress = ""   # Replace with your recipient's email address
$fromAddress = ""  # Your email address

# Define the backup location
$backupLocation = "" #Replace with your actual location

# Get the last backup file
$lastBackup = Get-ChildItem -Path $backupLocation -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($lastBackup) {
    $backupDate = $lastBackup.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    
    # Calculate the backup file size in MB and ensure it shows at least 1 decimal point
    $backupFileSize = $lastBackup.Length / 1MB
    $backupFileSizeFormatted = "{0:N2}" -f $backupFileSize

    # Handle cases where the size might be 0 but the file is valid
    if ($backupFileSize -lt 0.01) {
        $backupFileSizeFormatted = "File too small or no data"
    }

    # Calculate backup duration (from the backup start to the current time)
    $backupStartTime = $lastBackup.LastWriteTime
    $currentTime = Get-Date
    $backupDuration = $currentTime - $backupStartTime
    $backupDurationFormatted = "{0:D2}:{1:D2}:{2:D2}" -f $backupDuration.Hours, $backupDuration.Minutes, $backupDuration.Seconds
} else {
    $backupDate = "No backup found"
    $backupFileSizeFormatted = "N/A"
    $backupDurationFormatted = "N/A"
}

# Create the email body in HTML format
$emailBody = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; color: #333; }
        h1 { color: #4CAF50; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; text-align: left; padding: 8px; }
        th { background-color: #4CAF50; color: white; }
    </style>
</head>
<body>
    <h1>Backup Status Report</h1>
    <p>Hello,</p>
    <p>The latest backup activity has been completed. Below are the details:</p>
    <table>
        <tr>
            <th>Backup Date</th>
            <td>$backupDate</td>
        </tr>
        <tr>
            <th>Backup Location</th>
            <td>$backupLocation</td>
        </tr>
        <tr>
            <th>Backup File</th>
            <td>$($lastBackup.Name)</td>
        </tr>
        <tr>
            <th>Backup Size</th>
            <td>$backupFileSizeFormatted MB</td>
        </tr>
        <tr>
            <th>Backup Duration</th>
            <td>$backupDurationFormatted</td>
        </tr>
    </table>
    <p>Thank you,<br>IT Operations Team</p>
</body>
</html>
"@

# Set the email subject
$emailSubject = "Backup Status Report"

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
    Write-Host "Backup status email sent successfully."
} catch {
    Write-Host "Error sending email: $_"
}
