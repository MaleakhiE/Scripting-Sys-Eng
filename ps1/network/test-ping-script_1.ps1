# Define the path to the output file where results will be saved
$outputFile = "C:\Users\Administrator\Documents\Script\Test_Ping_Results.txt"

# Initialize the output file
"Ping Test Results with Hostnames" | Out-File -FilePath $outputFile -Encoding UTF8

# Import the Active Directory module
Import-Module ActiveDirectory

# Get the list of computer names from Active Directory
$computers = Get-ADComputer -Filter * -Property Name | Select-Object -ExpandProperty Name

foreach ($computer in $computers) {
    # Ping the computer
    $pingResult = Test-Connection -ComputerName $computer -Count 1 -ErrorAction SilentlyContinue

    if ($pingResult) {
        $pingStatus = "Reply from $($computer): bytes=32 time=$($pingResult.ResponseTime)ms TTL=$($pingResult.Ttl)"
    } else {
        $pingStatus = "Request timed out."
    }

    # Resolve the hostname
    try {
        $hostname = [System.Net.Dns]::GetHostEntry($computer).HostName
    } catch {
        $hostname = "Hostname not resolved"
    }

    # Write results to the output file
    "$computer" | Out-File -FilePath $outputFile -Append -Encoding UTF8
    "$pingStatus" | Out-File -FilePath $outputFile -Append -Encoding UTF8
    "Hostname: $hostname" | Out-File -FilePath $outputFile -Append -Encoding UTF8
    "" | Out-File -FilePath $outputFile -Append -Encoding UTF8
}

"Ping test complete. Results saved to $outputFile." | Out-File -FilePath $outputFile -Append -Encoding UTF8
