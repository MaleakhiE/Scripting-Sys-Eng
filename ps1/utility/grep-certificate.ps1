# Define the output CSV file path
$csvOutputPath = "C:\certificates.csv"

# Get the list of all issued certificates and their details
$certificates = certutil -view -out "RequestID,CommonName,CertificateTemplate" 

# Convert the output to a proper CSV format and save it
$certificates | ConvertFrom-Csv | Export-Csv -Path $csvOutputPath -NoTypeInformation

# Output the path of the created CSV file
Write-Output "Certificates exported to: $csvOutputPath"
