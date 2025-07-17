if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All"
}

$csvPath = "M365_Users_Groups.csv"
$userData = Import-Csv -Path $csvPath -Delimiter ";"

# List of group IDs to exclude
$excludedGroupIds = @(
    "7d056282-a2d1-4f69-8847-875c3c475cd3",  # all user stp grup
    "4e6601a0-9fed-48f2-9f4b-99adb2202b98",  # GL F3 Step up
    "21e9a3ec-d70c-4952-beaa-1c0eb5b4ba55"   # GL STP E3
)

foreach ($user in $userData) {
    $userId = $user.ObjectId
    $groupIds = $user.GroupIds -split ", " 

    foreach ($groupId in $groupIds) {
        if ($excludedGroupIds -contains $groupId) {
            Write-Host "⚠️ Skipping group $groupId for user $userId (excluded)"
            continue
        }

        try {
            # Correct Graph endpoint pattern for adding a member
            New-MgGroupMemberByRef -GroupId $groupId -BodyParameter @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
            }

            Write-Host "✅ User $userId assigned to group $groupId"
        } catch {
            Write-Host "❌ Failed to add $userId to group $groupId - $_"
        }
    }
}

Write-Host "✅ Assignment process completed."
