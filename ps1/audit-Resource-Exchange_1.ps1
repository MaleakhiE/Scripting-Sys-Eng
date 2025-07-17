<#
.SYNOPSIS
Exchange Server Monitoring Script

.DESCRIPTION
Collects Exchange server metrics (resource usage, queues, DB status), generates an HTML report,
and emails it to specified recipients.

.NOTES
Author: Example / ChatGPT
#>

# ==============================
# === CONFIG SECTION ===========
# ==============================
# SMTP settings
$smtpServer = "smtp.gmail.com"
$smtpPort = 587
$smtpFrom = "ekiputra543@gmail.com"
$smtpTo = "ekiputra234@gmail.com"
$smtpUser = "ekiputra543@gmail.com"
$smtpPass = "kobl keqi ybnk qwfq"

# =============================
# === GET ALL EXCHANGE SERVERS 
# =============================
$servers = Get-ExchangeServer | Where { $_.IsMailboxServer -or $_.IsClientAccessServer -or $_.IsHubTransportServer }

# =============================
# === BUILD HTML HEADER =======
# =============================
$html = @"
<html><head>
<style>
    body { font-family: Arial; }
    h2 { background-color: #0078d7; color: white; padding: 5px; }
    table { border-collapse: collapse; width: 95%; margin-bottom: 20px; }
    th, td { border: 1px solid #ccc; padding: 5px; }
    th { background: #f2f2f2; }
</style>
</head><body>
<h1>Exchange Multi-Server Health Report - $(Get-Date)</h1>
"@

# =============================
# === LOOP THROUGH SERVERS ====
# =============================

foreach ($server in $servers) {
    Write-Host "Processing $($server.Name)..."

    # === Resource Usage ===
    $cpu = Get-WmiObject Win32_Processor -ComputerName $server.Name | 
        Measure-Object -Property LoadPercentage -Average | 
        Select-Object -ExpandProperty Average

    $mem = Get-WmiObject Win32_OperatingSystem -ComputerName $server.Name
    $totalMemGB = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 2)
    $freeMemGB = [math]::Round($mem.FreePhysicalMemory / 1MB, 2)
    $usedMemGB = $totalMemGB - $freeMemGB

    $diskInfo = Get-WmiObject Win32_LogicalDisk -ComputerName $server.Name -Filter "DriveType=3" | 
        Select-Object DeviceID,
                      @{Name="SizeGB";Expression={[math]::Round($_.Size/1GB,2)}},
                      @{Name="FreeGB";Expression={[math]::Round($_.FreeSpace/1GB,2)}},
                      @{Name="UsedGB";Expression={[math]::Round(($_.Size - $_.FreeSpace)/1GB,2)}},
                      @{Name="Usage%";Expression={[math]::Round((($_.Size - $_.FreeSpace)/$_.Size)*100,2)}}

    # === Exchange Queues ===
    $queues = Get-Queue -Server $server.Name | Select Identity, MessageCount, Status

    # === Database copies ===
    $dbs = Get-MailboxDatabaseCopyStatus -Server $server.Name | 
        Select Name, Status, CopyQueueLength, ReplayQueueLength, ContentIndexState

    # =========================
    # === APPEND TO HTML =======
    # =========================
    $html += "<h2>Server: $($server.Name)</h2>"

    # Resource Table
    $html += "<table>
    <tr><th>CPU Usage (%)</th><td>$cpu</td></tr>
    <tr><th>Total Memory (GB)</th><td>$totalMemGB</td></tr>
    <tr><th>Used Memory (GB)</th><td>$usedMemGB</td></tr>
    <tr><th>Free Memory (GB)</th><td>$freeMemGB</td></tr>
    </table>"

    # Disk Table
    $html += "<table>
    <tr><th>Drive</th><th>Size(GB)</th><th>Used(GB)</th><th>Free(GB)</th></tr>"
    foreach ($disk in $diskInfo) {
        $html += "<tr><td>$($disk.DeviceID)</td><td>$($disk.SizeGB)</td><td>$($disk.UsedGB)</td><td>$($disk.FreeGB)</td></tr>"
    }
    $html += "</table>"

    # Queue Table
    $html += "<h3>Transport Queues</h3><table>
    <tr><th>Identity</th><th>Messages</th><th>Status</th></tr>"
    foreach ($q in $queues) {
        $html += "<tr><td>$($q.Identity)</td><td>$($q.MessageCount)</td><td>$($q.Status)</td></tr>"
    }
    $html += "</table>"

    # DB Copy Table
    $html += "<h3>Mailbox Database Copies</h3><table>
    <tr><th>Name</th><th>Status</th><th>Copy Queue</th><th>Replay Queue</th><th>Content Index</th></tr>"
    foreach ($db in $dbs) {
        $html += "<tr><td>$($db.Name)</td><td>$($db.Status)</td><td>$($db.CopyQueueLength)</td><td>$($db.ReplayQueueLength)</td><td>$($db.ContentIndexState)</td></tr>"
    }
    $html += "</table>"
}

# =========================
# === FINALIZE & SEND =====
# =========================
$html += "</body></html>"

# Create credential object
$securePass = ConvertTo-SecureString $smtpPass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($smtpUser, $securePass)

Send-MailMessage -From $smtpFrom `
                 -To $smtpTo `
                 -Subject "Exchange Multi-Server Health Report - $(Get-Date -Format 'yyyy-MM-dd')" `
                 -BodyAsHtml $html `
                 -SmtpServer $smtpServer `
                 -Port $smtpPort `
                 -Credential $cred `
                 -UseSsl

Write-Host "[Done] - Exchange multi-server report sent."

