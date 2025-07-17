# Install required modules if not already installed
Install-Module Microsoft.Graph -Force
Import-Module Microsoft.Graph

# Authentication parameters
$clientId = "14dfa8f3-e0e9-420c-889a-f7c3d369f604"
$clientSecret = "KtX8Q~tIi8NEGujS2sUBi3jgt~nGgZ8mEpSwMbJk"
$tenantId = "39c345ae-bf0d-40bf-aba9-081979356879"

# Convert client secret to secure string
$secureClientSecret = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force

# Create certificate based credentials
$clientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $secureClientSecret

# Connect to Microsoft Graph using client credentials
Connect-MgGraph -ClientSecretCredential $clientSecretCredential -TenantId $tenantId

# Define the notification recipient
$recipientEmail = "maleakhi@dikstrasolusi.com"

# Function to send consolidated email notification
function Send-ConsolidatedNotification {
    param (
        [string]$ConsolidatedDetails
    )

    # Email content
    $subject = "[Info] Consolidated Secrets and Certificates Report"
    $body = @"
<html>
<head>
    <style>
        table {
            border-collapse: collapse;
            width: 100%;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px 0;
            font-size: 14px;
        }
        th {
            background-color: #2a9df4;
            color: white;
            text-align: center;
            padding: 12px;
            font-weight: bold;
        }
        td {
            border: 1px solid #ddd;
            text-align: center;
            padding: 10px;
            font-size: 13px;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        tr:nth-child(odd) {
            background-color: #ffffff;
        }
        tr:hover {
            background-color: #f1f1f1;
        }
        caption {
            caption-side: top;
            font-size: 16px;
            font-weight: bold;
            margin-bottom: 10px;
        }
        p {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            font-size: 14px;
            line-height: 1.6;
        }
    </style>
</head>
<body>
    <p>Hello,</p>
    <p>Below is the consolidated report of secrets and certificates for all applications on Protelindo.com :</p>
    <div>
        $ConsolidatedDetails
    </div>
    <p>Please review and take necessary actions if needed.</p>
    <p>Best regards,</p>
    <p><strong>Admin Team - Protelindo</strong></p>
</body>
</html>
"@

    # Send email using Microsoft Graph
    Send-MgUserMail -UserId $recipientEmail -Message @{
        Subject = $subject
        Body = @{
            ContentType = "HTML"
            Content = $body
        }
        ToRecipients = @(@{ EmailAddress = @{ Address = $recipientEmail } })
    }
    Write-Output "Consolidated notification sent to $recipientEmail"
}

# Get today's date and the date for 60 days ahead
$currentDate = Get-Date
$sixtyDaysFromNow = $currentDate.AddDays(60)

# Get all Enterprise Applications
$applications = Get-MgApplication

# Initialize the consolidated details table
$consolidatedDetails = "<table>
    <caption>Secrets and Certificates Report</caption>
    <tr><th>Application</th><th>Type</th><th>Start Date</th><th>End Date</th></tr>"

foreach ($app in $applications) {
    $appName = $app.DisplayName

    # Add key credentials (certificates) to details if expiring in the next 60 days
    foreach ($key in $app.KeyCredentials) {
        $endDate = [datetime]$key.EndDateTime
        if ($endDate -le $sixtyDaysFromNow) {
            $consolidatedDetails += "<tr><td>$appName</td><td>Certificate</td><td>$([datetime]$key.StartDateTime)</td><td>$endDate</td></tr>"
        }
    }

    # Add password credentials (secrets) to details if expiring in the next 60 days
    foreach ($password in $app.PasswordCredentials) {
        $endDate = [datetime]$password.EndDateTime
        if ($endDate -le $sixtyDaysFromNow) {
            $consolidatedDetails += "<tr><td>$appName</td><td>Secret</td><td>$([datetime]$password.StartDateTime)</td><td>$endDate</td></tr>"
        }
    }
}

# Close the HTML table
$consolidatedDetails += "</table>"

# Send the consolidated email notification if there are details to report
if ($consolidatedDetails -ne "<table><caption>Secrets and Certificates Report</caption><tr><th>Application</th><th>Type</th><th>Start Date</th><th>End Date</th></tr></table>") {
    Send-ConsolidatedNotification -ConsolidatedDetails $consolidatedDetails
} else {
    Write-Output "No secrets or certificates expiring in the next 60 days."
}

# Disconnect from Microsoft Graph
Disconnect-MgGraph