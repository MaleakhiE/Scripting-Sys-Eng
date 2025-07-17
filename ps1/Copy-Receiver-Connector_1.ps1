# Import data dari CSV
$csvPath = 'C:\Script\Copy Receiver Connector\ReceieveConnector19062025(1).csv'
$connectors = Import-Csv -Path $csvPath -Delimiter ";" 

# Daftar server tujuan
$serverNames = @("PVEXCH01WBD25WP")

foreach ($serverName in $serverNames) {
    foreach ($connector in $connectors) {
        # Ambil hanya nama konektor, karena identity lama biasanya server lama
        $connectorName = ($connector.Identity -split '\\')[-1]
        $identity = "$serverName\$connectorName"

        # Prepare AuthMechanism dan PermissionGroups
        $authMechanism = $connector.AuthMechanism -split ',\s*'
        $permissionGroups = $connector.PermissionGroups -split ',\s*'

        # Prepare Bindings
        $bindings = $connector.'$_.Bindings'

        # Remote IP Ranges bisa mengandung banyak IP/range
        $remoteIPRanges = $connector.'$_.RemoteIPRanges' -split '\s+'

        # Cek apakah sudah ada Receive Connector
        $existing = Get-ReceiveConnector -Server $serverName | Where-Object { $_.Identity -eq $identity }

        if (-not $existing) {
            Write-Host "---------------------------------------------"
            Write-Host "Creating Receive Connector '$connectorName' on $serverName"

            New-ReceiveConnector -Name $connectorName `
                -Server $serverName `
                -AuthMechanism $authMechanism `
                -PermissionGroups $permissionGroups `
                -Bindings $bindings `
                -RemoteIPRanges $remoteIPRanges `
                -Usage Custom `
                -TransportRole FrontendTransport

            Write-Host "Created Receive Connector '$connectorName' on $serverName"
            Write-Host "Bindings: $bindings"
            Write-Host "RemoteIPRanges: $($remoteIPRanges -join ', ')"
            Write-Host "---------------------------------------------"
        }
        else {
            Write-Host "---------------------------------------------"
            Write-Host "Updating existing Receive Connector '$connectorName' on $serverName"

            Set-ReceiveConnector -Identity $identity `
                -AuthMechanism $authMechanism `
                -PermissionGroups $permissionGroups `
                -Bindings $bindings `
                -RemoteIPRanges $remoteIPRanges

            Write-Host "Updated Receive Connector '$connectorName' on $serverName"
            Write-Host "Bindings: $bindings"
            Write-Host "RemoteIPRanges: $($remoteIPRanges -join ', ')"
            Write-Host "---------------------------------------------"
        }
    }
}
