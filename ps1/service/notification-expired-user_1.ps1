# Install and import the Microsoft.Graph module
Import-Module Microsoft.Graph

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.Read.All", "Mail.Send", "User.Read.All", "AuditLog.Read.All (Delegated)"

$senderEmail = "maleakhi@dikstrasolusi.com"

# Function to send individual email notifications
function Send-UserNotification {
    param (
        [string]$RecipientEmail,
        [string]$UserDetails
    )

    # Email content
    $subject = "[Notification - Testing] Your Account Expiration Status"
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
    <h1>Account Expiration Notification</h1>
    <p>Hello,</p>
    <p>We wanted to notify you about your account expiration status. Please see the details below:</p>
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
$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members"

if ($response.value) {
    foreach ($user in $response.value) {
        $userDetails = ""
        # Check account status for password expiration or non-expiration
        if ($user.passwordPolicies -match "DisablePasswordExpiration") {
            $userDetails = "<tr><td>Password Expiration</td><td>Your password is set to never expire.</td></tr>"
        } else {
            # Fetch SignInActivity for the user
            $signInActivity = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)?$select=signInActivity"

            $lastPasswordChange = $signInActivity.signInActivity.lastPasswordChangeDateTime
            if ($lastPasswordChange) {
                # Calculate password expiration date (assuming 14-day expiration policy)
                $expirationDate = [datetime]$lastPasswordChange.AddDays(14)
                $daysToExpire = ($expirationDate - (Get-Date)).Days

                if ($daysToExpire -gt 0 -and $daysToExpire -le 14) {
                    $userDetails = "<tr><td>Password Expiration</td><td>Your password will expire on $($expirationDate.ToString('yyyy-MM-dd')). Please ensure it is updated before then.</td></tr>"
                    
                    # Send notification to the user
                    Send-UserNotification -RecipientEmail $user.userPrincipalName -UserDetails $userDetails

                } 
            } else {
                $userDetails = "<tr><td>Password Expiration</td><td>Your Password Policy is Set to 'Never Expired'</td></tr>"
                Write-Output("Password expiration status for $($user.userPrincipalName): Never Expired")
            }
        }
    }
} else {
    Write-Output "No users were retrieved from the group. Check API permissions or the query."
}
