# Import the DNS module
Import-Module DnsServer

# Specify the DNS server and zone you want to query
$pathFile = "yourpath"
$zoneName = "yourdomain.com"

# Get all DNS records in the specified zone
Get-DnsServerResourceRecord -ZoneName $zoneName | Export-Csv $pathFile
