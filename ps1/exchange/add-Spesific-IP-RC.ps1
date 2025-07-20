# Define the single IP to add as an IPRange object (no subnet, just single IP)
$targetIP = [Microsoft.Exchange.Data.IPRange]::Parse("10.254.151.107")

# Target connector name
$connectorName = "BCM Preparedness & Crisis Management System - Arief Sendra - APD"

# Generate server names
$servers = @()
1..7 | ForEach-Object {
    $servers += "PVEXCH0$_" + "WBD25WP"
    $servers += "RVEXCH0$_" + "WBD25WP"
}

# Loop through servers and update the connector
foreach ($server in $servers) {
    try {
        $connector = Get-ReceiveConnector -Server $server | Where-Object { $_.Name -eq $connectorName }

        if ($connector) {
            if ($connector.RemoteIPRanges -notcontains $targetIP) {
                # Clone existing list and add new IP
                $updatedRanges = $connector.RemoteIPRanges + $targetIP
                Set-ReceiveConnector -Identity $connector.Identity -RemoteIPRanges $updatedRanges
                Write-Host "✅ Added $($targetIP.IPAddress) to '$connectorName' on $server"
            } else {
                Write-Host "ℹ️ IP $($targetIP.IPAddress) already exists on '$connectorName' on $server"
            }
        } else {
            Write-Warning "❌ Connector '$connectorName' not found on $server"
        }
    } catch {
        Write-Warning "⚠️ Error on $server : $_"
    }
}
