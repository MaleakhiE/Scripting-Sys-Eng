#Requires -Version 5.1
<#
.SYNOPSIS
    Removes all custom Exchange Receive Connectors from specified servers
.DESCRIPTION
    This script removes all custom Receive Connectors from Exchange servers while preserving
    default system connectors. It includes safety checks and detailed logging.
.PARAMETER ServerNames
    Array of Exchange server names where connectors should be removed
.PARAMETER LogPath
    Path for the log file (optional)
.PARAMETER IncludeDefaults
    Switch to include removal of default connectors (use with caution)
.PARAMETER WhatIf
    Switch to preview what would be removed without actually removing anything
.EXAMPLE
    .\Remove-ReceiveConnectors.ps1 -ServerNames @("PVEXCH01WBD25WP") -WhatIf
.EXAMPLE
    .\Remove-ReceiveConnectors.ps1 -ServerNames @("PVEXCH01WBD25WP")
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$ServerNames = @("PVEXCH01WBD25WP"),
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Temp\CustomRC\Logs\RemoveConnectors_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeDefaults = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf = $false
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
    
    return $true
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

function Get-ConnectorsToRemove {
    param(
        [string]$ServerName,
        [bool]$IncludeDefaults
    )
    
    try {
        $allConnectors = Get-ReceiveConnector -Server $ServerName -ErrorAction Stop
        
        if ($IncludeDefaults) {
            Write-LogMessage "Getting ALL connectors for removal (including defaults)" -Level "WARNING"
            return $allConnectors
        }
        else {
            # Define default connector patterns to preserve
            $defaultPatterns = @(
                "*Default*",
                "*Client*",
                "*Proxy*",
                "*Hub*",
                "*Frontend*",
                "*Backend*"
            )
            
            $customConnectors = $allConnectors | Where-Object {
                $connector = $_
                $isDefault = $false
                
                foreach ($pattern in $defaultPatterns) {
                    if ($connector.Name -like $pattern) {
                        $isDefault = $true
                        break
                    }
                }
                
                # Also check if it's a system connector by TransportRole
                if ($connector.TransportRole -eq "HubTransport" -or 
                    $connector.TransportRole -eq "MailboxTransport") {
                    $isDefault = $true
                }
                
                return -not $isDefault
            }
            
            Write-LogMessage "Found $($customConnectors.Count) custom connectors to remove"
            Write-LogMessage "Preserving $($allConnectors.Count - $customConnectors.Count) default/system connectors"
            
            return $customConnectors
        }
    }
    catch {
        Write-LogMessage "Failed to get connectors from server '$ServerName': $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Remove-ConnectorSafe {
    param(
        [object]$Connector,
        [bool]$WhatIfMode
    )
    
    try {
        $connectorInfo = "Connector: '$($Connector.Name)' | Identity: '$($Connector.Identity)' | Role: '$($Connector.TransportRole)'"
        
        if ($WhatIfMode) {
            Write-LogMessage "[WHATIF] Would remove $connectorInfo" -Level "INFO"
            return $true
        }
        else {
            Write-LogMessage "Removing $connectorInfo..."
            Remove-ReceiveConnector -Identity $Connector.Identity -Confirm:$false -ErrorAction Stop
            Write-LogMessage "Successfully removed connector '$($Connector.Name)'" -Level "SUCCESS"
            return $true
        }
    }
    catch {
        Write-LogMessage "Failed to remove connector '$($Connector.Name)': $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Show-RemovalSummary {
    param(
        [array]$ConnectorsToRemove,
        [string]$ServerName
    )
    
    Write-LogMessage ("=" * 60)
    Write-LogMessage "REMOVAL SUMMARY for server: $ServerName"
    Write-LogMessage ("=" * 60)
    
    if ($ConnectorsToRemove.Count -eq 0) {
        Write-LogMessage "No connectors found for removal" -Level "INFO"
        return
    }
    
    Write-LogMessage "The following $($ConnectorsToRemove.Count) connector(s) will be removed:"
    
    foreach ($connector in $ConnectorsToRemove) {
        Write-LogMessage "  - Name: '$($connector.Name)'"
        Write-LogMessage "    Identity: '$($connector.Identity)'"
        Write-LogMessage "    Transport Role: '$($connector.TransportRole)'"
        Write-LogMessage "    Bindings: '$($connector.Bindings -join ', ')'"
        Write-LogMessage "    Remote IP Ranges: '$($connector.RemoteIPRanges -join ', ')'"
        Write-LogMessage "    ---"
    }
    
    Write-LogMessage ("=" * 60)
}

# Main execution
try {
    $modeText = if ($WhatIf) { "PREVIEW MODE (WhatIf)" } else { "EXECUTION MODE" }
    $defaultsText = if ($IncludeDefaults) { "INCLUDING DEFAULT CONNECTORS" } else { "CUSTOM CONNECTORS ONLY" }
    
    Write-LogMessage "Starting Receive Connector removal script - $modeText" -Level "INFO"
    Write-LogMessage "Mode: $defaultsText" -Level "INFO"
    Write-LogMessage "Target Servers: $($ServerNames -join ', ')"
    Write-LogMessage "Log Path: $LogPath"
    Write-LogMessage ("=" * 80)
    
    # Safety warning for default connectors
    if ($IncludeDefaults) {
        Write-LogMessage "WARNING: IncludeDefaults is enabled. This will remove ALL connectors including system defaults!" -Level "WARNING"
        Write-LogMessage "This may break email flow. Use with extreme caution!" -Level "WARNING"
    }
    
    # Check prerequisites
    if (-not (Test-Prerequisites)) {
        exit 1
    }
    
    # Initialize counters
    $totalProcessed = 0
    $successCount = 0
    $errorCount = 0
    $totalConnectors = 0
    
    # Process each server
    foreach ($serverName in $ServerNames) {
        Write-LogMessage ("=" * 50)
        Write-LogMessage "Processing server: $serverName"
        
        # Test server connectivity
        if (-not (Test-ServerConnectivity -ServerName $serverName)) {
            Write-LogMessage "Skipping server '$serverName' due to connectivity issues" -Level "WARNING"
            continue
        }
        
        # Get connectors to remove
        $connectorsToRemove = Get-ConnectorsToRemove -ServerName $serverName -IncludeDefaults $IncludeDefaults
        
        if (-not $connectorsToRemove -or $connectorsToRemove.Count -eq 0) {
            Write-LogMessage "No connectors found for removal on server '$serverName'" -Level "INFO"
            continue
        }
        
        $totalConnectors += $connectorsToRemove.Count
        
        # Show what will be removed
        Show-RemovalSummary -ConnectorsToRemove $connectorsToRemove -ServerName $serverName
        
        # Confirmation prompt (only in execution mode)
        if (-not $WhatIf) {
            $confirmation = Read-Host "Are you sure you want to remove these $($connectorsToRemove.Count) connector(s) from $serverName? (y/N)"
            if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
                Write-LogMessage "Removal cancelled by user for server '$serverName'" -Level "WARNING"
                continue
            }
        }
        
        # Remove connectors
        foreach ($connector in $connectorsToRemove) {
            $totalProcessed++
            
            if (Remove-ConnectorSafe -Connector $connector -WhatIfMode $WhatIf) {
                $successCount++
            } else {
                $errorCount++
            }
        }
        
        Write-LogMessage "Completed processing server '$serverName'" -Level "INFO"
    }
    
    # Final Summary
    Write-LogMessage ("=" * 80)
    Write-LogMessage "FINAL SUMMARY:" -Level "INFO"
    Write-LogMessage "Mode: $modeText"
    Write-LogMessage "Total Connectors Found: $totalConnectors"
    Write-LogMessage "Total Processed: $totalProcessed"
    Write-LogMessage "Successful: $successCount" -Level "SUCCESS"
    Write-LogMessage "Errors: $errorCount" -Level $(if ($errorCount -eq 0) { "SUCCESS" } else { "WARNING" })
    
    if ($WhatIf) {
        Write-LogMessage "This was a preview run. No connectors were actually removed." -Level "INFO"
        Write-LogMessage "Run without -WhatIf to perform actual removal." -Level "INFO"
    }
    else {
        Write-LogMessage "Connector removal completed" -Level "SUCCESS"
    }
    
    if ($errorCount -gt 0) {
        exit 1
    }
}
catch {
    Write-LogMessage "Critical error in main execution: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}
