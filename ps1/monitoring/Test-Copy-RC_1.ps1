#Requires -Version 5.1
<#
.SYNOPSIS
    Creates or updates Exchange Receive Connectors from CSV data
.DESCRIPTION
    This script imports connector configuration from a CSV file and creates or updates
    Receive Connectors on specified Exchange servers with proper error handling and logging.
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
    [string]$CsvPath = 'C:\Script\Copy Receiver Connector\ReceieveConnector19062025(1).csv',
    
    [Parameter(Mandatory = $false)]
    [string[]]$ServerNames = @("PVEXCH01WBD25WP"),
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Script\Copy Receiver Connector\Logs\ReceiveConnector_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

function Import-ConnectorData {
    param([string]$Path)
    
    try {
        Write-LogMessage "Importing connector data from CSV..."
        $connectors = Import-Csv -Path $Path -Delimiter ";" -ErrorAction Stop
        
        if ($connectors.Count -eq 0) {
            Write-LogMessage "No connector data found in CSV file" -Level "WARNING"
            return $null
        }
        
        Write-LogMessage "Successfully imported $($connectors.Count) connector(s) from CSV" -Level "SUCCESS"
        return $connectors
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
        $connectorName = ($Connector.Identity -split '\\')[-1]
        
        # Parse AuthMechanism
        $authMechanism = if ($Connector.AuthMechanism) {
            $Connector.AuthMechanism -split ',\s*' | Where-Object { $_.Trim() -ne '' }
        } else {
            @('Tls')  # Default value
        }
        
        # Parse PermissionGroups
        $permissionGroups = if ($Connector.PermissionGroups) {
            $Connector.PermissionGroups -split ',\s*' | Where-Object { $_.Trim() -ne '' }
        } else {
            @('ExchangeServers')  # Default value
        }
        
        # Parse Bindings
        $bindings = if ($Connector.'$_.Bindings') {
            $Connector.'$_.Bindings'
        } elseif ($Connector.Bindings) {
            $Connector.Bindings
        } else {
            '0.0.0.0:25'  # Default binding
        }
        
        # Parse RemoteIPRanges
        $remoteIPRanges = if ($Connector.'$_.RemoteIPRanges') {
            $Connector.'$_.RemoteIPRanges' -split '\s+' | Where-Object { $_.Trim() -ne '' }
        } elseif ($Connector.RemoteIPRanges) {
            $Connector.RemoteIPRanges -split '\s+' | Where-Object { $_.Trim() -ne '' }
        } else {
            @('0.0.0.0-255.255.255.255')  # Default range
        }
        
        return @{
            Name = $connectorName
            AuthMechanism = $authMechanism
            PermissionGroups = $permissionGroups
            Bindings = $bindings
            RemoteIPRanges = $remoteIPRanges
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
        
        $params = @{
            Name = $ConnectorConfig.Name
            Server = $ServerName
            AuthMechanism = $ConnectorConfig.AuthMechanism
            PermissionGroups = $ConnectorConfig.PermissionGroups
            Bindings = $ConnectorConfig.Bindings
            RemoteIPRanges = $ConnectorConfig.RemoteIPRanges
            Usage = 'Custom'
            TransportRole = 'FrontendTransport'
            ErrorAction = 'Stop'
        }
        
        New-ReceiveConnector @params | Out-Null
        
        Write-LogMessage "Successfully created Receive Connector '$($ConnectorConfig.Name)' on $ServerName" -Level "SUCCESS"
        Write-LogMessage "  Bindings: $($ConnectorConfig.Bindings)"
        Write-LogMessage "  RemoteIPRanges: $($ConnectorConfig.RemoteIPRanges -join ', ')"
        
        return $true
    }
    catch {
        Write-LogMessage "Failed to create Receive Connector '$($ConnectorConfig.Name)' on $ServerName : $($_.Exception.Message)" -Level "ERROR"
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
            ErrorAction = 'Stop'
        }
        
        Set-ReceiveConnector @params | Out-Null
        
        Write-LogMessage "Successfully updated Receive Connector '$($ConnectorConfig.Name)'" -Level "SUCCESS"
        Write-LogMessage "  Bindings: $($ConnectorConfig.Bindings)"
        Write-LogMessage "  RemoteIPRanges: $($ConnectorConfig.RemoteIPRanges -join ', ')"
        
        return $true
    }
    catch {
        Write-LogMessage "Failed to update Receive Connector '$($ConnectorConfig.Name)': $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Main execution
try {
    Write-LogMessage "Starting Receive Connector management script" -Level "INFO"
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
                    Where-Object { $_.Identity -eq $identity }
                
                if (-not $existingConnector) {
                    # Create new connector
                    if (New-ReceiveConnectorSafe -ServerName $serverName -ConnectorConfig $connectorConfig) {
                        $successCount++
                    } else {
                        $errorCount++
                    }
                } else {
                    # Update existing connector
                    if (Set-ReceiveConnectorSafe -Identity $identity -ConnectorConfig $connectorConfig) {
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
    Write-LogMessage "Errors: $errorCount" -Level $(if ($errorCount -eq 0) { "SUCCESS" } else { "WARNING" })
    Write-LogMessage "Script completed" -Level "SUCCESS"
    
    if ($errorCount -gt 0) {
        exit 1
    }
}
catch {
    Write-LogMessage "Critical error in main execution: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}