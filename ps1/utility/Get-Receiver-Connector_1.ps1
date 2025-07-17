# Must run in Exchange Management Shell
# Or ensure Exchange module is loaded (Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn)

$outputCsv = "C:\Temp\ReceiverConnectors_AllServers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

# Get all Exchange servers
$exchangeServers = Get-ExchangeServer | Where-Object {$_.IsHubTransportServer -or $_.IsClientAccessServer -or $_.IsMailboxServer}

$allConnectors = @()

foreach ($server in $exchangeServers) {
    $serverName = $server.Name
    Write-Host "Fetching Receive Connectors from server: $serverName" -ForegroundColor Cyan

    try {
        $connectors = Get-ReceiveConnector

        foreach ($connector in $connectors) {
            $allConnectors += [PSCustomObject]@{
                Identity                = $connector.Identity
                Server                  = $serverName
                Name                    = $connector.Name
                Bindings                = ($connector.Bindings -join ', ')
                RemoteIPRanges          = ($connector.RemoteIPRanges -join ', ')
                AuthMechanism           = $connector.AuthMechanism
                PermissionGroups        = $connector.PermissionGroups
                MaxMessageSize          = $connector.MaxMessageSize
                MaxLocalHopCount        = $connector.MaxLocalHopCount
                MaxHopCount             = $connector.MaxHopCount
                MaxInboundConnection    = $connector.MaxInboundConnection
                MaxInboundConnectionPerSource = $connector.MaxInboundConnectionPerSource
                MessageRateLimit = $connector.MessageRateLimit
            }
        }

        Write-Host " -> Found $($connectors.Count) connectors on $serverName"
    }
    catch {
        Write-Warning "Failed to get connectors from server '$serverName': $_"
    }
}

# Export results
if ($allConnectors.Count -gt 0) {
    $allConnectors | Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8
    Write-Host "`n✅ Export complete. File saved to: $outputCsv" -ForegroundColor Green
} else {
    Write-Warning "No connectors found to export."
}

