# ============================================
# Exchange Server Assessment Script
# ============================================
# Script ini memerlukan Exchange Management Shell
# Jalankan dengan hak Administrator di Exchange Server

# Set lokasi output
$OutputPath = "C:\ExchangeAssessment"
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "=== Exchange Server Assessment ===" -ForegroundColor Cyan
Write-Host "Timestamp: $Timestamp" -ForegroundColor Green
Write-Host ""

# Check if Exchange cmdlets are available
try {
    $null = Get-ExchangeServer -ErrorAction Stop
} catch {
    Write-Host "ERROR: Exchange Management Shell tidak tersedia!" -ForegroundColor Red
    Write-Host "Pastikan script dijalankan di Exchange Management Shell" -ForegroundColor Yellow
    Write-Host "Atau jalankan: Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn" -ForegroundColor Yellow
    exit
}

# ============================================
# 1. Informasi Jumlah Exchange Server
# ============================================
Write-Host "[1/14] Mengambil informasi jumlah Exchange Server..." -ForegroundColor Yellow

$ExchangeServers = @(Get-ExchangeServer)
$ExchCounter = 0
$ExchServerInfo = $ExchangeServers | ForEach-Object {
    $ExchCounter++
    [PSCustomObject]@{
        No = $ExchCounter
        Name = $_.Name
        FQDN = $_.Fqdn
        Site = $_.Site.Name
        ServerRole = ($_.ServerRole -join ', ')
        Edition = $_.Edition
        AdminDisplayVersion = $_.AdminDisplayVersion
        IsHubTransportServer = $_.IsHubTransportServer
        IsClientAccessServer = $_.IsClientAccessServer
        IsMailboxServer = $_.IsMailboxServer
        IsEdgeServer = $_.IsEdgeServer
    }
}

$ExchServerInfo | Export-Csv "$OutputPath\01_ExchangeServers_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($ExchangeServers.Count) Exchange Server" -ForegroundColor Green


# ============================================
# 2. Informasi Versi OS dari Exchange Server
# ============================================
Write-Host "[2/14] Mengambil informasi versi OS dari Exchange Server..." -ForegroundColor Yellow

$OSInfo = @()
$OSCounter = 0
foreach ($server in $ExchangeServers) {
    $OSCounter++
    try {
        $os = Get-WmiObject Win32_OperatingSystem -ComputerName $server.Name -ErrorAction Stop
        $lastBoot = $os.ConvertToDateTime($os.LastBootUpTime)
        $uptime = New-TimeSpan -Start $lastBoot -End (Get-Date)
        
        $eolStatus = switch -Wildcard ($os.Caption) {
            "*2012*" { "Extended Support Ended - Upgrade Recommended" }
            "*2016*" { "Mainstream Support" }
            "*2019*" { "Mainstream Support" }
            "*2022*" { "Current" }
            default { "Unknown" }
        }
        
        $OSInfo += [PSCustomObject]@{
            No = $OSCounter
            ServerName = $server.Name
            OperatingSystem = $os.Caption
            Version = $os.Version
            BuildNumber = $os.BuildNumber
            ServicePackMajor = $os.ServicePackMajorVersion
            Architecture = $os.OSArchitecture
            LastBootTime = $lastBoot
            UptimeDays = [math]::Round($uptime.TotalDays, 2)
            SupportStatus = $eolStatus
        }
    } catch {
        $OSInfo += [PSCustomObject]@{
            No = $OSCounter
            ServerName = $server.Name
            OperatingSystem = "Error"
            Version = $_.Exception.Message
            BuildNumber = "-"
            ServicePackMajor = "-"
            Architecture = "-"
            LastBootTime = "-"
            UptimeDays = "-"
            SupportStatus = "Error"
        }
    }
}

$OSInfo | Export-Csv "$OutputPath\02_OS_Versions_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Informasi OS berhasil dikumpulkan" -ForegroundColor Green


# ============================================
# 3. Informasi Versi Exchange Server
# ============================================
Write-Host "[3/14] Mengambil informasi versi Exchange Server..." -ForegroundColor Yellow

$ExchVersionInfo = @()
$VerCounter = 0
foreach ($server in $ExchangeServers) {
    $VerCounter++
    $version = $server.AdminDisplayVersion
    
    # Determine Exchange version and CU
    $exchVersion = switch -Regex ($version.ToString()) {
        "15\.2\." { "Exchange 2019" }
        "15\.1\." { "Exchange 2016" }
        "15\.0\." { "Exchange 2013" }
        "14\." { "Exchange 2010" }
        default { "Unknown" }
    }
    
    # Get build number for CU detection
    $buildNumber = "$($version.Major).$($version.Minor).$($version.Build).$($version.Revision)"
    
    # Check if version is current (simplified check)
    $isCurrentCU = "Check Microsoft documentation for latest CU"
    
    $ExchVersionInfo += [PSCustomObject]@{
        No = $VerCounter
        ServerName = $server.Name
        ExchangeVersion = $exchVersion
        AdminDisplayVersion = $version.ToString()
        BuildNumber = $buildNumber
        MajorVersion = $version.Major
        MinorVersion = $version.Minor
        Build = $version.Build
        Revision = $version.Revision
        Edition = $server.Edition
        Recommendation = $isCurrentCU
    }
}

$ExchVersionInfo | Export-Csv "$OutputPath\03_Exchange_Versions_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Informasi versi Exchange berhasil dikumpulkan" -ForegroundColor Green


# ============================================
# 4. Informasi Update/Patch yang terinstall
# ============================================
Write-Host "[4/14] Mengambil informasi Update/Patch (ini mungkin memakan waktu)..." -ForegroundColor Yellow

$PatchInfo = @()
$PatchCounter = 0
foreach ($server in $ExchangeServers) {
    try {
        $Patches = Get-HotFix -ComputerName $server.Name -ErrorAction Stop | 
                   Sort-Object InstalledOn -Descending |
                   Select-Object -First 15
        
        foreach ($Patch in $Patches) {
            $PatchCounter++
            $PatchInfo += [PSCustomObject]@{
                No = $PatchCounter
                ServerName = $server.Name
                HotFixID = $Patch.HotFixID
                Description = $Patch.Description
                InstalledOn = $Patch.InstalledOn
                InstalledBy = $Patch.InstalledBy
            }
        }
    } catch {
        $PatchCounter++
        $PatchInfo += [PSCustomObject]@{
            No = $PatchCounter
            ServerName = $server.Name
            HotFixID = "Error"
            Description = $_.Exception.Message
            InstalledOn = "-"
            InstalledBy = "-"
        }
    }
}

$PatchInfo | Export-Csv "$OutputPath\04_Patches_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Informasi patch berhasil dikumpulkan" -ForegroundColor Green


# ============================================
# 5. Informasi Utilitas (Disk, Memory, CPU)
# ============================================
Write-Host "[5/14] Mengambil informasi Utilitas (Disk, Memory, CPU)..." -ForegroundColor Yellow

$UtilitasInfo = @()
$UtilCounter = 0
foreach ($server in $ExchangeServers) {
    try {
        # Disk Info
        $Disks = Get-WmiObject Win32_LogicalDisk -ComputerName $server.Name -Filter "DriveType=3" -ErrorAction Stop
        
        # Memory Info
        $Memory = Get-WmiObject Win32_ComputerSystem -ComputerName $server.Name -ErrorAction Stop
        $MemoryGB = [math]::Round($Memory.TotalPhysicalMemory / 1GB, 2)
        
        # Available Memory
        $AvailMem = Get-WmiObject Win32_OperatingSystem -ComputerName $server.Name -ErrorAction Stop
        $AvailMemGB = [math]::Round($AvailMem.FreePhysicalMemory / 1MB, 2)
        $MemUsedPercent = [math]::Round((($MemoryGB - $AvailMemGB) / $MemoryGB) * 100, 2)
        
        # CPU Info
        $CPU = Get-WmiObject Win32_Processor -ComputerName $server.Name -ErrorAction Stop | Select-Object -First 1
        
        foreach ($Disk in $Disks) {
            $UtilCounter++
            $percentFree = [math]::Round(($Disk.FreeSpace / $Disk.Size) * 100, 2)
            $diskStatus = if ($percentFree -lt 10) { "CRITICAL" } elseif ($percentFree -lt 20) { "WARNING" } else { "OK" }
            
            $UtilitasInfo += [PSCustomObject]@{
                No = $UtilCounter
                ServerName = $server.Name
                DriveLetter = $Disk.DeviceID
                VolumeName = $Disk.VolumeName
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
            }
        }
    } catch {
        $UtilCounter++
        $UtilitasInfo += [PSCustomObject]@{
            No = $UtilCounter
            ServerName = $server.Name
            DriveLetter = "Error"
            VolumeName = "-"
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
        }
    }
}

$UtilitasInfo | Export-Csv "$OutputPath\05_Utilitas_Resources_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Informasi utilitas berhasil dikumpulkan" -ForegroundColor Green


# ============================================
# 6. Informasi Database di setiap Exchange Server
# ============================================
Write-Host "[6/14] Mengambil informasi Database..." -ForegroundColor Yellow

$Databases = @(Get-MailboxDatabase -Status)
$DBCounter = 0
$DBInfo = $Databases | ForEach-Object {
    $DBCounter++
    $db = $_
    $dbSize = $null
    $whiteSpace = $null
    
    try {
        $dbSize = $db.DatabaseSize
        $whiteSpace = $db.AvailableNewMailboxSpace
    } catch {}
    
    [PSCustomObject]@{
        No = $DBCounter
        DatabaseName = $db.Name
        Server = $db.Server.Name
        EdbFilePath = $db.EdbFilePath
        LogFolderPath = $db.LogFolderPath
        DatabaseSizeGB = if ($dbSize) { 
            try { 
                if ($dbSize.Value) { [math]::Round($dbSize.Value.ToBytes() / 1GB, 2) }
                elseif ($dbSize -is [Microsoft.Exchange.Data.ByteQuantifiedSize]) { [math]::Round($dbSize.ToBytes() / 1GB, 2) }
                else { [math]::Round([int64]$dbSize.ToString().Split('(')[1].Split(' ')[0].Replace(',','') / 1GB, 2) }
            } catch { "N/A" }
        } else { "N/A" }
        AvailableWhiteSpaceGB = if ($whiteSpace) { 
            try { 
                if ($whiteSpace.Value) { [math]::Round($whiteSpace.Value.ToBytes() / 1GB, 2) }
                elseif ($whiteSpace -is [Microsoft.Exchange.Data.ByteQuantifiedSize]) { [math]::Round($whiteSpace.ToBytes() / 1GB, 2) }
                else { [math]::Round([int64]$whiteSpace.ToString().Split('(')[1].Split(' ')[0].Replace(',','') / 1GB, 2) }
            } catch { "N/A" }
        } else { "N/A" }
        MailboxCount = (Get-Mailbox -Database $db.Name -ResultSize Unlimited -ErrorAction SilentlyContinue).Count
        Mounted = $db.Mounted
        MasterType = $db.MasterType
        Recovery = $db.Recovery
        CircularLoggingEnabled = $db.CircularLoggingEnabled
        DeletedItemRetention = $db.DeletedItemRetention.Days
        MailboxRetention = $db.MailboxRetention.Days
        ProhibitSendQuota = $db.ProhibitSendQuota
        ProhibitSendReceiveQuota = $db.ProhibitSendReceiveQuota
        IssueWarningQuota = $db.IssueWarningQuota
        LastFullBackup = $db.LastFullBackup
        LastIncrementalBackup = $db.LastIncrementalBackup
        BackupInProgress = $db.BackupInProgress
    }
}

$DBInfo | Export-Csv "$OutputPath\06_Databases_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Databases.Count) Database" -ForegroundColor Green

# Public Folder Databases (if exists)
try {
    $PFDatabases = @(Get-PublicFolderDatabase -Status -ErrorAction SilentlyContinue)
    if ($PFDatabases.Count -gt 0) {
        $PFDBCounter = 0
        $PFDBInfo = $PFDatabases | ForEach-Object {
            $PFDBCounter++
            [PSCustomObject]@{
                No = $PFDBCounter
                DatabaseName = $_.Name
                Server = $_.Server.Name
                EdbFilePath = $_.EdbFilePath
                Mounted = $_.Mounted
                LastFullBackup = $_.LastFullBackup
            }
        }
        $PFDBInfo | Export-Csv "$OutputPath\06b_PublicFolderDatabases_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
        Write-Host "   Ditemukan $($PFDatabases.Count) Public Folder Database" -ForegroundColor Green
    }
} catch {}


# ============================================
# 7. Informasi DAG (Status, Replikasi dan Witness)
# ============================================
Write-Host "[7/14] Mengambil informasi DAG..." -ForegroundColor Yellow

$DAGs = @(Get-DatabaseAvailabilityGroup -Status -ErrorAction SilentlyContinue)
$DAGInfo = @()
$DAGCounter = 0

if ($DAGs.Count -gt 0) {
    foreach ($dag in $DAGs) {
        $DAGCounter++
        $DAGInfo += [PSCustomObject]@{
            No = $DAGCounter
            DAGName = $dag.Name
            WitnessServer = $dag.WitnessServer
            WitnessDirectory = $dag.WitnessDirectory
            AlternateWitnessServer = $dag.AlternateWitnessServer
            AlternateWitnessDirectory = $dag.AlternateWitnessDirectory
            PrimaryActiveManager = $dag.PrimaryActiveManager
            Servers = ($dag.Servers.Name -join '; ')
            ServerCount = $dag.Servers.Count
            OperationalServers = ($dag.OperationalServers.Name -join '; ')
            OperationalServerCount = $dag.OperationalServers.Count
            DatabaseAvailabilityGroupIpv4Addresses = ($dag.DatabaseAvailabilityGroupIpv4Addresses -join '; ')
            DatacenterActivationMode = $dag.DatacenterActivationMode
            WitnessShareInUse = $dag.WitnessShareInUse
            ReplicationPort = $dag.ReplicationPort
            NetworkCompression = $dag.NetworkCompression
            NetworkEncryption = $dag.NetworkEncryption
        }
    }
    
    $DAGInfo | Export-Csv "$OutputPath\07a_DAG_Configuration_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($DAGs.Count) DAG" -ForegroundColor Green
    
    # DAG Database Copy Status
    Write-Host "   Mengambil status replikasi database..." -ForegroundColor Gray
    $DBCopyStatus = @()
    $CopyCounter = 0
    
    foreach ($db in $Databases) {
        try {
            $copies = Get-MailboxDatabaseCopyStatus $db.Name -ErrorAction SilentlyContinue
            foreach ($copy in $copies) {
                $CopyCounter++
                $DBCopyStatus += [PSCustomObject]@{
                    No = $CopyCounter
                    DatabaseName = $copy.DatabaseName
                    MailboxServer = $copy.MailboxServer
                    Status = $copy.Status
                    CopyQueueLength = $copy.CopyQueueLength
                    ReplayQueueLength = $copy.ReplayQueueLength
                    ContentIndexState = $copy.ContentIndexState
                    ContentIndexErrorMessage = $copy.ContentIndexErrorMessage
                    LastInspectedLogTime = $copy.LastInspectedLogTime
                    LatestAvailableLogTime = $copy.LatestAvailableLogTime
                    ActivationPreference = $copy.ActivationPreference
                    ActiveCopy = $copy.ActiveCopy
                    HealthStatus = if ($copy.Status -eq "Mounted" -or $copy.Status -eq "Healthy") { "OK" } else { "CHECK" }
                }
            }
        } catch {}
    }
    
    if ($DBCopyStatus.Count -gt 0) {
        $DBCopyStatus | Export-Csv "$OutputPath\07b_DAG_DatabaseCopyStatus_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
        Write-Host "   Ditemukan $($DBCopyStatus.Count) Database Copy entries" -ForegroundColor Green
    }
} else {
    Write-Host "   Tidak ada DAG yang dikonfigurasi (Standalone)" -ForegroundColor Yellow
}


# ============================================
# 8. Informasi Hybrid Config
# ============================================
Write-Host "[8/14] Mengambil informasi Hybrid Configuration..." -ForegroundColor Yellow

$HybridInfo = @()
try {
    $HybridConfig = Get-HybridConfiguration -ErrorAction SilentlyContinue
    if ($HybridConfig) {
        $HybridInfo += [PSCustomObject]@{
            No = 1
            ConfigType = "Hybrid Configuration"
            Domains = ($HybridConfig.Domains -join '; ')
            OnPremisesSmartHost = $HybridConfig.OnPremisesSmartHost
            ReceivingTransportServers = ($HybridConfig.ReceivingTransportServers.Name -join '; ')
            SendingTransportServers = ($HybridConfig.SendingTransportServers.Name -join '; ')
            EdgeTransportServers = ($HybridConfig.EdgeTransportServers.Name -join '; ')
            TlsCertificateName = $HybridConfig.TlsCertificateName
            Features = ($HybridConfig.Features -join '; ')
            ServiceInstance = $HybridConfig.ServiceInstance
            ExternalIPAddresses = ($HybridConfig.ExternalIPAddresses -join '; ')
        }
        
        $HybridInfo | Export-Csv "$OutputPath\08_Hybrid_Configuration_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
        Write-Host "   Hybrid Configuration ditemukan" -ForegroundColor Green
        
        # Get OAuth Configuration
        try {
            $IntraOrgConnector = Get-IntraOrganizationConnector -ErrorAction SilentlyContinue
            if ($IntraOrgConnector) {
                $IOCCounter = 0
                $IOCInfo = $IntraOrgConnector | ForEach-Object {
                    $IOCCounter++
                    [PSCustomObject]@{
                        No = $IOCCounter
                        Name = $_.Name
                        TargetAddressDomains = ($_.TargetAddressDomains -join '; ')
                        DiscoveryEndpoint = $_.DiscoveryEndpoint
                        Enabled = $_.Enabled
                    }
                }
                $IOCInfo | Export-Csv "$OutputPath\08b_IntraOrgConnector_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
            }
        } catch {}
        
    } else {
        Write-Host "   Tidak ada Hybrid Configuration (On-Premises only)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   Tidak dapat mengambil Hybrid Configuration" -ForegroundColor Yellow
}


# ============================================
# 9. Informasi Email Pengguna (Mailbox)
# ============================================
Write-Host "[9/14] Mengambil informasi Mailbox (ini mungkin memakan waktu)..." -ForegroundColor Yellow

$Mailboxes = @(Get-Mailbox -ResultSize Unlimited)
$MBCounter = 0
$MailboxInfo = $Mailboxes | ForEach-Object {
    $MBCounter++
    $mb = $_
    $stats = $null
    try {
        $stats = Get-MailboxStatistics $mb.Identity -ErrorAction SilentlyContinue
    } catch {}
    
    [PSCustomObject]@{
        No = $MBCounter
        DisplayName = $mb.DisplayName
        Alias = $mb.Alias
        PrimarySmtpAddress = $mb.PrimarySmtpAddress
        RecipientType = $mb.RecipientTypeDetails
        Database = $mb.Database.Name
        ServerName = $mb.ServerName
        OrganizationalUnit = $mb.OrganizationalUnit
        IsMailboxEnabled = $mb.IsMailboxEnabled
        ProhibitSendQuota = $mb.ProhibitSendQuota
        ProhibitSendReceiveQuota = $mb.ProhibitSendReceiveQuota
        IssueWarningQuota = $mb.IssueWarningQuota
        TotalItemSizeMB = if ($stats -and $stats.TotalItemSize) { 
            try { 
                if ($stats.TotalItemSize.Value) { [math]::Round($stats.TotalItemSize.Value.ToBytes() / 1MB, 2) }
                else { [math]::Round([int64]$stats.TotalItemSize.ToString().Split('(')[1].Split(' ')[0].Replace(',','') / 1MB, 2) }
            } catch { "N/A" }
        } else { "N/A" }
        ItemCount = if ($stats) { $stats.ItemCount } else { "N/A" }
        LastLogonTime = if ($stats) { $stats.LastLogonTime } else { "N/A" }
        LastLogoffTime = if ($stats) { $stats.LastLogoffTime } else { "N/A" }
        ArchiveStatus = $mb.ArchiveStatus
        ArchiveDatabase = $mb.ArchiveDatabase
        LitigationHoldEnabled = $mb.LitigationHoldEnabled
        RetentionPolicy = $mb.RetentionPolicy
        AddressBookPolicy = $mb.AddressBookPolicy
        WhenCreated = $mb.WhenCreated
        WhenMailboxCreated = $mb.WhenMailboxCreated
    }
}

$MailboxInfo | Export-Csv "$OutputPath\09a_Mailboxes_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($Mailboxes.Count) Mailbox" -ForegroundColor Green

# Mailbox Statistics Summary
$MBStats = [PSCustomObject]@{
    TotalMailboxes = $Mailboxes.Count
    UserMailboxes = ($Mailboxes | Where-Object { $_.RecipientTypeDetails -eq "UserMailbox" }).Count
    SharedMailboxes = ($Mailboxes | Where-Object { $_.RecipientTypeDetails -eq "SharedMailbox" }).Count
    RoomMailboxes = ($Mailboxes | Where-Object { $_.RecipientTypeDetails -eq "RoomMailbox" }).Count
    EquipmentMailboxes = ($Mailboxes | Where-Object { $_.RecipientTypeDetails -eq "EquipmentMailbox" }).Count
    DiscoveryMailboxes = ($Mailboxes | Where-Object { $_.RecipientTypeDetails -eq "DiscoveryMailbox" }).Count
    ArchivedMailboxes = ($Mailboxes | Where-Object { $_.ArchiveStatus -eq "Active" }).Count
    LitigationHoldEnabled = ($Mailboxes | Where-Object { $_.LitigationHoldEnabled }).Count
}
$MBStats | Export-Csv "$OutputPath\09b_Mailbox_Statistics_$Timestamp.csv" -NoTypeInformation -Encoding UTF8


# ============================================
# 10. Informasi Domain (Accepted Domain)
# ============================================
Write-Host "[10/14] Mengambil informasi Accepted Domain..." -ForegroundColor Yellow

$AcceptedDomains = @(Get-AcceptedDomain)
$ADCounter = 0
$AcceptedDomainInfo = $AcceptedDomains | ForEach-Object {
    $ADCounter++
    [PSCustomObject]@{
        No = $ADCounter
        DomainName = $_.DomainName
        Name = $_.Name
        DomainType = $_.DomainType
        Default = $_.Default
        AddressBookEnabled = $_.AddressBookEnabled
        MatchSubDomains = $_.MatchSubDomains
        AuthenticationType = $_.AuthenticationType
        LiveIdInstanceType = $_.LiveIdInstanceType
        PendingRemoval = $_.PendingRemoval
    }
}

$AcceptedDomainInfo | Export-Csv "$OutputPath\10_Accepted_Domains_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($AcceptedDomains.Count) Accepted Domain" -ForegroundColor Green

# Email Address Policies
$EmailPolicies = @(Get-EmailAddressPolicy)
$EPCounter = 0
$EmailPolicyInfo = $EmailPolicies | ForEach-Object {
    $EPCounter++
    [PSCustomObject]@{
        No = $EPCounter
        Name = $_.Name
        Priority = $_.Priority
        EnabledEmailAddressTemplates = ($_.EnabledEmailAddressTemplates -join '; ')
        RecipientFilter = $_.RecipientFilter
        RecipientFilterApplied = $_.RecipientFilterApplied
        IsValid = $_.IsValid
    }
}
$EmailPolicyInfo | Export-Csv "$OutputPath\10b_Email_Address_Policies_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($EmailPolicies.Count) Email Address Policy" -ForegroundColor Green


# ============================================
# 11. Informasi Status Sertifikat (SSL/TLS)
# ============================================
Write-Host "[11/14] Mengambil informasi Sertifikat SSL/TLS..." -ForegroundColor Yellow

$CertInfo = @()
$CertCounter = 0
foreach ($server in $ExchangeServers) {
    try {
        $certs = Get-ExchangeCertificate -Server $server.Name -ErrorAction Stop
        foreach ($cert in $certs) {
            $CertCounter++
            $daysToExpiry = if ($cert.NotAfter) { (New-TimeSpan -Start (Get-Date) -End $cert.NotAfter).Days } else { "N/A" }
            $expiryStatus = if ($daysToExpiry -eq "N/A") { "Unknown" }
                           elseif ($daysToExpiry -lt 0) { "EXPIRED" }
                           elseif ($daysToExpiry -lt 30) { "CRITICAL - Expiring Soon" }
                           elseif ($daysToExpiry -lt 60) { "WARNING - Expiring" }
                           else { "OK" }
            
            $CertInfo += [PSCustomObject]@{
                No = $CertCounter
                ServerName = $server.Name
                Subject = $cert.Subject
                FriendlyName = $cert.FriendlyName
                Thumbprint = $cert.Thumbprint
                NotBefore = $cert.NotBefore
                NotAfter = $cert.NotAfter
                DaysToExpiry = $daysToExpiry
                ExpiryStatus = $expiryStatus
                Services = ($cert.Services -join ', ')
                IsSelfSigned = $cert.IsSelfSigned
                Status = $cert.Status
                Issuer = $cert.Issuer
                CertificateDomains = ($cert.CertificateDomains -join '; ')
                HasPrivateKey = $cert.HasPrivateKey
            }
        }
    } catch {
        $CertCounter++
        $CertInfo += [PSCustomObject]@{
            No = $CertCounter
            ServerName = $server.Name
            Subject = "Error"
            FriendlyName = $_.Exception.Message
            Thumbprint = "-"
            NotBefore = "-"
            NotAfter = "-"
            DaysToExpiry = "-"
            ExpiryStatus = "Error"
            Services = "-"
            IsSelfSigned = "-"
            Status = "-"
            Issuer = "-"
            CertificateDomains = "-"
            HasPrivateKey = "-"
        }
    }
}

$CertInfo | Export-Csv "$OutputPath\11_Certificates_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($CertInfo.Count) Certificate entries" -ForegroundColor Green


# ============================================
# 12. Informasi Relay (SMTP Relay)
# ============================================
Write-Host "[12/14] Mengambil informasi SMTP Relay..." -ForegroundColor Yellow

# Get Receive Connectors with Relay settings
$RelayInfo = @()
$RelayCounter = 0

$ReceiveConnectors = @(Get-ReceiveConnector)
foreach ($connector in $ReceiveConnectors) {
    # Check if connector allows relay
    $isRelay = $false
    $relayType = "None"
    
    if ($connector.PermissionGroups -match "Anonymous") {
        $isRelay = $true
        $relayType = "Anonymous Relay"
    }
    if ($connector.AuthMechanism -match "ExternalAuthoritative") {
        $isRelay = $true
        $relayType = "External Authoritative"
    }
    
    $RelayCounter++
    $RelayInfo += [PSCustomObject]@{
        No = $RelayCounter
        ConnectorName = $connector.Name
        Server = $connector.Server.Name
        Enabled = $connector.Enabled
        Bindings = ($connector.Bindings -join '; ')
        RemoteIPRanges = ($connector.RemoteIPRanges -join '; ')
        PermissionGroups = ($connector.PermissionGroups -join ', ')
        AuthMechanism = ($connector.AuthMechanism -join ', ')
        IsRelayConnector = $isRelay
        RelayType = $relayType
        MaxMessageSize = $connector.MaxMessageSize
        MaxRecipientsPerMessage = $connector.MaxRecipientsPerMessage
        RequireTLS = $connector.RequireTLS
        TlsDomainCapabilities = ($connector.TlsDomainCapabilities -join '; ')
    }
}

$RelayInfo | Export-Csv "$OutputPath\12_SMTP_Relay_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($RelayInfo.Count) Connector dengan info relay" -ForegroundColor Green


# ============================================
# 13. Informasi Send dan Receive Connector
# ============================================
Write-Host "[13/14] Mengambil informasi Send dan Receive Connector..." -ForegroundColor Yellow

# Receive Connectors
$RCCounter = 0
$ReceiveConnectorInfo = $ReceiveConnectors | ForEach-Object {
    $RCCounter++
    [PSCustomObject]@{
        No = $RCCounter
        Name = $_.Name
        Server = $_.Server.Name
        TransportRole = $_.TransportRole
        Enabled = $_.Enabled
        Bindings = ($_.Bindings -join '; ')
        RemoteIPRanges = ($_.RemoteIPRanges -join '; ')
        PermissionGroups = ($_.PermissionGroups -join ', ')
        AuthMechanism = ($_.AuthMechanism -join ', ')
        Banner = $_.Banner
        MaxMessageSize = $_.MaxMessageSize
        MaxRecipientsPerMessage = $_.MaxRecipientsPerMessage
        MaxInboundConnectionPerSource = $_.MaxInboundConnectionPerSource
        MaxInboundConnection = $_.MaxInboundConnection
        ConnectionTimeout = $_.ConnectionTimeout
        ConnectionInactivityTimeout = $_.ConnectionInactivityTimeout
        RequireTLS = $_.RequireTLS
        RequireEHLODomain = $_.RequireEHLODomain
        ProtocolLoggingLevel = $_.ProtocolLoggingLevel
        Fqdn = $_.Fqdn
    }
}

$ReceiveConnectorInfo | Export-Csv "$OutputPath\13a_Receive_Connectors_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($ReceiveConnectors.Count) Receive Connector" -ForegroundColor Green

# Send Connectors
$SendConnectors = @(Get-SendConnector)
$SCCounter = 0
$SendConnectorInfo = $SendConnectors | ForEach-Object {
    $SCCounter++
    [PSCustomObject]@{
        No = $SCCounter
        Name = $_.Name
        Enabled = $_.Enabled
        AddressSpaces = ($_.AddressSpaces -join '; ')
        SourceTransportServers = ($_.SourceTransportServers.Name -join '; ')
        SmartHosts = ($_.SmartHosts -join '; ')
        SmartHostAuthMechanism = $_.SmartHostAuthMechanism
        DNSRoutingEnabled = $_.DNSRoutingEnabled
        MaxMessageSize = $_.MaxMessageSize
        ProtocolLoggingLevel = $_.ProtocolLoggingLevel
        RequireTLS = $_.RequireTLS
        TlsAuthLevel = $_.TlsAuthLevel
        TlsDomain = $_.TlsDomain
        DomainSecureEnabled = $_.DomainSecureEnabled
        IgnoreSTARTTLS = $_.IgnoreSTARTTLS
        CloudServicesMailEnabled = $_.CloudServicesMailEnabled
        Fqdn = $_.Fqdn
        ConnectionInactivityTimeout = $_.ConnectionInactivityTimeout
        IsSmtpConnector = $_.IsSmtpConnector
    }
}

$SendConnectorInfo | Export-Csv "$OutputPath\13b_Send_Connectors_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($SendConnectors.Count) Send Connector" -ForegroundColor Green


# ============================================
# 14. Cek Alur Email (Send and Receive) Internal dan External
# ============================================
Write-Host "[14/14] Mengambil informasi Mail Flow dan Transport Rules..." -ForegroundColor Yellow

# Transport Configuration
$TransportConfig = Get-TransportConfig
$TransportConfigInfo = [PSCustomObject]@{
    MaxSendSize = $TransportConfig.MaxSendSize
    MaxReceiveSize = $TransportConfig.MaxReceiveSize
    InternalSMTPServers = ($TransportConfig.InternalSMTPServers -join '; ')
    ExternalPostmasterAddress = $TransportConfig.ExternalPostmasterAddress
    JournalingReportNdrTo = $TransportConfig.JournalingReportNdrTo
    TLSSendDomainSecureList = ($TransportConfig.TLSSendDomainSecureList -join '; ')
    TLSReceiveDomainSecureList = ($TransportConfig.TLSReceiveDomainSecureList -join '; ')
    ShadowRedundancyEnabled = $TransportConfig.ShadowRedundancyEnabled
    SafetyNetHoldTime = $TransportConfig.SafetyNetHoldTime
}
$TransportConfigInfo | Export-Csv "$OutputPath\14a_Transport_Configuration_$Timestamp.csv" -NoTypeInformation -Encoding UTF8

# Transport Rules
$TransportRules = @(Get-TransportRule)
$TRCounter = 0
$TransportRuleInfo = $TransportRules | ForEach-Object {
    $TRCounter++
    [PSCustomObject]@{
        No = $TRCounter
        Name = $_.Name
        State = $_.State
        Priority = $_.Priority
        Mode = $_.Mode
        Comments = $_.Comments
        Conditions = ($_.Conditions | ForEach-Object { $_.ToString() }) -join '; '
        Actions = ($_.Actions | ForEach-Object { $_.ToString() }) -join '; '
        Exceptions = ($_.Exceptions | ForEach-Object { $_.ToString() }) -join '; '
        SentToScope = $_.SentToScope
        FromScope = $_.FromScope
        WhenChanged = $_.WhenChanged
    }
}

if ($TransportRules.Count -gt 0) {
    $TransportRuleInfo | Export-Csv "$OutputPath\14b_Transport_Rules_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($TransportRules.Count) Transport Rule" -ForegroundColor Green
}

# Remote Domains
$RemoteDomains = @(Get-RemoteDomain)
$RDCounter = 0
$RemoteDomainInfo = $RemoteDomains | ForEach-Object {
    $RDCounter++
    [PSCustomObject]@{
        No = $RDCounter
        Name = $_.Name
        DomainName = $_.DomainName
        IsInternal = $_.IsInternal
        AllowedOOFType = $_.AllowedOOFType
        AutoReplyEnabled = $_.AutoReplyEnabled
        AutoForwardEnabled = $_.AutoForwardEnabled
        DeliveryReportEnabled = $_.DeliveryReportEnabled
        NDREnabled = $_.NDREnabled
        TNEFEnabled = $_.TNEFEnabled
        CharacterSet = $_.CharacterSet
        ContentType = $_.ContentType
        TrustedMailOutboundEnabled = $_.TrustedMailOutboundEnabled
        TrustedMailInboundEnabled = $_.TrustedMailInboundEnabled
    }
}

$RemoteDomainInfo | Export-Csv "$OutputPath\14c_Remote_Domains_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Ditemukan $($RemoteDomains.Count) Remote Domain" -ForegroundColor Green


# Mail Flow Test Summary
Write-Host "   Mengambil informasi Mail Flow..." -ForegroundColor Gray

$MailFlowInfo = @()
$MFCounter = 0

# Internal Mail Flow (between Exchange servers)
foreach ($server in $ExchangeServers) {
    $MFCounter++
    $MailFlowInfo += [PSCustomObject]@{
        No = $MFCounter
        FlowType = "Internal"
        Direction = "Inbound/Outbound"
        Server = $server.Name
        Connector = "Internal Transport"
        Description = "Mail flow between Exchange servers in organization"
        SmartHost = "N/A (Direct)"
        AddressSpace = "Internal"
    }
}

# External Mail Flow (Send Connectors)
foreach ($sc in $SendConnectors) {
    $MFCounter++
    $flowType = if ($sc.AddressSpaces -match "\*") { "External - Internet" } else { "External - Specific Domain" }
    $MailFlowInfo += [PSCustomObject]@{
        No = $MFCounter
        FlowType = $flowType
        Direction = "Outbound"
        Server = ($sc.SourceTransportServers.Name -join ', ')
        Connector = $sc.Name
        Description = "Outbound mail to: $($sc.AddressSpaces -join ', ')"
        SmartHost = if ($sc.SmartHosts) { $sc.SmartHosts -join ', ' } else { "DNS Routing" }
        AddressSpace = ($sc.AddressSpaces -join ', ')
    }
}

# External Mail Flow (Receive Connectors for external)
foreach ($rc in $ReceiveConnectors) {
    if ($rc.PermissionGroups -match "Anonymous" -or $rc.TransportRole -eq "FrontendTransport") {
        $MFCounter++
        $MailFlowInfo += [PSCustomObject]@{
            No = $MFCounter
            FlowType = "External - Internet"
            Direction = "Inbound"
            Server = $rc.Server.Name
            Connector = $rc.Name
            Description = "Inbound mail from external sources"
            SmartHost = "N/A"
            AddressSpace = ($rc.RemoteIPRanges -join ', ')
        }
    }
}

$MailFlowInfo | Export-Csv "$OutputPath\14d_Mail_Flow_Summary_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
Write-Host "   Mail Flow summary berhasil dikumpulkan" -ForegroundColor Green

# Queue Status
Write-Host "   Mengambil status Queue..." -ForegroundColor Gray
$QueueInfo = @()
$QCounter = 0
foreach ($server in $ExchangeServers) {
    try {
        $queues = Get-Queue -Server $server.Name -ErrorAction SilentlyContinue
        foreach ($q in $queues) {
            $QCounter++
            $QueueInfo += [PSCustomObject]@{
                No = $QCounter
                Server = $server.Name
                Identity = $q.Identity
                DeliveryType = $q.DeliveryType
                Status = $q.Status
                MessageCount = $q.MessageCount
                NextHopDomain = $q.NextHopDomain
                LastError = $q.LastError
            }
        }
    } catch {}
}

if ($QueueInfo.Count -gt 0) {
    $QueueInfo | Export-Csv "$OutputPath\14e_Queue_Status_$Timestamp.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "   Ditemukan $($QueueInfo.Count) Queue entries" -ForegroundColor Green
}


# ============================================
# Summary Report
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "     EXCHANGE SERVER ASSESSMENT SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "INFRASTRUCTURE:" -ForegroundColor Yellow
Write-Host "  Exchange Servers      : $($ExchangeServers.Count)" -ForegroundColor White
Write-Host "  DAG Configured        : $(if ($DAGs.Count -gt 0) { 'Yes (' + $DAGs.Count + ' DAG)' } else { 'No (Standalone)' })" -ForegroundColor White
Write-Host "  Databases             : $($Databases.Count)" -ForegroundColor White
Write-Host ""
Write-Host "MAILBOXES:" -ForegroundColor Yellow
Write-Host "  Total Mailboxes       : $($Mailboxes.Count)" -ForegroundColor White
Write-Host "  User Mailboxes        : $(($Mailboxes | Where-Object { $_.RecipientTypeDetails -eq 'UserMailbox' }).Count)" -ForegroundColor White
Write-Host "  Shared Mailboxes      : $(($Mailboxes | Where-Object { $_.RecipientTypeDetails -eq 'SharedMailbox' }).Count)" -ForegroundColor White
Write-Host "  Room Mailboxes        : $(($Mailboxes | Where-Object { $_.RecipientTypeDetails -eq 'RoomMailbox' }).Count)" -ForegroundColor White
Write-Host ""
Write-Host "MAIL FLOW:" -ForegroundColor Yellow
Write-Host "  Accepted Domains      : $($AcceptedDomains.Count)" -ForegroundColor White
Write-Host "  Send Connectors       : $($SendConnectors.Count)" -ForegroundColor White
Write-Host "  Receive Connectors    : $($ReceiveConnectors.Count)" -ForegroundColor White
Write-Host "  Transport Rules       : $($TransportRules.Count)" -ForegroundColor White
Write-Host ""
Write-Host "CERTIFICATES:" -ForegroundColor Yellow
$expiredCerts = ($CertInfo | Where-Object { $_.ExpiryStatus -eq "EXPIRED" }).Count
$expiringCerts = ($CertInfo | Where-Object { $_.ExpiryStatus -like "*Expiring*" }).Count
Write-Host "  Total Certificates    : $($CertInfo.Count)" -ForegroundColor White
if ($expiredCerts -gt 0) {
    Write-Host "  EXPIRED               : $expiredCerts" -ForegroundColor Red
}
if ($expiringCerts -gt 0) {
    Write-Host "  Expiring Soon         : $expiringCerts" -ForegroundColor Yellow
}
Write-Host ""

# DAG Health Summary
if ($DAGs.Count -gt 0 -and $DBCopyStatus.Count -gt 0) {
    Write-Host "DAG HEALTH:" -ForegroundColor Yellow
    $healthyCopies = ($DBCopyStatus | Where-Object { $_.HealthStatus -eq "OK" }).Count
    $unhealthyCopies = ($DBCopyStatus | Where-Object { $_.HealthStatus -eq "CHECK" }).Count
    Write-Host "  Healthy DB Copies     : $healthyCopies" -ForegroundColor Green
    if ($unhealthyCopies -gt 0) {
        Write-Host "  Unhealthy DB Copies   : $unhealthyCopies" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "HYBRID:" -ForegroundColor Yellow
Write-Host "  Hybrid Configured     : $(if ($HybridInfo.Count -gt 0) { 'Yes' } else { 'No' })" -ForegroundColor White
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
    <title>Exchange Assessment Report - $Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        h2 { color: #34495e; border-bottom: 2px solid #e74c3c; padding-bottom: 5px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #e74c3c; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .healthy { color: green; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        .critical { color: red; font-weight: bold; }
        .summary-box { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h1>Exchange Server Assessment Report</h1>
    <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    
    <div class="summary-box">
        <h2>Executive Summary</h2>
        <ul>
            <li>Exchange Servers: $($ExchangeServers.Count)</li>
            <li>DAG: $(if ($DAGs.Count -gt 0) { $DAGs.Count.ToString() + ' configured' } else { 'Not configured (Standalone)' })</li>
            <li>Databases: $($Databases.Count)</li>
            <li>Total Mailboxes: $($Mailboxes.Count)</li>
            <li>Accepted Domains: $($AcceptedDomains.Count)</li>
            <li>Hybrid: $(if ($HybridInfo.Count -gt 0) { 'Configured' } else { 'Not configured' })</li>
            <li>Certificates Expiring: $expiringCerts | Expired: $expiredCerts</li>
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
