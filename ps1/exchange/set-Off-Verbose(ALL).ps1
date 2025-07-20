# Get all Exchange servers
$servers = Get-ExchangeServer | Where-Object { $_.ServerRole -match "HubTransport|Mailbox" }

foreach ($server in $servers) {
    $serverName = $server.Name
    try {
        # Get all Receive Connectors on the server
        $connectors = Get-ReceiveConnector -Server $serverName
        foreach ($connector in $connectors) {
            Write-Host "Disabling verbose logging on connector '$($connector.Name)' on server '$serverName'..."
            Set-ReceiveConnector -Identity "$($connector.Identity)" -ProtocolLoggingLevel None
        }
    } catch {
        Write-Warning "Failed to update connectors on $serverName. Error: $_"
    }
}
