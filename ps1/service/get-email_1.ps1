# Define internal domains
$internalDomains = @("dikstrasolusi.com", "dikstrasolusi.com")

# Prompt user for date range
$startDateInput = Read-Host "Enter start date (YYYY-MM-DD)"
$endDateInput = Read-Host "Enter end date (YYYY-MM-DD)"

# Convert input to DateTime format
$startDate = [DateTime]::ParseExact($startDateInput, "yyyy-MM-dd", $null)
$endDate = [DateTime]::ParseExact($endDateInput, "yyyy-MM-dd", $null).AddDays(1).AddSeconds(-1)  # Ensure full-day coverage

# Array to store all emails
$allExternalEmails = @()

# Loop over the date range day-by-day
$currentStartDate = $startDate
$currentEndDate = $currentStartDate.AddDays(1).AddSeconds(-1)

while ($currentStartDate -le $endDate) {
    Write-Host "`nQuerying emails from ${currentStartDate} to ${currentEndDate}..." -ForegroundColor Cyan

    # Initialize result variable
    $externalEmails = @()

    # Split day into 10-minute intervals
    $intervalStart = $currentStartDate
    $intervalEnd = $currentStartDate.AddMinutes(5).AddSeconds(-1)

    while ($intervalStart -lt $currentEndDate) {
        Write-Host "`nQuerying from ${intervalStart} to ${intervalEnd}..." -ForegroundColor Green

        # Get emails for the current 10-minute interval
        $batchEmails = Get-MessageTrace -StartDate $intervalStart -EndDate $intervalEnd | Where-Object {
            ($_.RecipientAddress -notmatch ($internalDomains -join "|")) -and  # Exclude internal recipients
            ($_.SenderAddress -match ($internalDomains -join "|")) -and        # Ensure sender is internal
            ($_.Status -eq "Delivered")                                        # Filter only delivered emails
        }

        # Append today's emails to the list
        if ($batchEmails.Count -gt 0) {
            $externalEmails += $batchEmails
        }

        # Move to the next 10-minute interval
        $intervalStart = $intervalStart.AddMinutes(5)
        $intervalEnd = $intervalEnd.AddMinutes(5)
    }

    # Append today's emails to the overall list
    if ($externalEmails.Count -gt 0) {
        $allExternalEmails += $externalEmails
    }

    # Move to the next day
    $currentStartDate = $currentStartDate.AddDays(1)
    $currentEndDate = $currentEndDate.AddDays(1)
}

# Display results in a readable table
if ($allExternalEmails.Count -gt 0) {
    Write-Host "`nEmails sent to external recipients (Delivered) from ${startDateInput} to ${endDateInput}:`n" -ForegroundColor Cyan
    $allExternalEmails | Format-Table -AutoSize

    # Adjust the DateTime to local time (if needed)
    $allExternalEmails | ForEach-Object {
        if ($_.Received) { 
            $_.Received = $_.Received.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")  # Convert to local time
        }
        if ($_.SendDate) {
            $_.SendDate = $_.SendDate.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")  # Convert to local time
        }
        $_
    }

    # Export specific fields to CSV
    $csvPath = "/Users/$(whoami)/Documents/DeliveredExternalEmails_${startDateInput}_to_${endDateInput}.csv"
    $allExternalEmails | Select-Object Received, SenderAddress, RecipientAddress, Subject, Status | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "`nResults exported to: $csvPath" -ForegroundColor Green
} else {
    Write-Host "`nNo delivered emails found for external recipients in the specified date range.`n" -ForegroundColor Yellow
}
