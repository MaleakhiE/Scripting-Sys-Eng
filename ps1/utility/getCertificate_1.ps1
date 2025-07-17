$outputFile = "C:\Temp\AllCertificates.csv"

function Get-CertificatesFromStore {
    param (
        [string]$StoreName,
        [string]$StoreLocation
    )
    
    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, $StoreLocation)
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
        
        $certs = $store.Certificates | ForEach-Object {
            [PSCustomObject]@{
                Subject = $_.Subject
                Issuer = $_.Issuer
                Thumbprint = $_.Thumbprint
                NotBefore = $_.NotBefore
                NotAfter = $_.NotAfter
                SerialNumber = $_.SerialNumber
                FriendlyName = if ($_.FriendlyName) { $_.FriendlyName } else { "N/A" }
                Store = $StoreName
                Location = $StoreLocation
                Source = "CertificateStore"
                Path = "cert:\$StoreLocation\$StoreName\$($_.Thumbprint)"
            }
        }
        
        $store.Close()
        return $certs
    }
    catch {
        Write-Warning "Gagal mengakses sertifikat di $StoreLocation\$StoreName : $_"
        return @()
    }
}

# Fungsi untuk mengambil sertifikat dari file
function Get-CertificatesFromFiles {
    param (
        [string[]]$FileExtensions = @("*.cer", "*.crt", "*.pem", "*.pfx", "*.p12"),
        [string[]]$FoldersToSearch
    )
    
    $results = @()
    
    foreach ($folder in $FoldersToSearch) {
        if (Test-Path $folder) {
            foreach ($ext in $FileExtensions) {
                try {
                    $files = Get-ChildItem -Path $folder -Filter $ext -Recurse -ErrorAction SilentlyContinue
                    
                    foreach ($file in $files) {
                        try {
                            # Untuk file PFX/P12, kita perlu password tapi bisa skip untuk pemindaian
                            if ($file.Extension -eq ".pfx" -or $file.Extension -eq ".p12") {
                                $results += [PSCustomObject]@{
                                    Subject = "Pemindaian file diperlukan password"
                                    Issuer = "N/A"
                                    Thumbprint = "N/A"
                                    NotBefore = $null
                                    NotAfter = $null
                                    SerialNumber = "N/A"
                                    FriendlyName = "N/A"
                                    Store = "N/A"
                                    Location = "N/A"
                                    Source = "File"
                                    Path = $file.FullName
                                }
                                continue
                            }
                            
                            # Coba baca sertifikat dari file
                            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                            $cert.Import($file.FullName)
                            
                            $results += [PSCustomObject]@{
                                Subject = $cert.Subject
                                Issuer = $cert.Issuer
                                Thumbprint = $cert.Thumbprint
                                NotBefore = $cert.NotBefore
                                NotAfter = $cert.NotAfter
                                SerialNumber = $cert.SerialNumber
                                FriendlyName = if ($cert.FriendlyName) { $cert.FriendlyName } else { "N/A" }
                                Store = "N/A"
                                Location = "N/A"
                                Source = "File"
                                Path = $file.FullName
                            }
                        }
                        catch {
                            # Catat file yang gagal dibaca tetapi jangan berhenti
                            Write-Verbose "Gagal memproses file $($file.FullName): $_"
                        }
                    }
                }
                catch {
                    Write-Warning "Gagal mencari file $ext di $folder : $_"
                }
            }
        }
        else {
            Write-Warning "Folder tidak ditemukan: $folder"
        }
    }
    
    return $results
}

# Kumpulkan sertifikat dari semua lokasi penyimpanan sertifikat standar
$allCertificates = @()

# Lokasi sertifikat yang umum
$storeLocations = @("CurrentUser", "LocalMachine")
$storeNames = @("My", "Root", "CA", "AuthRoot", "TrustedPeople", "TrustedPublisher", "SmartCardRoot", "Trust", "Disallowed")

# Ambil semua sertifikat dari certificate stores
foreach ($location in $storeLocations) {
    foreach ($store in $storeNames) {
        $certs = Get-CertificatesFromStore -StoreName $store -StoreLocation $location
        $allCertificates += $certs
    }
}

# Daftar folder umum yang mungkin berisi file sertifikat
$commonFolders = @(
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Downloads",
    "$env:ProgramData\Microsoft\Crypto",
    "$env:SystemRoot\System32\config\systemprofile\AppData\Roaming\Microsoft\Crypto",
    "$env:USERPROFILE\AppData\Roaming\Microsoft\Crypto",
    "$env:USERPROFILE\AppData\Roaming\Microsoft\SystemCertificates",
    "$env:ProgramData\Microsoft\SystemCertificates"
)

# Ambil sertifikat dari file di folder umum
$fileCertificates = Get-CertificatesFromFiles -FoldersToSearch $commonFolders
$allCertificates += $fileCertificates

# Ekspor ke CSV dengan format tanggal yang benar
$allCertificates | Select-Object Subject, Issuer, Thumbprint, 
                    @{Name="NotBefore"; Expression={$_.NotBefore.ToString("yyyy-MM-dd HH:mm:ss")}},
                    @{Name="NotAfter"; Expression={$_.NotAfter.ToString("yyyy-MM-dd HH:mm:ss")}},
                    SerialNumber, FriendlyName, Store, Location, Source, Path |
                    Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "Pemindaian sertifikat selesai. Hasil disimpan ke file: $outputFile"
Write-Host "Total sertifikat ditemukan: $($allCertificates.Count)"
