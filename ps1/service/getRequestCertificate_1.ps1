$outputFile = "C:\Temp\CARequests.csv"

# Fungsi untuk mendapatkan nama CA dari server lokal
function Get-LocalCAName {
    try {
        $caView = New-Object -ComObject CertificateAuthority.View
        $caView.OpenConnection()
        $caNames = @()
        
        foreach ($ca in $caView.EnumCertificateAuthority(0, 0, 0)) {
            $caNames += $ca.DisplayName
        }
        
        return $caNames
    }
    catch {
        Write-Warning "Tidak dapat mendapatkan daftar CA: $_"
        return $null
    }
}

# Fungsi untuk mendapatkan daftar permintaan sertifikat dari CA
function Get-CACertificateRequests {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CAName,
        
        [Parameter(Mandatory=$false)]
        [string]$CAServer = "localhost"
    )
    
    try {
        # Buat koneksi ke CA
        $caView = New-Object -ComObject CertificateAuthority.View
        $caView.OpenConnection($CAServer + "\" + $CAName)
        
        # Tentukan kolom yang ingin diambil
        $caView.SetResultColumnCount(12)
        
        # Definisikan kolom dari permintaan sertifikat
        # https://docs.microsoft.com/en-us/windows/win32/api/certview/nf-certview-icertificateauthorityview-setresultcolumn
        $caView.SetResultColumn(0)  # Request ID
        $caView.SetResultColumn(1)  # Raw Request
        $caView.SetResultColumn(2)  # Request Attribute
        $caView.SetResultColumn(3)  # Request Type
        $caView.SetResultColumn(4)  # Request Status
        $caView.SetResultColumn(5)  # Request Disposition
        $caView.SetResultColumn(6)  # Request Disposition Message
        $caView.SetResultColumn(7)  # Request Submitted When
        $caView.SetResultColumn(8)  # Request Resolved When
        $caView.SetResultColumn(9)  # Request Revoked When
        $caView.SetResultColumn(10) # Request Revocation Reason
        $caView.SetResultColumn(11) # Raw Certificate
        
        # Ambil semua permintaan sertifikat
        $requests = @()
        
        # Ambil seluruh permintaan (issued dan pending)
        $caView.SetRestriction(4, 0, 0, "") # Disposition column, no restrictions
        
        # Mulai enumerasi
        $rowObj = $caView.EnumRow(0, 0, 0)
        
        while ($rowObj -ne $null) {
            $requestId = $rowObj.GetValue(0)
            $rawRequest = $rowObj.GetValue(1)
            $requestAttr = $rowObj.GetValue(2)
            $requestType = $rowObj.GetValue(3)
            $requestStatus = $rowObj.GetValue(4)
            $requestDisposition = $rowObj.GetValue(5)
            $requestDispositionMessage = $rowObj.GetValue(6)
            $requestSubmittedWhen = $rowObj.GetValue(7)
            $requestResolvedWhen = $rowObj.GetValue(8)
            $requestRevokedWhen = $rowObj.GetValue(9)
            $requestRevocationReason = $rowObj.GetValue(10)
            $rawCertificate = $rowObj.GetValue(11)
            
            # Mengonversi nilai numerik ke string yang lebih mudah dibaca
            $requestTypeString = switch ($requestType) {
                1 {"User"}
                2 {"Machine"}
                3 {"CA"}
                4 {"CrossCA"}
                5 {"KRA"}
                6 {"DSClient"}
                7 {"DSServer"}
                8 {"Router"}
                9 {"OfflineRouter"}
                10 {"SmartCard"}
                11 {"EFS"}
                12 {"EFSRecovery"}
                13 {"CEPEncryption"}
                default {"Unknown ($requestType)"}
            }
            
            $requestStatusString = switch ($requestStatus) {
                0 {"Unknown"}
                1 {"New Request"}
                2 {"Denied Request"}
                3 {"Issued Certificate"}
                4 {"Revoked Certificate"}
                5 {"Pending Certificate"}
                default {"Unknown ($requestStatus)"}
            }
            
            $requestDispositionString = switch ($requestDisposition) {
                0 {"None"}
                1 {"New Request"}
                2 {"Pending Request"}
                3 {"Denied Request"}
                4 {"Issued Certificate"}
                5 {"Revoked Certificate"}
                default {"Unknown ($requestDisposition)"}
            }
            
            # Ekstrak nama subjek dan masa berlaku dari permintaan yang sudah dikeluarkan
            $subjectName = "N/A"
            $expirationDate = $null
            $notBeforeDate = $null
            
            if ($rawCertificate -ne $null -and $requestStatusString -eq "Issued Certificate") {
                try {
                    # Konversi byte array menjadi objek X509Certificate2
                    $certBytes = [System.Convert]::FromBase64String($rawCertificate)
                    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                    $cert.Import($certBytes)
                    
                    $subjectName = $cert.Subject
                    $notBeforeDate = $cert.NotBefore
                    $expirationDate = $cert.NotAfter
                }
                catch {
                    Write-Warning "Tidak dapat memproses sertifikat untuk Request ID $requestId : $_"
                }
            }
            
            # Tambahkan data ke array
            $requestObj = [PSCustomObject]@{
                RequestID = $requestId
                SubjectName = $subjectName
                RequestType = $requestTypeString
                RequestStatus = $requestStatusString
                RequestDisposition = $requestDispositionString
                SubmittedDate = $requestSubmittedWhen
                ResolvedDate = $requestResolvedWhen
                ValidFrom = $notBeforeDate
                ExpirationDate = $expirationDate
                RevokedDate = $requestRevokedWhen
                RevocationReason = $requestRevocationReason
                DispositionMessage = $requestDispositionMessage
                CAName = $CAName
            }
            
            $requests += $requestObj
            
            # Ambil baris berikutnya
            try {
                $rowObj = $caView.EnumRow(1, 0, 0)
            }
            catch {
                $rowObj = $null
            }
        }
        
        return $requests
    }
    catch {
        Write-Warning "Gagal mendapatkan permintaan sertifikat dari $CAName : $_"
        return @()
    }
}

# Main script

# Cek apakah pengguna memiliki hak administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Script ini memerlukan hak administrator untuk mengakses Certification Authority. Silakan jalankan PowerShell sebagai administrator."
    exit
}

# Cek apakah ada CA yang berjalan di server lokal
$caNames = Get-LocalCAName

if ($null -eq $caNames -or $caNames.Count -eq 0) {
    Write-Warning "Tidak ada Certification Authority yang ditemukan di komputer ini. Pastikan server CA diinstal dan berjalan."
    exit
}

$allRequests = @()

# Ambil permintaan dari setiap CA
foreach ($caName in $caNames) {
    Write-Host "Mengambil permintaan sertifikat dari CA: $caName"
    $requests = Get-CACertificateRequests -CAName $caName
    $allRequests += $requests
    Write-Host "Jumlah permintaan dari $caName : $($requests.Count)"
}

# Ekspor ke CSV
if ($allRequests.Count -gt 0) {
    $allRequests | Select-Object RequestID, SubjectName, RequestType, RequestStatus, RequestDisposition, 
                    @{Name="SubmittedDate"; Expression={$_.SubmittedDate.ToString("yyyy-MM-dd HH:mm:ss")}},
                    @{Name="ResolvedDate"; Expression={if ($_.ResolvedDate) {$_.ResolvedDate.ToString("yyyy-MM-dd HH:mm:ss")} else {"N/A"}}},
                    @{Name="ValidFrom"; Expression={if ($_.ValidFrom) {$_.ValidFrom.ToString("yyyy-MM-dd HH:mm:ss")} else {"N/A"}}},
                    @{Name="ExpirationDate"; Expression={if ($_.ExpirationDate) {$_.ExpirationDate.ToString("yyyy-MM-dd HH:mm:ss")} else {"N/A"}}},
                    @{Name="RevokedDate"; Expression={if ($_.RevokedDate) {$_.RevokedDate.ToString("yyyy-MM-dd HH:mm:ss")} else {"N/A"}}},
                    RevocationReason, DispositionMessage, CAName |
                    Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    
    Write-Host "Berhasil mengekspor $($allRequests.Count) permintaan sertifikat ke file: $outputFile"
}
else {
    Write-Warning "Tidak ada permintaan sertifikat yang ditemukan."
}