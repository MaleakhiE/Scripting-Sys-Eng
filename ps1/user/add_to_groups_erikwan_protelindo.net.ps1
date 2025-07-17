Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Connect-ExchangeOnline

try {
    Add-DistributionGroupMember -Identity "it-support@iforte.co.id" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'it-support@iforte.co.id'"
    Add-UnifiedGroupLinks -Identity "it-support@iforte.co.id" -LinkType Members -Links "erikwan@protelindo.net"
}

try {
    Add-DistributionGroupMember -Identity "it-helpdesk@stptower.com" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'it-helpdesk@stptower.com'"
    Add-UnifiedGroupLinks -Identity "it-helpdesk@stptower.com" -LinkType Members -Links "erikwan@protelindo.net"
}

try {
    Add-DistributionGroupMember -Identity "stp-pti@stptower.com" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'stp-pti@stptower.com'"
    Add-UnifiedGroupLinks -Identity "stp-pti@stptower.com" -LinkType Members -Links "erikwan@protelindo.net"
}

try {
    Add-DistributionGroupMember -Identity "migrate-users@stptower.com" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'migrate-users@stptower.com'"
    Add-UnifiedGroupLinks -Identity "migrate-users@stptower.com" -LinkType Members -Links "erikwan@protelindo.net"
}

try {
    Add-DistributionGroupMember -Identity "FinanceDepartementTest@iforte.co.id" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'FinanceDepartementTest@iforte.co.id'"
    Add-UnifiedGroupLinks -Identity "FinanceDepartementTest@iforte.co.id" -LinkType Members -Links "erikwan@protelindo.net"
}

try {
    Add-DistributionGroupMember -Identity "it-support@protelindo.net" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'it-support@protelindo.net'"
    Add-UnifiedGroupLinks -Identity "it-support@protelindo.net" -LinkType Members -Links "erikwan@protelindo.net"
}

try {
    Add-DistributionGroupMember -Identity "ITHelpdesk@protelindo.net" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'ITHelpdesk@protelindo.net'"
    Add-UnifiedGroupLinks -Identity "ITHelpdesk@protelindo.net" -LinkType Members -Links "erikwan@protelindo.net"
}

try {
    Add-DistributionGroupMember -Identity "TrialTeam@iforte.co.id" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'TrialTeam@iforte.co.id'"
    Add-UnifiedGroupLinks -Identity "TrialTeam@iforte.co.id" -LinkType Members -Links "erikwan@protelindo.net"
}

try {
    Add-DistributionGroupMember -Identity "it-test@iforte.co.id" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'it-test@iforte.co.id'"
    Add-UnifiedGroupLinks -Identity "it-test@iforte.co.id" -LinkType Members -Links "erikwan@protelindo.net"
}

try {
    Add-DistributionGroupMember -Identity "IT@protelindo.net" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'IT@protelindo.net'"
    Add-UnifiedGroupLinks -Identity "IT@protelindo.net" -LinkType Members -Links "erikwan@protelindo.net"
}

try {
    Add-DistributionGroupMember -Identity "DelineaUser.Mailgroup@protelindo.net" -Member "erikwan@protelindo.net" -BypassSecurityGroupManagerCheck
} catch {
    Write-Warning "Falling back to Add-UnifiedGroupLinks for group 'DelineaUser.Mailgroup@protelindo.net'"
    Add-UnifiedGroupLinks -Identity "DelineaUser.Mailgroup@protelindo.net" -LinkType Members -Links "erikwan@protelindo.net"
}

Install-Module Microsoft.Graph -Force -AllowClobber
Import-Module Microsoft.Graph
Connect-MgGraph -Scopes "Group.ReadWrite.All User.Read.All"
Select-MgProfile -Name beta

$user = Get-MgUser -UserId "erikwan@protelindo.net"

$groupNames = @(
 "SF USER Office 365 STP",
 "SF IT STP",
 "Delinea User",
 "Intune User"
)

foreach ($groupName in $groupNames) {
    try {
        $group = Get-MgGroup -Filter "displayName eq '$groupName'"
        if ($group) {
            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
        }
    } catch {
        Write-Warning "Failed to add user to '$groupName'. Likely an on-prem AD group."
    }
}
