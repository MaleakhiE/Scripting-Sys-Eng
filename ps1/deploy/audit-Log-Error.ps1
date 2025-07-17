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
    # === Connection and Rate Limiting Errors ===
    @{ Pattern = "421 4\.3\.2 The maximum number of concurrent server connections has exceeded a per-source limit"; Type = "Connection Limit Exceeded"; Description = "421 Connection limit exceeded per source"; Category = "Rate Limiting" },
    @{ Pattern = "421 4\.7\.0 TLS required but not supported"; Type = "TLS Required"; Description = "421 TLS required but not supported by client"; Category = "Security" },
    @{ Pattern = "421 4\.7\.1 Service not available"; Type = "Service Unavailable"; Description = "421 Service not available, closing transmission channel"; Category = "Service" },
    
    # === Authentication and Security Errors ===
    @{ Pattern = "530 5\.7\.0 Must issue a STARTTLS command first"; Type = "STARTTLS Required"; Description = "530 STARTTLS command required"; Category = "Security" },
    @{ Pattern = "530 5\.7\.1 Authentication required"; Type = "Authentication Required"; Description = "530 Authentication required"; Category = "Security" },
    @{ Pattern = "535 5\.7\.3 Authentication unsuccessful"; Type = "Authentication Failed"; Description = "535 Authentication unsuccessful"; Category = "Security" },
    @{ Pattern = "535 5\.7\.8 Authentication credentials invalid"; Type = "Invalid Credentials"; Description = "535 Authentication credentials invalid"; Category = "Security" },
    @{ Pattern = "454 4\.7\.1 Temporary authentication failure"; Type = "Temporary Authentication Failure"; Description = "454 Temporary authentication failure"; Category = "Security" },
    
    # === Message Size and Storage Errors ===
    @{ Pattern = "552 5\.3\.4 Message size exceeds fixed maximum message size"; Type = "Message Too Large"; Description = "552 Message size exceeds maximum allowed"; Category = "Message Size" },
    @{ Pattern = "552 5\.2\.3 Message size exceeds maximum allowed"; Type = "Message Size Limit"; Description = "552 Message size exceeds limit"; Category = "Message Size" },
    @{ Pattern = "452 4\.3\.1 Insufficient system storage"; Type = "Insufficient Storage"; Description = "452 Insufficient system storage"; Category = "Storage" },
    @{ Pattern = "552 5\.2\.2 Mailbox full"; Type = "Mailbox Full"; Description = "552 Recipient mailbox full"; Category = "Storage" },
    
    # === Recipient and Address Errors ===
    @{ Pattern = "550 5\.1\.1 User unknown"; Type = "User Unknown"; Description = "550 User unknown in local recipient table"; Category = "Recipient" },
    @{ Pattern = "550 5\.1\.2 Host unknown"; Type = "Host Unknown"; Description = "550 Host unknown"; Category = "Recipient" },
    @{ Pattern = "550 5\.1\.3 Bad destination mailbox address"; Type = "Bad Mailbox Address"; Description = "550 Bad destination mailbox address"; Category = "Recipient" },
    @{ Pattern = "550 5\.1\.7 Bad sender's mailbox address"; Type = "Bad Sender Address"; Description = "550 Bad sender's mailbox address"; Category = "Sender" },
    @{ Pattern = "550 5\.1\.8 Bad sender's system address"; Type = "Bad Sender System"; Description = "550 Bad sender's system address"; Category = "Sender" },
    @{ Pattern = "553 5\.1\.3 Bad recipient address syntax"; Type = "Bad Recipient Syntax"; Description = "553 Bad recipient address syntax"; Category = "Recipient" },
    @{ Pattern = "553 5\.5\.4 Invalid domain name"; Type = "Invalid Domain"; Description = "553 Invalid domain name"; Category = "Domain" },
    
    # === Policy and Filtering Errors ===
    @{ Pattern = "550 5\.7\.1 Message rejected due to content"; Type = "Content Rejected"; Description = "550 Message rejected due to content policy"; Category = "Policy" },
    @{ Pattern = "550 5\.7\.1 Sender blocked"; Type = "Sender Blocked"; Description = "550 Sender blocked by policy"; Category = "Policy" },
    @{ Pattern = "550 5\.7\.1 Recipient blocked"; Type = "Recipient Blocked"; Description = "550 Recipient blocked by policy"; Category = "Policy" },
    @{ Pattern = "554 5\.7\.1 Message rejected"; Type = "Message Rejected"; Description = "554 Message rejected by policy"; Category = "Policy" },
    @{ Pattern = "541 5\.7\.1 Recipient address rejected"; Type = "Recipient Rejected"; Description = "541 Recipient address rejected"; Category = "Policy" },
    @{ Pattern = "550 5\.7\.1 Relaying denied"; Type = "Relaying Denied"; Description = "550 Relaying denied"; Category = "Policy" },
    
    # === Spam and Security Filtering ===
    @{ Pattern = "550 5\.7\.1 Spam message rejected"; Type = "Spam Rejected"; Description = "550 Message rejected as spam"; Category = "Spam Filter" },
    @{ Pattern = "554 5\.7\.1 Virus detected"; Type = "Virus Detected"; Description = "554 Message contains virus"; Category = "Antivirus" },
    @{ Pattern = "550 5\.7\.1 Malware detected"; Type = "Malware Detected"; Description = "550 Message contains malware"; Category = "Antivirus" },
    @{ Pattern = "550 5\.7\.1 Phishing detected"; Type = "Phishing Detected"; Description = "550 Phishing content detected"; Category = "Security" },
    
    # === Protocol and Syntax Errors ===
    @{ Pattern = "500 5\.5\.1 Command unrecognized"; Type = "Command Unrecognized"; Description = "500 Command unrecognized"; Category = "Protocol" },
    @{ Pattern = "501 5\.5\.4 Invalid parameters"; Type = "Invalid Parameters"; Description = "501 Invalid parameters or arguments"; Category = "Protocol" },
    @{ Pattern = "502 5\.5\.1 Command not implemented"; Type = "Command Not Implemented"; Description = "502 Command not implemented"; Category = "Protocol" },
    @{ Pattern = "503 5\.5\.1 Bad sequence of commands"; Type = "Bad Command Sequence"; Description = "503 Bad sequence of commands"; Category = "Protocol" },
    @{ Pattern = "504 5\.5\.4 Command parameter not implemented"; Type = "Parameter Not Implemented"; Description = "504 Command parameter not implemented"; Category = "Protocol" },
    
    # === Temporary Failures (4xx) ===
    @{ Pattern = "421 4\.4\.2 Connection dropped"; Type = "Connection Dropped"; Description = "421 Connection dropped"; Category = "Network" },
    @{ Pattern = "431 4\.3\.1 Insufficient system resources"; Type = "System Resources"; Description = "431 Insufficient system resources"; Category = "System" },
    @{ Pattern = "441 4\.4\.1 Connection timeout"; Type = "Connection Timeout"; Description = "441 Connection timeout"; Category = "Network" },
    @{ Pattern = "442 4\.4\.2 Connection lost"; Type = "Connection Lost"; Description = "442 Connection lost"; Category = "Network" },
    @{ Pattern = "446 4\.4\.6 Maximum hop count exceeded"; Type = "Max Hops Exceeded"; Description = "446 Maximum hop count exceeded"; Category = "Routing" },
    @{ Pattern = "450 4\.2\.1 Mailbox busy"; Type = "Mailbox Busy"; Description = "450 Mailbox temporarily unavailable"; Category = "Mailbox" },
    @{ Pattern = "451 4\.3\.0 Local error in processing"; Type = "Local Processing Error"; Description = "451 Local error in processing"; Category = "Processing" },
    @{ Pattern = "452 4\.3\.1 Insufficient system storage"; Type = "Storage Full"; Description = "452 Insufficient system storage"; Category = "Storage" },
    
    # === DNS and Network Errors ===
    @{ Pattern = "421 4\.4\.1 DNS lookup failed"; Type = "DNS Lookup Failed"; Description = "421 DNS lookup failed"; Category = "DNS" },
    @{ Pattern = "451 4\.4\.3 Domain name required"; Type = "Domain Required"; Description = "451 Domain name required"; Category = "DNS" },
    @{ Pattern = "450 4\.1\.8 Domain of sender address does not exist"; Type = "Sender Domain Invalid"; Description = "450 Sender domain does not exist"; Category = "DNS" },
    @{ Pattern = "550 5\.1\.2 Domain does not exist"; Type = "Domain Not Found"; Description = "550 Domain does not exist"; Category = "DNS" },
    
    # === Certificate and TLS Errors ===
    @{ Pattern = "454 4\.7\.5 Certificate validation failed"; Type = "Certificate Validation Failed"; Description = "454 Certificate validation failed"; Category = "TLS" },
    @{ Pattern = "530 5\.7\.0 TLS handshake failed"; Type = "TLS Handshake Failed"; Description = "530 TLS handshake failed"; Category = "TLS" },
    @{ Pattern = "421 4\.7\.0 TLS handshake timeout"; Type = "TLS Handshake Timeout"; Description = "421 TLS handshake timeout"; Category = "TLS" },
    
    # === Rate Limiting and Throttling ===
    @{ Pattern = "421 4\.7\.1 Service temporarily unavailable"; Type = "Service Throttled"; Description = "421 Service temporarily unavailable due to throttling"; Category = "Rate Limiting" },
    @{ Pattern = "452 4\.7\.1 Too many recipients"; Type = "Too Many Recipients"; Description = "452 Too many recipients"; Category = "Rate Limiting" },
    @{ Pattern = "421 4\.7\.0 Too many errors"; Type = "Too Many Errors"; Description = "421 Too many errors from client"; Category = "Rate Limiting" },
    
    # === Exchange-specific Errors ===
    @{ Pattern = "432 4\.3\.2 STOREDRV.Deliver.Exception"; Type = "Store Driver Exception"; Description = "432 Store driver delivery exception"; Category = "Exchange" },
    @{ Pattern = "554 5\.6\.0 SMTPSEND.DNS.NonExistentDomain"; Type = "DNS Non-existent Domain"; Description = "554 DNS non-existent domain"; Category = "Exchange" },
    @{ Pattern = "421 4\.3\.2 STOREDRV.ClientSubmit"; Type = "Store Driver Submit Error"; Description = "421 Store driver client submit error"; Category = "Exchange" },
    
    # === Generic Patterns (should be last) ===
    @{ Pattern = "^4\d{2}"; Type = "Temporary Failure"; Description = "4xx Temporary failure"; Category = "Temporary" },
    @{ Pattern = "^5\d{2}"; Type = "Permanent Failure"; Description = "5xx Permanent failure"; Category = "Permanent" }
) 


# === LOAD CONFIGURATION ===
function Load-Configuration {
    param([string]$ConfigPath)
    
    $defaultConfig = @{
        LogDirectories = @(
            "C:\Program Files\Microsoft\Exchange Server\V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SMTPReceive",
            "C:\Program Files\Microsoft\Exchange Server\V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SMTPSend"
        )
        OutputDirectory = "C:\Script\Task Scheduler\Audit Error Logs\SMTPLogReports"
        EmailConfig = @{
            SMTPServer = "10.248.58.22"
            SMTPPort = 25
            Username = ""
            Password = ""
            From = "report.envi.exchange@bankmandiri.co.id"
            To = "wsdemail@bankmandiri.co.id"
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
        
        # Removed "Connection Error" handling block:
        # Check event field for error indicators
        # $eventField = $record.event
        # if ($eventField -and ($eventField -eq "*" -or $eventField -eq "!")) {
        #     $isError = $true
        #     if (-not $errorType) {
        #         $errorType = "Connection Error"
        #         $errorDescription = "Connection issue detected"
        #     }
        # }
        
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

    # ===============================================
    # De-duplicate: only keep one error per Connector + ErrorType
    # ===============================================
    $DistinctErrors = @{}
    foreach ($item in $ErrorData) {
        $key = "$($item.'connector-id')|$($item.ErrorType)"
        if (-not $DistinctErrors.ContainsKey($key)) {
            $DistinctErrors[$key] = $item
        }
    }
    $UniqueErrorData = $DistinctErrors.Values

    # ===============================================
    # Build summaries based on unique error data
    # ===============================================

    # Get time range
    $timestamps = $UniqueErrorData | ForEach-Object { $_.ParsedTimestamp } | Sort-Object
    $earliestError = $timestamps | Select-Object -First 1
    $latestError = $timestamps | Select-Object -Last 1

    # Error distribution by type
    $errorsByType = $UniqueErrorData | Group-Object ErrorType | 
        Select-Object @{Name='ErrorType';Expression={$_.Name}}, 
                      @{Name='Count';Expression={$_.Count}}, 
                      @{Name='Percentage';Expression={[math]::Round(($_.Count / $UniqueErrorData.Count) * 100, 2)}} | 
        Sort-Object Count -Descending

    # Error distribution by hour
    $errorsByHour = $UniqueErrorData | Group-Object { $_.ParsedTimestamp.Hour } | 
        Select-Object @{Name='Hour';Expression={$_.Name}}, 
                      @{Name='Count';Expression={$_.Count}} | 
        Sort-Object Hour

    # Error distribution by log type
    $errorsByLogType = $UniqueErrorData | Group-Object LogType | 
        Select-Object @{Name='LogType';Expression={$_.Name}}, 
                      @{Name='Count';Expression={$_.Count}}

    # Error distribution by connector
    $errorsByConnector = $UniqueErrorData | Group-Object 'connector-id' | 
        Select-Object @{Name='Connector';Expression={$_.Name}}, 
                      @{Name='Count';Expression={$_.Count}} | 
        Sort-Object Count -Descending | 
        Select-Object -First 50

    # Recent errors (last 100)
    $recentErrors = $UniqueErrorData | Sort-Object ParsedTimestamp -Descending | Select-Object -First 100

    return @{
        TotalErrors = $UniqueErrorData.Count
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
            <h2>Affected Connectors</h2>
            <table>
                <thead>
                    <tr><th>Connector</th></tr>
                </thead>
                <tbody>
"@
        
        foreach ($connector in $Summary.ErrorsByConnector) {
            $html += "<tr><td>$($connector.Connector)</td></tr>"
        }
        
        $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Recent Errors (Last 100)</h2>
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
