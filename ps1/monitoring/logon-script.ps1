# Ensure the ActiveDirectory module is imported
Import-Module ActiveDirectory

# Get all computers in the domain
$computers = Get-ADComputer -Filter * -Property LastLogonDate

# Prepare an array to hold the results
$results = @()

foreach ($computer in $computers) {
    # Get the last logon date and time
    $lastLogon = $computer.LastLogonDate

    # Add the computer and last logon info to the results array
    $results += [PSCustomObject]@{
        ComputerName = $computer.Name
        LastLogon    = $lastLogon
    }
}

# Specify the path to the text file
$txtPath = "C:\Users\Administrator\Documents\Script\Computer-LastLogon.txt"

# Convert the results to a formatted string
$resultsString = $results | Format-Table -AutoSize | Out-String

# Export the results to a text file
$resultsString | Out-File -FilePath $txtPath

# Optional: Display the results in the console
$resultsString
