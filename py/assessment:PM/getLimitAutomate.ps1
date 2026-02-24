# ============================================================
# SCRIPT: CHECK SHAREPOINT UNIQUE PERMISSIONS LIMIT & USAGE
# Purpose: Mengetahui berapa current usage vs limit
# ============================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "SharePoint Limit & Usage Checker" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# STEP 1: INSTALL PnP POWERSHELL (Jika belum ada)
# ============================================================

Write-Host "Checking PnP PowerShell module..." -ForegroundColor Yellow

if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    Write-Host "Installing PnP.PowerShell module..." -ForegroundColor Yellow
    Install-Module -Name PnP.PowerShell -Force -AllowClobber -Scope CurrentUser
    Write-Host "✅ PnP.PowerShell installed successfully!" -ForegroundColor Green
} else {
    Write-Host "✅ PnP.PowerShell already installed" -ForegroundColor Green
}

Write-Host ""

# ============================================================
# STEP 2: CONNECT TO SHAREPOINT
# ============================================================

# GANTI INI DENGAN SITE URL ANDA
$siteUrl = "https://smbc.sharepoint.com/sites/Treasury"
$libraryName = "Documents"  # Atau "Shared Documents"

Write-Host "Connecting to SharePoint..." -ForegroundColor Yellow
Write-Host "Site: $siteUrl" -ForegroundColor White

try {
    Connect-PnPOnline -Url $siteUrl -Interactive
    Write-Host "✅ Connected successfully!" -ForegroundColor Green
} catch {
    Write-Host "❌ Connection failed: $_" -ForegroundColor Red
    exit
}

Write-Host ""

# ============================================================
# STEP 3: GET LIBRARY INFO
# ============================================================

Write-Host "Getting library information..." -ForegroundColor Yellow

try {
    $list = Get-PnPList -Identity $libraryName -Includes ItemCount
    Write-Host "✅ Library found: $libraryName" -ForegroundColor Green
    Write-Host "   Total Items: $($list.ItemCount)" -ForegroundColor White
} catch {
    Write-Host "❌ Library not found: $_" -ForegroundColor Red
    exit
}

Write-Host ""

# ============================================================
# STEP 4: COUNT UNIQUE PERMISSIONS
# ============================================================

Write-Host "Scanning for unique permissions..." -ForegroundColor Yellow
Write-Host "(This may take a few minutes for large libraries)" -ForegroundColor Gray

$uniquePermCount = 0
$brokenInheritanceCount = 0
$totalShareLinks = 0
$processedItems = 0

# Get all items in batches
$items = Get-PnPListItem -List $libraryName -PageSize 2000 -Fields "FileRef","HasUniqueRoleAssignments"

$totalItems = $items.Count
Write-Host "Total items to scan: $totalItems" -ForegroundColor White
Write-Host ""

foreach($item in $items) {
    $processedItems++
    
    # Progress indicator
    if ($processedItems % 100 -eq 0) {
        $percentComplete = [math]::Round(($processedItems / $totalItems) * 100, 1)
        Write-Host "Progress: $processedItems / $totalItems ($percentComplete%)" -ForegroundColor Gray
    }
    
    # Check if item has unique permissions (broken inheritance)
    if($item.FieldValues.HasUniqueRoleAssignments -eq $true) {
        $brokenInheritanceCount++
        
        # Get role assignments to count unique permissions
        try {
            $roleAssignments = Get-PnPProperty -ClientObject $item -Property "RoleAssignments"
            $uniquePermCount += $roleAssignments.Count
        } catch {
            # Some items might not be accessible
        }
        
        # Try to get sharing links
        try {
            $fileUrl = $item.FieldValues.FileRef
            $links = Get-PnPFileSharingLink -FileUrl $fileUrl -ErrorAction SilentlyContinue
            if($links) {
                $totalShareLinks += $links.Count
            }
        } catch {
            # Skip if cannot get sharing links
        }
    }
}

Write-Host ""
Write-Host "✅ Scan completed!" -ForegroundColor Green
Write-Host ""

# ============================================================
# STEP 5: CALCULATE & DISPLAY RESULTS
# ============================================================

# SharePoint Limits (as of 2025)
$LIMIT_UNIQUE_PERMISSIONS = 50000
$LIMIT_ITEMS_WITH_UNIQUE_PERMS = 5000

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "           RESULTS & ANALYSIS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Library Stats
Write-Host "📁 LIBRARY INFORMATION:" -ForegroundColor Yellow
Write-Host "   Library Name: $libraryName" -ForegroundColor White
Write-Host "   Total Items: $totalItems" -ForegroundColor White
Write-Host ""

# Unique Permissions Stats
Write-Host "🔐 UNIQUE PERMISSIONS:" -ForegroundColor Yellow
Write-Host "   Items with Broken Inheritance: $brokenInheritanceCount" -ForegroundColor White
Write-Host "   Total Unique Permissions: $uniquePermCount" -ForegroundColor White
Write-Host "   Total Sharing Links: $totalShareLinks" -ForegroundColor White
Write-Host ""

# Limits
Write-Host "📏 LIMITS:" -ForegroundColor Yellow
Write-Host "   Unique Permissions Limit: $LIMIT_UNIQUE_PERMISSIONS" -ForegroundColor White
Write-Host "   Items with Unique Perms Limit: $LIMIT_ITEMS_WITH_UNIQUE_PERMS" -ForegroundColor White
Write-Host ""

# Calculate percentages
$percentUsed = [math]::Round(($uniquePermCount / $LIMIT_UNIQUE_PERMISSIONS) * 100, 2)
$percentItemsUsed = [math]::Round(($brokenInheritanceCount / $LIMIT_ITEMS_WITH_UNIQUE_PERMS) * 100, 2)

# Usage Status
Write-Host "📊 CURRENT USAGE:" -ForegroundColor Yellow

# Unique Permissions Usage
Write-Host "   Unique Permissions: $uniquePermCount / $LIMIT_UNIQUE_PERMISSIONS ($percentUsed%)" -ForegroundColor White

if($percentUsed -ge 90) {
    Write-Host "   Status: 🔴 CRITICAL - Immediate action required!" -ForegroundColor Red
    Write-Host "   You are at $percentUsed% capacity" -ForegroundColor Red
} elseif($percentUsed -ge 70) {
    Write-Host "   Status: 🟠 WARNING - Start planning cleanup" -ForegroundColor Yellow
    Write-Host "   You are at $percentUsed% capacity" -ForegroundColor Yellow
} elseif($percentUsed -ge 50) {
    Write-Host "   Status: 🟡 CAUTION - Monitor closely" -ForegroundColor DarkYellow
    Write-Host "   You are at $percentUsed% capacity" -ForegroundColor DarkYellow
} else {
    Write-Host "   Status: 🟢 HEALTHY" -ForegroundColor Green
    Write-Host "   You are at $percentUsed% capacity" -ForegroundColor Green
}

Write-Host ""

# Items with Unique Perms Usage
Write-Host "   Items with Unique Perms: $brokenInheritanceCount / $LIMIT_ITEMS_WITH_UNIQUE_PERMS ($percentItemsUsed%)" -ForegroundColor White

if($percentItemsUsed -ge 90) {
    Write-Host "   Status: 🔴 CRITICAL" -ForegroundColor Red
} elseif($percentItemsUsed -ge 70) {
    Write-Host "   Status: 🟠 WARNING" -ForegroundColor Yellow
} elseif($percentItemsUsed -ge 50) {
    Write-Host "   Status: 🟡 CAUTION" -ForegroundColor DarkYellow
} else {
    Write-Host "   Status: 🟢 HEALTHY" -ForegroundColor Green
}

Write-Host ""

# Remaining capacity
$remainingPerms = $LIMIT_UNIQUE_PERMISSIONS - $uniquePermCount
$remainingItems = $LIMIT_ITEMS_WITH_UNIQUE_PERMS - $brokenInheritanceCount

Write-Host "💾 REMAINING CAPACITY:" -ForegroundColor Yellow
Write-Host "   Remaining Unique Permissions: $remainingPerms" -ForegroundColor White
Write-Host "   Remaining Items Slots: $remainingItems" -ForegroundColor White
Write-Host ""

# Estimate days until limit
if($totalShareLinks -gt 0 -and $processedItems -gt 0) {
    # Estimate based on last 30 days (you can adjust this)
    Write-Host "📈 PROJECTION:" -ForegroundColor Yellow
    
    # Assuming current rate continues
    $linksPerItem = $totalShareLinks / $brokenInheritanceCount
    $averageLinksPerDay = 100  # Adjust based on your actual daily volume
    
    $daysUntilLimit = [math]::Round($remainingPerms / $averageLinksPerDay, 0)
    
    Write-Host "   Estimated days until limit (at $averageLinksPerDay links/day): $daysUntilLimit days" -ForegroundColor White
    Write-Host "   Estimated date: $((Get-Date).AddDays($daysUntilLimit).ToString('yyyy-MM-dd'))" -ForegroundColor White
    Write-Host ""
}

# ============================================================
# STEP 6: RECOMMENDATIONS
# ============================================================

Write-Host "💡 RECOMMENDATIONS:" -ForegroundColor Yellow

if($percentUsed -ge 70) {
    Write-Host "   ⚠️  URGENT ACTIONS NEEDED:" -ForegroundColor Red
    Write-Host "   1. Implement 'Reuse Share Links' pattern immediately" -ForegroundColor White
    Write-Host "   2. Set expiration for all new links (30 days)" -ForegroundColor White
    Write-Host "   3. Run cleanup script for old/expired links" -ForegroundColor White
    Write-Host "   4. Consider using 'Grant Access' instead of links" -ForegroundColor White
} elseif($percentUsed -ge 50) {
    Write-Host "   ⚠️  RECOMMENDED ACTIONS:" -ForegroundColor Yellow
    Write-Host "   1. Implement 'Reuse Share Links' pattern" -ForegroundColor White
    Write-Host "   2. Set expiration for new links" -ForegroundColor White
    Write-Host "   3. Schedule regular cleanup (monthly)" -ForegroundColor White
} else {
    Write-Host "   ✅ You're in good shape!" -ForegroundColor Green
    Write-Host "   1. Continue monitoring monthly" -ForegroundColor White
    Write-Host "   2. Set expiration for new links as best practice" -ForegroundColor White
}

Write-Host ""

# ============================================================
# STEP 7: EXPORT REPORT
# ============================================================

$reportDate = Get-Date -Format "yyyy-MM-dd_HHmmss"
$reportFile = "SharePoint_Limit_Report_$reportDate.csv"

$report = [PSCustomObject]@{
    'Report Date' = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    'Site URL' = $siteUrl
    'Library Name' = $libraryName
    'Total Items' = $totalItems
    'Items with Unique Permissions' = $brokenInheritanceCount
    'Total Unique Permissions' = $uniquePermCount
    'Total Share Links' = $totalShareLinks
    'Unique Permissions Limit' = $LIMIT_UNIQUE_PERMISSIONS
    'Percentage Used' = $percentUsed
    'Remaining Capacity' = $remainingPerms
    'Status' = if($percentUsed -ge 90){"CRITICAL"}elseif($percentUsed -ge 70){"WARNING"}elseif($percentUsed -ge 50){"CAUTION"}else{"HEALTHY"}
}

$report | Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8

Write-Host "📄 Report exported to: $reportFile" -ForegroundColor Green
Write-Host ""

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         Script completed successfully!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Disconnect
Disconnect-PnPOnline
