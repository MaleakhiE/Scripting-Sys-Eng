if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes "User.Read.All", "GroupMember.Read.All"
}

$users = Get-MgUser -All

$userGroupList = @()

foreach ($user in $users) {
    $groups = @()
    $groupIds = @()
    $groupList = Get-MgUserTransitiveMemberOf -UserId $user.Id -All

    foreach ($group in $groupList) {
        if ($group.AdditionalProperties."@odata.type" -match "group") {
            $groups += $group.AdditionalProperties.displayName
            $groupIds += $group.Id
        }
    }

    $groupNames = if ($groups.Count -gt 0) { $groups -join ", " } else { "No Groups" }
    $groupIdList = if ($groupIds.Count -gt 0) { $groupIds -join ", " } else { "No Group IDs" }

    $userInfo = [PSCustomObject]@{
        UserId            = $user.Id 
        UserPrincipalName = $user.UserPrincipalName
        DisplayName       = $user.DisplayName
        Email             = $user.Mail
        Groups            = $groupNames  
        GroupIds          = $groupIdList
    }

    $userGroupList += $userInfo
}

$userGroupList | Export-Csv -Path "M365_Users_Groups.csv" -NoTypeInformation -Encoding UTF8

Write-Host "✅ Export completed. File saved as M365_Users_Groups.csv"
