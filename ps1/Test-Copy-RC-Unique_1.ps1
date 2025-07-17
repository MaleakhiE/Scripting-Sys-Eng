#Requires -Version 5.1
<#
.SYNOPSIS
    Creates or updates Exchange Receive Connectors from CSV data with intelligent IP range consolidation
.DESCRIPTION
    This script imports connector configuration from a CSV file, consolidates duplicate connector
    names with multiple IP addresses, intelligently creates IP ranges when possible, and creates 
    or updates Receive Connectors on specified Exchange servers with proper error handling and logging.
.PARAMETER CsvPath
    Path to the CSV file containing connector configurations
.PARAMETER ServerNames
    Array of Exchange server names where connectors should be created/updated
.PARAMETER LogPath
    Path for the log file (optional)
.EXAMPLE
    .\Manage-ReceiveConnectors.ps1 -CsvPath "C:\Data\connectors.csv" -ServerNames @("PVEXCH01WBD25WP")
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CsvPath = 'C:\Temp\Unique-Receiver-Connector.csv',
    
    [Parameter(Mandatory = $false)]
    [string[]]$ServerNames = @("EXC01"),
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Temp\Logs\ReceiveConnector_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# Initialize logging
function Write-LogMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console with colors
    switch ($Level) {
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default   { Write-Host $logEntry -ForegroundColor White }
    }
    
    # Write to log file if path is provided
    if ($LogPath) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            Add-Content -Path $LogPath -Value $logEntry -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
        }
    }
}

function Test-Prerequisites {
    Write-LogMessage "Checking prerequisites..."
    
    # Check if Exchange Management Shell is available
    try {
        Get-Command Get-ReceiveConnector -ErrorAction Stop | Out-Null
        Write-LogMessage "Exchange Management Shell commands are available" -Level "SUCCESS"
    }
    catch {
        Write-LogMessage "Exchange Management Shell is not available. Please run this script from Exchange Management Shell." -Level "ERROR"
        return $false
    }
    
    # Check CSV file existence
    if (-not (Test-Path $CsvPath)) {
        Write-LogMessage "CSV file not found at path: $CsvPath" -Level "ERROR"
        return $false
    }
    
    Write-LogMessage "CSV file found: $CsvPath" -Level "SUCCESS"
    return $true
}

function Convert-IPToInt {
    param([string]$IP)
    try {
        $octets = $IP.Split('.')
        return [int64]($octets[0]) * 16777216 + [int64]($octets[1]) * 65536 + [int64]($octets[2]) * 256 + [int64]($octets[3])
    }
    catch {
        return -1
    }
}

function Convert-IntToIP {
    param([int64]$IntIP)
    try {
        $octet1 = [math]::Floor($IntIP / 16777216)
        $octet2 = [math]::Floor(($IntIP % 16777216) / 65536)
        $octet3 = [math]::Floor(($IntIP % 65536) / 256)
        $octet4 = $IntIP % 256
        return "$octet1.$octet2.$octet3.$octet4"
    }
    catch {
        return ""
    }
}

function Get-ConsecutiveRanges {
    param([string[]]$IPAddresses)
    
    Write-LogMessage "Analyzing $($IPAddresses.Count) IP addresses for range consolidation..."
    
    # Convert IPs to integers and sort
    $ipInts = @()
    foreach ($ip in $IPAddresses) {
        $ipInt = Convert-IPToInt -IP $ip
        if ($ipInt -ne -1) {
            $ipInts += $ipInt
        }
    }
    
    $ipInts = $ipInts | Sort-Object
    
    if ($ipInts.Count -eq 0) {
        Write-LogMessage "No valid IP addresses found" -Level "WARNING"
        return @()
    }
    
    Write-LogMessage "Found $($ipInts.Count) valid IP addresses"
    
    # Group consecutive IPs
    $ranges = @()
    $rangeStart = $ipInts[0]
    $rangeEnd = $ipInts[0]
    
    for ($i = 1; $i -lt $ipInts.Count; $i++) {
        if ($ipInts[$i] -eq ($rangeEnd + 1)) {
            # Consecutive IP
            $rangeEnd = $ipInts[$i]
        } else {
            # Non-consecutive, save current range
            if ($rangeStart -eq $rangeEnd) {
                # Single IP
                $ranges += Convert-IntToIP -IntIP $rangeStart
            } else {
                # Range
                $startIP = Convert-IntToIP -IntIP $rangeStart
                $endIP = Convert-IntToIP -IntIP $rangeEnd
                $ranges += "$startIP-$endIP"
            }
            
            # Start new range
            $rangeStart = $ipInts[$i]
            $rangeEnd = $ipInts[$i]
        }
    }
    
    # Add the last range
    if ($rangeStart -eq $rangeEnd) {
        $ranges += Convert-IntToIP -IntIP $rangeStart
    } else {
        $startIP = Convert-IntToIP -IntIP $rangeStart
        $endIP = Convert-IntToIP -IntIP $rangeEnd
        $ranges += "$startIP-$endIP"
    }
    
    Write-LogMessage "Consolidated $($IPAddresses.Count) IP addresses into $($ranges.Count) ranges/IPs:"
    foreach ($range in $ranges) {
        Write-LogMessage "  - $range"
    }
    
    return $ranges
}

function Parse-MessageSize {
    param([string]$MessageSizeString)
    
    try {
        if ([string]::IsNullOrWhiteSpace($MessageSizeString)) {
            return "36MB"  # Default value
        }
        
        # Handle format like "36 MB (37,748,736 bytes)"
        if ($MessageSizeString -match '(\d+)\s*MB') {
            return "$($matches[1])MB"
        }
        
        # Handle format like "37748736" (bytes)
        if ($MessageSizeString -match '^\d+$') {
            $bytes = [int64]$MessageSizeString
            $mb = [math]::Round($bytes / 1MB, 0)
            return "${mb}MB"
        }
        
        # Handle format like "37,748,736 bytes"
        if ($MessageSizeString -match '([\d,]+)\s*bytes') {
            $bytesString = $matches[1] -replace ',', ''
            $bytes = [int64]$bytesString
            $mb = [math]::Round($bytes / 1MB, 0)
            return "${mb}MB"
        }
        
        # If already in correct format, return as-is
        if ($MessageSizeString -match '^\d+MB$') {
            return $MessageSizeString
        }
        
        Write-LogMessage "Could not parse message size '$MessageSizeString', using default 36MB" -Level "WARNING"
        return "36MB"
    }
    catch {
        Write-LogMessage "Error parsing message size '$MessageSizeString': $($_.Exception.Message)" -Level "WARNING"
        return "36MB"
    }
}

function Convert-ToInt {
    param([string]$Value, [int]$Default)
    
    try {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $Default
        }
        
        # Remove any non-numeric characters except for the number itself
        $cleanValue = $Value -replace '[^\d]', ''
        
        if ([string]::IsNullOrWhiteSpace($cleanValue)) {
            return $Default
        }
        
        return [int]$cleanValue
    }
    catch {
        Write-LogMessage "Could not convert '$Value' to integer, using default $Default" -Level "WARNING"
        return $Default
    }
}

function Import-ConnectorData {
    param([string]$Path)
    
    try {
        Write-LogMessage "Importing connector data from CSV..."
        $rawData = Import-Csv -Path $Path -Delimiter ";" -ErrorAction Stop
        
        if ($rawData.Count -eq 0) {
            Write-LogMessage "No connector data found in CSV file" -Level "WARNING"
            return $null
        }
        
        Write-LogMessage "Successfully imported $($rawData.Count) raw connector entries from CSV" -Level "SUCCESS"
        
        # Group by connector name and consolidate IP addresses
        $consolidatedConnectors = @{}
        
        foreach ($row in $rawData) {
            $connectorName = $row.Identity
            
            if (-not $connectorName) {
                Write-LogMessage "Skipping row with empty Identity" -Level "WARNING"
                continue
            }
            
            # Handle IP (support normal + CIDR)
            $remoteIP = $row.RemoteIPAddress
            
            if (-not $remoteIP) {
                Write-LogMessage "Skipping row for '$connectorName' - empty IP" -Level "WARNING"
                continue
            }
            
            $remoteIP = $remoteIP.Trim()
            
            if ($remoteIP -match '^\d{1,3}(\.\d{1,3}){3}(/\d{1,2})?$') {
                # Valid IP or CIDR
                # Optionally normalize /32 to plain IP:
                if ($remoteIP -match '^(\d{1,3}(\.\d{1,3}){3})/32$') {
                    $remoteIP = $matches[1]
                }
            }
            else {
                Write-LogMessage "Skipping row for '$connectorName' - invalid IP format: '$remoteIP'" -Level "WARNING"
                continue
            }
            
            # Initialize connector object if not exists
            if (-not $consolidatedConnectors.ContainsKey($connectorName)) {
                $consolidatedConnectors[$connectorName] = @{
                    Identity = $connectorName
                    AuthMechanism = $row.AuthMechanism
                    PermissionGroups = $row.PermissionGroups
                    Bindings = $row.Bindings
                    MaxMessageSize = $row.MaxMessageSize
                    MaxLocalHopCount = $row.MaxLocalHopCount
                    MaxHopCount = $row.MaxHopCount
                    MaxInboundConnection = $row.MaxInboundConnection
                    MaxInboundConnectionPerSource = $row.MaxInboundConnectionPerSource
                    MessageRateLimit = $row.MessageRateLimit
                    RemoteIPAddresses = @()
                }
            }
            
            # Add IP address if not already present
            if ($consolidatedConnectors[$connectorName].RemoteIPAddresses -notcontains $remoteIP) {
                $consolidatedConnectors[$connectorName].RemoteIPAddresses += $remoteIP
            }
        }
        
        Write-LogMessage "Consolidated into $($consolidatedConnectors.Count) unique connector(s)" -Level "SUCCESS"
        
        # Log consolidation details and apply IP range consolidation
        foreach ($connector in $consolidatedConnectors.Values) {
            Write-LogMessage "Processing connector '$($connector.Identity)' with $($connector.RemoteIPAddresses.Count) IP address(es)"
            
            # Apply intelligent IP range consolidation
            $consolidatedRanges = Get-ConsecutiveRanges -IPAddresses $connector.RemoteIPAddresses
            $connector.RemoteIPRanges = $consolidatedRanges
            
            Write-LogMessage "Connector '$($connector.Identity)' consolidated to $($consolidatedRanges.Count) range(s): $($consolidatedRanges -join ', ')"
        }
        
        return $consolidatedConnectors.Values
    }
    catch {
        Write-LogMessage "Failed to import CSV data: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Test-ServerConnectivity {
    param([string]$ServerName)
    
    try {
        $null = Get-ReceiveConnector -Server $ServerName -ErrorAction Stop | Select-Object -First 1
        return $true
    }
    catch {
        Write-LogMessage "Cannot connect to server '$ServerName': $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Parse-ConnectorProperties {
    param($Connector)
    
    try {
        # Extract connector name from Identity
        $connectorName = $Connector.Identity
        
        # Parse AuthMechanism
        $authMechanism = if ($Connector.AuthMechanism) {
            $Connector.AuthMechanism -split ',\s*' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
        } else {
            @('Tls')  # Default value
        }
        
        # Parse PermissionGroups
        $permissionGroups = if ($Connector.PermissionGroups) {
            $Connector.PermissionGroups -split ',\s*' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
        } else {
            @('ExchangeServers')  # Default value
        }
        
        # Parse Bindings
        $bindings = if ($Connector.Bindings) {
            $Connector.Bindings
        } else {
            '0.0.0.0:25'  # Default binding
        }
        
        # Use the pre-consolidated RemoteIPRanges
        $remoteIPRanges = if ($Connector.RemoteIPRanges -and $Connector.RemoteIPRanges.Count -gt 0) {
            $Connector.RemoteIPRanges
        } else {
            @('0.0.0.0-255.255.255.255')  # Default range
        }
        
        # Parse message size
        $maxMessageSize = Parse-MessageSize -MessageSizeString $Connector.MaxMessageSize
        
        # Parse numeric values
        $maxLocalHopCount = Convert-ToInt -Value $Connector.MaxLocalHopCount -Default 12
        $maxHopCount = Convert-ToInt -Value $Connector.MaxHopCount -Default 60
        $maxInboundConnection = Convert-ToInt -Value $Connector.MaxInboundConnection -Default 5000
        $maxInboundConnectionPerSource = Convert-ToInt -Value $Connector.MaxInboundConnectionPerSource -Default 20
        
        # Parse MessageRateLimit
        $messageRateLimit = if ($Connector.MessageRateLimit -and $Connector.MessageRateLimit -ne "Unlimited") {
            Convert-ToInt -Value $Connector.MessageRateLimit -Default 1000
        } else {
            "Unlimited"
        }
        
        return @{
            Name = $connectorName
            AuthMechanism = $authMechanism
            PermissionGroups = $permissionGroups
            Bindings = $bindings
            RemoteIPRanges = $remoteIPRanges
            MaxMessageSize = $maxMessageSize
            MaxLocalHopCount = $maxLocalHopCount
            MaxHopCount = $maxHopCount
            MaxInboundConnection = $maxInboundConnection
            MaxInboundConnectionPerSource = $maxInboundConnectionPerSource
            MessageRateLimit = $messageRateLimit
        }
    }
    catch {
        Write-LogMessage "Failed to parse connector properties: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function New-ReceiveConnectorSafe {
    param(
        [string]$ServerName,
        [hashtable]$ConnectorConfig
    )
    
    try {
        Write-LogMessage "Creating Receive Connector '$($ConnectorConfig.Name)' on $ServerName..."
        Write-LogMessage "  IP Ranges/IPs: $($ConnectorConfig.RemoteIPRanges.Count) entries"
        
        $params = @{
            Name = $ConnectorConfig.Name
            Server = $ServerName
            AuthMechanism = $ConnectorConfig.AuthMechanism
            PermissionGroups = $ConnectorConfig.PermissionGroups
            Bindings = $ConnectorConfig.Bindings
            RemoteIPRanges = $ConnectorConfig.RemoteIPRanges
            MaxMessageSize = $ConnectorConfig.MaxMessageSize
            MaxLocalHopCount = $ConnectorConfig.MaxLocalHopCount
            MaxHopCount = $ConnectorConfig.MaxHopCount
            MaxInboundConnection = $ConnectorConfig.MaxInboundConnection
            MaxInboundConnectionPerSource = $ConnectorConfig.MaxInboundConnectionPerSource
            Usage = 'Custom'
            TransportRole = 'FrontendTransport'
            ErrorAction = 'Stop'
        }
        
        # Add MessageRateLimit only if it's not "Unlimited"
        if ($ConnectorConfig.MessageRateLimit -ne "Unlimited") {
            $params.MessageRateLimit = $ConnectorConfig.MessageRateLimit
        }
        
        New-ReceiveConnector @params | Out-Null
        
        Write-LogMessage "Successfully created Receive Connector '$($ConnectorConfig.Name)' on $ServerName" -Level "SUCCESS"
        Write-LogMessage "  Bindings: $($ConnectorConfig.Bindings)"
        Write-LogMessage "  RemoteIPRanges: $($ConnectorConfig.RemoteIPRanges -join ', ')"
        Write-LogMessage "  AuthMechanism: $($ConnectorConfig.AuthMechanism -join ', ')"
        Write-LogMessage "  PermissionGroups: $($ConnectorConfig.PermissionGroups -join ', ')"
        Write-LogMessage "  MaxMessageSize: $($ConnectorConfig.MaxMessageSize)"
        Write-LogMessage "  MaxInboundConnection: $($ConnectorConfig.MaxInboundConnection)"
        Write-LogMessage "  MessageRateLimit: $($ConnectorConfig.MessageRateLimit)"
        Write-LogMessage "  MaxLocalHopCount: $($ConnectorConfig.MaxLocalHopCount)"
        Write-LogMessage "  MaxHopCount: $($ConnectorConfig.MaxHopCount)"
        Write-LogMessage "  MaxInboundConnectionPerSource: $($ConnectorConfig.MaxInboundConnectionPerSource)"
        
        return $true
    }
    catch {
        if ($_.Exception.Message -match "administrative limit") {
            Write-LogMessage "Administrative limit exceeded for '$($ConnectorConfig.Name)' - attempting fallback strategy..." -Level "WARNING"
            return $false
        }
        
        Write-LogMessage "Failed to create Receive Connector '$($ConnectorConfig.Name)' on $ServerName : $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function New-ReceiveConnectorFallback {
    param(
        [string]$ServerName,
        [hashtable]$ConnectorConfig
    )
    
    try {
        Write-LogMessage "Attempting fallback strategy: creating individual connectors for each IP range..." -Level "INFO"
        
        $baseConnectorName = $ConnectorConfig.Name
        $successCount = 0
        $totalRanges = $ConnectorConfig.RemoteIPRanges.Count
        
        for ($i = 0; $i -lt $totalRanges; $i++) {
            $ipRange = $ConnectorConfig.RemoteIPRanges[$i]
            $connectorName = if ($totalRanges -eq 1) {
                $baseConnectorName
            } else {
                "$baseConnectorName-$($i + 1)"
            }
            
            # Create a new config for this specific IP range
            $singleIPConfig = $ConnectorConfig.Clone()
            $singleIPConfig.Name = $connectorName
            $singleIPConfig.RemoteIPRanges = @($ipRange)
            
            Write-LogMessage "Creating fallback connector '$connectorName' for IP range: $ipRange"
            
            try {
                $params = @{
                    Name = $singleIPConfig.Name
                    Server = $ServerName
                    AuthMechanism = $singleIPConfig.AuthMechanism
                    PermissionGroups = $singleIPConfig.PermissionGroups
                    Bindings = $singleIPConfig.Bindings
                    RemoteIPRanges = $singleIPConfig.RemoteIPRanges
                    MaxMessageSize = $singleIPConfig.MaxMessageSize
                    MaxLocalHopCount = $singleIPConfig.MaxLocalHopCount
                    MaxHopCount = $singleIPConfig.MaxHopCount
                    MaxInboundConnection = $singleIPConfig.MaxInboundConnection
                    MaxInboundConnectionPerSource = $singleIPConfig.MaxInboundConnectionPerSource
                    Usage = 'Custom'
                    TransportRole = 'FrontendTransport'
                    ErrorAction = 'Stop'
                }
                
                if ($singleIPConfig.MessageRateLimit -ne "Unlimited") {
                    $params.MessageRateLimit = $singleIPConfig.MessageRateLimit
                }
                
                New-ReceiveConnector @params | Out-Null
                Write-LogMessage "Successfully created fallback connector '$connectorName'" -Level "SUCCESS"
                $successCount++
            }
            catch {
                Write-LogMessage "Failed to create fallback connector '$connectorName': $($_.Exception.Message)" -Level "ERROR"
            }
        }
        
        Write-LogMessage "Fallback strategy completed: $successCount/$totalRanges connectors created successfully" -Level "INFO"
        return $successCount -gt 0
    }
    catch {
        Write-LogMessage "Fallback strategy failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Set-ReceiveConnectorSafe {
    param(
        [string]$Identity,
        [hashtable]$ConnectorConfig
    )
    
    try {
        Write-LogMessage "Updating existing Receive Connector '$($ConnectorConfig.Name)'..."
        
        $params = @{
            Identity = $Identity
            AuthMechanism = $ConnectorConfig.AuthMechanism
            PermissionGroups = $ConnectorConfig.PermissionGroups
            Bindings = $ConnectorConfig.Bindings
            RemoteIPRanges = $ConnectorConfig.RemoteIPRanges
            MaxMessageSize = $ConnectorConfig.MaxMessageSize
            MaxLocalHopCount = $ConnectorConfig.MaxLocalHopCount
            MaxHopCount = $ConnectorConfig.MaxHopCount
            MaxInboundConnection = $ConnectorConfig.MaxInboundConnection
            MaxInboundConnectionPerSource = $ConnectorConfig.MaxInboundConnectionPerSource
            ErrorAction = 'Stop'
        }
        
        # Add MessageRateLimit only if it's not "Unlimited"
        if ($ConnectorConfig.MessageRateLimit -ne "Unlimited") {
            $params.MessageRateLimit = $ConnectorConfig.MessageRateLimit
        }
        
        Set-ReceiveConnector @params | Out-Null
        
        Write-LogMessage "Successfully updated Receive Connector '$($ConnectorConfig.Name)'" -Level "SUCCESS"
        Write-LogMessage "  Bindings: $($ConnectorConfig.Bindings)"
        Write-LogMessage "  RemoteIPRanges: $($ConnectorConfig.RemoteIPRanges -join ', ')"
        Write-LogMessage "  AuthMechanism: $($ConnectorConfig.AuthMechanism -join ', ')"
        Write-LogMessage "  PermissionGroups: $($ConnectorConfig.PermissionGroups -join ', ')"
        Write-LogMessage "  MaxMessageSize: $($ConnectorConfig.MaxMessageSize)"
        Write-LogMessage "  MaxInboundConnection: $($ConnectorConfig.MaxInboundConnection)"
        Write-LogMessage "  MessageRateLimit: $($ConnectorConfig.MessageRateLimit)"
        Write-LogMessage "  MaxLocalHopCount: $($ConnectorConfig.MaxLocalHopCount)"
        Write-LogMessage "  MaxHopCount: $($ConnectorConfig.MaxHopCount)"
        Write-LogMessage "  MaxInboundConnectionPerSource: $($ConnectorConfig.MaxInboundConnectionPerSource)"
        Write-LogMessage "  MaxInboundConnection: $($ConnectorConfig.MaxInboundConnection)"
        
        return $true
    }
    catch {
        if ($_.Exception.Message -match "administrative limit") {
            Write-LogMessage "Administrative limit exceeded during update - this may require manual intervention" -Level "WARNING"
        }
        
        Write-LogMessage "Failed to update Receive Connector '$($ConnectorConfig.Name)': $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Main execution
try {
    Write-LogMessage "Starting Receive Connector management script with intelligent IP range consolidation" -Level "INFO"
    Write-LogMessage "CSV Path: $CsvPath"
    Write-LogMessage "Target Servers: $($ServerNames -join ', ')"
    Write-LogMessage "Log Path: $LogPath"
    Write-LogMessage ("=" * 80)
    
    # Check prerequisites
    if (-not (Test-Prerequisites)) {
        exit 1
    }
    
    # Import connector data
    $connectors = Import-ConnectorData -Path $CsvPath
    if (-not $connectors) {
        exit 1
    }
    
    # Initialize counters
    $totalProcessed = 0
    $successCount = 0
    $errorCount = 0
    $fallbackCount = 0
    
    # Process each server
    foreach ($serverName in $ServerNames) {
        Write-LogMessage ("=" * 50)
        Write-LogMessage "Processing server: $serverName"
        
        # Test server connectivity
        if (-not (Test-ServerConnectivity -ServerName $serverName)) {
            Write-LogMessage "Skipping server '$serverName' due to connectivity issues" -Level "WARNING"
            continue
        }
        
        # Process each connector
        foreach ($connector in $connectors) {
            $totalProcessed++
            
            # Parse connector properties
            $connectorConfig = Parse-ConnectorProperties -Connector $connector
            if (-not $connectorConfig) {
                $errorCount++
                continue
            }
            
            $identity = "$serverName\$($connectorConfig.Name)"
            
            try {
                # Check if connector already exists
                $existingConnector = Get-ReceiveConnector -Server $serverName | 
                    Where-Object { $_.Name -eq $connectorConfig.Name }
                
                if (-not $existingConnector) {
                    # Create new connector
                    $success = New-ReceiveConnectorSafe -ServerName $serverName -ConnectorConfig $connectorConfig
                    
                    if ($success) {
                        $successCount++
                    } else {
                        # Try fallback strategy
                        Write-LogMessage "Attempting fallback strategy for '$($connectorConfig.Name)'" -Level "INFO"
                        $fallbackSuccess = New-ReceiveConnectorFallback -ServerName $serverName -ConnectorConfig $connectorConfig
                        
                        if ($fallbackSuccess) {
                            $fallbackCount++
                        } else {
                            $errorCount++
                        }
                    }
                } else {
                    # Update existing connector
                    if (Set-ReceiveConnectorSafe -Identity $existingConnector.Identity -ConnectorConfig $connectorConfig) {
                        $successCount++
                    } else {
                        $errorCount++
                    }
                }
            }
            catch {
                Write-LogMessage "Unexpected error processing connector '$($connectorConfig.Name)': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }
    }
    
    # Summary
    Write-LogMessage ("=" * 80)
    Write-LogMessage "SUMMARY:" -Level "INFO"
    Write-LogMessage "Total Processed: $totalProcessed"
    Write-LogMessage "Successful: $successCount" -Level "SUCCESS"
    Write-LogMessage "Fallback Success: $fallbackCount" -Level "SUCCESS"
    Write-LogMessage "Errors: $errorCount" -Level $(if ($errorCount -eq 0) { "SUCCESS" } else { "WARNING" })
    
    if ($fallbackCount -gt 0) {
        Write-LogMessage "NOTE: $fallbackCount connector(s) were created using fallback strategy (individual connectors per IP range)" -Level "INFO"
    }
    
    Write-LogMessage "Script completed" -Level "SUCCESS"
    
    if ($errorCount -gt 0) {
        exit 1
    }
}
catch {
    Write-LogMessage "Critical error in main execution: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}