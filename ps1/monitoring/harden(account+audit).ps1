# AuditPol /get /category:* (get audit policy settings)
# Import required module
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# Paths for logs and reports
$logPath = "C:\Temp\PolicyApplicationLog.txt"
$reportPath = "C:\Temp\PolicyApplicationReport.html"

# Clear old log file if exists
if (Test-Path $logPath) { Remove-Item $logPath }

# Log function for better readability
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logPath -Append
    Write-Host $Message
}

# Function to get existing audit policies
function Get-ExistingAuditPolicies {
    Write-Log "Retrieving existing audit policies..."
    $existingPolicies = @()
    $output = AuditPol /get /category:*
    $currentCategory = ""
    
    foreach ($line in $output) {
        if ($line -match "^\s*Category:\s*(.+)$") {
            $currentCategory = $matches[1]
        } elseif ($line -match "^\s*(.+?)\s*-\s*(.+?)\s*-\s*(.+)$") {
            $existingPolicies += @{
                Category = $currentCategory
                Subcategory = $matches[1].Trim()
                Success = $matches[2].Trim()
                Failure = $matches[3].Trim()
            }
        }
    }

    Write-Log "Existing audit policies retrieved."
    return $existingPolicies
}

# Function to apply password and account policies
function Set-AccountPolicies {
    Write-Log "Applying Password and Account Policies..."
    $accountPolicies = @()

    # Password Policies
    secedit /export /cfg C:\Windows\Temp\secpol.cfg
    (Get-Content C:\Windows\Temp\secpol.cfg) -replace 'PasswordHistorySize = .+', 'PasswordHistorySize = 13' |
        Set-Content C:\Windows\Temp\secpol.cfg
    $accountPolicies += @{ Policy = "Enforce password history"; Value = "13 passwords remembered"; Status = "Applied" }

    (Get-Content C:\Windows\Temp\secpol.cfg) -replace 'MaximumPasswordAge = .+', 'MaximumPasswordAge = 30' |
        Set-Content C:\Windows\Temp\secpol.cfg
    $accountPolicies += @{ Policy = "Maximum password age"; Value = "30 days"; Status = "Applied" }

    (Get-Content C:\Windows\Temp\secpol.cfg) -replace 'MinimumPasswordAge = .+', 'MinimumPasswordAge = 0' |
        Set-Content C:\Windows\Temp\secpol.cfg
    $accountPolicies += @{ Policy = "Minimum password age"; Value = "0 days"; Status = "Applied" }

    (Get-Content C:\Windows\Temp\secpol.cfg) -replace 'MinimumPasswordLength = .+', 'MinimumPasswordLength = 8' |
        Set-Content C:\Windows\Temp\secpol.cfg
    $accountPolicies += @{ Policy = "Minimum password length"; Value = "8 characters"; Status = "Applied" }

    secedit /configure /db secedit.sdb /cfg C:\Windows\Temp\secpol.cfg /quiet

    # Account Lockout Policies
    net accounts /lockoutthreshold:6
    net accounts /lockoutduration:5
    net accounts /lockoutwindow:5
    $accountPolicies += @{ Policy = "Account lockout threshold"; Value = "6 valid login attempts"; Status = "Applied" }
    $accountPolicies += @{ Policy = "Account lockout duration"; Value = "5 minutes"; Status = "Applied" }
    $accountPolicies += @{ Policy = "Reset account lockout counter after"; Value = "5 minutes"; Status = "Applied" }

    Write-Log "Password and Account Policies Applied."
    return $accountPolicies
}

# Function to apply advanced audit policies
function Set-AdvancedAuditPolicies {
    Write-Log "Applying Advanced Audit Policies..."
    $existingPolicies = Get-ExistingAuditPolicies
    $auditPoliciesApplied = @()

    # Define desired audit policies
    $desiredPolicies = @(
        @{Subcategory = "IPsec Driver"; Setting = "Success and Failure"},
        @{Subcategory = "Security State Change"; Setting = "Success and Failure"},
        @{Subcategory = "Security System Extension"; Setting = "Success and Failure"},
        @{Subcategory = "System Integrity"; Setting = "Success and Failure"},
        @{Subcategory = "Logoff"; Setting = "Success"},
        @{Subcategory = "Logon"; Setting = "Success and Failure"},
        @{Subcategory = "Special Logon"; Setting = "Success and Failure"},
        @{Subcategory = "File System"; Setting = "Failure"},
        @{Subcategory = "Registry"; Setting = "Failure"},
        @{Subcategory = "Sensitive Privilege Use"; Setting = "Success and Failure"},
        @{Subcategory = "Process Creation"; Setting = "Success"},
        @{Subcategory = "Audit Policy Change"; Setting = "Success and Failure"},
        @{Subcategory = "Authentication Policy Change"; Setting = "Success"},
        @{Subcategory = "Computer Account Management"; Setting = "Success and Failure"},
        @{Subcategory = "Other Account Management Events"; Setting = "Success and Failure"},
        @{Subcategory = "Security Group Management"; Setting = "Success and Failure"},
        @{Subcategory = "User Account Management"; Setting = "Success and Failure"},
        @{Subcategory = "Directory Service Access"; Setting = "Success and Failure"},
        @{Subcategory = "Directory Service Changes"; Setting = "Success and Failure"},
        @{Subcategory = "Credential Validation"; Setting = "Success and Failure"}
    )

    # Compare and apply missing policies
    foreach ($policy in $desiredPolicies) {
        $existing = $existingPolicies | Where-Object { $_.Subcategory -eq $policy.Subcategory }
        if ($existing -and $existing.Success -eq "Enable" -and $existing.Failure -eq "Enable") {
            $auditPoliciesApplied += @{ Policy = $policy.Subcategory; Setting = $policy.Setting; Status = "Already Applied" }
        } else {
            $success = "Disable"
            $failure = "Disable"
            if ($policy.Setting -match "Success") { $success = "Enable" }
            if ($policy.Setting -match "Failure") { $failure = "Enable" }
            AuditPol /set /subcategory:"$($policy.Subcategory)" /success:$success /failure:$failure
            $auditPoliciesApplied += @{ Policy = $policy.Subcategory; Setting = $policy.Setting; Status = "Applied" }
            Write-Log "Applied policy: $($policy.Subcategory) - Setting: $($policy.Setting)"
        }
    }

    Write-Log "Advanced Audit Policies Applied."
    return $auditPoliciesApplied
}

function Generate-Report {
    param (
        [Parameter(Mandatory = $true)]
        [Array]$AccountPolicies,
        [Parameter(Mandatory = $true)]
        [Array]$AuditPolicies
    )

    # Filter out any policies with missing data to avoid blank fields
    $filteredAccountPolicies = $AccountPolicies | Where-Object { $_.Policy -and $_.Value -and $_.Status }
    $filteredAuditPolicies = $AuditPolicies | Where-Object { $_.Policy -and $_.Setting -and $_.Status }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Policy Application Report</title>
    <style>
        body {
            font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 0;
            background-color: #f8f9fa;
            color: #212529;
        }
        .container {
            margin: 20px auto;
            max-width: 80%;
            padding: 20px;
            background: #fff;
            border-radius: 8px;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
        }
        h1, h2 {
            font-weight: 600;
            color: #343a40;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin-top: 20px;
            font-size: 14px;
        }
        th, td {
            border: 1px solid #dee2e6;
            padding: 10px;
            text-align: left;
        }
        th {
            background-color: #007bff;
            color: white;
        }
        tr:nth-child(even) {
            background-color: #f8f9fa;
        }
        tr:hover {
            background-color: #e9ecef;
        }
        .status-applied {
            color: #28a745;
            font-weight: bold;
        }
        .status-already-applied {
            color: #6c757d;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Policy Application Report</h1>
        <h2>Account Policies</h2>
        <table>
            <tr>
                <th>Policy</th>
                <th>Value</th>
                <th>Status</th>
            </tr>
"@

    # Add Account Policies to HTML
    foreach ($policy in $filteredAccountPolicies) {
        $statusClass = ""
        if ($policy.Status -eq "Applied") {
            $statusClass = "status-applied"
        } elseif ($policy.Status -eq "Already Applied") {
            $statusClass = "status-already-applied"
        }
        $html += "<tr><td>$($policy.Policy)</td><td>$($policy.Value)</td><td class='$statusClass'>$($policy.Status)</td></tr>"
    }

    $html += @"
        </table>
        <h2>Audit Policies</h2>
        <table>
            <tr>
                <th>Policy</th>
                <th>Value</th>
                <th>Status</th>
            </tr>
"@

    # Add Audit Policies to HTML
    foreach ($policy in $filteredAuditPolicies) {
        $statusClass = ""
        if ($policy.Status -eq "Applied") {
            $statusClass = "status-applied"
        } elseif ($policy.Status -eq "Already Applied") {
            $statusClass = "status-already-applied"
        }
        $html += "<tr><td>$($policy.Policy)</td><td>$($policy.Setting)</td><td class='$statusClass'>$($policy.Status)</td></tr>"
    }

    $html += @"
        </table>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Log "Report generated at: $reportPath"
}


# Main Script Execution
try {
    Write-Log "Starting Policy Application Process..."

    # Apply policies
    $accountPolicies = Set-AccountPolicies
    $auditPolicies = Set-AdvancedAuditPolicies

    # Generate report
    Generate-Report -AccountPolicies $accountPolicies -AuditPolicies $auditPolicies
    Write-Log "Policy application process completed successfully."
} catch {
    Write-Log "An error occurred: $_"
}
