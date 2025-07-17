# Exchange SMTP Protocol Log Parser - Error Reporting
# Author: System Engineer  
# Version: 1.0
# Last Updated: $(Get-Date -Format "yyyy-MM-dd")

param(
    [string]$ConfigFile = "config.json",
    [switch]$SendEmail,
    [switch]$GenerateHTML = $true,
    [switch]$Verbose,
    [int]$HourRange = 1,
    [switch]$ErrorsOnly = $true
)

# === LOGGING CONFIGURATION ===
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LOG_FILE = Join-Path $SCRIPT_DIR ("smtp_log_analyzer_" + (Get-Date -Format "yyyyMMdd") + ".log")

# === SMTP ERROR PATTERNS ===
$SMTP_ERROR_PATTERNS = @(
    @{ Pattern = "^4\d{2}"; Type = "Temporary Error"; Description = "4xx Temporary failure" },
    @{ Pattern = "^5\d{2}"; Type = "Permanent Error"; Description = "5xx Permanent failure" },
    @{ Pattern = "421"; Type = "Service Not Available"; Description = "Service not available, closing transmission channel" },
    @{ Pattern = "450"; Type = "Mailbox Unavailable"; Description = "Requested mail action not taken: mailbox unavailable" },
    @{ Pattern = "451"; Type = "Local Error"; Description = "Requested action aborted: local error in processing" },
    @{ Pattern = "452"; Type = "Insufficient Storage"; Description = "Requested action not taken: insufficient system storage" },
    @{ Pattern = "500"; Type = "Syntax Error"; Description = "Syntax error, command unrecognized" },
    @{ Pattern = "501"; Type = "Parameter Error"; Description = "Syntax error in parameters or arguments" },
    @{ Pattern = "502"; Type = "Command Not Implemented"; Description = "Command not implemented" },
    @{ Pattern = "503"; Type = "Bad Sequence"; Description = "Bad sequence of commands" },
    @{ Pattern = "504"; Type = "Parameter Not Implemented"; Description = "Command parameter not implemented" },
    @{ Pattern = "550"; Type = "Mailbox Unavailable"; Description = "Requested action not taken: mailbox unavailable" },
    @{ Pattern = "551"; Type = "User Not Local"; Description = "User not local; please try forward-path" },
    @{ Pattern = "552"; Type = "Storage Exceeded"; Description = "Requested mail action aborted: exceeded storage allocation" },
    @{ Pattern = "553"; Type = "Mailbox Name Invalid"; Description = "Requested action not taken: mailbox name not allowed" },
    @{ Pattern = "554"; Type = "Transaction Failed"; Description = "Transaction failed" },
    @{ Pattern = "timeout"; Type = "Connection Timeout"; Description = "Connection timeout" },
    @{ Pattern = "connection.*reset"; Type = "Connection Reset"; Description = "Connection reset by peer" },
    @{ Pattern = "authentication.*fail"; Type = "Authentication Failed"; Description = "Authentication failure" },
    @{ Pattern = "SSL.*error"; Type = "SSL Error"; Description = "SSL/TLS connection error" },
    @{ Pattern = "certificate.*error"; Type = "Certificate Error"; Description = "Certificate validation error" },
    @{ Pattern = "disconnected"; Type = "Disconnection"; Description = "Unexpected disconnection" },
    @{ Pattern = "rejected"; Type = "Message Rejected"; Description = "Message rejected" },
    @{ Pattern = "blocked"; Type = "Blocked"; Description = "Connection or message blocked" },
    @{ Pattern = "quarantine"; Type = "Quarantined"; Description = "Message quarantined" },
    @{ Pattern = "virus"; Type = "Virus Detected"; Description = "Virus or malware detected" },
    @{ Pattern = "spam"; Type = "Spam Detected"; Description = "Spam filter triggered" }
)

# === LOAD CONFIGURATION ===
function Load-Configuration {
    param([string]$ConfigPath)
    
    $defaultConfig = @{
        LogDirectories = @(
            "C:\Program Files\Microsoft\Exchange Server\V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SMTPReceive",
            "C:\Program Files\Microsoft\Exchange Server\V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SMTPSend"
        )
        OutputDirectory = "C:\Scripts\SMTPLogReports"
        EmailConfig = @{
            SMTPServer = "smtp.gmail.com"
            SMTPPort = 587
            Username = "ekiputra543@gmail.com"
            Password = "kobl keqi ybnk qwfq"
            From = "ekiputra543@gmail.com"
            To = "ekiputra234@gmail.com"
            Subject = "SMTP Protocol Error Report - {DATE}"
            EnableSSL = $true
        }
        ReportConfig = @{
            CompanyName = "PT Bank Mandiri"
            ReportTitle = "Exchange SMTP Protocol Error Report"
            HourRange = 1
            ErrorsOnly = $true
        }
        CleanupConfig = @{
            RetentionDays = 30
            CleanupReports = $true
        }
    }
    
    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath | ConvertFrom-Json
            Write-Log "Configuration loaded from: $ConfigPath"
            return $config
        }
        catch {
            Write-Log "Error loading configuration: $($_.Exception.Message)" -Level "ERROR"
            Write-Log "Using default configuration"
            return $defaultConfig
        }
    }
    else {
        Write-Log "Configuration file not found. Creating default configuration at: $ConfigPath"
        $defaultConfig | ConvertTo-Json -Depth 10 | Out-File $ConfigPath -Encoding UTF8
        return $defaultConfig
    }
}

# === LOGGING FUNCTIONS ===
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry }
    }
    
    # Write to log file
    try {
        Add-Content -Path $LOG_FILE -Value $logEntry -Encoding UTF8
    }
    catch {
        Write-Host "Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Start-LogSession {
    Write-Log "=== SMTP PROTOCOL LOG ANALYZER SESSION STARTED ===" -Level "INFO"
    Write-Log "Script Version: 1.0"
    Write-Log "Execution Time: $(Get-Date)"
    Write-Log "Hour Range: $HourRange hour(s)"
    Write-Log "Errors Only: $ErrorsOnly"
}

function End-LogSession {
    param([bool]$Success = $true)
    
    $status = if ($Success) { "SUCCESS" } else { "FAILED" }
    Write-Log "=== SMTP PROTOCOL LOG ANALYZER SESSION ENDED: $status ===" -Level $(if ($Success) { "SUCCESS" } else { "ERROR" })
}

# === MAIN FUNCTIONS ===
function Get-LogFilesInTimeRange {
    param(
        [string[]]$LogDirectories,
        [int]$HourRange = 1
    )
    
    $now = Get-Date
    $startTime = $now.AddHours(-$HourRange)
    $endTime = $now
    
    Write-Log "Searching for log files between $($startTime.ToString("yyyy-MM-dd HH:mm:ss")) and $($endTime.ToString("yyyy-MM-dd HH:mm:ss"))"
    
    $logFiles = @()
    
    foreach ($logDir in $LogDirectories) {
        if (-not (Test-Path $logDir)) {
            Write-Log "Log directory does not exist: $logDir" -Level "WARNING"
            continue
        }
        
        $files = Get-ChildItem -Path $logDir -Filter "*.log" | Where-Object {
            $_.LastWriteTime -ge $startTime -and $_.LastWriteTime -le $endTime
        }
        
        Write-Log "Found $($files.Count) log files in $logDir"
        $logFiles += $files
    }
    
    Write-Log "Total log files found: $($logFiles.Count)"
    return $logFiles
}

function Parse-SMTPLogFile {
    param(
        [System.IO.FileInfo]$LogFile
    )
    
    Write-Log "Parsing log file: $($LogFile.Name)"
    
    try {
        $lines = Get-Content -Path $LogFile.FullName -ErrorAction Stop
        $parsedData = @()
        
        # Find header line
        $headerLine = $null
        foreach ($line in $lines) {
            if ($line.StartsWith("#Fields:")) {
                $headerLine = $line.Replace("#Fields: ", "").Trim().Split(",")
                break
            }
        }
        
        if (-not $headerLine) {
            Write-Log "Header not found in $($LogFile.Name)" -Level "WARNING"
            return @()
        }
        
        # Parse data lines
        $dataLines = $lines | Where-Object { -not $_.StartsWith("#") -and $_.Trim() -ne "" }

        foreach ($dataLine in $dataLines) {
            $fields = $dataLine.Split(",")
            if ($fields.Count -ge $headerLine.Count) {
                $obj = New-Object PSObject
                for ($i = 0; $i -lt $headerLine.Count; $i++) {
                    if ($i -lt $fields.Count) {
                        $obj | Add-Member -MemberType NoteProperty -Name $headerLine[$i] -Value $fields[$i]
                    } else {
                        $obj | Add-Member -MemberType NoteProperty -Name $headerLine[$i] -Value ""
                    }
                }

                $logType = if ($LogFile.DirectoryName -like "*SMTPReceive*") { 
                    "SMTP Receive" 
                } else { 
                    "SMTP Send" 
                }

                $obj | Add-Member -MemberType NoteProperty -Name "SourceFile" -Value $LogFile.Name
                $obj | Add-Member -MemberType NoteProperty -Name "LogType" -Value $logType

                $parsedData += $obj
            }
        }

        Write-Log "Parsed $($parsedData.Count) records from $($LogFile.Name)"
        return $parsedData
        
    }
    catch {
        Write-Log "Error parsing file $($LogFile.Name): $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

function Identify-ErrorRecords {
    param([array]$Data)
    
    Write-Log "Identifying error records..."
    $errorRecords = @()
    
    foreach ($record in $Data) {
        $isError = $false
        $errorType = ""
        $errorDescription = ""
        
        # Check data field for error patterns
        $dataField = $record.data
        if ($dataField) {
            foreach ($pattern in $SMTP_ERROR_PATTERNS) {
                if ($dataField -match $pattern.Pattern) {
                    $isError = $true
                    $errorType = $pattern.Type
                    $errorDescription = $pattern.Description
                    break
                }
            }
        }
        
        # Check event field for error indicators
        $eventField = $record.event
        if ($eventField -and ($eventField -eq "*" -or $eventField -eq "!")) {
            $isError = $true
            if (-not $errorType) {
                $errorType = "Connection Error"
                $errorDescription = "Connection issue detected"
            }
        }
        
        if ($isError) {
            $record | Add-Member -MemberType NoteProperty -Name "ErrorType" -Value $errorType -Force
            $record | Add-Member -MemberType NoteProperty -Name "ErrorDescription" -Value $errorDescription -Force
            $record | Add-Member -MemberType NoteProperty -Name "ParsedTimestamp" -Value ([DateTime]::Parse($record."date-time")) -Force
            $errorRecords += $record
        }
    }
    
    Write-Log "Found $($errorRecords.Count) error records"
    return $errorRecords
}

function Generate-ErrorSummary {
    param([array]$ErrorData)
    
    Write-Log "Generating error summary..."
    
    if ($ErrorData.Count -eq 0) {
        return @{
            TotalErrors = 0
            ErrorsByType = @()
            ErrorsByHour = @()
            ErrorsByLogType = @()
            ErrorsByConnector = @()
            RecentErrors = @()
            DateRange = @{ Start = "N/A"; End = "N/A" }
        }
    }
    
    # Get time range
    $timestamps = $ErrorData | ForEach-Object { $_.ParsedTimestamp } | Sort-Object
    $earliestError = $timestamps | Select-Object -First 1
    $latestError = $timestamps | Select-Object -Last 1
    
    # Error distribution by type
    $errorsByType = $ErrorData | Group-Object ErrorType | Select-Object @{Name='ErrorType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}}, @{Name='Percentage';Expression={[math]::Round(($_.Count / $ErrorData.Count) * 100, 2)}} | Sort-Object Count -Descending
    
    # Error distribution by hour
    $errorsByHour = $ErrorData | Group-Object { $_.ParsedTimestamp.Hour } | Select-Object @{Name='Hour';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Hour
    
    # Error distribution by log type
    $errorsByLogType = $ErrorData | Group-Object LogType | Select-Object @{Name='LogType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}}
    
    # Error distribution by connector
    $errorsByConnector = $ErrorData | Group-Object 'connector-id' | Select-Object @{Name='Connector';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Count -Descending | Select-Object -First 10
    
    # Recent errors (last 20)
    $recentErrors = $ErrorData | Sort-Object ParsedTimestamp -Descending | Select-Object -First 20
    
    return @{
        TotalErrors = $ErrorData.Count
        ErrorsByType = $errorsByType
        ErrorsByHour = $errorsByHour
        ErrorsByLogType = $errorsByLogType
        ErrorsByConnector = $errorsByConnector
        RecentErrors = $recentErrors
        DateRange = @{
            Start = if ($earliestError) { $earliestError.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
            End = if ($latestError) { $latestError.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
        }
    }
}

function Generate-HTMLErrorReport {
    param([hashtable]$Summary, [object]$Config)
    
    Write-Log "Generating HTML error report..."
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$($Config.ReportConfig.ReportTitle)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 30px; border-bottom: 2px solid #dc3545; padding-bottom: 20px; }
        .header h1 { color: #dc3545; margin: 0; }
        .header p { color: #666; margin: 5px 0; }
        .summary-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .card { background: linear-gradient(135deg, #dc3545, #c82333); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .card.warning { background: linear-gradient(135deg, #ffc107, #e0a800); }
        .card.info { background: linear-gradient(135deg, #17a2b8, #138496); }
        .card h3 { margin: 0 0 10px 0; font-size: 14px; opacity: 0.9; }
        .card .value { font-size: 24px; font-weight: bold; margin: 0; }
        .section { margin-bottom: 30px; }
        .section h2 { color: #dc3545; border-bottom: 1px solid #ddd; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; font-weight: 600; }
        tr:hover { background-color: #f8f9fa; }
        .error-high { background-color: #f8d7da; color: #721c24; }
        .error-medium { background-color: #fff3cd; color: #856404; }
        .error-low { background-color: #d4edda; color: #155724; }
        .footer { text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
        .no-errors { text-align: center; color: #28a745; font-size: 18px; margin: 40px 0; }
        .timestamp { font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>$($Config.ReportConfig.ReportTitle)</h1>
            <p><strong>$($Config.ReportConfig.CompanyName)</strong></p>
            <p>Report Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>Time Range: Last $($Config.ReportConfig.HourRange) hour(s)</p>
            <p>Analysis Period: $($Summary.DateRange.Start) to $($Summary.DateRange.End)</p>
        </div>
"@

    if ($Summary.TotalErrors -eq 0) {
        $html += @"
        <div class="no-errors">
            <h2>✅ No SMTP Protocol Errors Found</h2>
            <p>All SMTP connections are operating normally during the analyzed period.</p>
        </div>
"@
    } else {
        $html += @"
        <div class="summary-cards">
            <div class="card">
                <h3>Total Errors</h3>
                <p class="value">$($Summary.TotalErrors)</p>
            </div>
            <div class="card warning">
                <h3>Error Types</h3>
                <p class="value">$(($Summary.ErrorsByType | Measure-Object).Count)</p>
            </div>
            <div class="card info">
                <h3>Affected Connectors</h3>
                <p class="value">$(($Summary.ErrorsByConnector | Measure-Object).Count)</p>
            </div>
        </div>
        
        <div class="section">
            <h2>Error Distribution by Type</h2>
            <table>
                <thead>
                    <tr><th>Error Type</th><th>Count</th><th>Percentage</th><th>Description</th></tr>
                </thead>
                <tbody>
"@
        
        foreach ($error in $Summary.ErrorsByType) {
            $cssClass = if ($error.Percentage -ge 50) { "error-high" } elseif ($error.Percentage -ge 20) { "error-medium" } else { "error-low" }
            $description = ($SMTP_ERROR_PATTERNS | Where-Object { $_.Type -eq $error.ErrorType }).Description
            if (-not $description) { $description = "Unknown error type" }
            
            $html += "<tr class='$cssClass'><td>$($error.ErrorType)</td><td>$($error.Count)</td><td>$($error.Percentage)%</td><td>$description</td></tr>"
        }
        
        $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Error Distribution by Hour</h2>
            <table>
                <thead>
                    <tr><th>Hour</th><th>Error Count</th></tr>
                </thead>
                <tbody>
"@
        
        foreach ($hour in $Summary.ErrorsByHour) {
            $html += "<tr><td>$($hour.Hour):00</td><td>$($hour.Count)</td></tr>"
        }
        
        $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Error Distribution by Log Type</h2>
            <table>
                <thead>
                    <tr><th>Log Type</th><th>Error Count</th></tr>
                </thead>
                <tbody>
"@
        
        foreach ($logType in $Summary.ErrorsByLogType) {
            $html += "<tr><td>$($logType.LogType)</td><td>$($logType.Count)</td></tr>"
        }
        
        $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Top Affected Connectors</h2>
            <table>
                <thead>
                    <tr><th>Connector</th><th>Error Count</th></tr>
                </thead>
                <tbody>
"@
        
        foreach ($connector in $Summary.ErrorsByConnector) {
            $html += "<tr><td>$($connector.Connector)</td><td>$($connector.Count)</td></tr>"
        }
        
        $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Recent Errors (Last 20)</h2>
            <table>
                <thead>
                    <tr><th>Timestamp</th><th>Error Type</th><th>Connector</th><th>Remote Endpoint</th><th>Error Details</th></tr>
                </thead>
                <tbody>
"@
        
        foreach ($error in $Summary.RecentErrors) {
            $html += "<tr><td class='timestamp'>$($error.ParsedTimestamp.ToString("yyyy-MM-dd HH:mm:ss"))</td><td>$($error.ErrorType)</td><td>$($error.'connector-id')</td><td>$($error.'remote-endpoint')</td><td>$($error.data)</td></tr>"
        }
        
        $html += @"
                </tbody>
            </table>
        </div>
"@
    }
    
    $html += @"
        <div class="footer">
            <p>Report generated by Exchange SMTP Protocol Log Analyzer v1.0 | $($Config.ReportConfig.CompanyName)</p>
            <p>Monitoring Period: Last $($Config.ReportConfig.HourRange) hour(s) | Errors Only: $($Config.ReportConfig.ErrorsOnly)</p>
            <p>For questions or issues, please contact your system administrator.</p>
        </div>
    </div>
</body>
</html>
"@
    
    Write-Log "HTML error report generated successfully"
    return $html
}

function Send-EmailReport {
    param([string]$HtmlContent, [object]$Config, [hashtable]$Summary)
    
    Write-Log "Preparing to send email report..."
    
    try {
        $smtpConfig = $Config.EmailConfig
        $subject = $smtpConfig.Subject -replace "{DATE}", (Get-Date -Format "yyyy-MM-dd")
        
        # Add error count to subject
        $subject += " - $($Summary.TotalErrors) Errors Found"
        
        # Create secure credentials if password is provided
        if ($smtpConfig.Password) {
            $securePassword = ConvertTo-SecureString $smtpConfig.Password -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($smtpConfig.Username, $securePassword)
        }
        
        $emailParams = @{
            To = $smtpConfig.To
            From = $smtpConfig.From
            Subject = $subject
            Body = $HtmlContent
            BodyAsHtml = $true
            SmtpServer = $smtpConfig.SMTPServer
            Port = $smtpConfig.SMTPPort
            UseSsl = $smtpConfig.EnableSSL
        }
        
        if ($credential) {
            $emailParams.Credential = $credential
        }
        
        Send-MailMessage @emailParams
        Write-Log "Email report sent successfully to: $($smtpConfig.To -join ', ')" -Level "SUCCESS"
    }
    catch {
        Write-Log "Failed to send email report: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# === MAIN EXECUTION ===
function Main {
    $success = $false
    
    try {
        Start-LogSession
        
        # Load configuration
        $config = Load-Configuration -ConfigPath $ConfigFile
        
        # Override config with parameters
        $config.ReportConfig.HourRange = $HourRange
        $config.ReportConfig.ErrorsOnly = $ErrorsOnly
        
        # Create output directory
        $outputDir = $config.OutputDirectory
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # Get log files in time range
        $logFiles = Get-LogFilesInTimeRange -LogDirectories $config.LogDirectories -HourRange $HourRange
        
        if ($logFiles.Count -eq 0) {
            Write-Log "No log files found in specified time range" -Level "WARNING"
            $allData = @()
        } else {
            # Parse all log files
            $allData = @()
            foreach ($logFile in $logFiles) {
                $parsedData = Parse-SMTPLogFile -LogFile $logFile
                $allData += $parsedData
            }
        }
        
        Write-Log "Total records parsed: $($allData.Count)"
        
        # Identify errors
        $errorData = if ($ErrorsOnly) {
            Identify-ErrorRecords -Data $allData
        } else {
            $allData
        }
        
        # Generate summary
        $summary = Generate-ErrorSummary -ErrorData $errorData
        
        # Generate HTML report
        $htmlContent = Generate-HTMLErrorReport -Summary $summary -Config $config
        
        # Save HTML report
        $dateStr = Get-Date -Format "yyyy-MM-dd_HH-mm"
        $htmlFile = Join-Path $outputDir "SMTP_Error_Report_$dateStr.html"
        $htmlContent | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Log "HTML report saved: $htmlFile"
        
        # Save CSV report
        if ($errorData.Count -gt 0) {
            $csvFile = Join-Path $outputDir "SMTP_Errors_$dateStr.csv"
            $errorData | Select-Object ParsedTimestamp, ErrorType, ErrorDescription, LogType, 'connector-id', 'remote-endpoint', 'local-endpoint', event, data, SourceFile | Export-Csv -Path $csvFile -NoTypeInformation
            Write-Log "CSV report saved: $csvFile"
        }
        
        # Send email if requested
        if ($SendEmail) {
            Send-EmailReport -HtmlContent $htmlContent -Config $config -Summary $summary
        }
        
        # Display summary
        Write-Log "=== PROCESSING SUMMARY ===" -Level "SUCCESS"
        Write-Log "Log files processed: $($logFiles.Count)" -Level "SUCCESS"
        Write-Log "Total records parsed: $($allData.Count)" -Level "SUCCESS"
        Write-Log "Errors found: $($errorData.Count)" -Level "SUCCESS"
        Write-Log "Time range: $($summary.DateRange.Start) to $($summary.DateRange.End)" -Level "SUCCESS"
        Write-Log "Reports saved to: $outputDir" -Level "SUCCESS"
        
        $success = $true
    }
    catch {
        Write-Log "Critical error: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
        $success = $false
    }
    finally {
        End-LogSession -Success $success
    }
    
    if (-not $success) {
        exit 1
    }
}

# Execute main function
Main
