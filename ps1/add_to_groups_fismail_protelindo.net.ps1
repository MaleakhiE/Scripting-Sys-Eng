# PowerShell script to add user to various group types
# Generated for: fismail@protelindo.net

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

function Add-UserToGroup {
    param(
        [string]$Identity,
        [string]$UserEmail
    )

    # First, try to determine what type of group this is
    try {
        # Check if it's a Microsoft 365 Group
        $unified = Get-UnifiedGroup -Identity $Identity -ErrorAction SilentlyContinue
        if ($unified) {
            Write-Host "Adding to Microsoft 365 Group: $Identity"
            Add-UnifiedGroupLinks -Identity $unified.Identity -LinkType Members -Links $UserEmail
            return $true
        }

        # Check if it's a Distribution Group
        $distGroup = Get-DistributionGroup -Identity $Identity -ErrorAction SilentlyContinue
        if ($distGroup) {
            Write-Host "Adding to Distribution Group: $Identity"
            Add-DistributionGroupMember -Identity $distGroup.Identity -Member $UserEmail -BypassSecurityGroupManagerCheck
            return $true
        }

        # Check if it's a mail-enabled security group
        $mailGroup = Get-Group -Identity $Identity -ErrorAction SilentlyContinue | Where-Object {$_.RecipientTypeDetails -eq "MailUniversalSecurityGroup"}
        if ($mailGroup) {
            Write-Host "Adding to Mail-Enabled Security Group: $Identity"
            Add-DistributionGroupMember -Identity $mailGroup.Identity -Member $UserEmail -BypassSecurityGroupManagerCheck
            return $true
        }

        Write-Warning "Could not identify group type for: $Identity"
        return $false
    } catch {
        Write-Warning "Error processing group $Identity : $($_.Exception.Message)"
        return $false
    }
}

# Process mail-enabled groups
Write-Host "Processing group: stp-pti@stptower.com" -ForegroundColor Cyan
Add-UserToGroup -Identity "stp-pti@stptower.com" -UserEmail "fismail@protelindo.net"

Write-Host "Processing group: migrate-users@stptower.com" -ForegroundColor Cyan
Add-UserToGroup -Identity "migrate-users@stptower.com" -UserEmail "fismail@protelindo.net"

Write-Host "Processing group: ITInfraSharepointSite@iforte.co.id" -ForegroundColor Cyan
Add-UserToGroup -Identity "ITInfraSharepointSite@iforte.co.id" -UserEmail "fismail@protelindo.net"

Write-Host "Processing group: ITHelpdesk@protelindo.net" -ForegroundColor Cyan
Add-UserToGroup -Identity "ITHelpdesk@protelindo.net" -UserEmail "fismail@protelindo.net"

Write-Host "Processing group: it.infra@protelindo.net" -ForegroundColor Cyan
Add-UserToGroup -Identity "it.infra@protelindo.net" -UserEmail "fismail@protelindo.net"

Write-Host "Processing group: dmarc-rua@protelindo.net" -ForegroundColor Cyan
Add-UserToGroup -Identity "dmarc-rua@protelindo.net" -UserEmail "fismail@protelindo.net"

Write-Host "Processing group: dmarc-ruf@protelindo.net" -ForegroundColor Cyan
Add-UserToGroup -Identity "dmarc-ruf@protelindo.net" -UserEmail "fismail@protelindo.net"

Write-Host "Processing group: IT@protelindo.net" -ForegroundColor Cyan
Add-UserToGroup -Identity "IT@protelindo.net" -UserEmail "fismail@protelindo.net"

Write-Host "Processing group: Sysadmin@protelindo.net" -ForegroundColor Cyan
Add-UserToGroup -Identity "Sysadmin@protelindo.net" -UserEmail "fismail@protelindo.net"

Write-Host "Processing group: DelineaUser.Mailgroup@protelindo.net" -ForegroundColor Cyan
Add-UserToGroup -Identity "DelineaUser.Mailgroup@protelindo.net" -UserEmail "fismail@protelindo.net"


# --- Microsoft Graph Section for Security Groups ---
# Import Microsoft Graph module if not already loaded
if (-not (Get-Module -Name Microsoft.Graph.Groups -ListAvailable)) {
    Write-Warning "Microsoft Graph PowerShell module not found."
    Write-Host "To install: Install-Module Microsoft.Graph -Scope CurrentUser"
    Write-Host "Then connect: Connect-MgGraph -Scopes 'Group.ReadWrite.All','User.Read.All'"
} else {
    # Ensure we're connected to Microsoft Graph
    $graphConnection = Get-MgContext
    if (-not $graphConnection) {
        Write-Warning "Not connected to Microsoft Graph. Please run: Connect-MgGraph -Scopes 'Group.ReadWrite.All','User.Read.All'"
    }
}

# Get user object
try {
    $user = Get-MgUser -UserId "fismail@protelindo.net" -ErrorAction Stop
    if ($user) {
        Write-Host "Found user: $($user.DisplayName) ($($user.Id))" -ForegroundColor Green
    }
} catch {
    Write-Error "Could not find user fismail@protelindo.net: $($_.Exception.Message)"
    exit
}

# Process security groups
Write-Host "Processing security group: SF USER Office 365 STP" -ForegroundColor Yellow
try {
    $group = Get-MgGroup -Filter "displayName eq 'SF USER Office 365 STP'" -ErrorAction Stop
    if ($group) {
        Write-Host "Found group: $($group.DisplayName) ($($group.Id))"
        try {
            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
            Write-Host "Successfully added user to security group: SF USER Office 365 STP" -ForegroundColor Green
        } catch {
            $errorMsg = $_.Exception.Message
            if ($errorMsg -like "*One or more added object references already exist*") {
                Write-Host "User is already a member of SF USER Office 365 STP" -ForegroundColor Cyan
            } else {
                Write-Warning "Failed to add user to SF USER Office 365 STP: $errorMsg"
            }
        }
    } else {
        Write-Warning "Security group 'SF USER Office 365 STP' not found"
    }
} catch {
    Write-Warning "Error searching for group 'SF USER Office 365 STP': $($_.Exception.Message)"
}

Write-Host "Processing security group: SF IT STP" -ForegroundColor Yellow
try {
    $group = Get-MgGroup -Filter "displayName eq 'SF IT STP'" -ErrorAction Stop
    if ($group) {
        Write-Host "Found group: $($group.DisplayName) ($($group.Id))"
        try {
            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
            Write-Host "Successfully added user to security group: SF IT STP" -ForegroundColor Green
        } catch {
            $errorMsg = $_.Exception.Message
            if ($errorMsg -like "*One or more added object references already exist*") {
                Write-Host "User is already a member of SF IT STP" -ForegroundColor Cyan
            } else {
                Write-Warning "Failed to add user to SF IT STP: $errorMsg"
            }
        }
    } else {
        Write-Warning "Security group 'SF IT STP' not found"
    }
} catch {
    Write-Warning "Error searching for group 'SF IT STP': $($_.Exception.Message)"
}

Write-Host "Processing security group: IT Infra STP" -ForegroundColor Yellow
try {
    $group = Get-MgGroup -Filter "displayName eq 'IT Infra STP'" -ErrorAction Stop
    if ($group) {
        Write-Host "Found group: $($group.DisplayName) ($($group.Id))"
        try {
            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
            Write-Host "Successfully added user to security group: IT Infra STP" -ForegroundColor Green
        } catch {
            $errorMsg = $_.Exception.Message
            if ($errorMsg -like "*One or more added object references already exist*") {
                Write-Host "User is already a member of IT Infra STP" -ForegroundColor Cyan
            } else {
                Write-Warning "Failed to add user to IT Infra STP: $errorMsg"
            }
        }
    } else {
        Write-Warning "Security group 'IT Infra STP' not found"
    }
} catch {
    Write-Warning "Error searching for group 'IT Infra STP': $($_.Exception.Message)"
}

Write-Host "Processing security group: Delinea User" -ForegroundColor Yellow
try {
    $group = Get-MgGroup -Filter "displayName eq 'Delinea User'" -ErrorAction Stop
    if ($group) {
        Write-Host "Found group: $($group.DisplayName) ($($group.Id))"
        try {
            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
            Write-Host "Successfully added user to security group: Delinea User" -ForegroundColor Green
        } catch {
            $errorMsg = $_.Exception.Message
            if ($errorMsg -like "*One or more added object references already exist*") {
                Write-Host "User is already a member of Delinea User" -ForegroundColor Cyan
            } else {
                Write-Warning "Failed to add user to Delinea User: $errorMsg"
            }
        }
    } else {
        Write-Warning "Security group 'Delinea User' not found"
    }
} catch {
    Write-Warning "Error searching for group 'Delinea User': $($_.Exception.Message)"
}

Write-Host "`nGroup membership processing complete for fismail@protelindo.net" -ForegroundColor Green
