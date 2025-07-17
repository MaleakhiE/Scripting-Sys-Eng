# Enhanced Exchange SMTP Error Monitor - Multi-Server Support
# Version: 2.0 | Optimized for comprehensive error analysis
param(
    [string]$ConfigFile = "config.json",
    [switch]$SendEmail,
    [switch]$GenerateHTML = $true,
    [switch]$Verbose,
    [int]$HourRange = 1,
    [switch]$ErrorsOnly = $true
)

# === CORE CONFIGURATION ===
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LOG_FILE = Join-Path $SCRIPT_DIR ("smtp_error_monitor_" + (Get-Date -Format "yyyyMMdd") + ".log")

# Enhanced SMTP Error Pattern Database
$SMTP_ERROR_PATTERNS = @(
    @{ Code = "4\d{2}"; Type = "Temporary"; Severity = "Medium"; Category = "Retry" },
    @{ Code = "5\d{2}"; Type = "Permanent"; Severity = "High"; Category = "Failure" },
    @{ Code = "421"; Type = "Service Unavailable"; Severity = "High"; Category = "Infrastructure" },
    @{ Code = "450"; Type = "Mailbox Busy"; Severity = "Medium"; Category = "Recipient" },
    @{ Code = "451"; Type = "Processing Error"; Severity = "Medium"; Category = "Server" },
    @{ Code = "452"; Type = "Storage Full"; Severity = "High"; Category = "Infrastructure" },
    @{ Code = "500"; Type = "Syntax Error"; Severity = "Low"; Category = "Protocol" },
    @{ Code = "550"; Type = "Mailbox Not Found"; Severity = "Low"; Category = "Recipient" },
    @{ Code = "551"; Type = "Relay Denied"; Severity = "Medium"; Category = "Security" },
    @{ Code = "552"; Type = "Quota Exceeded"; Severity = "Medium"; Category = "Recipient" },
    @{ Code = "553"; Type = "Invalid Address"; Severity = "Low"; Category = "Recipient" },
    @{ Code = "554"; Type = "Transaction Failed"; Severity = "High"; Category = "Protocol" },
    @{ Code = "timeout"; Type = "Connection Timeout"; Severity = "High"; Category = "Network" },
    @{ Code = "reset"; Type = "Connection Reset"; Severity = "Medium"; Category = "Network" },
    @{ Code = "auth.*fail"; Type = "Auth Failed"; Severity = "Medium"; Category = "Security" },
    @{ Code = "SSL"; Type = "TLS Error"; Severity = "Medium"; Category = "Security" },
    @{ Code = "certificate"; Type = "Cert Error"; Severity = "Medium"; Category = "Security" },
    @{ Code = "virus"; Type = "Malware"; Severity = "High"; Category = "Security" },
    @{ Code = "spam"; Type = "Spam Block"; Severity = "Low"; Category = "Content" }
)

# === CONFIGURATION MANAGEMENT ===
function Get-DefaultConfig {
    return @{
        ExchangeServers = @(
            @{ Name = "EX01"; LogPaths = @("C:\Program Files\Microsoft\Exchange Server\V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SMTPReceive", "C:\Program Files\Microsoft\Exchange Server\V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SMTPSend") },
            @{ Name = "EX02"; LogPaths = @("\\EX02\C$\Program Files\Microsoft\Exchange Server\V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SMTPReceive", "\\EX02\C$\Program Files\Microsoft\Exchange Server\V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SMTPSend") },
            @{ Name = "EX03"; LogPaths = @("\\EX03\C$\Program Files\Microsoft\Exchange Server\V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SMTPReceive", "\\EX03\C$\Program Files\Microsoft\Exchange Server\V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SMTPSend") }
        )
        OutputDirectory = "C:\Scripts\SMTPErrorReports"
        EmailConfig = @{
            SMTPServer = "smtp.gmail.com"; SMTPPort = 587; EnableSSL = $true
            Username = "ekiputra543@gmail.com"; Password = "kobl keqi ybnk qwfq"
            From = "ekiputra543@gmail.com"; To = "ekiputra234@gmail.com"
            Subject = "Exchange SMTP Error Alert - {DATE}"
        }
        ReportConfig = @{
            CompanyName = "PT Bank Mandiri"; Title = "Exchange SMTP Error Dashboard"
            HourRange = 1; ErrorsOnly = $true; ShowTrends = $true
        }
        AlertThresholds = @{ Critical = 100; Warning = 50; Info = 10 }
        RetentionDays = 30
    }
}

function Load-Config {
    param([string]$Path)
    if (Test-Path $Path) {
        try { return Get-Content $Path | ConvertFrom-Json }
        catch { Write-Log "Config error, using defaults" -Level "WARN"; return Get-DefaultConfig }
    }
    $default = Get-DefaultConfig
    $default | ConvertTo-Json -Depth 10 | Out-File $Path -Encoding UTF8
    return $default
}

# === LOGGING SYSTEM ===
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    
    $colors = @{ "ERROR" = "Red"; "WARN" = "Yellow"; "SUCCESS" = "Green" }
    Write-Host $entry -ForegroundColor $colors[$Level]
    
    try { Add-Content -Path $LOG_FILE -Value $entry -Encoding UTF8 }
    catch { Write-Host "Log write failed" -ForegroundColor Red }
}

# === CORE PROCESSING FUNCTIONS ===
function Get-ServerLogFiles {
    param([object]$Server, [int]$Hours)
    $cutoff = (Get-Date).AddHours(-$Hours)
    $allFiles = @()
    
    foreach ($logPath in $Server.LogPaths) {
        if (Test-Path $logPath) {
            $files = Get-ChildItem -Path $logPath -Filter "*.log" | Where-Object { $_.LastWriteTime -ge $cutoff }
            foreach ($file in $files) {
                $allFiles += @{
                    File = $file
                    Server = $Server.Name
                    Type = if ($logPath -like "*SMTPReceive*") { "Receive" } else { "Send" }
                    Path = $logPath
                }
            }
        } else {
            Write-Log "Path not found: $logPath on $($Server.Name)" -Level "WARN"
        }
    }
    return $allFiles
}

function Parse-LogFile {
    param([hashtable]$LogInfo)
    
    try {
        $content = Get-Content -Path $LogInfo.File.FullName -ErrorAction Stop
        $headers = ($content | Where-Object { $_.StartsWith("#Fields:") } | Select-Object -First 1) -replace "#Fields: ", "" -split ","
        
        if (-not $headers) { return @() }
        
        $data = $content | Where-Object { -not $_.StartsWith("#") -and $_.Trim() } | ForEach-Object {
            $fields = $_ -split ","
            $record = @{}
            for ($i = 0; $i -lt [Math]::Min($headers.Count, $fields.Count); $i++) {
                $record[$headers[$i]] = $fields[$i]
            }
            $record.Server = $LogInfo.Server
            $record.LogType = $LogInfo.Type
            $record.SourceFile = $LogInfo.File.Name
            $record
        }
        
        return $data
    }
    catch {
        Write-Log "Parse error: $($LogInfo.File.Name) - $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

function Classify-Errors {
    param([array]$Records)
    
    $errors = @()
    foreach ($record in $Records) {
        $errorInfo = $null
        
        # Check for SMTP error patterns
        foreach ($pattern in $SMTP_ERROR_PATTERNS) {
            if ($record.data -match $pattern.Code) {
                $errorInfo = @{
                    Type = $pattern.Type
                    Severity = $pattern.Severity
                    Category = $pattern.Category
                    Code = $matches[0]
                }
                break
            }
        }
        
        # Only include errors that have meaningful details OR are not connection errors
        if ($errorInfo -or $record.event -in @("*", "!")) {
            # Filter out connection errors without meaningful details
            $shouldInclude = $true
            
            # If it's a connection error (no specific error pattern matched)
            if (-not $errorInfo) {
                # Check if data field is null, empty, or contains only basic connection info
                if ([string]::IsNullOrWhiteSpace($record.data) -or 
                    $record.data -match "^\s*$" -or 
                    $record.data -match "^[-\s]*$") {
                    $shouldInclude = $false
                    Write-Log "Skipping connection error without details: $($record.event)" -Level "WARN"
                }
            }
            
            if ($shouldInclude) {
                $errors += @{
                    Timestamp = [DateTime]::Parse($record.'date-time')
                    Server = $record.Server
                    LogType = $record.LogType
                    ConnectorId = $record.'connector-id'
                    RemoteEndpoint = $record.'remote-endpoint'
                    LocalEndpoint = $record.'local-endpoint'
                    Event = $record.event
                    Data = $record.data
                    ErrorType = if ($errorInfo.Type) { $errorInfo.Type } else { "Connection Error" }
                    Severity = if ($errorInfo.Severity) { $errorInfo.Severity } else { "Medium" }
                    Category = if ($errorInfo.Category) { $errorInfo.Category } else { "Network" }
                    Code = if ($errorInfo.Code) { $errorInfo.Code } else { "N/A" }
                    SourceFile = $record.SourceFile
                }
            }
        }
    }
    
    return $errors
}

function Generate-ErrorAnalysis {
    param([array]$Errors)
    
    if ($Errors.Count -eq 0) {
        return @{
            Summary = @{ Total = 0; Critical = 0; Warning = 0; Info = 0 }
            ByServer = @(); BySeverity = @(); ByCategory = @(); ByHour = @()
            TopErrors = @(); RecentErrors = @()
            TimeRange = @{ Start = "N/A"; End = "N/A" }
        }
    }
    
    $sorted = $Errors | Sort-Object Timestamp
    $severityCount = $Errors | Group-Object Severity | ForEach-Object { @{ Severity = $_.Name; Count = $_.Count } }
    
    return @{
        Summary = @{
            Total = $Errors.Count
            Critical = ($Errors | Where-Object { $_.Severity -eq "High" }).Count
            Warning = ($Errors | Where-Object { $_.Severity -eq "Medium" }).Count
            Info = ($Errors | Where-Object { $_.Severity -eq "Low" }).Count
        }
        ByServer = $Errors | Group-Object Server | ForEach-Object { @{ Server = $_.Name; Count = $_.Count; Errors = $_.Group } }
        BySeverity = $severityCount
        ByCategory = $Errors | Group-Object Category | ForEach-Object { @{ Category = $_.Name; Count = $_.Count } }
        ByHour = $Errors | Group-Object { $_.Timestamp.Hour } | ForEach-Object { @{ Hour = $_.Name; Count = $_.Count } }
        TopErrors = $Errors | Group-Object ErrorType | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Type = $_.Name; Count = $_.Count } }
        RecentErrors = $sorted | Select-Object -Last 20
        TimeRange = @{
            Start = $sorted[0].Timestamp.ToString("yyyy-MM-dd HH:mm:ss")
            End = $sorted[-1].Timestamp.ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

function Generate-HTMLReport {
    param([hashtable]$Analysis, [object]$Config)
    
    $alertLevel = if ($Analysis.Summary.Critical -gt 0) { "critical" } elseif ($Analysis.Summary.Warning -gt 0) { "warning" } else { "success" }
    $alertColors = @{ critical = "#dc3545"; warning = "#ffc107"; success = "#28a745" }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>$($Config.ReportConfig.Title)</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f8f9fa; }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, $($alertColors[$alertLevel]), $(if($alertLevel -eq "critical"){"#c82333"}elseif($alertLevel -eq "warning"){"#e0a800"}else{"#20c997"})); color: white; padding: 30px; border-radius: 12px; margin-bottom: 25px; text-align: center; }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { opacity: 0.9; margin: 5px 0; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: white; padding: 25px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); text-align: center; }
        .stat-card.critical { border-left: 5px solid #dc3545; }
        .stat-card.warning { border-left: 5px solid #ffc107; }
        .stat-card.info { border-left: 5px solid #17a2b8; }
        .stat-card.success { border-left: 5px solid #28a745; }
        .stat-value { font-size: 2.5em; font-weight: bold; margin-bottom: 10px; }
        .stat-label { color: #6c757d; font-size: 0.9em; }
        .section { background: white; margin-bottom: 25px; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section-header { background: #f8f9fa; padding: 20px; border-bottom: 1px solid #dee2e6; }
        .section-content { padding: 20px; }
        .section h2 { color: #495057; margin-bottom: 10px; }
        .table-responsive { overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #dee2e6; }
        th { background: #f8f9fa; font-weight: 600; color: #495057; }
        tr:hover { background: #f8f9fa; }
        .severity-high { color: #dc3545; font-weight: bold; }
        .severity-medium { color: #ffc107; font-weight: bold; }
        .severity-low { color: #28a745; font-weight: bold; }
        .server-health { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .server-card { border: 1px solid #dee2e6; border-radius: 8px; padding: 15px; }
        .server-card.healthy { border-color: #28a745; }
        .server-card.warning { border-color: #ffc107; }
        .server-card.critical { border-color: #dc3545; }
        .server-name { font-weight: bold; margin-bottom: 10px; }
        .server-stats { display: flex; justify-content: space-between; align-items: center; }
        .badge { padding: 4px 8px; border-radius: 4px; font-size: 0.8em; font-weight: bold; }
        .badge.success { background: #d4edda; color: #155724; }
        .badge.warning { background: #fff3cd; color: #856404; }
        .badge.danger { background: #f8d7da; color: #721c24; }
        .timestamp { font-size: 0.85em; color: #6c757d; }
        .no-errors { text-align: center; color: #28a745; padding: 40px; }
        .footer { text-align: center; margin-top: 30px; padding: 20px; color: #6c757d; font-size: 0.9em; }
        .filter-note { background: #e3f2fd; border: 1px solid #2196f3; border-radius: 8px; padding: 15px; margin-bottom: 20px; }
        .filter-note h3 { color: #1976d2; margin-bottom: 8px; }
        .filter-note p { color: #424242; margin: 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>$($Config.ReportConfig.Title)</h1>
            <p><strong>$($Config.ReportConfig.CompanyName)</strong></p>
            <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Analysis Period: $($Analysis.TimeRange.Start) - $($Analysis.TimeRange.End)</p>
        </div>
        
        <div class="filter-note">
            <h3>📊 Report Focus</h3>
            <p>This report shows only meaningful SMTP errors with detailed information. Connection errors without specific details are filtered out to focus on core Exchange issues.</p>
        </div>
"@

    if ($Analysis.Summary.Total -eq 0) {
        $html += '<div class="no-errors"><h2>✅ All Exchange Servers Operating Normally</h2><p>No meaningful SMTP errors detected during the monitoring period.</p></div>'
    } else {
        $html += @"
        <div class="stats-grid">
            <div class="stat-card critical">
                <div class="stat-value">$($Analysis.Summary.Total)</div>
                <div class="stat-label">Meaningful Errors</div>
            </div>
            <div class="stat-card critical">
                <div class="stat-value">$($Analysis.Summary.Critical)</div>
                <div class="stat-label">Critical Issues</div>
            </div>
            <div class="stat-card warning">
                <div class="stat-value">$($Analysis.Summary.Warning)</div>
                <div class="stat-label">Warnings</div>
            </div>
            <div class="stat-card info">
                <div class="stat-value">$($Analysis.Summary.Info)</div>
                <div class="stat-label">Info Messages</div>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">
                <h2>Exchange Server Health Status</h2>
            </div>
            <div class="section-content">
                <div class="server-health">
"@
        
        foreach ($server in $Analysis.ByServer) {
            $status = if ($server.Count -eq 0) { "healthy" } elseif ($server.Count -lt 10) { "warning" } else { "critical" }
            $badge = if ($status -eq "healthy") { "success" } elseif ($status -eq "warning") { "warning" } else { "danger" }
            
            $html += @"
                    <div class="server-card $status">
                        <div class="server-name">$($server.Server)</div>
                        <div class="server-stats">
                            <span>$($server.Count) Errors</span>
                            <span class="badge $badge">$($status.ToUpper())</span>
                        </div>
                    </div>
"@
        }
        
        $html += @"
                </div>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">
                <h2>Error Distribution by Type</h2>
            </div>
            <div class="section-content">
                <div class="table-responsive">
                    <table>
                        <thead>
                            <tr><th>Error Type</th><th>Count</th><th>Percentage</th></tr>
                        </thead>
                        <tbody>
"@
        
        foreach ($error in $Analysis.TopErrors) {
            $percentage = [math]::Round(($error.Count / $Analysis.Summary.Total) * 100, 1)
            $html += "<tr><td>$($error.Type)</td><td>$($error.Count)</td><td>$percentage%</td></tr>"
        }
        
        $html += @"
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">
                <h2>Recent Critical Errors with Details</h2>
            </div>
            <div class="section-content">
                <div class="table-responsive">
                    <table>
                        <thead>
                            <tr><th>Time</th><th>Server</th><th>Type</th><th>Severity</th><th>Remote Host</th><th>Details</th></tr>
                        </thead>
                        <tbody>
"@
        
        foreach ($error in $Analysis.RecentErrors) {
            $severityClass = "severity-$($error.Severity.ToLower())"
            $html += "<tr><td class='timestamp'>$($error.Timestamp.ToString("HH:mm:ss"))</td><td>$($error.Server)</td><td>$($error.ErrorType)</td><td class='$severityClass'>$($error.Severity)</td><td>$($error.RemoteEndpoint)</td><td>$($error.Data)</td></tr>"
        }
        
        $html += @"
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
"@
    }
    
    $html += @"
        <div class="footer">
            <p>Enhanced Exchange SMTP Monitor v2.0 | $($Config.ReportConfig.CompanyName)</p>
            <p>Monitoring $(($Config.ExchangeServers | Measure-Object).Count) Exchange Servers | Last $($Config.ReportConfig.HourRange) Hour(s) | Filtered for Meaningful Errors</p>
        </div>
    </div>
</body>
</html>
"@
    
    return $html
}

function Send-AlertEmail {
    param([string]$Html, [object]$Config, [hashtable]$Analysis)
    
    try {
        $smtp = $Config.EmailConfig
        $subject = $smtp.Subject -replace "{DATE}", (Get-Date -Format "yyyy-MM-dd")
        $subject += " - $($Analysis.Summary.Total) Meaningful Errors"
        
        $params = @{
            SmtpServer = $smtp.SMTPServer; Port = $smtp.SMTPPort; UseSsl = $smtp.EnableSSL
            From = $smtp.From; To = $smtp.To; Subject = $subject
            Body = $Html; BodyAsHtml = $true
        }
        
        if ($smtp.Username) {
            $params.Credential = New-Object System.Management.Automation.PSCredential(
                $smtp.Username, 
                (ConvertTo-SecureString $smtp.Password -AsPlainText -Force)
            )
        }
        
        Send-MailMessage @params
        Write-Log "Alert email sent successfully" -Level "SUCCESS"
    }
    catch {
        Write-Log "Email failed: $($_.Exception.Message)" -Level "ERROR"
    }
}

# === MAIN EXECUTION ===
function Main {
    Write-Log "=== Exchange SMTP Error Monitor v2.0 Started ==="
    
    try {
        $config = Load-Config -Path $ConfigFile
        $config.ReportConfig.HourRange = $HourRange
        $config.ReportConfig.ErrorsOnly = $ErrorsOnly
        
        # Create output directory
        if (-not (Test-Path $config.OutputDirectory)) {
            New-Item -ItemType Directory -Path $config.OutputDirectory -Force | Out-Null
        }
        
        # Process all servers
        Write-Log "Processing $($config.ExchangeServers.Count) Exchange servers..."
        $allRecords = @()
        
        foreach ($server in $config.ExchangeServers) {
            Write-Log "Processing server: $($server.Name)"
            $logFiles = Get-ServerLogFiles -Server $server -Hours $HourRange
            
            foreach ($logFile in $logFiles) {
                $records = Parse-LogFile -LogInfo $logFile
                $allRecords += $records
            }
        }
        
        Write-Log "Total records processed: $($allRecords.Count)"
        
        # Analyze errors
        $errors = Classify-Errors -Records $allRecords
        $analysis = Generate-ErrorAnalysis -Errors $errors
        
        # Generate reports
        $html = Generate-HTMLReport -Analysis $analysis -Config $config
        
        # Save reports
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
        $htmlPath = Join-Path $config.OutputDirectory "SMTP_Error_Dashboard_$timestamp.html"
        $html | Out-File -FilePath $htmlPath -Encoding UTF8
        
        if ($errors.Count -gt 0) {
            $csvPath = Join-Path $config.OutputDirectory "SMTP_Errors_$timestamp.csv"
            $errors | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Log "CSV report saved: $csvPath"
        }
        
        # Send email alert
        if ($SendEmail) {
            Send-AlertEmail -Html $html -Config $config -Analysis $analysis
        }
        
        # Summary
        Write-Log "=== MONITORING SUMMARY ===" -Level "SUCCESS"
        Write-Log "Servers monitored: $($config.ExchangeServers.Count)" -Level "SUCCESS"
        Write-Log "Meaningful errors found: $($errors.Count)" -Level "SUCCESS"
        Write-Log "Critical: $($analysis.Summary.Critical) | Warning: $($analysis.Summary.Warning) | Info: $($analysis.Summary.Info)" -Level "SUCCESS"
        Write-Log "Report saved: $htmlPath" -Level "SUCCESS"
        
    }
    catch {
        Write-Log "Critical error: $($_.Exception.Message)" -Level "ERROR"
        exit 1
    }
    
    Write-Log "=== Exchange SMTP Error Monitor Completed ==="
}

# Execute
Main