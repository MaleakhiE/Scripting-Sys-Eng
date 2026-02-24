# ============================================
# GPO DETAIL EXTRACTION - Tambahan untuk Assessment AD v3
# ============================================
# Jalankan setelah script utama atau gabungkan ke script utama
# Script ini mengekstrak ISI/DETAIL dari setiap GPO

Import-Module GroupPolicy -ErrorAction SilentlyContinue

$OutputPath = "C:\ADAssessment"
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "=== GPO Detail Extraction ===" -ForegroundColor Cyan

# ============================================
# 1. GPO Policy Settings - Detail Isi GPO
# ============================================
Write-Host "[1/4] Mengambil GPO Policy Settings (Isi GPO)..." -ForegroundColor Yellow

$GPOs = @(Get-GPO -All)
$GPOPolicySettings = @()
$GPOSettingsCounter = 0

foreach ($gpo in $GPOs) {
    Write-Host "   Processing: $($gpo.DisplayName)..." -ForegroundColor Gray
    try {
        $gpoReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction Stop)
        
        # Computer Configuration Settings
        if ($gpoReport.GPO.Computer.ExtensionData) {
            foreach ($ext in $gpoReport.GPO.Computer.ExtensionData) {
                $extName = $ext.Name
                $extType = $ext.Extension.type -replace 'q\d+:', ''
                
                # Process each setting in extension
                foreach ($setting in $ext.Extension.ChildNodes) {
                    if ($setting.LocalName -ne '#text' -and $setting.LocalName -ne 'type') {
                        $GPOSettingsCounter++
                        $settingValue = $setting.InnerText
                        if ($settingValue.Length -gt 500) { $settingValue = $settingValue.Substring(0, 500) + "..." }
                        
                        $GPOPolicySettings += [PSCustomObject]@{
                            No = $GPOSettingsCounter
                            GPOName = $gpo.DisplayName
                            GPOStatus = $gpo.GpoStatus
                            ConfigurationType = "Computer"
                            ExtensionName = $extName
                            ExtensionType = $extType
                            SettingCategory = $setting.LocalName
                            SettingName = if ($setting.Name) { $setting.Name } else { $setting.LocalName }
                            SettingState = if ($setting.State) { $setting.State } else { "Configured" }
                            SettingValue = ($settingValue -replace '\s+', ' ').Trim()
                        }
                    }
                }
            }
        }
        
        # User Configuration Settings
        if ($gpoReport.GPO.User.ExtensionData) {
            foreach ($ext in $gpoReport.GPO.User.ExtensionData) {
                $extName = $ext.Name
                $extType = $ext.Extension.type -replace 'q\d+:', ''
                
                foreach ($setting in $ext.Extension.ChildNodes) {
                    if ($setting.LocalName -ne '#text' -and $setting.LocalName -ne 'type') {
                        $GPOSettingsCounter++
                        $settingValue = $setting.InnerText
                        if ($settingValue.Length -gt 500) { $settingValue = $settingValue.Substring(0, 500) + "..." }
                        
                        $GPOPolicySettings += [PSCustomObject]@{
                            No = $GPOSettingsCounter
                            GPOName = $gpo.DisplayName
                            GPOStatus = $gpo.GpoStatus
                            ConfigurationType = "User"
                            ExtensionName = $extName
                            ExtensionType = $extType
                            SettingCategory = $setting.LocalName
                            SettingName = if ($setting.Name) { $setting.Name } else { $setting.LocalName }
                            SettingState = if ($setting.State) { $setting.State } else { "Configured" }
                            SettingValue = ($settingValue -replace '\s+', ' ').Trim()
                        }
                    }
                }
            }
        }
    } catch {
        $GPOSettingsCounter++
        $GPOPolicySettings += [PSCustomObject]@{
            No = $GPOSettingsCounter
            GPOName = $gpo.DisplayName
            GPOStatus = $gpo.GpoStatus
            ConfigurationType = "Error"
            ExtensionName = "-"
            ExtensionType = "-"
            SettingCategory = "Error"
            SettingName = "Error"
            SettingState = "-"
            SettingValue = $_.Exception.Message
        }
    }
}

$GPOPolicySettings | Export-Csv "$OutputPath\GPO_01_All_Policy_Settings_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($GPOPolicySettings.Count) GPO Policy Settings" -ForegroundColor Green


# ============================================
# 2. Security Settings dari GPO
# ============================================
Write-Host "[2/4] Mengambil Security Settings dari GPO..." -ForegroundColor Yellow

$SecuritySettings = @()
$SecCounter = 0

foreach ($gpo in $GPOs) {
    try {
        $gpoReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction Stop)
        
        # Security Options
        $securityOptions = $gpoReport.GPO.Computer.ExtensionData | Where-Object { $_.Name -like "*Security*" }
        if ($securityOptions) {
            foreach ($secOpt in $securityOptions.Extension.ChildNodes) {
                if ($secOpt.LocalName -ne '#text' -and $secOpt.LocalName -ne 'type') {
                    $SecCounter++
                    $SecuritySettings += [PSCustomObject]@{
                        No = $SecCounter
                        GPOName = $gpo.DisplayName
                        SettingType = "Security Option"
                        SettingName = if ($secOpt.Name) { $secOpt.Name } elseif ($secOpt.SystemAccessPolicyName) { $secOpt.SystemAccessPolicyName } else { $secOpt.LocalName }
                        SettingValue = if ($secOpt.SettingNumber) { $secOpt.SettingNumber } elseif ($secOpt.SettingString) { $secOpt.SettingString } else { $secOpt.InnerText }
                        State = if ($secOpt.State) { $secOpt.State } else { "Configured" }
                    }
                }
            }
        }
        
        # Account Policies (Password, Lockout, Kerberos)
        $accountPolicies = $gpoReport.GPO.Computer.ExtensionData | Where-Object { $_.Name -like "*Account*" }
        if ($accountPolicies) {
            foreach ($accPol in $accountPolicies.Extension.ChildNodes) {
                if ($accPol.LocalName -ne '#text' -and $accPol.LocalName -ne 'type') {
                    $SecCounter++
                    $SecuritySettings += [PSCustomObject]@{
                        No = $SecCounter
                        GPOName = $gpo.DisplayName
                        SettingType = "Account Policy"
                        SettingName = $accPol.LocalName
                        SettingValue = $accPol.InnerText
                        State = "Configured"
                    }
                }
            }
        }
    } catch {}
}

if ($SecuritySettings.Count -gt 0) {
    $SecuritySettings | Export-Csv "$OutputPath\GPO_02_Security_Settings_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($SecuritySettings.Count) Security Settings" -ForegroundColor Green
} else {
    Write-Host "   Tidak ada Security Settings yang dikonfigurasi" -ForegroundColor Yellow
}


# ============================================
# 3. Registry Settings dari GPO
# ============================================
Write-Host "[3/4] Mengambil Registry Settings dari GPO..." -ForegroundColor Yellow

$RegistrySettings = @()
$RegCounter = 0

foreach ($gpo in $GPOs) {
    try {
        $gpoReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction Stop)
        
        # Computer Registry
        $compRegistry = $gpoReport.GPO.Computer.ExtensionData | Where-Object { $_.Name -like "*Registry*" -or $_.Name -like "*Administrative*" }
        if ($compRegistry) {
            foreach ($reg in $compRegistry.Extension.ChildNodes) {
                if ($reg.LocalName -ne '#text' -and $reg.LocalName -ne 'type') {
                    $RegCounter++
                    $RegistrySettings += [PSCustomObject]@{
                        No = $RegCounter
                        GPOName = $gpo.DisplayName
                        ConfigType = "Computer"
                        PolicyName = if ($reg.Name) { $reg.Name } else { $reg.LocalName }
                        State = if ($reg.State) { $reg.State } else { "Configured" }
                        KeyPath = if ($reg.KeyPath) { $reg.KeyPath } else { "-" }
                        ValueName = if ($reg.ValueName) { $reg.ValueName } else { "-" }
                        Value = if ($reg.Value) { $reg.Value } elseif ($reg.Number) { $reg.Number } else { $reg.InnerText }
                        Category = if ($reg.Category) { $reg.Category } else { "-" }
                    }
                }
            }
        }
        
        # User Registry
        $userRegistry = $gpoReport.GPO.User.ExtensionData | Where-Object { $_.Name -like "*Registry*" -or $_.Name -like "*Administrative*" }
        if ($userRegistry) {
            foreach ($reg in $userRegistry.Extension.ChildNodes) {
                if ($reg.LocalName -ne '#text' -and $reg.LocalName -ne 'type') {
                    $RegCounter++
                    $RegistrySettings += [PSCustomObject]@{
                        No = $RegCounter
                        GPOName = $gpo.DisplayName
                        ConfigType = "User"
                        PolicyName = if ($reg.Name) { $reg.Name } else { $reg.LocalName }
                        State = if ($reg.State) { $reg.State } else { "Configured" }
                        KeyPath = if ($reg.KeyPath) { $reg.KeyPath } else { "-" }
                        ValueName = if ($reg.ValueName) { $reg.ValueName } else { "-" }
                        Value = if ($reg.Value) { $reg.Value } elseif ($reg.Number) { $reg.Number } else { $reg.InnerText }
                        Category = if ($reg.Category) { $reg.Category } else { "-" }
                    }
                }
            }
        }
    } catch {}
}

if ($RegistrySettings.Count -gt 0) {
    $RegistrySettings | Export-Csv "$OutputPath\GPO_03_Registry_Settings_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($RegistrySettings.Count) Registry/Administrative Settings" -ForegroundColor Green
} else {
    Write-Host "   Tidak ada Registry Settings yang dikonfigurasi" -ForegroundColor Yellow
}


# ============================================
# 4. Export Full GPO Report (HTML per GPO)
# ============================================
Write-Host "[4/4] Mengexport Full GPO Reports (HTML)..." -ForegroundColor Yellow

$GPOReportPath = "$OutputPath\GPO_Reports"
if (-not (Test-Path $GPOReportPath)) {
    New-Item -ItemType Directory -Path $GPOReportPath | Out-Null
}

foreach ($gpo in $GPOs) {
    try {
        $safeGPOName = $gpo.DisplayName -replace '[\\/:*?"<>|]', '_'
        $reportFile = "$GPOReportPath\$safeGPOName.html"
        Get-GPOReport -Guid $gpo.Id -ReportType Html -Path $reportFile
    } catch {
        Write-Host "   Warning: Tidak dapat export $($gpo.DisplayName)" -ForegroundColor Yellow
    }
}

Write-Host "   GPO HTML Reports disimpan di: $GPOReportPath" -ForegroundColor Green

# ============================================
# 5. GPO Summary per Category
# ============================================
Write-Host ""
Write-Host "=== GPO EXTRACTION SUMMARY ===" -ForegroundColor Cyan

$GPOSummary = @()
$SumCounter = 0
foreach ($gpo in $GPOs) {
    $SumCounter++
    $gpoSettings = $GPOPolicySettings | Where-Object { $_.GPOName -eq $gpo.DisplayName }
    $compSettings = ($gpoSettings | Where-Object { $_.ConfigurationType -eq "Computer" }).Count
    $userSettings = ($gpoSettings | Where-Object { $_.ConfigurationType -eq "User" }).Count
    
    $GPOSummary += [PSCustomObject]@{
        No = $SumCounter
        GPOName = $gpo.DisplayName
        Status = $gpo.GpoStatus
        TotalSettings = $gpoSettings.Count
        ComputerSettings = $compSettings
        UserSettings = $userSettings
        Created = $gpo.CreationTime
        Modified = $gpo.ModificationTime
        HasSecuritySettings = if ($SecuritySettings | Where-Object { $_.GPOName -eq $gpo.DisplayName }) { "Yes" } else { "No" }
        HasRegistrySettings = if ($RegistrySettings | Where-Object { $_.GPOName -eq $gpo.DisplayName }) { "Yes" } else { "No" }
    }
}

$GPOSummary | Export-Csv "$OutputPath\GPO_00_Summary_$Timestamp.csv" -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Total GPO                : $($GPOs.Count)" -ForegroundColor White
Write-Host "Total Policy Settings    : $($GPOPolicySettings.Count)" -ForegroundColor White
Write-Host "Total Security Settings  : $($SecuritySettings.Count)" -ForegroundColor White
Write-Host "Total Registry Settings  : $($RegistrySettings.Count)" -ForegroundColor White
Write-Host ""
Write-Host "Output Location: $OutputPath" -ForegroundColor Green
Write-Host "GPO HTML Reports: $GPOReportPath" -ForegroundColor Green
