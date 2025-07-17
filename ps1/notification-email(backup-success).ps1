# Define SMTP server (internal relay or Exchange)
$smtpServer = "mail.yourdomain.local"  # Ganti dengan hostname/IP SMTP server internal
$smtpPort = 25  # Biasanya tidak menggunakan SSL
$toAddress = "recipient@yourdomain.com"
$fromAddress = "it-ops@yourdomain.com"

# Define the backup location
$backupLocation = "D:\Backups"  # Ganti dengan lokasi sebenarnya

# Get the last backup file
$lastBackup = Get-ChildItem -Path $backupLocation -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($lastBackup) {
    $backupDate = $lastBackup.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    $backupFileSize = $lastBackup.Length / 1MB
    $backupFileSizeFormatted = "{0:N2}" -f $backupFileSize
    if ($backupFileSize -lt 0.01) {
        $backupFileSizeFormatted = "File too small or no data"
    }
    $backupStartTime = $lastBackup.LastWriteTime
    $currentTime = Get-Date
    $backupDuration = $currentTime - $backupStartTime
    $backupDurationFormatted = "{0:D2}:{1:D2}:{2:D2}" -f $backupDuration.Hours, $backupDuration.Minutes, $backupDuration.Seconds
} else {
    $backupDate = "No backup found"
    $backupFileSizeFormatted = "N/A"
    $backupDurationFormatted = "N/A"
}

# Compose HTML Email
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
        <tr><th>Backup Date</th><td>$backupDate</td></tr>
        <tr><th>Backup Location</th><td>$backupLocation</td></tr>
        <tr><th>Backup File</th><td>$($lastBackup.Name)</td></tr>
        <tr><th>Backup Size</th><td>$backupFileSizeFormatted MB</td></tr>
        <tr><th>Backup Duration</th><td>$backupDurationFormatted</td></tr>
    </table>
    <p>Thank you,<br>IT Operations Team</p>
</body>
</html>
"@

# Send email using Send-MailMessage (built-in, no credentials)
try {
    Send-MailMessage -From $fromAddress `
                     -To $toAddress `
                     -Subject "Backup Status Report" `
                     -Body $emailBody `
                     -SmtpServer $smtpServer `
                     -Port $smtpPort `
                     -BodyAsHtml
    Write-Host "Backup status email sent successfully."
} catch {
    Write-Host "Error sending email: $_"
}
