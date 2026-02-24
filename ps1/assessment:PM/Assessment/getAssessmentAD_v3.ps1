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
$OutputPath = "C:\ADAssessment"
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "=== Active Directory Assessment (Enhanced v3) ===" -ForegroundColor Cyan
Write-Host "Timestamp: $Timestamp" -ForegroundColor Green
Write-Host ""

# ============================================
# 1. Informasi Jumlah Server Active Directory
# ============================================
Write-Host "[1/18] Mengambil informasi jumlah server Active Directory..." -ForegroundColor Yellow

$DomainControllers = @(Get-ADDomainController -Filter *)
$DCCounter = 0
$DCInfo = $DomainControllers | ForEach-Object {
    $DCCounter++
    [PSCustomObject]@{
        No = $DCCounter
        Name = $_.Name
        HostName = $_.HostName
        Domain = $_.Domain
        Site = $_.Site
        OperatingSystem = $_.OperatingSystem
        OperatingSystemVersion = $_.OperatingSystemVersion
        IPv4Address = $_.IPv4Address
        IsGlobalCatalog = $_.IsGlobalCatalog
        IsReadOnly = $_.IsReadOnly
        Roles = ($_.OperationMasterRoles -join ', ')
        Enabled = $_.Enabled
        LdapPort = $_.LdapPort
        SslPort = $_.SslPort
    }
}

$DCInfo | Export-Csv "$OutputPath\01_DomainControllers_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($DomainControllers.Count) Domain Controller" -ForegroundColor Green


# ============================================
# 2. Informasi Versi OS Active Directory
# ============================================
Write-Host "[2/18] Mengambil informasi versi OS Active Directory..." -ForegroundColor Yellow

$OSCounter = 0
$OSInfo = $DomainControllers | ForEach-Object {
    $OSCounter++
    $osVersion = $_.OperatingSystemVersion
    $osBuild = if ($osVersion -match '\((\d+)\)') { $matches[1] } else { "N/A" }
    
    $eolStatus = switch -Wildcard ($_.OperatingSystem) {
        "*2008*" { "End of Life - Upgrade Required" }
        "*2012*" { "Extended Support Ended - Upgrade Recommended" }
        "*2016*" { "Mainstream Support" }
        "*2019*" { "Mainstream Support" }
        "*2022*" { "Current" }
        "*2025*" { "Current" }
        default { "Unknown" }
    }
    
    [PSCustomObject]@{
        No = $OSCounter
        ServerName = $_.Name
        OperatingSystem = $_.OperatingSystem
        OperatingSystemVersion = $osVersion
        OSBuild = $osBuild
        SupportStatus = $eolStatus
        Recommendation = if ($eolStatus -like "*End*" -or $eolStatus -like "*Ended*") { "Plan upgrade to Windows Server 2022/2025" } else { "OK" }
    }
}

$OSInfo | Export-Csv "$OutputPath\02_OS_Versions_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Informasi OS berhasil dikumpulkan" -ForegroundColor Green

# ============================================
# 3. Informasi Forest dan Domain Functional Level
# ============================================
Write-Host "[3/18] Mengambil informasi Forest dan Domain Functional Level..." -ForegroundColor Yellow

$Forest = Get-ADForest
$Domain = Get-ADDomain

$SchemaVersion = (Get-ADObject (Get-ADRootDSE).schemaNamingContext -Property objectVersion).objectVersion
$SchemaName = switch ($SchemaVersion) {
    87 { "Windows Server 2016/2019/2022" }
    88 { "Windows Server 2019" }
    89 { "Windows Server 2022" }
    90 { "Windows Server 2025" }
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
Write-Host "[4/18] Mengambil informasi Site dan Services..." -ForegroundColor Yellow

$Sites = @(Get-ADReplicationSite -Filter *)
$SiteCounter = 0
$SiteInfo = $Sites | ForEach-Object {
    $SiteCounter++
    $siteDN = $_.DistinguishedName
    $subnets = @(Get-ADReplicationSubnet -Filter * | Where-Object { $_.Site -eq $siteDN })
    $siteLinks = @(Get-ADReplicationSiteLink -Filter * | Where-Object { $_.SitesIncluded -contains $siteDN })
    
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

$SiteInfo | Export-Csv "$OutputPath\04a_Sites_Services_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
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

# Subnets Detail
$Subnets = @(Get-ADReplicationSubnet -Filter * -Properties *)
$SubnetCounter = 0
$SubnetInfo = $Subnets | ForEach-Object {
    $SubnetCounter++
    $siteName = if ($_.Site) { ($_.Site -split ',')[0] -replace 'CN=' } else { "Not Assigned" }
    [PSCustomObject]@{
        No = $SubnetCounter
        Name = $_.Name
        Site = $siteName
        Location = $_.Location
        Description = $_.Description
        Created = $_.Created
        Modified = $_.Modified
    }
}

$SubnetInfo | Export-Csv "$OutputPath\04c_Subnets_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Subnets.Count) Subnet" -ForegroundColor Green


# ============================================
# 5. Informasi Update/Patch yang terinstall
# ============================================
Write-Host "[5/18] Mengambil informasi Update/Patch (ini mungkin memakan waktu)..." -ForegroundColor Yellow

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
Write-Host "[6/18] Mengambil informasi Utilitas (Disk, Memory, CPU)..." -ForegroundColor Yellow

$UtilitasInfo = @()
$UtilCounter = 0
foreach ($DC in $DomainControllers) {
    try {
        $Disks = Get-WmiObject Win32_LogicalDisk -ComputerName $DC.HostName -Filter "DriveType=3" -ErrorAction Stop
        $Memory = Get-WmiObject Win32_ComputerSystem -ComputerName $DC.HostName -ErrorAction Stop
        $MemoryGB = [math]::Round($Memory.TotalPhysicalMemory / 1GB, 2)
        $AvailMem = Get-WmiObject Win32_OperatingSystem -ComputerName $DC.HostName -ErrorAction Stop
        $AvailMemGB = [math]::Round($AvailMem.FreePhysicalMemory / 1MB, 2)
        $MemUsedPercent = [math]::Round((($MemoryGB - $AvailMemGB) / $MemoryGB) * 100, 2)
        $CPU = Get-WmiObject Win32_Processor -ComputerName $DC.HostName -ErrorAction Stop | Select-Object -First 1
        
        $NTDSPath = "\\$($DC.HostName)\c$\Windows\NTDS"
        $NTDSSize = "N/A"
        $SYSVOLSize = "N/A"
        if (Test-Path $NTDSPath) {
            $ntdsFile = Get-Item "$NTDSPath\ntds.dit" -ErrorAction SilentlyContinue
            if ($ntdsFile) { $NTDSSize = [math]::Round($ntdsFile.Length / 1MB, 2) }
        }
        $SYSVOLPath = "\\$($DC.HostName)\SYSVOL"
        if (Test-Path $SYSVOLPath) {
            $sysvolFiles = Get-ChildItem $SYSVOLPath -Recurse -ErrorAction SilentlyContinue
            if ($sysvolFiles) { $SYSVOLSize = [math]::Round(($sysvolFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2) }
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
                SYSVOLSizeMB = $SYSVOLSize
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
            SYSVOLSizeMB = "-"
        }
    }
}

$UtilitasInfo | Export-Csv "$OutputPath\06_Utilitas_Resources_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Informasi utilitas berhasil dikumpulkan" -ForegroundColor Green


# ============================================
# 7. Informasi DNS di Domain Controller
# ============================================
Write-Host "[7/18] Mengambil informasi DNS..." -ForegroundColor Yellow

$DNSInfo = @()
$DNSCounter = 0
foreach ($DC in $DomainControllers) {
    try {
        $DNSZones = Get-DnsServerZone -ComputerName $DC.HostName -ErrorAction Stop
        
        foreach ($Zone in $DNSZones) {
            $DNSCounter++
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
# 8. Data User dengan Detail Lengkap
# ============================================
Write-Host "[8/18] Mengambil data User..." -ForegroundColor Yellow

$Users = @(Get-ADUser -Filter * -Properties Enabled, Created, LastLogonDate, PasswordLastSet, PasswordNeverExpires, PasswordExpired, LockedOut, AccountExpirationDate, Description, Department, Title, Manager, MemberOf, EmailAddress, Office, TelephoneNumber, whenCreated, whenChanged, adminCount, servicePrincipalName)
$UserCounter = 0
$UserInfo = $Users | ForEach-Object {
    $UserCounter++
    $daysSinceLastLogon = if ($_.LastLogonDate) { (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days } else { "Never" }
    $daysSincePasswordSet = if ($_.PasswordLastSet) { (New-TimeSpan -Start $_.PasswordLastSet -End (Get-Date)).Days } else { "Never" }
    $groupCount = ($_.MemberOf).Count
    $isServiceAccount = if ($_.servicePrincipalName) { "Yes" } else { "No" }
    $isPrivileged = if ($_.adminCount -eq 1) { "Yes" } else { "No" }
    
    $status = "Active"
    if (-not $_.Enabled) { $status = "Disabled" }
    elseif ($_.LockedOut) { $status = "Locked" }
    elseif ($daysSinceLastLogon -ne "Never" -and $daysSinceLastLogon -gt 90) { $status = "Inactive (90+ days)" }
    
    [PSCustomObject]@{
        No = $UserCounter
        Name = $_.Name
        SamAccountName = $_.SamAccountName
        UserPrincipalName = $_.UserPrincipalName
        EmailAddress = $_.EmailAddress
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
        IsServiceAccount = $isServiceAccount
        IsPrivileged = $isPrivileged
        Department = $_.Department
        Title = $_.Title
        Office = $_.Office
        TelephoneNumber = $_.TelephoneNumber
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
    PasswordExpired = ($Users | Where-Object { $_.PasswordExpired }).Count
    InactiveUsers90Days = ($Users | Where-Object { $_.LastLogonDate -and (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days -gt 90 }).Count
    NeverLoggedIn = ($Users | Where-Object { -not $_.LastLogonDate }).Count
    ServiceAccounts = ($Users | Where-Object { $_.servicePrincipalName }).Count
    PrivilegedUsers = ($Users | Where-Object { $_.adminCount -eq 1 }).Count
}
$UserStats | Export-Csv "$OutputPath\08a_User_Statistics_$Timestamp.csv" -NoTypeInformation -Encoding UTF8


# ============================================
# 9. Data Computer dengan Detail Lengkap (SEMUA DATA)
# ============================================
Write-Host "[9/18] Mengambil data Computer (semua data lengkap)..." -ForegroundColor Yellow

$Computers = @(Get-ADComputer -Filter * -Properties *)
$CompCounter = 0
$ComputerInfo = $Computers | ForEach-Object {
    $CompCounter++
    $daysSinceLastLogon = if ($_.LastLogonDate) { (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days } else { "Never" }
    $daysSinceCreated = if ($_.Created) { (New-TimeSpan -Start $_.Created -End (Get-Date)).Days } else { "N/A" }
    $daysSincePwdSet = if ($_.PasswordLastSet) { (New-TimeSpan -Start $_.PasswordLastSet -End (Get-Date)).Days } else { "Never" }
    
    $staleStatus = "Active"
    if ($daysSinceLastLogon -eq "Never") { $staleStatus = "Never Connected" }
    elseif ($daysSinceLastLogon -gt 90) { $staleStatus = "Stale (90+ days)" }
    elseif ($daysSinceLastLogon -gt 30) { $staleStatus = "Warning (30+ days)" }
    
    $computerType = "Workstation"
    if ($_.OperatingSystem -like "*Server*") { $computerType = "Server" }
    elseif ($_.OperatingSystem -like "*Domain Controller*") { $computerType = "Domain Controller" }
    
    [PSCustomObject]@{
        No = $CompCounter
        Name = $_.Name
        DNSHostName = $_.DNSHostName
        IPv4Address = $_.IPv4Address
        OperatingSystem = $_.OperatingSystem
        OperatingSystemVersion = $_.OperatingSystemVersion
        OperatingSystemServicePack = $_.OperatingSystemServicePack
        ComputerType = $computerType
        Enabled = $_.Enabled
        Created = $_.Created
        DaysSinceCreated = $daysSinceCreated
        LastLogonDate = $_.LastLogonDate
        DaysSinceLastLogon = $daysSinceLastLogon
        PasswordLastSet = $_.PasswordLastSet
        DaysSincePasswordSet = $daysSincePwdSet
        StaleStatus = $staleStatus
        Description = $_.Description
        Location = $_.Location
        ManagedBy = $_.ManagedBy
        MemberOf = ($_.MemberOf -join '; ')
        ServicePrincipalNames = ($_.servicePrincipalName -join '; ')
        TrustedForDelegation = $_.TrustedForDelegation
        PrimaryGroup = $_.PrimaryGroup
        SID = $_.SID
        DistinguishedName = $_.DistinguishedName
    }
}

$ComputerInfo | Export-Csv "$OutputPath\09a_Domain_Computers_All_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Computers.Count) Computer (semua data)" -ForegroundColor Green

# Servers (Windows Server OS) - Detail
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
        PasswordLastSet = $_.PasswordLastSet
        Description = $_.Description
        Location = $_.Location
        TrustedForDelegation = $_.TrustedForDelegation
        DistinguishedName = $_.DistinguishedName
    }
}

$ServerInfo | Export-Csv "$OutputPath\09b_Domain_Servers_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Servers.Count) Server" -ForegroundColor Green

# Workstations
$Workstations = @($Computers | Where-Object {$_.OperatingSystem -notlike "*Server*"})
$WksCounter = 0
$WorkstationInfo = $Workstations | ForEach-Object {
    $WksCounter++
    $daysSinceLastLogon = if ($_.LastLogonDate) { (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days } else { "Never" }
    
    [PSCustomObject]@{
        No = $WksCounter
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

$WorkstationInfo | Export-Csv "$OutputPath\09c_Domain_Workstations_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Workstations.Count) Workstation" -ForegroundColor Green

# Computer Statistics
$CompStats = [PSCustomObject]@{
    TotalComputers = $Computers.Count
    TotalServers = $Servers.Count
    TotalWorkstations = $Workstations.Count
    EnabledComputers = ($Computers | Where-Object { $_.Enabled }).Count
    DisabledComputers = ($Computers | Where-Object { -not $_.Enabled }).Count
    StaleComputers90Days = ($Computers | Where-Object { $_.LastLogonDate -and (New-TimeSpan -Start $_.LastLogonDate -End (Get-Date)).Days -gt 90 }).Count
    NeverConnected = ($Computers | Where-Object { -not $_.LastLogonDate }).Count
    TrustedForDelegation = ($Computers | Where-Object { $_.TrustedForDelegation }).Count
    Windows10_11 = ($Computers | Where-Object { $_.OperatingSystem -like "*Windows 10*" -or $_.OperatingSystem -like "*Windows 11*" }).Count
    Windows7_8 = ($Computers | Where-Object { $_.OperatingSystem -like "*Windows 7*" -or $_.OperatingSystem -like "*Windows 8*" }).Count
    Server2019_2022 = ($Servers | Where-Object { $_.OperatingSystem -like "*2019*" -or $_.OperatingSystem -like "*2022*" }).Count
    Server2016 = ($Servers | Where-Object { $_.OperatingSystem -like "*2016*" }).Count
    Server2012 = ($Servers | Where-Object { $_.OperatingSystem -like "*2012*" }).Count
    ServerOlder = ($Servers | Where-Object { $_.OperatingSystem -like "*2008*" -or $_.OperatingSystem -like "*2003*" }).Count
}
$CompStats | Export-Csv "$OutputPath\09d_Computer_Statistics_$Timestamp.csv" -NoTypeInformation -Encoding UTF8

# OS Distribution
$OSDistribution = $Computers | Group-Object OperatingSystem | Select-Object @{N='No';E={$null}}, @{N='OperatingSystem';E={$_.Name}}, Count | Sort-Object Count -Descending
$osCounter = 0
$OSDistribution | ForEach-Object { $osCounter++; $_.No = $osCounter }
$OSDistribution | Export-Csv "$OutputPath\09e_OS_Distribution_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   OS Distribution berhasil dikumpulkan" -ForegroundColor Green


# ============================================
# 10. Status dan Konfigurasi GPO serta Struktur OU
# ============================================
Write-Host "[10/18] Mengambil informasi GPO dan OU..." -ForegroundColor Yellow

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

$GPOInfo | Export-Csv "$OutputPath\10a_GPO_Information_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($GPOs.Count) GPO" -ForegroundColor Green

# GPO Policy Settings - Detail Isi GPO
Write-Host "   Mengambil GPO Policy Settings (Isi GPO)..." -ForegroundColor Gray
$GPOPolicySettings = @()
$GPOSettingsCounter = 0

foreach ($gpo in $GPOs) {
    try {
        $gpoReportDetail = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction Stop)
        
        # Computer Configuration Settings
        if ($gpoReportDetail.GPO.Computer.ExtensionData) {
            foreach ($ext in $gpoReportDetail.GPO.Computer.ExtensionData) {
                $extName = $ext.Name
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
                            SettingCategory = $setting.LocalName
                            SettingName = if ($setting.Name) { $setting.Name } else { $setting.LocalName }
                            SettingState = if ($setting.State) { $setting.State } else { "Configured" }
                            SettingValue = ($settingValue -replace '\s+', ' ').Trim()
                            LinkedTo = ($gpoReportDetail.GPO.LinksTo | ForEach-Object { $_.SOMPath }) -join '; '
                        }
                    }
                }
            }
        }
        
        # User Configuration Settings
        if ($gpoReportDetail.GPO.User.ExtensionData) {
            foreach ($ext in $gpoReportDetail.GPO.User.ExtensionData) {
                $extName = $ext.Name
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
                            SettingCategory = $setting.LocalName
                            SettingName = if ($setting.Name) { $setting.Name } else { $setting.LocalName }
                            SettingState = if ($setting.State) { $setting.State } else { "Configured" }
                            SettingValue = ($settingValue -replace '\s+', ' ').Trim()
                            LinkedTo = ($gpoReportDetail.GPO.LinksTo | ForEach-Object { $_.SOMPath }) -join '; '
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
            SettingCategory = "Error"
            SettingName = "Error"
            SettingState = "-"
            SettingValue = $_.Exception.Message
            LinkedTo = "-"
        }
    }
}

if ($GPOPolicySettings.Count -gt 0) {
    $GPOPolicySettings | Export-Csv "$OutputPath\10c_GPO_Policy_Settings_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($GPOPolicySettings.Count) GPO Policy Settings" -ForegroundColor Green
}

# Export GPO HTML Reports
Write-Host "   Mengexport GPO HTML Reports..." -ForegroundColor Gray
$GPOReportPath = "$OutputPath\GPO_Reports"
if (-not (Test-Path $GPOReportPath)) { New-Item -ItemType Directory -Path $GPOReportPath | Out-Null }
foreach ($gpo in $GPOs) {
    try {
        $safeGPOName = $gpo.DisplayName -replace '[\\/:*?"<>|]', '_'
        Get-GPOReport -Guid $gpo.Id -ReportType Html -Path "$GPOReportPath\$safeGPOName.html"
    } catch {}
}
Write-Host "   GPO HTML Reports disimpan di: $GPOReportPath" -ForegroundColor Green

# OU Structure dengan GPO Links
$OUs = @(Get-ADOrganizationalUnit -Filter * -Properties Created, Modified, Description, ManagedBy, gPLink, gPOptions)
$OUCounter = 0
$OUInfo = $OUs | ForEach-Object {
    $OUCounter++
    $ouDN = $_.DistinguishedName
    $linkedGPOs = @()
    if ($_.gPLink) {
        $gpLinks = $_.gPLink -split '\]\[' | ForEach-Object { $_ -replace '^\[|\]$' }
        foreach ($link in $gpLinks) {
            if ($link -match 'LDAP://cn=\{([^}]+)\}') {
                $gpoGuid = $matches[1]
                $gpo = $GPOs | Where-Object { $_.Id -eq $gpoGuid }
                if ($gpo) { $linkedGPOs += $gpo.DisplayName }
            }
        }
    }
    $inheritanceBlocked = if ($_.gPOptions -eq 1) { "Yes" } else { "No" }
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

$OUInfo | Export-Csv "$OutputPath\10b_OU_Structure_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($OUs.Count) Organizational Unit" -ForegroundColor Green


# ============================================
# 11. REPLICATION STATUS - LENGKAP (PERBAIKAN UTAMA)
# ============================================
Write-Host "[11/18] Mengecek status replikasi (LENGKAP)..." -ForegroundColor Yellow

# 11a. Replication Partner Metadata
$ReplInfo = @()
$ReplCounter = 0
foreach ($DC in $DomainControllers) {
    try {
        $ReplStatus = Get-ADReplicationPartnerMetadata -Target $DC.HostName -ErrorAction Stop
        foreach ($Repl in $ReplStatus) {
            $ReplCounter++
            $partnerName = ($Repl.Partner -split ',')[0] -replace 'CN='
            $partitionName = ($Repl.Partition -split ',')[0] -replace 'DC=|CN='
            $replLag = if ($Repl.LastReplicationSuccess) { 
                (New-TimeSpan -Start $Repl.LastReplicationSuccess -End (Get-Date)).TotalMinutes 
            } else { "N/A" }
            
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
                PartnerType = $Repl.PartnerType
                UsnFilter = $Repl.UsnFilter
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
            PartnerType = "-"
            UsnFilter = "-"
        }
    }
}

$ReplInfo | Export-Csv "$OutputPath\11a_Replication_Partner_Metadata_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Replication Partner Metadata: $($ReplInfo.Count) entries" -ForegroundColor Green


# 11b. Repadmin /showrepl output (RAW)
Write-Host "   Mengambil repadmin /showrepl..." -ForegroundColor Gray
$RepadminShowrepl = @()
$RepadminCounter = 0
try {
    $repadminOutput = repadmin /showrepl * /csv 2>$null | ConvertFrom-Csv
    foreach ($item in $repadminOutput) {
        $RepadminCounter++
        $RepadminShowrepl += [PSCustomObject]@{
            No = $RepadminCounter
            DestinationDCSite = $item.'Destination DC Site'
            DestinationDC = $item.'Destination DC'
            NamingContext = $item.'Naming Context'
            SourceDCSite = $item.'Source DC Site'
            SourceDC = $item.'Source DC'
            TransportType = $item.'Transport Type'
            NumberOfFailures = $item.'Number of Failures'
            LastFailureTime = $item.'Last Failure Time'
            LastSuccessTime = $item.'Last Success Time'
            LastFailureStatus = $item.'Last Failure Status'
        }
    }
    $RepadminShowrepl | Export-Csv "$OutputPath\11b_Repadmin_Showrepl_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Repadmin showrepl: $($RepadminShowrepl.Count) entries" -ForegroundColor Green
} catch {
    Write-Host "   Warning: Tidak dapat menjalankan repadmin /showrepl" -ForegroundColor Yellow
}

# 11c. Repadmin /replsummary
Write-Host "   Mengambil repadmin /replsummary..." -ForegroundColor Gray
try {
    $replSummaryRaw = repadmin /replsummary 2>$null
    $replSummaryRaw | Out-File "$OutputPath\11c_Repadmin_Replsummary_$Timestamp.txt" -Encoding UTF8
    Write-Host "   Repadmin replsummary saved" -ForegroundColor Green
} catch {
    Write-Host "   Warning: Tidak dapat menjalankan repadmin /replsummary" -ForegroundColor Yellow
}

# 11d. Replication Failures Detail
Write-Host "   Mengambil Replication Failures..." -ForegroundColor Gray
$ReplFailures = @()
$FailCounter = 0
foreach ($DC in $DomainControllers) {
    try {
        $failures = Get-ADReplicationFailure -Target $DC.HostName -ErrorAction Stop
        foreach ($fail in $failures) {
            $FailCounter++
            $ReplFailures += [PSCustomObject]@{
                No = $FailCounter
                Server = $DC.Name
                Partner = $fail.Partner
                PartnerGuid = $fail.PartnerGuid
                FailureCount = $fail.FailureCount
                FailureType = $fail.FailureType
                FirstFailureTime = $fail.FirstFailureTime
                LastError = $fail.LastError
            }
        }
    } catch {}
}
if ($ReplFailures.Count -gt 0) {
    $ReplFailures | Export-Csv "$OutputPath\11d_Replication_Failures_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($ReplFailures.Count) replication failure entries" -ForegroundColor Yellow
} else {
    Write-Host "   Tidak ada replication failure" -ForegroundColor Green
}


# 11e. Replication Connection Objects
Write-Host "   Mengambil Replication Connection Objects..." -ForegroundColor Gray
$ReplConnections = @()
$ConnCounter = 0
try {
    $connections = Get-ADReplicationConnection -Filter *
    foreach ($conn in $connections) {
        $ConnCounter++
        $ReplConnections += [PSCustomObject]@{
            No = $ConnCounter
            Name = $conn.Name
            ReplicateFromDirectoryServer = ($conn.ReplicateFromDirectoryServer -split ',')[0] -replace 'CN='
            ReplicateToDirectoryServer = ($conn.ReplicateToDirectoryServer -split ',')[0] -replace 'CN='
            AutoGenerated = $conn.AutoGenerated
            Enabled = $conn.EnabledConnection
            Options = $conn.Options
            Schedule = if ($conn.Schedule) { "Custom" } else { "Default" }
            TransportType = $conn.InterSiteTransportProtocol
            Created = $conn.Created
            Modified = $conn.Modified
        }
    }
    $ReplConnections | Export-Csv "$OutputPath\11e_Replication_Connections_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($ReplConnections.Count) connection objects" -ForegroundColor Green
} catch {
    Write-Host "   Warning: Tidak dapat mengambil connection objects" -ForegroundColor Yellow
}

# 11f. Replication Queue
Write-Host "   Mengambil Replication Queue..." -ForegroundColor Gray
$ReplQueue = @()
$QueueCounter = 0
foreach ($DC in $DomainControllers) {
    try {
        $queue = Get-ADReplicationQueueOperation -Server $DC.HostName -ErrorAction Stop
        foreach ($q in $queue) {
            $QueueCounter++
            $ReplQueue += [PSCustomObject]@{
                No = $QueueCounter
                Server = $DC.Name
                OperationType = $q.OperationType
                Partition = $q.Partition
                PartnerAddress = $q.PartnerAddress
                EnqueueTime = $q.EnqueueTime
                Priority = $q.Priority
            }
        }
    } catch {}
}
if ($ReplQueue.Count -gt 0) {
    $ReplQueue | Export-Csv "$OutputPath\11f_Replication_Queue_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($ReplQueue.Count) queue entries" -ForegroundColor Yellow
} else {
    Write-Host "   Replication queue kosong (normal)" -ForegroundColor Green
}

# 11g. Replication Uptime/Status per DC
Write-Host "   Mengambil Replication Uptime per DC..." -ForegroundColor Gray
$ReplUptime = @()
$UptimeCounter = 0
foreach ($DC in $DomainControllers) {
    $UptimeCounter++
    try {
        $uptodateVector = Get-ADReplicationUpToDatenessVectorTable -Target $DC.HostName -ErrorAction Stop
        foreach ($vector in $uptodateVector) {
            $ReplUptime += [PSCustomObject]@{
                No = $UptimeCounter
                Server = $DC.Name
                Partner = ($vector.Partner -split ',')[0] -replace 'CN='
                Partition = ($vector.Partition -split ',')[0] -replace 'DC='
                UsnFilter = $vector.UsnFilter
                LastReplicationSuccess = $vector.LastReplicationSuccess
            }
        }
    } catch {}
}
if ($ReplUptime.Count -gt 0) {
    $ReplUptime | Export-Csv "$OutputPath\11g_Replication_Uptodate_Vector_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Replication uptodate vector: $($ReplUptime.Count) entries" -ForegroundColor Green
}


# ============================================
# 12. Healthcheck Domain Controller
# ============================================
Write-Host "[12/18] Menjalankan healthcheck Domain Controller..." -ForegroundColor Yellow

$HealthInfo = @()
$HealthCounter = 0
foreach ($DC in $DomainControllers) {
    $HealthCounter++
    Write-Host "   Checking $($DC.Name)..." -ForegroundColor Gray
    
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
    
    $Services = @('NTDS', 'DNS', 'Netlogon', 'W32Time', 'DFSR', 'KDC')
    $ServiceStatus = @{}
    foreach ($Service in $Services) {
        try {
            $Svc = Get-Service -Name $Service -ComputerName $DC.HostName -ErrorAction Stop
            $ServiceStatus[$Service] = $Svc.Status.ToString()
        } catch { $ServiceStatus[$Service] = "N/A" }
    }
    
    $ErrorCount = 0; $WarningCount = 0
    try {
        $ErrorCount = (Get-EventLog -LogName System -ComputerName $DC.HostName -EntryType Error -After (Get-Date).AddDays(-1) -ErrorAction Stop).Count
        $WarningCount = (Get-EventLog -LogName System -ComputerName $DC.HostName -EntryType Warning -After (Get-Date).AddDays(-1) -ErrorAction Stop).Count
    } catch {}
    
    $uptime = "N/A"
    try {
        $os = Get-WmiObject Win32_OperatingSystem -ComputerName $DC.HostName -ErrorAction Stop
        $lastBoot = $os.ConvertToDateTime($os.LastBootUpTime)
        $uptimeSpan = New-TimeSpan -Start $lastBoot -End (Get-Date)
        $uptime = "$($uptimeSpan.Days)d $($uptimeSpan.Hours)h $($uptimeSpan.Minutes)m"
    } catch {}
    
    $passCount = ($dcdiagResults.Values | Where-Object { $_ -eq "PASS" }).Count
    $healthScore = [math]::Round(($passCount / $dcdiagResults.Count) * 100, 0)
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

$HealthInfo | Export-Csv "$OutputPath\12_DC_HealthCheck_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Healthcheck selesai" -ForegroundColor Green


# ============================================
# 13. Security Assessment - Privileged Groups
# ============================================
Write-Host "[13/18] Mengambil informasi Security Assessment..." -ForegroundColor Yellow

$PrivGroups = @('Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators', 'Account Operators', 'Backup Operators', 'Server Operators', 'Print Operators', 'DnsAdmins')
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

$PrivGroupInfo | Export-Csv "$OutputPath\13a_Privileged_Groups_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Privileged groups assessment selesai" -ForegroundColor Green


# ============================================
# 14. Password Policy
# ============================================
Write-Host "[14/18] Mengambil Password Policy..." -ForegroundColor Yellow

$PasswordPolicy = Get-ADDefaultDomainPasswordPolicy
$recommendations = @()
if ($PasswordPolicy.MinPasswordLength -lt 12) { $recommendations += "Increase min password length to 12+" }
if (-not $PasswordPolicy.ComplexityEnabled) { $recommendations += "Enable complexity" }
if ($PasswordPolicy.MaxPasswordAge.Days -gt 90) { $recommendations += "Consider reducing max password age" }
if ($PasswordPolicy.LockoutThreshold -eq 0) { $recommendations += "Enable account lockout" }

$AllPasswordPolicies = @()
$AllPasswordPolicies += [PSCustomObject]@{
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

$FGPPs = @(Get-ADFineGrainedPasswordPolicy -Filter * -Properties * -ErrorAction SilentlyContinue)
$FGPPCounter = 1
foreach ($fgpp in $FGPPs) {
    $FGPPCounter++
    $appliesToResolved = @()
    foreach ($dn in $fgpp.AppliesTo) {
        try {
            $obj = Get-ADObject $dn -Properties Name, objectClass -ErrorAction SilentlyContinue
            if ($obj) { $appliesToResolved += "$($obj.Name) ($($obj.objectClass))" }
        } catch { $appliesToResolved += $dn }
    }
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
        Recommendation = ""
    }
}

$AllPasswordPolicies | Export-Csv "$OutputPath\14_Password_Policies_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Total $($AllPasswordPolicies.Count) Password Policies" -ForegroundColor Green


# ============================================
# 15. FSMO Roles dan AD Configuration
# ============================================
Write-Host "[15/18] Mengambil informasi FSMO Roles dan AD Configuration..." -ForegroundColor Yellow

$FSMOInfo = @()
$FSMOInfo += [PSCustomObject]@{ No = 1; Role = "Schema Master"; Server = $Forest.SchemaMaster; Scope = "Forest" }
$FSMOInfo += [PSCustomObject]@{ No = 2; Role = "Domain Naming Master"; Server = $Forest.DomainNamingMaster; Scope = "Forest" }
$FSMOInfo += [PSCustomObject]@{ No = 3; Role = "PDC Emulator"; Server = $Domain.PDCEmulator; Scope = "Domain" }
$FSMOInfo += [PSCustomObject]@{ No = 4; Role = "RID Master"; Server = $Domain.RIDMaster; Scope = "Domain" }
$FSMOInfo += [PSCustomObject]@{ No = 5; Role = "Infrastructure Master"; Server = $Domain.InfrastructureMaster; Scope = "Domain" }

$FSMOInfo | Export-Csv "$OutputPath\15a_FSMO_Roles_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   FSMO Roles berhasil dikumpulkan" -ForegroundColor Green

$configNC = (Get-ADRootDSE).configurationNamingContext
$tombstoneLifetime = (Get-ADObject "CN=Directory Service,CN=Windows NT,CN=Services,$configNC" -Properties tombstoneLifetime).tombstoneLifetime
if (-not $tombstoneLifetime) { $tombstoneLifetime = 180 }

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

$ADConfigInfo | Export-Csv "$OutputPath\15b_AD_Configuration_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   AD Configuration berhasil dikumpulkan" -ForegroundColor Green


# ============================================
# 16. Groups Information
# ============================================
Write-Host "[16/18] Mengambil informasi Groups..." -ForegroundColor Yellow

$Groups = @(Get-ADGroup -Filter * -Properties Description, Created, Modified, ManagedBy, GroupCategory, GroupScope, MemberOf, Members)
$GroupCounter = 0
$GroupInfo = $Groups | ForEach-Object {
    $GroupCounter++
    [PSCustomObject]@{
        No = $GroupCounter
        Name = $_.Name
        SamAccountName = $_.SamAccountName
        GroupCategory = $_.GroupCategory
        GroupScope = $_.GroupScope
        Description = $_.Description
        MemberCount = $_.Members.Count
        MemberOfCount = $_.MemberOf.Count
        ManagedBy = $_.ManagedBy
        Created = $_.Created
        Modified = $_.Modified
        DistinguishedName = $_.DistinguishedName
    }
}

$GroupInfo | Export-Csv "$OutputPath\16_Groups_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Groups.Count) Groups" -ForegroundColor Green

# Group Statistics
$GroupStats = [PSCustomObject]@{
    TotalGroups = $Groups.Count
    SecurityGroups = ($Groups | Where-Object { $_.GroupCategory -eq 'Security' }).Count
    DistributionGroups = ($Groups | Where-Object { $_.GroupCategory -eq 'Distribution' }).Count
    GlobalScope = ($Groups | Where-Object { $_.GroupScope -eq 'Global' }).Count
    DomainLocalScope = ($Groups | Where-Object { $_.GroupScope -eq 'DomainLocal' }).Count
    UniversalScope = ($Groups | Where-Object { $_.GroupScope -eq 'Universal' }).Count
    EmptyGroups = ($Groups | Where-Object { $_.Members.Count -eq 0 }).Count
}
$GroupStats | Export-Csv "$OutputPath\16b_Group_Statistics_$Timestamp.csv" -NoTypeInformation -Encoding UTF8


# ============================================
# 17. Trust Relationships
# ============================================
Write-Host "[17/18] Mengambil informasi Trust Relationships..." -ForegroundColor Yellow

$Trusts = @(Get-ADTrust -Filter * -Properties * -ErrorAction SilentlyContinue)
$TrustCounter = 0
$TrustInfo = $Trusts | ForEach-Object {
    $TrustCounter++
    [PSCustomObject]@{
        No = $TrustCounter
        Name = $_.Name
        Source = $_.Source
        Target = $_.Target
        Direction = $_.Direction
        TrustType = $_.TrustType
        DisallowTransivity = $_.DisallowTransivity
        IntraForest = $_.IntraForest
        SelectiveAuthentication = $_.SelectiveAuthentication
        SIDFilteringForestAware = $_.SIDFilteringForestAware
        SIDFilteringQuarantined = $_.SIDFilteringQuarantined
        TGTDelegation = $_.TGTDelegation
        Created = $_.Created
        Modified = $_.Modified
    }
}

if ($TrustInfo.Count -gt 0) {
    $TrustInfo | Export-Csv "$OutputPath\17_Trust_Relationships_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($Trusts.Count) Trust Relationships" -ForegroundColor Green
} else {
    Write-Host "   Tidak ada Trust Relationships" -ForegroundColor Green
}


# ============================================
# 18. Service Accounts & SPNs
# ============================================
Write-Host "[18/18] Mengambil informasi Service Accounts & SPNs..." -ForegroundColor Yellow

$ServiceAccounts = @(Get-ADUser -Filter {servicePrincipalName -like "*"} -Properties servicePrincipalName, Enabled, LastLogonDate, PasswordLastSet, PasswordNeverExpires, Description)
$SACounter = 0
$SAInfo = $ServiceAccounts | ForEach-Object {
    $SACounter++
    [PSCustomObject]@{
        No = $SACounter
        Name = $_.Name
        SamAccountName = $_.SamAccountName
        Enabled = $_.Enabled
        LastLogonDate = $_.LastLogonDate
        PasswordLastSet = $_.PasswordLastSet
        PasswordNeverExpires = $_.PasswordNeverExpires
        Description = $_.Description
        SPNs = ($_.servicePrincipalName -join '; ')
        SPNCount = $_.servicePrincipalName.Count
    }
}

if ($SAInfo.Count -gt 0) {
    $SAInfo | Export-Csv "$OutputPath\18a_Service_Accounts_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($ServiceAccounts.Count) Service Accounts dengan SPN" -ForegroundColor Green
} else {
    Write-Host "   Tidak ada Service Accounts dengan SPN" -ForegroundColor Green
}

# Managed Service Accounts
$MSAs = @(Get-ADServiceAccount -Filter * -Properties * -ErrorAction SilentlyContinue)
$MSACounter = 0
$MSAInfo = $MSAs | ForEach-Object {
    $MSACounter++
    [PSCustomObject]@{
        No = $MSACounter
        Name = $_.Name
        SamAccountName = $_.SamAccountName
        Enabled = $_.Enabled
        Created = $_.Created
        HostComputers = ($_.HostComputers -join '; ')
        PrincipalsAllowedToRetrieveManagedPassword = ($_.PrincipalsAllowedToRetrieveManagedPassword -join '; ')
        ServicePrincipalNames = ($_.servicePrincipalName -join '; ')
    }
}

if ($MSAInfo.Count -gt 0) {
    $MSAInfo | Export-Csv "$OutputPath\18b_Managed_Service_Accounts_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($MSAs.Count) Managed Service Accounts" -ForegroundColor Green
}


# ============================================
# Summary Report
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   ACTIVE DIRECTORY ASSESSMENT SUMMARY v3" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "INFRASTRUCTURE:" -ForegroundColor Yellow
Write-Host "  Domain Controllers    : $($DomainControllers.Count)" -ForegroundColor White
Write-Host "  Global Catalogs       : $(($DomainControllers | Where-Object { $_.IsGlobalCatalog }).Count)" -ForegroundColor White
Write-Host "  Read-Only DCs         : $(($DomainControllers | Where-Object { $_.IsReadOnly }).Count)" -ForegroundColor White
Write-Host "  Sites                 : $($Sites.Count)" -ForegroundColor White
Write-Host "  Site Links            : $($SiteLinks.Count)" -ForegroundColor White
Write-Host "  Subnets               : $($Subnets.Count)" -ForegroundColor White
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
Write-Host "  - Servers             : $($Servers.Count)" -ForegroundColor White
Write-Host "  - Workstations        : $($Workstations.Count)" -ForegroundColor White
Write-Host "  Total Groups          : $($Groups.Count)" -ForegroundColor White
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

$healthyDCs = ($HealthInfo | Where-Object { $_.OverallStatus -eq "Healthy" }).Count
$warningDCs = ($HealthInfo | Where-Object { $_.OverallStatus -eq "Warning" }).Count
$criticalDCs = ($HealthInfo | Where-Object { $_.OverallStatus -eq "Critical" }).Count

Write-Host "DC HEALTH STATUS:" -ForegroundColor Yellow
Write-Host "  Healthy               : $healthyDCs" -ForegroundColor Green
Write-Host "  Warning               : $warningDCs" -ForegroundColor Yellow
Write-Host "  Critical              : $criticalDCs" -ForegroundColor Red
Write-Host ""

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
    <title>AD Assessment Report v3 - $Timestamp</title>
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
    <h1>Active Directory Assessment Report v3</h1>
    <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    <p>Domain: $($Domain.DNSRoot)</p>
    
    <div class="summary-box">
        <h2>Executive Summary</h2>
        <ul>
            <li>Domain Controllers: $($DomainControllers.Count) (Healthy: $healthyDCs, Warning: $warningDCs, Critical: $criticalDCs)</li>
            <li>Forest Functional Level: $($Forest.ForestMode)</li>
            <li>Domain Functional Level: $($Domain.DomainMode)</li>
            <li>Total Users: $($Users.Count) (Enabled: $(($Users | Where-Object { $_.Enabled }).Count))</li>
            <li>Total Computers: $($Computers.Count) (Servers: $($Servers.Count), Workstations: $($Workstations.Count))</li>
            <li>Total Groups: $($Groups.Count)</li>
            <li>Replication Status: Healthy: $replHealthy, Issues: $($replWarning + $replError)</li>
        </ul>
    </div>
    
    <p>Detailed CSV reports have been saved to: $OutputPath</p>
</body>
</html>
"@

$htmlReport | Out-File "$OutputPath\00_Assessment_Summary_v3_$Timestamp.html" -Encoding UTF8
Write-Host "HTML Summary Report generated: 00_Assessment_Summary_v3_$Timestamp.html" -ForegroundColor Green

# Open folder
explorer $OutputPath
