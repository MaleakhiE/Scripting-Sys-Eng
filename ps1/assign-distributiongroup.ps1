# === Configuration ===
$UserToAdd = "m365.admin@ProtelindoGroup.onmicrosoft.com"

# === Connect to Exchange Online ===
try {
    Write-Host "🔗 Connecting to Exchange Online..." -ForegroundColor Cyan
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Host "✅ Connected to Exchange Online." -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to connect: $_" -ForegroundColor Red
    exit 1
}

# === Get All Mail-Enabled Security & Distribution Groups ===
$groups = Get-DistributionGroup -ResultSize Unlimited
Write-Host "📦 Found $($groups.Count) distribution groups..." -ForegroundColor Yellow

foreach ($group in $groups) {
    $groupName = $group.DisplayName
    $groupEmail = $group.PrimarySmtpAddress

    try {
        # Add the user as an additional owner (preserve existing owners)
        Set-DistributionGroup -Identity $group.Identity -ManagedBy @{Add=$UserToAdd} -BypassSecurityGroupManagerCheck:$true -ErrorAction Stop
        Write-Host "✅ Added owner to group: $groupName <$groupEmail>" -ForegroundColor Green
    } catch {
        if ($_ -like "*is already a manager*") {
            Write-Host "ℹ️ Already a manager of group: $groupName <$groupEmail>" -ForegroundColor Yellow
        } else {
            Write-Host "❌ Failed for group: $groupName <$groupEmail> — $_" -ForegroundColor Red
        }
    }
}

# Disconnect
Disconnect-ExchangeOnline -Confirm:$false
Write-Host "✅ Finished. Disconnected from Exchange Online." -ForegroundColor Green
