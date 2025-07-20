# Define connector names to target
$targetConnectorNames = @(
    "Client Frontend",
    "Client Proxy",
    "Default",
    "Default Frontend",
    "Outbound Proxy Frontend"
)

# Server name prefixes
$prefixes = @("PVEXCH", "RVEXCH")

# Loop through each prefix and server number
foreach ($prefix in $prefixes) {
    for ($i = 1; $i -le 7; $i++) {
        $serverName = "{0}{1}WBD25WP" -f $prefix, $i

        try {
            # Get all receive connectors for the server
            $connectors = Get-ReceiveConnector -Server $serverName

            foreach ($connector in $connectors) {
                # Match against the connector names
                foreach ($targetName in $targetConnectorNames) {
                    if ($connector.Name -like "$targetName*") {
                        Write-Host "Enabling verbose logging on '$($connector.Name)' on server '$serverName'"
                        Set-ReceiveConnector -Identity $connector.Identity -ProtocolLoggingLevel Verbose
                    }
                }
            }
        } catch {
            Write-Warning "Failed to process $serverName. Error: $_"
        }
    }
}
