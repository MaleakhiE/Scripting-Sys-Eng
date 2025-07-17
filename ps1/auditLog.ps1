# Enhanced Audit Log Analyzer with Email & Scheduler Support
# Author: System Engineer
# Version: 2.1
# Last Updated: $(Get-Date -Format "yyyy-MM-dd")

param(
    [string]$ConfigFile = "config.json",
    [switch]$SendEmail,
    [switch]$GenerateHTML,
    [switch]$Verbose,
    [int]$MaxRecords = 100,
    [switch]$GetLatest = $true
)

# === LOGGING CONFIGURATION ===
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LOG_FILE = Join-Path $SCRIPT_DIR ("audit_log_analyzer_" + (Get-Date -Format "yyyyMMdd") + ".log")

# === LOAD CONFIGURATION ===
function Load-Configuration {
    param([string]$ConfigPath)
    
    $defaultConfig = @{
        LogDirectory = "/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Mandiri/Dokumen/Migrasi/Script/Traffic Log"
        OutputDirectory = "/Users/eki/File Eki/2023 - 2024/Kerjaan/System Engineer/Mandiri/Dokumen/Migrasi/Script/Traffic Log/Test Script/"
        EmailConfig = @{
            SMTPServer = "smtp.gmail.com"
            SMTPPort = 587
            Username = "ekiputra543@gmail.com"
            Password = "kobl keqi ybnk qwfq"
            From = "audit-system@company.com"
            To = @("ekiputra543@gmail.com")
            Subject = "Email Traffic Report - {DATE} (Latest $MaxRecords records)"
            EnableSSL = $true
        }
        ReportConfig = @{
            CompanyName = "Your Company"
            ReportTitle = "Email Traffic Analysis Report"
            IncludeCharts = $true
            MaxTopItems = 10
            MaxRecords = 100
            ProcessLatest = $true
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
    Write-Log "=== AUDIT LOG ANALYZER SESSION STARTED ===" -Level "INFO"
    Write-Log "Script Version: 2.1"
    Write-Log "Execution Time: $(Get-Date)"
    Write-Log "Script Path: $($MyInvocation.MyCommand.Definition)"
    Write-Log "Log File: $LOG_FILE"
    Write-Log "Max Records to Process: $MaxRecords"
    Write-Log "Get Latest Records: $GetLatest"
}

function End-LogSession {
    param([bool]$Success = $true)
    
    $status = if ($Success) { "SUCCESS" } else { "FAILED" }
    Write-Log "=== AUDIT LOG ANALYZER SESSION ENDED: $status ===" -Level $(if ($Success) { "SUCCESS" } else { "ERROR" })
}

# === MAIN FUNCTIONS ===
function Load-Logs {
    param(
        [string]$LogDir,
        [int]$MaxRecords = 100,
        [bool]$GetLatest = $true
    )
    
    Write-Log "Loading logs from directory: $LogDir"
    Write-Log "Max records to load: $MaxRecords"
    Write-Log "Get latest records: $GetLatest"
    
    if (-not (Test-Path $LogDir)) {
        throw "Log directory does not exist: $LogDir"
    }
    
    $allData = @()
    $logFiles = Get-ChildItem -Path $LogDir -Filter "*.log"
    
    if ($logFiles.Count -eq 0) {
        throw "No log files found in directory: $LogDir"
    }
    
    Write-Log "Found $($logFiles.Count) log files to process"
    
    # Sort files by last write time (newest first) if we want latest records
    if ($GetLatest) {
        $logFiles = $logFiles | Sort-Object LastWriteTime -Descending
        Write-Log "Files sorted by newest first for latest records"
    }
    
    $totalRecordsProcessed = 0
    
    foreach ($file in $logFiles) {
        if ($totalRecordsProcessed -ge $MaxRecords) {
            Write-Log "Reached maximum records limit ($MaxRecords). Stopping file processing."
            break
        }
        
        Write-Log "Processing file: $($file.Name)"
        
        try {
            $lines = Get-Content -Path $file.FullName -ErrorAction Stop
            
            # Find header line
            $headerLine = $null
            foreach ($line in $lines) {
                if ($line.StartsWith("#Fields:")) {
                    $headerLine = $line.Replace("#Fields: ", "").Trim().Split(",")
                    break
                }
            }
            
            if (-not $headerLine) {
                Write-Log "Header not found in $($file.Name)" -Level "WARNING"
                continue
            }
            
            # Filter data lines
            $dataLines = $lines | Where-Object { -not $_.StartsWith("#") -and $_.Trim() -ne "" }
            
            # Create temporary array for this file's data
            $fileData = @()
            
            foreach ($dataLine in $dataLines) {
                $fields = $dataLine.Split(",")
                if ($fields.Count -eq $headerLine.Count) {
                    $obj = New-Object PSObject
                    for ($i = 0; $i -lt $headerLine.Count; $i++) {
                        $obj | Add-Member -MemberType NoteProperty -Name $headerLine[$i] -Value $fields[$i]
                    }
                    $obj | Add-Member -MemberType NoteProperty -Name "SourceFile" -Value $file.Name
                    $obj | Add-Member -MemberType NoteProperty -Name "FileLastModified" -Value $file.LastWriteTime
                    $fileData += $obj
                }
            }
            
            # If we want latest records, sort by timestamp within each file
            if ($GetLatest -and $fileData.Count -gt 0) {
                $fileData = $fileData | Sort-Object { 
                    try {
                        [DateTime]::Parse($_."date-time")
                    }
                    catch {
                        [DateTime]::MinValue
                    }
                } -Descending
            }
            
            # Add records from this file up to the limit
            $remainingSlots = $MaxRecords - $totalRecordsProcessed
            $recordsToTake = [Math]::Min($fileData.Count, $remainingSlots)
            
            if ($recordsToTake -gt 0) {
                $allData += $fileData | Select-Object -First $recordsToTake
                $totalRecordsProcessed += $recordsToTake
                Write-Log "Added $recordsToTake records from $($file.Name) (Total: $totalRecordsProcessed)"
            }
            
        }
        catch {
            Write-Log "Error processing file $($file.Name): $($_.Exception.Message)" -Level "ERROR"
            continue
        }
    }
    
    # Final sort if we want latest records across all files
    if ($GetLatest -and $allData.Count -gt 0) {
        Write-Log "Performing final sort across all files for latest records"
        $allData = $allData | Sort-Object { 
            try {
                [DateTime]::Parse($_."date-time")
            }
            catch {
                [DateTime]::MinValue
            }
        } -Descending | Select-Object -First $MaxRecords
    }
    
    Write-Log "Total records loaded: $($allData.Count)"
    return $allData
}

function Clean-DataFrame {
    param([array]$Data)
    
    Write-Log "Cleaning data..."
    $cleanedData = @()
    $errorCount = 0
    
    foreach ($row in $Data) {
        try {
            # Normalize column names
            if ($row."date-time") { $row | Add-Member -MemberType NoteProperty -Name "Timestamp" -Value $row."date-time" -Force }
            if ($row."sender-address") { $row | Add-Member -MemberType NoteProperty -Name "Sender" -Value $row."sender-address" -Force }
            if ($row."recipient-address") { $row | Add-Member -MemberType NoteProperty -Name "Recipients" -Value $row."recipient-address" -Force }
            if ($row."event-id") { $row | Add-Member -MemberType NoteProperty -Name "EventId" -Value $row."event-id" -Force }
            if ($row."total-bytes") { $row | Add-Member -MemberType NoteProperty -Name "TotalBytes" -Value $row."total-bytes" -Force }
            
            # Parse timestamp
            $timestamp = [DateTime]::Parse($row.Timestamp)
            $row | Add-Member -MemberType NoteProperty -Name "ParsedTimestamp" -Value $timestamp -Force
            $row | Add-Member -MemberType NoteProperty -Name "Date" -Value $timestamp.Date.ToString("yyyy-MM-dd") -Force
            $row | Add-Member -MemberType NoteProperty -Name "Hour" -Value $timestamp.Hour -Force
            
            # Validate required fields
            if (-not $row.EventId -or -not $row.Sender -or -not $row.Recipients) {
                continue
            }
            
            # Convert TotalBytes to numeric
            try {
                $row | Add-Member -MemberType NoteProperty -Name "TotalBytesNumeric" -Value ([int]$row.TotalBytes) -Force
            }
            catch {
                $row | Add-Member -MemberType NoteProperty -Name "TotalBytesNumeric" -Value 0 -Force
            }
            
            # Extract recipient domain
            if ($row.Recipients -match "@([\w\.-]+)") {
                $row | Add-Member -MemberType NoteProperty -Name "RecipientDomain" -Value $matches[1] -Force
            }
            else {
                $row | Add-Member -MemberType NoteProperty -Name "RecipientDomain" -Value "unknown" -Force
            }
            
            # Extract sender domain
            if ($row.Sender -match "@([\w\.-]+)") {
                $row | Add-Member -MemberType NoteProperty -Name "SenderDomain" -Value $matches[1] -Force
            }
            else {
                $row | Add-Member -MemberType NoteProperty -Name "SenderDomain" -Value "unknown" -Force
            }
            
            $cleanedData += $row
        }
        catch {
            $errorCount++
            if ($Verbose) {
                Write-Log "Error cleaning row: $($_.Exception.Message)" -Level "WARNING"
            }
        }
    }
    
    Write-Log "Data cleaning completed. Clean records: $($cleanedData.Count), Errors: $errorCount"
    return $cleanedData
}

function Generate-Summary {
    param([array]$Data)
    
    Write-Log "Generating summary statistics..."
    
    # Get time range info
    $timestamps = $Data | ForEach-Object { $_.ParsedTimestamp } | Sort-Object
    $earliestRecord = $timestamps | Select-Object -First 1
    $latestRecord = $timestamps | Select-Object -Last 1
    
    # Daily events by EventId
    $dailyEvents = $Data | Group-Object Date, EventId | Select-Object @{Name='Date';Expression={($_.Name -split ', ')[0]}}, @{Name='EventId';Expression={($_.Name -split ', ')[1]}}, @{Name='Count';Expression={$_.Count}}
    
    # Hourly distribution
    $hourlyDistribution = $Data | Group-Object Hour | Select-Object @{Name='Hour';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} | Sort-Object Hour
    
    # Daily size in MB
    $dailySize = $Data | Group-Object Date | Select-Object @{Name='Date';Expression={$_.Name}}, @{Name='TotalSizeMB';Expression={[math]::Round(($_.Group | Measure-Object TotalBytesNumeric -Sum).Sum / (1024 * 1024), 2)}}
    
    # Top senders (SEND events only)
    $topSenders = $Data | Where-Object { $_.EventId -eq "SEND" } | Group-Object Sender | Sort-Object Count -Descending | Select-Object -First 10 @{Name='Sender';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}}
    
    # Top recipient domains
    $topDomains = $Data | Group-Object RecipientDomain | Sort-Object Count -Descending | Select-Object -First 10 @{Name='Domain';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}}
    
    # Top sender domains
    $topSenderDomains = $Data | Group-Object SenderDomain | Sort-Object Count -Descending | Select-Object -First 10 @{Name='Domain';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}}
    
    # Event type distribution
    $eventTypes = $Data | Group-Object EventId | Select-Object @{Name='EventType';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}}, @{Name='Percentage';Expression={[math]::Round(($_.Count / $Data.Count) * 100, 2)}}
    
    # File source distribution
    $fileDistribution = $Data | Group-Object SourceFile | Select-Object @{Name='SourceFile';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}}, @{Name='Percentage';Expression={[math]::Round(($_.Count / $Data.Count) * 100, 2)}}
    
    Write-Log "Summary generation completed"
    
    return @{
        DailyEvents = $dailyEvents
        HourlyDistribution = $hourlyDistribution
        DailySize = $dailySize
        TopSenders = $topSenders
        TopDomains = $topDomains
        TopSenderDomains = $topSenderDomains
        EventTypes = $eventTypes
        FileDistribution = $fileDistribution
        TotalRecords = $Data.Count
        DateRange = @{
            Start = if ($earliestRecord) { $earliestRecord.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
            End = if ($latestRecord) { $latestRecord.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
        }
        TotalSizeMB = [math]::Round(($Data | Measure-Object TotalBytesNumeric -Sum).Sum / (1024 * 1024), 2)
        ProcessingInfo = @{
            MaxRecords = $MaxRecords
            GetLatest = $GetLatest
            ProcessedRecords = $Data.Count
        }
    }
}

function Generate-HTMLReport {
    param([hashtable]$Summary, [object]$Config)
    
    Write-Log "Generating HTML report..."
    
    $recordsInfo = if ($Summary.ProcessingInfo.GetLatest) { "Latest $($Summary.ProcessingInfo.MaxRecords) records" } else { "First $($Summary.ProcessingInfo.MaxRecords) records" }
    
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
        .header { text-align: center; margin-bottom: 30px; border-bottom: 2px solid #007acc; padding-bottom: 20px; }
        .header h1 { color: #007acc; margin: 0; }
        .header p { color: #666; margin: 5px 0; }
        .summary-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .card { background: linear-gradient(135deg, #007acc, #0056b3); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .card h3 { margin: 0 0 10px 0; font-size: 14px; opacity: 0.9; }
        .card .value { font-size: 24px; font-weight: bold; margin: 0; }
        .section { margin-bottom: 30px; }
        .section h2 { color: #007acc; border-bottom: 1px solid #ddd; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; font-weight: 600; }
        tr:hover { background-color: #f8f9fa; }
        .chart-container { margin: 20px 0; }
        .footer { text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
        .status-success { color: #28a745; }
        .status-warning { color: #ffc107; }
        .status-error { color: #dc3545; }
        .info-badge { background-color: #17a2b8; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; margin-left: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>$($Config.ReportConfig.ReportTitle)</h1>
            <p><strong>$($Config.ReportConfig.CompanyName)</strong></p>
            <p>Report Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>Data Range: $($Summary.DateRange.Start) to $($Summary.DateRange.End)</p>
            <p>Processing: <span class="info-badge">$recordsInfo</span></p>
        </div>
        
        <div class="summary-cards">
            <div class="card">
                <h3>Processed Records</h3>
                <p class="value">$($Summary.TotalRecords.ToString("N0"))</p>
            </div>
            <div class="card">
                <h3>Total Traffic</h3>
                <p class="value">$($Summary.TotalSizeMB.ToString("N2")) MB</p>
            </div>
            <div class="card">
                <h3>Unique Senders</h3>
                <p class="value">$(($Summary.TopSenders | Measure-Object).Count)</p>
            </div>
            <div class="card">
                <h3>Unique Domains</h3>
                <p class="value">$(($Summary.TopDomains | Measure-Object).Count)</p>
            </div>
        </div>
        
        <div class="section">
            <h2>Event Type Distribution</h2>
            <table>
                <thead>
                    <tr><th>Event Type</th><th>Count</th><th>Percentage</th></tr>
                </thead>
                <tbody>
"@
    
    foreach ($event in $Summary.EventTypes) {
        $html += "<tr><td>$($event.EventType)</td><td>$($event.Count.ToString("N0"))</td><td>$($event.Percentage)%</td></tr>"
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Hourly Distribution</h2>
            <table>
                <thead>
                    <tr><th>Hour</th><th>Count</th></tr>
                </thead>
                <tbody>
"@
    
    foreach ($hour in $Summary.HourlyDistribution) {
        $html += "<tr><td>$($hour.Hour):00</td><td>$($hour.Count.ToString("N0"))</td></tr>"
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Top Senders</h2>
            <table>
                <thead>
                    <tr><th>Sender</th><th>Count</th></tr>
                </thead>
                <tbody>
"@
    
    foreach ($sender in $Summary.TopSenders) {
        $html += "<tr><td>$($sender.Sender)</td><td>$($sender.Count.ToString("N0"))</td></tr>"
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Top Recipient Domains</h2>
            <table>
                <thead>
                    <tr><th>Domain</th><th>Count</th></tr>
                </thead>
                <tbody>
"@
    
    foreach ($domain in $Summary.TopDomains) {
        $html += "<tr><td>$($domain.Domain)</td><td>$($domain.Count.ToString("N0"))</td></tr>"
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Source File Distribution</h2>
            <table>
                <thead>
                    <tr><th>Source File</th><th>Records</th><th>Percentage</th></tr>
                </thead>
                <tbody>
"@
    
    foreach ($file in $Summary.FileDistribution) {
        $html += "<tr><td>$($file.SourceFile)</td><td>$($file.Count.ToString("N0"))</td><td>$($file.Percentage)%</td></tr>"
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <p>Report generated by Audit Log Analyzer v2.1 | $($Config.ReportConfig.CompanyName)</p>
            <p>Processing Mode: $recordsInfo</p>
            <p>For questions or issues, please contact your system administrator.</p>
        </div>
    </div>
</body>
</html>
"@
    
    Write-Log "HTML report generated successfully"
    return $html
}

function Send-EmailReport {
    param([string]$HtmlContent, [object]$Config, [hashtable]$Summary)
    
    Write-Log "Preparing to send email report..."
    
    try {
        $smtpConfig = $Config.EmailConfig
        $subject = $smtpConfig.Subject -replace "{DATE}", (Get-Date -Format "yyyy-MM-dd")
        $subject = $subject -replace "{RECORDS}", $Summary.ProcessingInfo.MaxRecords
        
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

function Export-Summary {
    param([hashtable]$Summary, [array]$Data, [string]$OutputDir, [object]$Config)
    
    Write-Log "Exporting summary data to: $OutputDir"
    
    # Create output directory
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    
    $dateStr = Get-Date -Format "yyyy-MM-dd"
    $recordsStr = if ($Summary.ProcessingInfo.GetLatest) { "latest" } else { "first" }
    $mergedLogCsv = Join-Path $OutputDir ("Report_Traffic_" + $dateStr + "_" + $recordsStr + "_" + $Summary.ProcessingInfo.MaxRecords + ".csv")
    
    # Export CSV files
    $exports = @{
        "daily_events_${recordsStr}_${MaxRecords}.csv" = $Summary.DailyEvents
        "hourly_distribution_${recordsStr}_${MaxRecords}.csv" = $Summary.HourlyDistribution
        "daily_size_MB_${recordsStr}_${MaxRecords}.csv" = $Summary.DailySize
        "top_senders_${recordsStr}_${MaxRecords}.csv" = $Summary.TopSenders
        "top_domains_${recordsStr}_${MaxRecords}.csv" = $Summary.TopDomains
        "top_sender_domains_${recordsStr}_${MaxRecords}.csv" = $Summary.TopSenderDomains
        "event_types_${recordsStr}_${MaxRecords}.csv" = $Summary.EventTypes
        "file_distribution_${recordsStr}_${MaxRecords}.csv" = $Summary.FileDistribution
    }
    
    foreach ($file in $exports.Keys) {
        if ($exports[$file]) {
            $filePath = Join-Path $OutputDir $file
            $exports[$file] | Export-Csv -Path $filePath -NoTypeInformation
            Write-Log "Exported: $file"
        }
    }
    
    # Export merged raw log data
    $Data | Select-Object Timestamp, Sender, Recipients, EventId, TotalBytes, TotalBytesNumeric, Date, Hour, RecipientDomain, SenderDomain, SourceFile, FileLastModified | Export-Csv -Path $mergedLogCsv -NoTypeInformation
    Write-Log "Exported merged log: $mergedLogCsv"
    
    # Generate and export HTML report
    if ($GenerateHTML -or $Config.ReportConfig.IncludeCharts) {
        $htmlContent = Generate-HTMLReport -Summary $Summary -Config $Config
        $htmlFile = Join-Path $OutputDir ("Email_Traffic_Report_" + $dateStr + "_" + $recordsStr + "_" + $Summary.ProcessingInfo.MaxRecords + ".html")
        $htmlContent | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Log "Exported HTML report: $htmlFile"
        
        # Send email if requested
        if ($SendEmail) {
            Send-EmailReport -HtmlContent $htmlContent -Config $Config -Summary $Summary
        }
    }
}

function Cleanup-OldReports {
    param([string]$OutputDir, [object]$Config)
    
    if (-not $Config.CleanupConfig.CleanupReports) {
        return
    }
    
    Write-Log "Cleaning up old reports (retention: $($Config.CleanupConfig.RetentionDays) days)"
    
    $cutoffDate = (Get-Date).AddDays(-$Config.CleanupConfig.RetentionDays)
    $oldFiles = Get-ChildItem -Path $OutputDir -Recurse | Where-Object { $_.CreationTime -lt $cutoffDate }
    
    foreach ($file in $oldFiles) {
        try {
            Remove-Item $file.FullName -Force
            Write-Log "Deleted old file: $($file.Name)"
        }
        catch {
            Write-Log "Failed to delete file $($file.Name): $($_.Exception.Message)" -Level "WARNING"
        }
    }
}

# === MAIN EXECUTION ===
function Main {
    $success = $false
    
    try {
        Start-LogSession
        
        # Load configuration
        $config = Load-Configuration -ConfigPath $ConfigFile
        
        # Override config with parameters if provided
        if ($MaxRecords) {
            $config.ReportConfig.MaxRecords = $MaxRecords
        }
        if ($GetLatest) {
            $config.ReportConfig.ProcessLatest = $GetLatest
        }
        
        # Set output directory
        $outputDir = if ($config.OutputDirectory) { $config.OutputDirectory } else { (Get-Date -Format "yyyy-MM-dd") + "_report_output" }
        
        # Load and process logs with limits
        $rawData = Load-Logs -LogDir $config.LogDirectory -MaxRecords $MaxRecords -GetLatest $GetLatest
        
        if ($rawData.Count -eq 0) {
            throw "No log data found to process"
        }
        
        # Clean data
        $cleanData = Clean-DataFrame -Data $rawData
        
        if ($cleanData.Count -eq 0) {
            throw "No valid data after cleaning"
        }
        
        # Generate summary
        $summary = Generate-Summary -Data $cleanData
        
        # Export results
        Export-Summary -Summary $summary -Data $cleanData -OutputDir $outputDir -Config $config
        
        # Cleanup old reports
        Cleanup-OldReports -OutputDir $outputDir -Config $config
        
        # Display summary
        Write-Log "=== PROCESSING SUMMARY ===" -Level "SUCCESS"
        Write-Log "Records processed: $($cleanData.Count) out of max $MaxRecords" -Level "SUCCESS"
        Write-Log "Processing mode: $(if ($GetLatest) { 'Latest records' } else { 'First records' })" -Level "SUCCESS"
        Write-Log "Date range: $($summary.DateRange.Start) to $($summary.DateRange.End)" -Level "SUCCESS"
        Write-Log "Total traffic size: $($summary.TotalSizeMB) MB" -Level "SUCCESS"
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