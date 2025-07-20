$prefixes = @("PVEXCH", "RVEXCH")
foreach ($prefix in $prefixes) {
    for ($i = 1; $i -le 7; $i++) {
        # Pad the number with leading zero if necessary
        $serverName = "{0}{1:D2}WBD25WP" -f $prefix, $i
        try {
            # Get all receive connectors for the server
            $connectors = Get-ReceiveConnector -Server $serverName
            foreach ($connector in $connectors) {
                Write-Host "Enabling verbose protocol logging on connector '$($connector.Name)' on server '$serverName'..."
                Set-ReceiveConnector -Identity "$($connector.Identity)" -ProtocolLoggingLevel Verbose
            }
        } catch {
            Write-Warning "Failed to update connectors on $serverName. Error: $_"
        }
    }
}
