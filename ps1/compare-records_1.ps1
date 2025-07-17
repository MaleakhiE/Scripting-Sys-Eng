# Define paths for the HTML report, CSV report, and logs
$reportPath = "C:\AD_DNS_Comparison_Report.html"
$csvReportPath = "C:\AD_DNS_Comparison_Report.csv"
$logFile = "C:\AD_DNS_Comparison_Log.txt"

# Function to initialize the HTML report
function Initialize-HTMLReport {
    @"
<!DOCTYPE html>
<html>
<head>
    <title>DNS Comparison Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h2 { color: #003366; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #003366; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
<h2>DNS Comparison Report</h2>
<p>This report compares DNS records retrieved from multiple DNS servers.</p>
<table>
    <tr>
        <th>DNS Name</th>
        <th>Record Type</th>
        <th>Associated Data</th>
        <th>DNS Server</th>
        <th>DNS Location</th>
    </tr>
"@ | Out-File -FilePath $reportPath -Force -Encoding utf8
}

# Function to write entries to the HTML report
function Write-HTMLReport {
    param (
        [string]$dnsName,
        [string]$recordType,
        [string]$associatedData,
        [string]$dnsServer,
        [string]$dnsLocation
    )
    @"
<tr>
    <td>$dnsName</td>
    <td>$recordType</td>
    <td>$associatedData</td>
    <td>$dnsServer</td>
    <td>$dnsLocation</td>
</tr>
"@ | Out-File -FilePath $reportPath -Append -Encoding utf8
}

# Function to finalize the HTML report
function Finalize-HTMLReport {
    @"
</table>
</body>
</html>
"@ | Out-File -FilePath $reportPath -Append -Encoding utf8
    Write-Host "HTML report generated at: $reportPath"
}

# Function to log messages
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -FilePath $logFile -Append -Encoding utf8
}

# Function to retrieve DNS records using PowerShell Remoting
function Get-AllDNSRecords {
    # List of DNS servers to query
    $dnsServers = @("ad2.bukitmakmur.corp", "WIN-QGREOCF63RP.bukitmakmur.corp")
    $dnsRecords = @()

    foreach ($server in $dnsServers) {
        Write-Log "Retrieving records from DNS server: $server"
        try {
            # Use Invoke-Command to run the command on the remote DNS server
            $records = Invoke-Command -ComputerName $server -ScriptBlock {
                Get-DnsServerZone -ErrorAction Stop | ForEach-Object {
                    Get-DnsServerResourceRecord -ZoneName $_.ZoneName -ErrorAction Stop
                }
            }

            foreach ($record in $records) {
                $dnsRecords += [pscustomobject]@{
                    DNSName        = $record.HostName
                    RecordType     = $record.RecordType
                    AssociatedData = switch ($record.RecordType) {
                        "A" { $record.RecordData.IPv4Address }
                        "CNAME" { $record.RecordData.DomainName }
                        "PTR" { $record.RecordData.PtrDomainName }
                        "MX" { $record.RecordData.MailExchange }
                        default { "N/A" }
                    }
                    DNSServer      = $server
                    DNSLocation    = "Located on server: $server"
                }

                Write-Log "Retrieved record: $($record.HostName) from server $server"
            }
        } catch {
            Write-Log "Error retrieving records from DNS server $server - $_"
        }
    }
    return $dnsRecords
}

# Function to export records to CSV
function Export-ToCSV {
    param (
        [array]$dnsRecords
    )
    
    # Export to CSV
    try {
        $dnsRecords | Export-Csv -Path $csvReportPath -NoTypeInformation -Force -Encoding UTF8
        Write-Log "CSV report generated at: $csvReportPath"
    } catch {
        Write-Log "Error exporting to CSV: $_"
    }
}

# Function to compare and generate the HTML and CSV reports
function Compare-ADDNSRecords {
    $dnsRecords = Get-AllDNSRecords

    # Sort DNS records by DNS Name in ascending order
    $sortedRecords = $dnsRecords | Sort-Object -Property DNSName

    foreach ($record in $sortedRecords) {
        # Write the information to the HTML report
        Write-HTMLReport -dnsName $record.DNSName `
                         -recordType $record.RecordType `
                         -associatedData $record.AssociatedData `
                         -dnsServer $record.DNSServer `
                         -dnsLocation $record.DNSLocation
    }

    # Export to CSV
    Export-ToCSV -dnsRecords $sortedRecords
}

# Initialize HTML report and log file
Initialize-HTMLReport
Write-Log "=== Starting DNS Records Comparison ==="

# Retrieve, compare, and generate reports
Compare-ADDNSRecords

# Finalize the HTML report
Finalize-HTMLReport

Write-Log "=== DNS Records Comparison Completed ==="
Write-Host "DNS Comparison completed. Reports generated at: $reportPath and $csvReportPath"
