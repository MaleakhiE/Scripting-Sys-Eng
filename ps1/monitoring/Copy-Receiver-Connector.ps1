param (
    [Parameter(Mandatory = $true)]
    [string]$SourceServer,

    [Parameter(Mandatory = $true)]
    [string]$TargetServer,

    [Parameter(Mandatory = $false)]
    [string]$CsvReportPath = ".\ReceiveConnectorMigrationReport.csv",
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [switch]$AllowBindingModification
)

function Normalize-RemoteIPRanges {
    param ($ranges)
    return ($ranges | ForEach-Object { $_.ToString() } | Sort-Object) -join ','
}

# Ambil semua connector dari source dan target
Write-Host "🔍 Mengambil receive connector dari server sumber: $SourceServer" -ForegroundColor Cyan
$sourceConnectors = Get-ReceiveConnector -Server $SourceServer | Where-Object { $_ -ne $null }
Write-Host "ℹ️ Ditemukan $($sourceConnectors.Count) connector di server sumber" -ForegroundColor Cyan

Write-Host "🔍 Mengambil receive connector dari server target: $TargetServer" -ForegroundColor Cyan
$targetConnectors = Get-ReceiveConnector -Server $TargetServer | Where-Object { $_ -ne $null }
Write-Host "ℹ️ Ditemukan $($targetConnectors.Count) connector di server target" -ForegroundColor Cyan

# Hasil log
$results = @()

Write-Host "n🔄 Memulai proses migrasi connector..." -ForegroundColor Cyan

foreach ($src in $sourceConnectors) {
    try {
        $newConnectorName = $src.Name
        $ipListRaw = ($src.RemoteIPRanges | ForEach-Object { $_.ToString() }) -join '; '
        
        Write-Host "n📋 Memproses connector: $newConnectorName" -ForegroundColor Yellow

        # Cek nama sudah ada
        $existingByName = Get-ReceiveConnector -Server $TargetServer -Identity "$TargetServer\$newConnectorName" -ErrorAction SilentlyContinue
        
        if ($existingByName -and -not $Force) {
            Write-Warning "⚠️ Connector '$newConnectorName' sudah ada di $TargetServer. Melewati (gunakan -Force untuk menimpa)."
            $results += [pscustomobject]@{
                Name                 = $newConnectorName
                Status               = "Skipped"
                Reason               = "Name Exists"
                ConflictingConnector = $existingByName.Name
                RemoteIPRanges       = $ipListRaw
                TargetServer         = $TargetServer
            }
            continue
        }
        elseif ($existingByName -and $Force) {
            Write-Warning "⚠️ Menghapus connector yang sudah ada '$newConnectorName' karena parameter -Force digunakan."
            Remove-ReceiveConnector -Identity "$TargetServer\$newConnectorName" -Confirm:$false
        }

        # Cek konflik Bindings
        $bindings = $src.Bindings
        $bindingConflicts = $false
        $conflictingConnector = ""
        
        foreach ($binding in $bindings) {
            foreach ($targetConn in $targetConnectors) {
                foreach ($targetBinding in $targetConn.Bindings) {
                    # Jika ada IP dan port yang sama
                    if ($binding.ToString() -eq $targetBinding.ToString()) {
                        $bindingConflicts = $true
                        $conflictingConnector = $targetConn.Name
                        break
                    }
                }
                if ($bindingConflicts) { break }
            }
            if ($bindingConflicts) { break }
        }
        
        if ($bindingConflicts -and -not $Force) {
            Write-Warning "⚠️ Binding untuk connector '$newConnectorName' bertabrakan dengan '$conflictingConnector'. Melewati."
            $results += [pscustomobject]@{
                Name                 = $newConnectorName
                Status               = "Skipped" 
                Reason               = "Binding Conflict"
                ConflictingConnector = $conflictingConnector
                RemoteIPRanges       = $ipListRaw
                TargetServer         = $TargetServer
            }
            continue
        }
        elseif ($bindingConflicts -and $Force -and $AllowBindingModification) {
            # Modifikasi binding untuk menghindari konflik
            Write-Warning "⚠️ Memodifikasi bindings untuk menghindari konflik dengan '$conflictingConnector'"
            
            # Daftar port alternatif yang bisa digunakan
            $alternativePorts = @(2525, 2526, 9025, 9026, 25025, 25026, 35025, 35026)
            $modifiedBindings = @()
            
            foreach ($binding in $bindings) {
                $bindingParts = $binding.ToString().Split(':')
                $ipAddress = $bindingParts[0]
                
                # Coba port alternatif
                $portFound = $false
                foreach ($port in $alternativePorts) {
                    $newBinding = "$ipAddress : $port"
                    $hasConflict = $false
                    
                    # Periksa konflik dengan binding yang ada
                    foreach ($targetConn in $targetConnectors) {
                        foreach ($targetBinding in $targetConn.Bindings) {
                            if ($targetBinding.ToString() -eq $newBinding) {
                                $hasConflict = $true
                                break
                            }
                        }
                        if ($hasConflict) { break }
                    }
                    
                    if (-not $hasConflict) {
                        $modifiedBindings += $newBinding
                        $portFound = $true
                        break
                    }
                }
                
                if (-not $portFound) {
                    throw "Tidak dapat menemukan port alternatif yang tidak konflik untuk binding $binding"
                }
            }
            
            # Gunakan bindings yang telah dimodifikasi
            $bindings = $modifiedBindings
        }
        elseif ($bindingConflicts -and $Force -and -not $AllowBindingModification) {
            Write-Warning "⚠️ Melewati connector '$newConnectorName' karena konflik binding dengan '$conflictingConnector'. Tambahkan parameter -AllowBindingModification untuk memodifikasi port secara otomatis."
            $results += [pscustomobject]@{
                Name                 = $newConnectorName
                Status               = "Skipped" 
                Reason               = "Binding Conflict (-AllowBindingModification required)"
                ConflictingConnector = $conflictingConnector
                RemoteIPRanges       = $ipListRaw
                TargetServer         = $TargetServer
            }
            continue
        }

        # Mendapatkan semua properti yang tersedia dari connector sumber
        $properties = $src | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        Write-Host "ℹ️ Mendapatkan $($properties.Count) properti dari connector sumber" -ForegroundColor DarkGray

        # Buat connector baru dengan properti dasar yang diperlukan
        Write-Host "🔧 Membuat connector baru: $newConnectorName" -ForegroundColor DarkCyan
        
        # Validasi nilai Usage karena tidak boleh null
        $usageValue = if ($null -eq $src.Usage -or $src.Usage -eq '') { 'Custom' } else { $src.Usage }
        Write-Host "   🔹 Menggunakan Usage: $usageValue" -ForegroundColor DarkGray
        
        # Buat parameters untuk New-ReceiveConnector
        $newConnectorParams = @{
            Name = $newConnectorName
            Server = $TargetServer
            Bindings = $bindings  # Gunakan bindings asli atau yang sudah dimodifikasi
            RemoteIPRanges = $src.RemoteIPRanges
            Usage = $usageValue
            Comment = "Copied from $SourceServer on $(Get-Date -Format u)"
            ErrorAction = 'Stop'
        }
        
        # Tambahkan parameter Custom jika diperlukan
        if ($src.Custom) {
            $newConnectorParams.Add('Custom', $true)
        }
        
        # Buat connector baru
        $newConnector = New-ReceiveConnector @newConnectorParams

        # Menyalin properti tambahan yang tidak tersedia pada New-ReceiveConnector
        Write-Host "⚙️ Menyalin properti lanjutan..." -ForegroundColor DarkCyan
        
        # Daftar properti yang ingin disalin
        $propertiesToCopy = @(
            'AddressBook', 'AdvertiseClientSettings', 'AuthMechanism', 'Banner', 'BinaryMimeEnabled',
            'ChunkingEnabled', 'DefaultDomain', 'DeliveryStatusNotificationEnabled', 'DomainSecureEnabled',
            'EightBitMimeEnabled', 'EnableAuthGSSAPI', 'Enabled', 'EnhancedStatusCodesEnabled',
            'ExtendedProtectionPolicy', 'Fqdn', 'LongAddressesEnabled', 'MaxAcknowledgementDelay',
            'MaxHeaderSize', 'MaxHopCount', 'MaxInboundConnection', 'MaxInboundConnectionPercentagePerSource',
            'MaxInboundConnectionPerSource', 'MaxLocalHopCount', 'MaxLogonFailures', 'MaxMessageSize',
            'MaxProtocolErrors', 'MaxRecipientsPerMessage', 'MessageRateLimit', 'MessageRateSource',
            'OrarEnabled', 'PermissionGroups', 'PipeliningEnabled', 'ProtocolLoggingLevel',
            'RequireEHLODomain', 'RequireTLS', 'ServiceDiscoveryFqdn', 'SizeEnabled',
            'SuppressXAnonymousTls', 'TarpitInterval', 'TlsCertificateName', 'TlsDomainCapabilities'
        )

        foreach ($property in $propertiesToCopy) {
            if ($src | Get-Member -Name $property -MemberType Properties) {
                try {
                    $propertyValue = $src.$property
                    if ($null -ne $propertyValue) {
                        Write-Host "   🔹 Menyalin properti: $property" -ForegroundColor DarkGray
                        
                        # Gunakan splatting untuk parameter
                        $params = @{
                            Identity = $newConnector.Identity
                            ErrorAction = "SilentlyContinue"
                        }
                        
                        # Tambahkan properti yang akan diset
                        $params.Add($property, $propertyValue)
                        
                        # Jalankan Set-ReceiveConnector dengan parameters
                        Set-ReceiveConnector @params
                    }
                }
                catch {
                    Write-Warning "   ⚠️ Gagal menyalin properti $property : $_"
                }
            }
        }

        # Salin konfigurasi permission
        Write-Host "🔒 Menyalin konfigurasi permission..." -ForegroundColor DarkCyan
        try {
            $permissionLists = Get-ReceiveConnectorPermission -Identity $src.Identity -ErrorAction SilentlyContinue
            
            if ($permissionLists) {
                foreach ($permission in $permissionLists) {
                    try {
                        # Jangan salin inherited permission
                        if (-not $permission.IsInherited) {
                            Write-Host "   🔹 Menyalin permission untuk: $($permission.User)" -ForegroundColor DarkGray
                            
                            # Gunakan splatting untuk parameter
                            $permParams = @{
                                Identity = $newConnector.Identity
                                User = $permission.User
                                AccessRights = $permission.AccessRights
                                ErrorAction = "SilentlyContinue"
                            }
                            
                            # Tambahkan permission
                            Add-ADPermission @permParams
                        }
                    }
                    catch {
                        Write-Warning "   ⚠️ Gagal menyalin permission untuk $($permission.User): $_"
                    }
                }
            } else {
                Write-Host "   ℹ️ Tidak ada permission khusus yang perlu disalin" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Warning "   ⚠️ Gagal mendapatkan permission dari connector sumber: $_"
        }

        $results += [pscustomobject]@{
            Name                 = $newConnectorName
            Status               = "Success"
            Reason               = "Created"
            ConflictingConnector = ""
            RemoteIPRanges       = $ipListRaw
            TargetServer         = $TargetServer
        }

        Write-Host "✅ Berhasil membuat connector: $newConnectorName pada $TargetServer" -ForegroundColor Green

    } catch {
        $results += [pscustomobject]@{
            Name                 = $src.Name
            Status               = "Failed"
            Reason               = $_.Exception.Message
            ConflictingConnector = ""
            RemoteIPRanges       = ($src.RemoteIPRanges | ForEach-Object { $_.ToString() }) -join '; '
            TargetServer         = $TargetServer
        }
        Write-Error "❌ Gagal membuat connector '$($src.Name)' pada $TargetServer : $_"
    }
}

# Simpan laporan
$results | Export-Csv -Path $CsvReportPath -NoTypeInformation -Encoding UTF8
Write-Host "n📄 Laporan tersimpan di: $CsvReportPath" -ForegroundColor Cyan