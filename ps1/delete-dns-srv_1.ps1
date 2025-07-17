$Hostnames = Read-Host "Please provide Hostname"
$IPAddress = Read-Host "Please provide Ip Address"
$Zones = Get-DnsServerZone | ?{$_.ZoneType -eq "Primary"} | Select -ExpandProperty ZoneName
$Hostname = Resolve-DnsName $Hostnames | Select -ExpandProperty Name
$Hostname = $Hostname + "."
foreach($Zone in $Zones)
{
Get-DnsServerResourceRecord -ZoneName $Zone | Where-Object {$_.RecordData.IPv4Address -eq $IPAddress -or $_.RecordData.NameServer -like $Hostname -or $_.RecordData.DomainName -like $Hostname} | Remove-DnsServerResourceRecord -ZoneName $Zone -Force
}