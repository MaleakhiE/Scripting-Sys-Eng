# ============================================
# Active Directory Assessment Script (Enhanced v2)
# ============================================
# Script ini memerlukan modul ActiveDirectory dan GroupPolicy
# Jalankan dengan hak Administrator

# Import module Active Directory
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
Import-Module GroupPolicy -ErrorAction SilentlyContinue

if (-not (Get-Module -Name ActiveDirectory)) {
    Write-Host "ERROR: Module ActiveDirectory tidak ditemukan!" -ForegroundColor Red
    Write-Host "Install dengan: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    exit
}

if (-not (Get-Module -Name GroupPolicy)) {
    Write-Host "WARNING: Module GroupPolicy tidak ditemukan!" -ForegroundColor Yellow
    Write-Host "Beberapa fitur GPO mungkin tidak tersedia" -ForegroundColor Yellow
}

# Set lokasi output
$OutputPath = "C:\Temp\ADAssessment_$Timestamp"
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "=== Active Directory Assessment (Enhanced v2) ===" -ForegroundColor Cyan
Write-Host "Timestamp: $Timestamp" -ForegroundColor Green
Write-Host ""

# ============================================
# 1. Informasi Jumlah Server Active Directory
# ============================================
Write-Host "[1/17] Mengambil informasi jumlah server Active Directory..." -ForegroundColor Yellow

$DomainControllers = @(Get-ADDomainController -Filter *)
$DCCounter = 0
$DCInfo = $DomainControllers | ForEach-Object {
    $DCCounter++
    [PSCustomObject]@{
        No = $DCCounter
        Name = $_.Name
        Domain = $_.Domain
        Site = $_.Site
        OperatingSystem = $_.OperatingSystem
        OperatingSystemVersion = $_.OperatingSystemVersion
        IPv4Address = $_.IPv4Address
        IsGlobalCatalog = $_.IsGlobalCatalog
        IsReadOnly = $_.IsReadOnly
        Roles = ($_.OperationMasterRoles -join ', ')
        Enabled = $_.Enabled
    }
}

$DCInfo | Export-Csv "$OutputPath\01_DomainControllers_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($DomainControllers.Count) Domain Controller" -ForegroundColor Green


# ============================================
# 2. Informasi Versi OS Active Directory
# ============================================
Write-Host "[2/13] Mengambil informasi versi OS Active Directory..." -ForegroundColor Yellow

$OSCounter = 0
$OSInfo = $DomainControllers | ForEach-Object {
    $OSCounter++
    $osVersion = $_.OperatingSystemVersion
    $osBuild = if ($osVersion -match '\((\d+)\)') { $matches[1] } else { "N/A" }
    
    # Determine OS End of Support Status
    $eolStatus = switch -Wildcard ($_.OperatingSystem) {
        "*2008*" { "End of Life - Upgrade Required" }
        "*2012*" { "Extended Support Ended - Upgrade Recommended" }
        "*2016*" { "Mainstream Support" }
        "*2019*" { "Mainstream Support" }
        "*2022*" { "Current" }
        default { "Unknown" }
    }
    
    [PSCustomObject]@{
        No = $OSCounter
        ServerName = $_.Name
        OperatingSystem = $_.OperatingSystem
        OperatingSystemVersion = $osVersion
        OSBuild = $osBuild
        SupportStatus = $eolStatus
        Recommendation = if ($eolStatus -like "*End*" -or $eolStatus -like "*Ended*") { "Plan upgrade to Windows Server 2019/2022" } else { "OK" }
    }
}

$OSInfo | Export-Csv "$OutputPath\02_OS_Versions_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Informasi OS berhasil dikumpulkan" -ForegroundColor Green

# ============================================
# 3. Informasi Forest dan Domain Functional Level
# ============================================
Write-Host "[3/13] Mengambil informasi Forest dan Domain Functional Level..." -ForegroundColor Yellow

$Forest = Get-ADForest
$Domain = Get-ADDomain

# Get Schema Version
$SchemaVersion = (Get-ADObject (Get-ADRootDSE).schemaNamingContext -Property objectVersion).objectVersion
$SchemaName = switch ($SchemaVersion) {
    87 { "Windows Server 2016/2019/2022" }
    88 { "Windows Server 2019" }
    89 { "Windows Server 2022" }
    69 { "Windows Server 2012 R2" }
    56 { "Windows Server 2012" }
    47 { "Windows Server 2008 R2" }
    default { "Unknown ($SchemaVersion)" }
}

$FunctionalLevelInfo = @()
$FunctionalLevelInfo += [PSCustomObject]@{
    No = 1
    Type = "Forest"
    Name = $Forest.Name
    FunctionalLevel = $Forest.ForestMode
    SchemaVersion = $SchemaVersion
    SchemaName = $SchemaName
    DomainCount = $Forest.Domains.Count
    SitesCount = $Forest.Sites.Count
    GlobalCatalogs = ($Forest.GlobalCatalogs -join ', ')
    RootDomain = $Forest.RootDomain
    FSMORoles = "Schema Master: $($Forest.SchemaMaster), Domain Naming: $($Forest.DomainNamingMaster)"
}

$FunctionalLevelInfo += [PSCustomObject]@{
    No = 2
    Type = "Domain"
    Name = $Domain.DNSRoot
    FunctionalLevel = $Domain.DomainMode
    SchemaVersion = "-"
    SchemaName = "-"
    DomainCount = "-"
    SitesCount = "-"
    GlobalCatalogs = "-"
    RootDomain = "-"
    FSMORoles = "PDC: $($Domain.PDCEmulator), RID: $($Domain.RIDMaster), Infra: $($Domain.InfrastructureMaster)"
}

$FunctionalLevelInfo | Export-Csv "$OutputPath\03_Functional_Levels_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Forest Level: $($Forest.ForestMode) | Domain Level: $($Domain.DomainMode)" -ForegroundColor Green


# ============================================
# 4. Informasi Site dan Services Active Directory
# ============================================
Write-Host "[4/13] Mengambil informasi Site dan Services..." -ForegroundColor Yellow

$Sites = @(Get-ADReplicationSite -Filter *)
$SiteCounter = 0
$SiteInfo = $Sites | ForEach-Object {
    $SiteCounter++
    $siteDN = $_.DistinguishedName
    $subnets = @(Get-ADReplicationSubnet -Filter * | Where-Object { $_.Site -eq $siteDN })
    $siteLinks = @(Get-ADReplicationSiteLink -Filter * | Where-Object { $_.SitesIncluded -contains $siteDN })
    $dcInSite = @($DomainControllers | Where-Object { $_.Site -eq $_.Name })
    
    [PSCustomObject]@{
        No = $SiteCounter
        SiteName = $_.Name
        Description = $_.Description
        Location = $_.Location
        Subnets = ($subnets.Name -join '; ')
        SubnetCount = $subnets.Count
        SiteLinks = ($siteLinks.Name -join '; ')
        SiteLinkCount = $siteLinks.Count
        DCsInSite = ($DomainControllers | Where-Object { $_.Site -eq $_.Name }).Count
        Created = $_.Created
        Modified = $_.Modified
    }
}

$SiteInfo | Export-Csv "$OutputPath\04_Sites_Services_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Sites.Count) Site" -ForegroundColor Green

# Site Links Detail
$SiteLinks = @(Get-ADReplicationSiteLink -Filter * -Properties *)
$SiteLinkCounter = 0
$SiteLinkInfo = $SiteLinks | ForEach-Object {
    $SiteLinkCounter++
    [PSCustomObject]@{
        No = $SiteLinkCounter
        Name = $_.Name
        Cost = $_.Cost
        ReplicationFrequencyInMinutes = $_.ReplicationFrequencyInMinutes
        SitesIncluded = ($_.SitesIncluded | ForEach-Object { ($_ -split ',')[0] -replace 'CN=' }) -join '; '
        Options = $_.Options
        Schedule = if ($_.Schedule) { "Custom" } else { "24x7" }
        InterSiteTransportProtocol = $_.InterSiteTransportProtocol
    }
}

$SiteLinkInfo | Export-Csv "$OutputPath\04b_SiteLinks_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($SiteLinks.Count) Site Link" -ForegroundColor Green


# ============================================
# 5. Informasi Update/Patch yang terinstall
# ============================================
Write-Host "[5/13] Mengambil informasi Update/Patch (ini mungkin memakan waktu)..." -ForegroundColor Yellow

$PatchInfo = @()
$PatchCounter = 0
foreach ($DC in $DomainControllers) {
    try {
        $Patches = Get-HotFix -ComputerName $DC.HostName -ErrorAction Stop | 
                   Sort-Object InstalledOn -Descending |
                   Select-Object -First 10
        
        foreach ($Patch in $Patches) {
            $PatchCounter++
            $PatchInfo += [PSCustomObject]@{
                No = $PatchCounter
                ServerName = $DC.Name
                HotFixID = $Patch.HotFixID
                Description = $Patch.Description
                InstalledOn = $Patch.InstalledOn
                InstalledBy = $Patch.InstalledBy
                Source = $Patch.Source
            }
        }
    } catch {
        $PatchCounter++
        $PatchInfo += [PSCustomObject]@{
            No = $PatchCounter
            ServerName = $DC.Name
            HotFixID = "Error"
            Description = $_.Exception.Message
            InstalledOn = "-"
            InstalledBy = "-"
            Source = "-"
        }
    }
}

$PatchInfo | Export-Csv "$OutputPath\05_Patches_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Informasi patch berhasil dikumpulkan" -ForegroundColor Green


# ============================================
# 6. Informasi Utilitas (Disk, Memory, CPU)
# ============================================
Write-Host "[6/13] Mengambil informasi Utilitas (Disk, Memory, CPU)..." -ForegroundColor Yellow

$UtilitasInfo = @()
$UtilCounter = 0
foreach ($DC in $DomainControllers) {
    try {
        # Disk Info
        $Disks = Get-WmiObject Win32_LogicalDisk -ComputerName $DC.HostName -Filter "DriveType=3" -ErrorAction Stop
        
        # Memory Info
        $Memory = Get-WmiObject Win32_ComputerSystem -ComputerName $DC.HostName -ErrorAction Stop
        $MemoryGB = [math]::Round($Memory.TotalPhysicalMemory / 1GB, 2)
        
        # Available Memory
        $AvailMem = Get-WmiObject Win32_OperatingSystem -ComputerName $DC.HostName -ErrorAction Stop
        $AvailMemGB = [math]::Round($AvailMem.FreePhysicalMemory / 1MB, 2)
        $MemUsedPercent = [math]::Round((($MemoryGB - $AvailMemGB) / $MemoryGB) * 100, 2)
        
        # CPU Info
        $CPU = Get-WmiObject Win32_Processor -ComputerName $DC.HostName -ErrorAction Stop | Select-Object -First 1
        
        # NTDS Database Size
        $NTDSPath = "\\$($DC.HostName)\c$\Windows\NTDS"
        $NTDSSize = "N/A"
        if (Test-Path $NTDSPath) {
            $ntdsFile = Get-Item "$NTDSPath\ntds.dit" -ErrorAction SilentlyContinue
            if ($ntdsFile) {
                $NTDSSize = [math]::Round($ntdsFile.Length / 1MB, 2)
            }
        }
        
        foreach ($Disk in $Disks) {
            $UtilCounter++
            $percentFree = [math]::Round(($Disk.FreeSpace / $Disk.Size) * 100, 2)
            $diskStatus = if ($percentFree -lt 10) { "CRITICAL" } elseif ($percentFree -lt 20) { "WARNING" } else { "OK" }
            
            $UtilitasInfo += [PSCustomObject]@{
                No = $UtilCounter
                ServerName = $DC.Name
                DriveLetter = $Disk.DeviceID
                TotalSizeGB = [math]::Round($Disk.Size / 1GB, 2)
                FreeSpaceGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
                UsedSpaceGB = [math]::Round(($Disk.Size - $Disk.FreeSpace) / 1GB, 2)
                PercentFree = $percentFree
                DiskStatus = $diskStatus
                TotalMemoryGB = $MemoryGB
                AvailableMemoryGB = $AvailMemGB
                MemoryUsedPercent = $MemUsedPercent
                CPUName = $CPU.Name
                CPUCores = $CPU.NumberOfCores
                CPULogicalProcessors = $CPU.NumberOfLogicalProcessors
                NTDSSizeMB = $NTDSSize
            }
        }
    } catch {
        $UtilCounter++
        $UtilitasInfo += [PSCustomObject]@{
            No = $UtilCounter
            ServerName = $DC.Name
            DriveLetter = "Error"
            TotalSizeGB = "-"
            FreeSpaceGB = "-"
            UsedSpaceGB = "-"
            PercentFree = "-"
            DiskStatus = "ERROR"
            TotalMemoryGB = "-"
            AvailableMemoryGB = "-"
            MemoryUsedPercent = "-"
            CPUName = $_.Exception.Message
            CPUCores = "-"
            CPULogicalProcessors = "-"
            NTDSSizeMB = "-"
        }
    }
}

$UtilitasInfo | Export-Csv "$OutputPath\06_Utilitas_Resources_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Informasi utilitas berhasil dikumpulkan" -ForegroundColor Green


# ============================================
# 7. Informasi DNS di Domain Controller
# ============================================
Write-Host "[7/13] Mengambil informasi DNS..." -ForegroundColor Yellow

$DNSInfo = @()
$DNSCounter = 0
foreach ($DC in $DomainControllers) {
    try {
        $DNSZones = Get-DnsServerZone -ComputerName $DC.HostName -ErrorAction Stop
        
        foreach ($Zone in $DNSZones) {
            $DNSCounter++
            
            # Get zone aging settings
            $aging = "N/A"
            try {
                $zoneAging = Get-DnsServerZoneAging -Name $Zone.ZoneName -ComputerName $DC.HostName -ErrorAction SilentlyContinue
                if ($zoneAging) {
                    $aging = if ($zoneAging.AgingEnabled) { "Enabled (Refresh: $($zoneAging.RefreshInterval), NoRefresh: $($zoneAging.NoRefreshInterval))" } else { "Disabled" }
                }
            } catch {}
            
            $DNSInfo += [PSCustomObject]@{
                No = $DNSCounter
                ServerName = $DC.Name
                ZoneName = $Zone.ZoneName
                ZoneType = $Zone.ZoneType
                ReplicationScope = $Zone.ReplicationScope
                IsDsIntegrated = $Zone.IsDsIntegrated
                IsReverseLookupZone = $Zone.IsReverseLookupZone
                DynamicUpdate = $Zone.DynamicUpdate
                AgingSettings = $aging
                RecordCount = (Get-DnsServerResourceRecord -ZoneName $Zone.ZoneName -ComputerName $DC.HostName -ErrorAction SilentlyContinue).Count
            }
        }
    } catch {
        $DNSCounter++
        $DNSInfo += [PSCustomObject]@{
            No = $DNSCounter
            ServerName = $DC.Name
            ZoneName = "Error"
            ZoneType = "-"
            ReplicationScope = "-"
            IsDsIntegrated = "-"
            IsReverseLookupZone = "-"
            DynamicUpdate = "-"
            AgingSettings = "-"
            RecordCount = $_.Exception.Message
        }
    }
}

$DNSInfo | Export-Csv "$OutputPath\07_DNS_Information_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($DNSInfo.Count) DNS Zone entries" -ForegroundColor Green


# ============================================
# 8. Data User, Computer, Server yang Join ke Domain
# ============================================
Write-Host "[8/13] Mengambil data User, Computer, Server..." -ForegroundColor Yellow

# Users dengan informasi lebih lengkap
$Users = @(Get-ADUser -Filter * -Properties Enabled, Created, LastLogonDate, PasswordLastSet, PasswordNeverExpires, PasswordExpired, LockedOut, AccountExpirationDate, Description, Department, Title, Manager, MemberOf)
$UserCounter = 0
$UserInfo = $Users | ForEach-Object {
    $UserCounter++
    $daysSinceLastLogon = if ($_.LastLogonDate) { (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days } else { "Never" }
    $daysSincePasswordSet = if ($_.PasswordLastSet) { (New-TimeSpan -Start $_.PasswordLastSet -End (Get-Date)).Days } else { "Never" }
    $groupCount = ($_.MemberOf).Count
    
    # Status Assessment
    $status = "Active"
    if (-not $_.Enabled) { $status = "Disabled" }
    elseif ($_.LockedOut) { $status = "Locked" }
    elseif ($daysSinceLastLogon -ne "Never" -and $daysSinceLastLogon -gt 90) { $status = "Inactive (90+ days)" }
    
    [PSCustomObject]@{
        No = $UserCounter
        Name = $_.Name
        SamAccountName = $_.SamAccountName
        Enabled = $_.Enabled
        Status = $status
        Created = $_.Created
        LastLogonDate = $_.LastLogonDate
        DaysSinceLastLogon = $daysSinceLastLogon
        PasswordLastSet = $_.PasswordLastSet
        DaysSincePasswordSet = $daysSincePasswordSet
        PasswordNeverExpires = $_.PasswordNeverExpires
        PasswordExpired = $_.PasswordExpired
        LockedOut = $_.LockedOut
        AccountExpires = $_.AccountExpirationDate
        GroupMemberships = $groupCount
        Department = $_.Department
        Title = $_.Title
        DistinguishedName = $_.DistinguishedName
    }
}

$UserInfo | Export-Csv "$OutputPath\08a_Domain_Users_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Users.Count) User" -ForegroundColor Green

# User Statistics Summary
$UserStats = [PSCustomObject]@{
    TotalUsers = $Users.Count
    EnabledUsers = ($Users | Where-Object { $_.Enabled }).Count
    DisabledUsers = ($Users | Where-Object { -not $_.Enabled }).Count
    LockedOutUsers = ($Users | Where-Object { $_.LockedOut }).Count
    PasswordNeverExpires = ($Users | Where-Object { $_.PasswordNeverExpires }).Count
    InactiveUsers90Days = ($Users | Where-Object { $_.LastLogonDate -and (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days -gt 90 }).Count
    NeverLoggedIn = ($Users | Where-Object { -not $_.LastLogonDate }).Count
}
$UserStats | Export-Csv "$OutputPath\08a_User_Statistics_$Timestamp.csv" -NoTypeInformation -Encoding UTF8


# Computers dengan informasi lebih lengkap
$Computers = @(Get-ADComputer -Filter * -Properties OperatingSystem, OperatingSystemVersion, Created, LastLogonDate, Description, ManagedBy, IPv4Address)
$CompCounter = 0
$ComputerInfo = $Computers | ForEach-Object {
    $CompCounter++
    $daysSinceLastLogon = if ($_.LastLogonDate) { (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days } else { "Never" }
    
    # Determine if stale
    $staleStatus = "Active"
    if ($daysSinceLastLogon -eq "Never") { $staleStatus = "Never Connected" }
    elseif ($daysSinceLastLogon -gt 90) { $staleStatus = "Stale (90+ days)" }
    elseif ($daysSinceLastLogon -gt 30) { $staleStatus = "Warning (30+ days)" }
    
    [PSCustomObject]@{
        No = $CompCounter
        Name = $_.Name
        DNSHostName = $_.DNSHostName
        IPv4Address = $_.IPv4Address
        OperatingSystem = $_.OperatingSystem
        OperatingSystemVersion = $_.OperatingSystemVersion
        Enabled = $_.Enabled
        Created = $_.Created
        LastLogonDate = $_.LastLogonDate
        DaysSinceLastLogon = $daysSinceLastLogon
        StaleStatus = $staleStatus
        Description = $_.Description
        DistinguishedName = $_.DistinguishedName
    }
}

$ComputerInfo | Export-Csv "$OutputPath\08b_Domain_Computers_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Computers.Count) Computer" -ForegroundColor Green

# Servers (Windows Server OS)
$Servers = @($Computers | Where-Object {$_.OperatingSystem -like "*Server*"})
$SrvCounter = 0
$ServerInfo = $Servers | ForEach-Object {
    $SrvCounter++
    $daysSinceLastLogon = if ($_.LastLogonDate) { (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days } else { "Never" }
    
    [PSCustomObject]@{
        No = $SrvCounter
        Name = $_.Name
        DNSHostName = $_.DNSHostName
        IPv4Address = $_.IPv4Address
        OperatingSystem = $_.OperatingSystem
        OperatingSystemVersion = $_.OperatingSystemVersion
        Enabled = $_.Enabled
        Created = $_.Created
        LastLogonDate = $_.LastLogonDate
        DaysSinceLastLogon = $daysSinceLastLogon
        Description = $_.Description
        DistinguishedName = $_.DistinguishedName
    }
}

$ServerInfo | Export-Csv "$OutputPath\08c_Domain_Servers_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Servers.Count) Server" -ForegroundColor Green

# Computer Statistics
$CompStats = [PSCustomObject]@{
    TotalComputers = $Computers.Count
    TotalServers = $Servers.Count
    TotalWorkstations = $Computers.Count - $Servers.Count
    EnabledComputers = ($Computers | Where-Object { $_.Enabled }).Count
    DisabledComputers = ($Computers | Where-Object { -not $_.Enabled }).Count
    StaleComputers90Days = ($Computers | Where-Object { $_.LastLogonDate -and (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days -gt 90 }).Count
    NeverConnected = ($Computers | Where-Object { -not $_.LastLogonDate }).Count
}
$CompStats | Export-Csv "$OutputPath\08b_Computer_Statistics_$Timestamp.csv" -NoTypeInformation -Encoding UTF8


# ============================================
# 9. Status dan Konfigurasi GPO serta Struktur OU dengan GPO Links
# ============================================
Write-Host "[9/13] Mengambil informasi GPO dan OU dengan GPO Links..." -ForegroundColor Yellow

# GPO Info dengan detail lebih lengkap
$GPOs = @(Get-GPO -All)
$GPOCounter = 0
$GPOInfo = $GPOs | ForEach-Object {
    $GPOCounter++
    $gpoReport = [xml](Get-GPOReport -Guid $_.Id -ReportType Xml)
    $links = $gpoReport.GPO.LinksTo
    $linkPaths = if ($links) { ($links | ForEach-Object { $_.SOMPath }) -join '; ' } else { "Not Linked" }
    
    [PSCustomObject]@{
        No = $GPOCounter
        DisplayName = $_.DisplayName
        GpoStatus = $_.GpoStatus
        CreationTime = $_.CreationTime
        ModificationTime = $_.ModificationTime
        LinksCount = if ($links) { $links.Count } else { 0 }
        LinkedTo = $linkPaths
        ComputerEnabled = $gpoReport.GPO.Computer.Enabled
        UserEnabled = $gpoReport.GPO.User.Enabled
        WMIFilter = $_.WmiFilter.Name
        Owner = $_.Owner
        Id = $_.Id
    }
}

$GPOInfo | Export-Csv "$OutputPath\09a_GPO_Information_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($GPOs.Count) GPO" -ForegroundColor Green


# OU Structure dengan GPO yang ter-link
$OUs = @(Get-ADOrganizationalUnit -Filter * -Properties Created, Modified, Description, ManagedBy, gPLink, gPOptions)
$OUCounter = 0
$OUInfo = $OUs | ForEach-Object {
    $OUCounter++
    $ouDN = $_.DistinguishedName
    
    # Parse GPO Links dari gPLink attribute
    $linkedGPOs = @()
    if ($_.gPLink) {
        $gpLinks = $_.gPLink -split '\]\[' | ForEach-Object { $_ -replace '^\[|\]$' }
        foreach ($link in $gpLinks) {
            if ($link -match 'LDAP://cn=\{([^}]+)\}') {
                $gpoGuid = $matches[1]
                $gpo = $GPOs | Where-Object { $_.Id -eq $gpoGuid }
                if ($gpo) {
                    $enforced = if ($link -match ';(\d+)$' -and $matches[1] -eq '2') { "(Enforced)" } else { "" }
                    $linkedGPOs += "$($gpo.DisplayName) $enforced".Trim()
                }
            }
        }
    }
    
    # Get inheritance status
    $inheritanceBlocked = if ($_.gPOptions -eq 1) { "Yes" } else { "No" }
    
    # Count objects in OU
    $userCount = (Get-ADUser -Filter * -SearchBase $ouDN -SearchScope OneLevel -ErrorAction SilentlyContinue).Count
    $compCount = (Get-ADComputer -Filter * -SearchBase $ouDN -SearchScope OneLevel -ErrorAction SilentlyContinue).Count
    
    [PSCustomObject]@{
        No = $OUCounter
        Name = $_.Name
        DistinguishedName = $ouDN
        Description = $_.Description
        Created = $_.Created
        Modified = $_.Modified
        Level = ($ouDN -split ',OU=').Count - 1
        LinkedGPOs = if ($linkedGPOs.Count -gt 0) { $linkedGPOs -join '; ' } else { "None" }
        LinkedGPOCount = $linkedGPOs.Count
        InheritanceBlocked = $inheritanceBlocked
        UsersInOU = $userCount
        ComputersInOU = $compCount
        ManagedBy = $_.ManagedBy
    }
}

$OUInfo | Export-Csv "$OutputPath\09b_OU_Structure_GPO_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($OUs.Count) Organizational Unit" -ForegroundColor Green


# ============================================
# 10. Cek Status Replikasi Active Directory (IMPROVED)
# ============================================
Write-Host "[10/13] Mengecek status replikasi (detail)..." -ForegroundColor Yellow

$ReplInfo = @()
$ReplCounter = 0
foreach ($DC in $DomainControllers) {
    try {
        $ReplStatus = Get-ADReplicationPartnerMetadata -Target $DC.HostName -ErrorAction Stop
        
        foreach ($Repl in $ReplStatus) {
            $ReplCounter++
            $partnerName = ($Repl.Partner -split ',')[0] -replace 'CN='
            $partitionName = ($Repl.Partition -split ',')[0] -replace 'DC=|CN='
            
            # Calculate replication lag
            $replLag = if ($Repl.LastReplicationSuccess) { 
                (New-TimeSpan -Start $Repl.LastReplicationSuccess -End (Get-Date)).TotalMinutes 
            } else { "N/A" }
            
            # Determine health status
            $healthStatus = "Healthy"
            if ($Repl.ConsecutiveReplicationFailures -gt 0) { $healthStatus = "Warning" }
            if ($Repl.ConsecutiveReplicationFailures -gt 5) { $healthStatus = "Critical" }
            if ($Repl.LastReplicationResult -ne 0) { $healthStatus = "Error" }
            
            $ReplInfo += [PSCustomObject]@{
                No = $ReplCounter
                SourceDC = $DC.Name
                PartnerDC = $partnerName
                Partition = $partitionName
                LastReplicationSuccess = $Repl.LastReplicationSuccess
                LastReplicationAttempt = $Repl.LastReplicationAttempt
                ReplicationLagMinutes = if ($replLag -ne "N/A") { [math]::Round($replLag, 2) } else { "N/A" }
                ConsecutiveFailures = $Repl.ConsecutiveReplicationFailures
                LastReplicationResult = $Repl.LastReplicationResult
                HealthStatus = $healthStatus
                IntersiteTransport = $Repl.IntersiteTransportType
            }
        }
    } catch {
        $ReplCounter++
        $ReplInfo += [PSCustomObject]@{
            No = $ReplCounter
            SourceDC = $DC.Name
            PartnerDC = "Error"
            Partition = "-"
            LastReplicationSuccess = "-"
            LastReplicationAttempt = "-"
            ReplicationLagMinutes = "-"
            ConsecutiveFailures = "-"
            LastReplicationResult = $_.Exception.Message
            HealthStatus = "Error"
            IntersiteTransport = "-"
        }
    }
}

$ReplInfo | Export-Csv "$OutputPath\10a_Replication_Status_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Status replikasi berhasil dikumpulkan" -ForegroundColor Green


# Replication Failures Detail menggunakan repadmin
Write-Host "   Mengambil detail replication failures..." -ForegroundColor Gray
$ReplFailures = @()
$ReplFailCounter = 0
try {
    $repadminOutput = repadmin /showrepl * /csv 2>$null | ConvertFrom-Csv
    foreach ($item in $repadminOutput) {
        $ReplFailCounter++
        $ReplFailures += [PSCustomObject]@{
            No = $ReplFailCounter
            DestinationDC = $item.'Destination DC'
            SourceDC = $item.'Source DC'
            NamingContext = $item.'Naming Context'
            SourceDCSite = $item.'Source DC Site'
            DestinationDCSite = $item.'Destination DC Site'
            LastSuccess = $item.'Last Success Time'
            LastFailure = $item.'Last Failure Time'
            NumberOfFailures = $item.'Number of Failures'
            LastFailureStatus = $item.'Last Failure Status'
        }
    }
    $ReplFailures | Export-Csv "$OutputPath\10b_Replication_Repadmin_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
} catch {
    Write-Host "   Warning: Tidak dapat menjalankan repadmin" -ForegroundColor Yellow
}

# Replication Summary
$ReplSummary = @()
foreach ($DC in $DomainControllers) {
    try {
        $failures = Get-ADReplicationFailure -Target $DC.HostName -ErrorAction Stop
        foreach ($fail in $failures) {
            $ReplSummary += [PSCustomObject]@{
                Server = $DC.Name
                Partner = $fail.Partner
                FailureCount = $fail.FailureCount
                FailureType = $fail.FailureType
                FirstFailureTime = $fail.FirstFailureTime
                LastError = $fail.LastError
            }
        }
    } catch {}
}
if ($ReplSummary.Count -gt 0) {
    $ReplSummary | Export-Csv "$OutputPath\10c_Replication_Failures_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($ReplSummary.Count) replication failure entries" -ForegroundColor Yellow
}


# ============================================
# 11. Script untuk Healthcheck Semua Domain Controller
# ============================================
Write-Host "[11/13] Menjalankan healthcheck Domain Controller..." -ForegroundColor Yellow

$HealthInfo = @()
$HealthCounter = 0
foreach ($DC in $DomainControllers) {
    $HealthCounter++
    Write-Host "   Checking $($DC.Name)..." -ForegroundColor Gray
    
    # DCDIAG Tests
    $dcdiagResults = @{}
    try {
        $dcdiagOutput = dcdiag /s:$($DC.HostName) /test:services /test:replications /test:advertising /test:fsmocheck /test:ridmanager /test:machineaccount 2>&1
        $dcdiagResults['Services'] = if ($dcdiagOutput -match "passed test Services") { "PASS" } else { "FAIL" }
        $dcdiagResults['Replications'] = if ($dcdiagOutput -match "passed test Replications") { "PASS" } else { "FAIL" }
        $dcdiagResults['Advertising'] = if ($dcdiagOutput -match "passed test Advertising") { "PASS" } else { "FAIL" }
        $dcdiagResults['FsmoCheck'] = if ($dcdiagOutput -match "passed test FsmoCheck") { "PASS" } else { "FAIL" }
        $dcdiagResults['RidManager'] = if ($dcdiagOutput -match "passed test RidManager") { "PASS" } else { "FAIL" }
        $dcdiagResults['MachineAccount'] = if ($dcdiagOutput -match "passed test MachineAccount") { "PASS" } else { "FAIL" }
    } catch {
        $dcdiagResults['Services'] = "ERROR"
        $dcdiagResults['Replications'] = "ERROR"
        $dcdiagResults['Advertising'] = "ERROR"
        $dcdiagResults['FsmoCheck'] = "ERROR"
        $dcdiagResults['RidManager'] = "ERROR"
        $dcdiagResults['MachineAccount'] = "ERROR"
    }
    
    # Service Status
    $Services = @('NTDS', 'DNS', 'Netlogon', 'W32Time', 'DFSR', 'KDC')
    $ServiceStatus = @{}
    foreach ($Service in $Services) {
        try {
            $Svc = Get-Service -Name $Service -ComputerName $DC.HostName -ErrorAction Stop
            $ServiceStatus[$Service] = $Svc.Status.ToString()
        } catch {
            $ServiceStatus[$Service] = "N/A"
        }
    }
    
    # Event Log Errors
    $ErrorCount = 0
    $WarningCount = 0
    try {
        $ErrorCount = (Get-EventLog -LogName System -ComputerName $DC.HostName -EntryType Error -After (Get-Date).AddDays(-1) -ErrorAction Stop).Count
        $WarningCount = (Get-EventLog -LogName System -ComputerName $DC.HostName -EntryType Warning -After (Get-Date).AddDays(-1) -ErrorAction Stop).Count
    } catch {}
    
    # Uptime
    $uptime = "N/A"
    try {
        $os = Get-WmiObject Win32_OperatingSystem -ComputerName $DC.HostName -ErrorAction Stop
        $lastBoot = $os.ConvertToDateTime($os.LastBootUpTime)
        $uptimeSpan = New-TimeSpan -Start $lastBoot -End (Get-Date)
        $uptime = "$($uptimeSpan.Days)d $($uptimeSpan.Hours)h $($uptimeSpan.Minutes)m"
    } catch {}

    
    # Overall Health Score
    $passCount = ($dcdiagResults.Values | Where-Object { $_ -eq "PASS" }).Count
    $totalTests = $dcdiagResults.Count
    $healthScore = [math]::Round(($passCount / $totalTests) * 100, 0)
    $overallStatus = if ($healthScore -eq 100) { "Healthy" } elseif ($healthScore -ge 80) { "Warning" } else { "Critical" }
    
    $HealthInfo += [PSCustomObject]@{
        No = $HealthCounter
        ServerName = $DC.Name
        Site = $DC.Site
        OverallStatus = $overallStatus
        HealthScore = "$healthScore%"
        Uptime = $uptime
        DCDiag_Services = $dcdiagResults['Services']
        DCDiag_Replications = $dcdiagResults['Replications']
        DCDiag_Advertising = $dcdiagResults['Advertising']
        DCDiag_FsmoCheck = $dcdiagResults['FsmoCheck']
        DCDiag_RidManager = $dcdiagResults['RidManager']
        DCDiag_MachineAccount = $dcdiagResults['MachineAccount']
        Svc_NTDS = $ServiceStatus['NTDS']
        Svc_DNS = $ServiceStatus['DNS']
        Svc_Netlogon = $ServiceStatus['Netlogon']
        Svc_W32Time = $ServiceStatus['W32Time']
        Svc_DFSR = $ServiceStatus['DFSR']
        Svc_KDC = $ServiceStatus['KDC']
        EventErrorsLast24h = $ErrorCount
        EventWarningsLast24h = $WarningCount
        LastCheck = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

$HealthInfo | Export-Csv "$OutputPath\11_DC_HealthCheck_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Healthcheck selesai" -ForegroundColor Green


# ============================================
# 12. Security Assessment - Privileged Groups & Accounts
# ============================================
Write-Host "[12/13] Mengambil informasi Security Assessment..." -ForegroundColor Yellow

# Privileged Groups Members
$PrivGroups = @('Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators', 'Account Operators', 'Backup Operators', 'Server Operators')
$PrivGroupInfo = @()
$PrivCounter = 0

foreach ($group in $PrivGroups) {
    try {
        $members = Get-ADGroupMember -Identity $group -ErrorAction Stop
        foreach ($member in $members) {
            $PrivCounter++
            $memberDetails = $null
            if ($member.objectClass -eq 'user') {
                $memberDetails = Get-ADUser -Identity $member -Properties LastLogonDate, PasswordLastSet, Enabled -ErrorAction SilentlyContinue
            }
            
            $PrivGroupInfo += [PSCustomObject]@{
                No = $PrivCounter
                GroupName = $group
                MemberName = $member.Name
                MemberSamAccountName = $member.SamAccountName
                MemberType = $member.objectClass
                Enabled = if ($memberDetails) { $memberDetails.Enabled } else { "N/A" }
                LastLogonDate = if ($memberDetails) { $memberDetails.LastLogonDate } else { "N/A" }
                PasswordLastSet = if ($memberDetails) { $memberDetails.PasswordLastSet } else { "N/A" }
            }
        }
        if ($members.Count -eq 0) {
            $PrivCounter++
            $PrivGroupInfo += [PSCustomObject]@{
                No = $PrivCounter
                GroupName = $group
                MemberName = "(No Members)"
                MemberSamAccountName = "-"
                MemberType = "-"
                Enabled = "-"
                LastLogonDate = "-"
                PasswordLastSet = "-"
            }
        }
    } catch {
        $PrivCounter++
        $PrivGroupInfo += [PSCustomObject]@{
            No = $PrivCounter
            GroupName = $group
            MemberName = "Error: $($_.Exception.Message)"
            MemberSamAccountName = "-"
            MemberType = "-"
            Enabled = "-"
            LastLogonDate = "-"
            PasswordLastSet = "-"
        }
    }
}

$PrivGroupInfo | Export-Csv "$OutputPath\12a_Privileged_Groups_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Privileged groups assessment selesai" -ForegroundColor Green


# Password Policy - Default Domain Policy
Write-Host "   Mengambil Password Policy..." -ForegroundColor Gray
$PasswordPolicy = Get-ADDefaultDomainPasswordPolicy

# Recommendations
$recommendations = @()
if ($PasswordPolicy.MinPasswordLength -lt 12) { $recommendations += "Increase min password length to 12+" }
if (-not $PasswordPolicy.ComplexityEnabled) { $recommendations += "Enable complexity" }
if ($PasswordPolicy.MaxPasswordAge.Days -gt 90) { $recommendations += "Consider reducing max password age" }
if ($PasswordPolicy.LockoutThreshold -eq 0) { $recommendations += "Enable account lockout" }

$PasswordPolicyInfo = [PSCustomObject]@{
    No = 1
    PolicyType = "Default Domain Policy"
    PolicyName = "Default Domain Password Policy"
    MinPasswordLength = $PasswordPolicy.MinPasswordLength
    PasswordHistoryCount = $PasswordPolicy.PasswordHistoryCount
    MaxPasswordAgeDays = $PasswordPolicy.MaxPasswordAge.Days
    MinPasswordAgeDays = $PasswordPolicy.MinPasswordAge.Days
    ComplexityEnabled = $PasswordPolicy.ComplexityEnabled
    ReversibleEncryptionEnabled = $PasswordPolicy.ReversibleEncryptionEnabled
    LockoutThreshold = $PasswordPolicy.LockoutThreshold
    LockoutDurationMinutes = $PasswordPolicy.LockoutDuration.TotalMinutes
    LockoutObservationWindowMinutes = $PasswordPolicy.LockoutObservationWindow.TotalMinutes
    AppliesTo = "All Domain Users (Default)"
    Precedence = "N/A"
    Recommendation = ($recommendations -join '; ')
}

# Fine-Grained Password Policies (Custom Policies) - More Detailed
$FGPPs = @(Get-ADFineGrainedPasswordPolicy -Filter * -Properties * -ErrorAction SilentlyContinue)
$AllPasswordPolicies = @()
$AllPasswordPolicies += $PasswordPolicyInfo

$FGPPCounter = 1
if ($FGPPs.Count -gt 0) {
    foreach ($fgpp in $FGPPs) {
        $FGPPCounter++
        
        # Resolve AppliesTo to get actual names
        $appliesToResolved = @()
        foreach ($dn in $fgpp.AppliesTo) {
            try {
                $obj = Get-ADObject $dn -Properties Name, objectClass -ErrorAction SilentlyContinue
                if ($obj) {
                    $appliesToResolved += "$($obj.Name) ($($obj.objectClass))"
                } else {
                    $appliesToResolved += $dn
                }
            } catch {
                $appliesToResolved += $dn
            }
        }
        
        # Recommendations for FGPP
        $fgppRecommendations = @()
        if ($fgpp.MinPasswordLength -lt 12) { $fgppRecommendations += "Increase min password length to 12+" }
        if (-not $fgpp.ComplexityEnabled) { $fgppRecommendations += "Enable complexity" }
        if ($fgpp.LockoutThreshold -eq 0) { $fgppRecommendations += "Enable account lockout" }
        
        $AllPasswordPolicies += [PSCustomObject]@{
            No = $FGPPCounter
            PolicyType = "Fine-Grained Password Policy"
            PolicyName = $fgpp.Name
            MinPasswordLength = $fgpp.MinPasswordLength
            PasswordHistoryCount = $fgpp.PasswordHistoryCount
            MaxPasswordAgeDays = $fgpp.MaxPasswordAge.Days
            MinPasswordAgeDays = $fgpp.MinPasswordAge.Days
            ComplexityEnabled = $fgpp.ComplexityEnabled
            ReversibleEncryptionEnabled = $fgpp.ReversibleEncryptionEnabled
            LockoutThreshold = $fgpp.LockoutThreshold
            LockoutDurationMinutes = $fgpp.LockoutDuration.TotalMinutes
            LockoutObservationWindowMinutes = $fgpp.LockoutObservationWindow.TotalMinutes
            AppliesTo = ($appliesToResolved -join '; ')
            Precedence = $fgpp.Precedence
            Recommendation = ($fgppRecommendations -join '; ')
        }
    }
    Write-Host "   Ditemukan $($FGPPs.Count) Fine-Grained Password Policy" -ForegroundColor Green
}

# Export all password policies to single CSV
$AllPasswordPolicies | Export-Csv "$OutputPath\12b_All_Password_Policies_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Total $($AllPasswordPolicies.Count) Password Policies (Default + Custom)" -ForegroundColor Green

# GPO Policy Settings - Extract all policy settings from GPOs
Write-Host "   Mengambil GPO Policy Settings..." -ForegroundColor Gray
$GPOPolicySettings = @()
$GPOSettingsCounter = 0

foreach ($gpo in $GPOs) {
    try {
        $gpoReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction Stop)
        
        # Computer Configuration Settings
        if ($gpoReport.GPO.Computer.ExtensionData) {
            foreach ($ext in $gpoReport.GPO.Computer.ExtensionData) {
                $extName = $ext.Name
                foreach ($setting in $ext.Extension.ChildNodes) {
                    $GPOSettingsCounter++
                    $GPOPolicySettings += [PSCustomObject]@{
                        No = $GPOSettingsCounter
                        GPOName = $gpo.DisplayName
                        GPOStatus = $gpo.GpoStatus
                        ConfigurationType = "Computer"
                        ExtensionName = $extName
                        SettingName = $setting.LocalName
                        SettingValue = ($setting.InnerText -replace '\s+', ' ').Trim()
                        LinkedTo = ($gpoReport.GPO.LinksTo | ForEach-Object { $_.SOMPath }) -join '; '
                    }
                }
            }
        }
        
        # User Configuration Settings
        if ($gpoReport.GPO.User.ExtensionData) {
            foreach ($ext in $gpoReport.GPO.User.ExtensionData) {
                $extName = $ext.Name
                foreach ($setting in $ext.Extension.ChildNodes) {
                    $GPOSettingsCounter++
                    $GPOPolicySettings += [PSCustomObject]@{
                        No = $GPOSettingsCounter
                        GPOName = $gpo.DisplayName
                        GPOStatus = $gpo.GpoStatus
                        ConfigurationType = "User"
                        ExtensionName = $extName
                        SettingName = $setting.LocalName
                        SettingValue = ($setting.InnerText -replace '\s+', ' ').Trim()
                        LinkedTo = ($gpoReport.GPO.LinksTo | ForEach-Object { $_.SOMPath }) -join '; '
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
            SettingName = "Error"
            SettingValue = $_.Exception.Message
            LinkedTo = "-"
        }
    }
}

if ($GPOPolicySettings.Count -gt 0) {
    $GPOPolicySettings | Export-Csv "$OutputPath\12d_GPO_Policy_Settings_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($GPOPolicySettings.Count) GPO Policy Settings" -ForegroundColor Green
}


# ============================================
# 13. FSMO Roles dan Tombstone Lifetime
# ============================================
Write-Host "[13/13] Mengambil informasi FSMO Roles dan AD Configuration..." -ForegroundColor Yellow

$FSMOInfo = @()
$FSMOInfo += [PSCustomObject]@{ No = 1; Role = "Schema Master"; Server = $Forest.SchemaMaster; Scope = "Forest" }
$FSMOInfo += [PSCustomObject]@{ No = 2; Role = "Domain Naming Master"; Server = $Forest.DomainNamingMaster; Scope = "Forest" }
$FSMOInfo += [PSCustomObject]@{ No = 3; Role = "PDC Emulator"; Server = $Domain.PDCEmulator; Scope = "Domain" }
$FSMOInfo += [PSCustomObject]@{ No = 4; Role = "RID Master"; Server = $Domain.RIDMaster; Scope = "Domain" }
$FSMOInfo += [PSCustomObject]@{ No = 5; Role = "Infrastructure Master"; Server = $Domain.InfrastructureMaster; Scope = "Domain" }

$FSMOInfo | Export-Csv "$OutputPath\13a_FSMO_Roles_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   FSMO Roles berhasil dikumpulkan" -ForegroundColor Green

# AD Configuration Info
$configNC = (Get-ADRootDSE).configurationNamingContext
$tombstoneLifetime = (Get-ADObject "CN=Directory Service,CN=Windows NT,CN=Services,$configNC" -Properties tombstoneLifetime).tombstoneLifetime
if (-not $tombstoneLifetime) { $tombstoneLifetime = 180 } # Default

$ADConfigInfo = [PSCustomObject]@{
    ForestName = $Forest.Name
    DomainName = $Domain.DNSRoot
    NetBIOSName = $Domain.NetBIOSName
    ForestFunctionalLevel = $Forest.ForestMode
    DomainFunctionalLevel = $Domain.DomainMode
    SchemaVersion = $SchemaVersion
    SchemaName = $SchemaName
    TombstoneLifetimeDays = $tombstoneLifetime
    RecycleBinEnabled = (Get-ADOptionalFeature -Filter 'Name -like "Recycle Bin Feature"').EnabledScopes.Count -gt 0
    TotalDomainControllers = $DomainControllers.Count
    TotalGlobalCatalogs = ($DomainControllers | Where-Object { $_.IsGlobalCatalog }).Count
    TotalRODCs = ($DomainControllers | Where-Object { $_.IsReadOnly }).Count
    TotalSites = $Sites.Count
    TotalUsers = $Users.Count
    TotalComputers = $Computers.Count
    TotalGroups = (Get-ADGroup -Filter *).Count
    TotalOUs = $OUs.Count
    TotalGPOs = $GPOs.Count
}

$ADConfigInfo | Export-Csv "$OutputPath\13b_AD_Configuration_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   AD Configuration berhasil dikumpulkan" -ForegroundColor Green


# ============================================
# Summary Report
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       ACTIVE DIRECTORY ASSESSMENT SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "INFRASTRUCTURE:" -ForegroundColor Yellow
Write-Host "  Domain Controllers    : $($DomainControllers.Count)" -ForegroundColor White
Write-Host "  Global Catalogs       : $(($DomainControllers | Where-Object { $_.IsGlobalCatalog }).Count)" -ForegroundColor White
Write-Host "  Read-Only DCs         : $(($DomainControllers | Where-Object { $_.IsReadOnly }).Count)" -ForegroundColor White
Write-Host "  Sites                 : $($Sites.Count)" -ForegroundColor White
Write-Host "  Site Links            : $($SiteLinks.Count)" -ForegroundColor White
Write-Host ""
Write-Host "FUNCTIONAL LEVELS:" -ForegroundColor Yellow
Write-Host "  Forest Level          : $($Forest.ForestMode)" -ForegroundColor White
Write-Host "  Domain Level          : $($Domain.DomainMode)" -ForegroundColor White
Write-Host "  Schema Version        : $SchemaVersion ($SchemaName)" -ForegroundColor White
Write-Host ""
Write-Host "OBJECTS:" -ForegroundColor Yellow
Write-Host "  Total Users           : $($Users.Count)" -ForegroundColor White
Write-Host "  - Enabled             : $(($Users | Where-Object { $_.Enabled }).Count)" -ForegroundColor White
Write-Host "  - Disabled            : $(($Users | Where-Object { -not $_.Enabled }).Count)" -ForegroundColor White
Write-Host "  - Inactive (90+ days) : $(($Users | Where-Object { $_.LastLogonDate -and (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days -gt 90 }).Count)" -ForegroundColor White
Write-Host "  Total Computers       : $($Computers.Count)" -ForegroundColor White
Write-Host "  Total Servers         : $($Servers.Count)" -ForegroundColor White
Write-Host "  Total OUs             : $($OUs.Count)" -ForegroundColor White
Write-Host "  Total GPOs            : $($GPOs.Count)" -ForegroundColor White
Write-Host ""
Write-Host "SECURITY:" -ForegroundColor Yellow
Write-Host "  Password Min Length   : $($PasswordPolicy.MinPasswordLength)" -ForegroundColor White
Write-Host "  Complexity Enabled    : $($PasswordPolicy.ComplexityEnabled)" -ForegroundColor White
Write-Host "  Lockout Threshold     : $($PasswordPolicy.LockoutThreshold)" -ForegroundColor White
Write-Host "  Recycle Bin Enabled   : $($ADConfigInfo.RecycleBinEnabled)" -ForegroundColor White
Write-Host "  Tombstone Lifetime    : $tombstoneLifetime days" -ForegroundColor White
Write-Host ""

# Health Summary
$healthyDCs = ($HealthInfo | Where-Object { $_.OverallStatus -eq "Healthy" }).Count
$warningDCs = ($HealthInfo | Where-Object { $_.OverallStatus -eq "Warning" }).Count
$criticalDCs = ($HealthInfo | Where-Object { $_.OverallStatus -eq "Critical" }).Count

Write-Host "DC HEALTH STATUS:" -ForegroundColor Yellow
Write-Host "  Healthy               : $healthyDCs" -ForegroundColor Green
Write-Host "  Warning               : $warningDCs" -ForegroundColor Yellow
Write-Host "  Critical              : $criticalDCs" -ForegroundColor Red
Write-Host ""

# Replication Summary
$replHealthy = ($ReplInfo | Where-Object { $_.HealthStatus -eq "Healthy" }).Count
$replWarning = ($ReplInfo | Where-Object { $_.HealthStatus -eq "Warning" }).Count
$replError = ($ReplInfo | Where-Object { $_.HealthStatus -eq "Error" -or $_.HealthStatus -eq "Critical" }).Count

Write-Host "REPLICATION STATUS:" -ForegroundColor Yellow
Write-Host "  Healthy               : $replHealthy" -ForegroundColor Green
Write-Host "  Warning               : $replWarning" -ForegroundColor Yellow
Write-Host "  Error/Critical        : $replError" -ForegroundColor Red
Write-Host ""

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Output Files Location: $OutputPath" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Generate HTML Summary Report
$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>AD Assessment Report - $Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        h2 { color: #34495e; border-bottom: 2px solid #3498db; padding-bottom: 5px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #3498db; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .healthy { color: green; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        .critical { color: red; font-weight: bold; }
        .summary-box { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h1>Active Directory Assessment Report</h1>
    <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    <p>Domain: $($Domain.DNSRoot)</p>
    
    <div class="summary-box">
        <h2>Executive Summary</h2>
        <ul>
            <li>Domain Controllers: $($DomainControllers.Count) (Healthy: $healthyDCs, Warning: $warningDCs, Critical: $criticalDCs)</li>
            <li>Forest Functional Level: $($Forest.ForestMode)</li>
            <li>Domain Functional Level: $($Domain.DomainMode)</li>
            <li>Total Users: $($Users.Count) (Enabled: $(($Users | Where-Object { $_.Enabled }).Count))</li>
            <li>Total Computers: $($Computers.Count)</li>
            <li>Replication Status: Healthy: $replHealthy, Issues: $($replWarning + $replError)</li>
        </ul>
    </div>
    
    <p>Detailed CSV reports have been saved to: $OutputPath</p>
</body>
</html>
"@

$htmlReport | Out-File "$OutputPath\00_Assessment_Summary_$Timestamp.html" -Encoding UTF8
Write-Host "HTML Summary Report generated: 00_Assessment_Summary_$Timestamp.html" -ForegroundColor Green

# Open folder
explorer $OutputPath
