# Install and import the Microsoft.Graph module
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

$senderEmail = "maleakhi@dikstrasolusi.com"

# Function to send individual email notifications
function Send-UserNotification {
    param (
        [string]$RecipientEmail,
        [string]$UserDetails
    )

    # Email content
    $subject = "[Notification - Testing] Your Account Password Status"
    $body = @"
<html>
<head>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            font-size: 14px;
            line-height: 1.6;
            color: #333333;
            margin: 20px;
        }
        h1 {
            color: #2a9df4;
            text-align: center;
        }
        p {
            margin: 10px 0;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin-top: 20px;
            font-size: 14px;
        }
        th, td {
            border: 1px solid #ddd;
            text-align: left;
            padding: 8px;
        }
        th {
            background-color: #2a9df4;
            color: white;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        tr:hover {
            background-color: #f1f1f1;
        }
    </style>
</head>
<body>
    <h1>Password Status Notification</h1>
    <p>Hello,</p>
    <p>We wanted to notify you about your password status. Please see the details below:</p>
    <table>
        <thead>
            <tr>
                <th>Detail</th>
                <th>Information</th>
            </tr>
        </thead>
        <tbody>
            $UserDetails
        </tbody>
    </table>
    <p>If you have any questions or need further assistance, please contact the admin team.</p>
    <p>Best regards,</p>
    <p><strong>Admin Team</strong></p>
</body>
</html>
"@

    # Send email using Microsoft Graph
    Send-MgUserMail -UserId $senderEmail -Message @{
        Subject = $subject
        Body = @{
            ContentType = "HTML"
            Content = $body
        }
        ToRecipients = @(@{ EmailAddress = @{ Address = $RecipientEmail } })
    }
    Write-Output "Notification sent to $RecipientEmail"
}

# Fetch all members from a specific Azure AD group
$groupId = "c1e156b9-3105-44c6-ae2c-b2c70c5f0fb1"  # Replace with your group's ID
$users = Get-MgGroupMember -GroupId $groupId

foreach ($user in $users) {
    # Get detailed user information
    $userDetails = Get-MgUser -UserId $user.Id -Property Id, UserPrincipalName, PasswordPolicies, LastPasswordChangeDateTime

    $userTableDetails = ""
    
    # Check if password is set to never expire
    if ($userDetails.PasswordPolicies -contains "DisablePasswordExpiration") {
        $userTableDetails = "<tr><td>Password Status</td><td>Your password is set to never expire.</td></tr>"
    } else {
        if ($userDetails.LastPasswordChangeDateTime) {
            # Calculate password expiration date (assuming 14-day expiration policy)
            $lastPasswordChange = [DateTime]$userDetails.LastPasswordChangeDateTime
            $expirationDate = $lastPasswordChange.AddDays(14)
            $daysToExpire = ($expirationDate - (Get-Date)).Days

            if ($daysToExpire -gt 0) {
                $userTableDetails = "<tr><td>Password Status</td><td>Your password will expire on $($expirationDate.ToString('yyyy-MM-dd')) (in $daysToExpire days).</td></tr>"
                
                # Only send notification if password will expire within 14 days
                if ($daysToExpire -le 14) {
                    Send-UserNotification -RecipientEmail $userDetails.UserPrincipalName -UserDetails $userTableDetails
                }
            } else {
                $userTableDetails = "<tr><td>Password Status</td><td>Your password has expired. Please update it immediately.</td></tr>"
                # Export to CSV
                $CSVPath = "/Users/eki/Documents/Temp/expired_users.csv"
                $userDetails | Select-Object UserPrincipalName, PasswordPolicies, LastPasswordChangeDateTime | Export-Csv -Path $CSVPath -Append -NoTypeInformation
                # Send-UserNotification -RecipientEmail $userDetails.UserPrincipalName -UserDetails $userTableDetails
            }
        } else {
            $userTableDetails = "<tr><td>Password Status</td><td>Unable to determine password status.</td></tr>"
        }
    }
    
    Write-Output "Processed user: $($userDetails.UserPrincipalName)"
}

# Disconnect from Microsoft Graph
Disconnect-MgGraph