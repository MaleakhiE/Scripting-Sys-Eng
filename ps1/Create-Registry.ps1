# Perintah Menambahkan Data / Registry Pada Internal dan External EWS dan ECP Url
$internalEWSUrl = "Enter InternalEWSUrl"
$internalECPUrl = "Enter InternalECPUrl"
$externalEWSUrl = "Enter ExternalEWSUrl"
$externalECPUrl = "Enter ExternalECPUrl"

# Function untuk mendapatkan User Principal Name - User yang Sedang Login
function Get-UserPrincipalName {
    try {
        # Inisiasi Assembly (.NET assembly)
        Add-Type -AssemblyName 'System.DirectoryServices.AccountManagement'

        # Mendapatkan Informasi User yang sedang Login
        $userPrincipal = [System.DirectoryServices.AccountManagement.UserPrincipal]::Current

        # Mengembalikan atau Mengambil User Principal Name Pada User
        $userPrincipalName = $userPrincipal.UserPrincipalName
        if (-not $userPrincipalName) {
            $userPrincipalName = $userPrincipal.EmailAddress
        }

        return $userPrincipalName
    } catch {
        Write-Host "Error retrieving UserPrincipalName or Email: $_"
        return $null
    }
}

# Mendapatkan User Principal Name
$userPrincipalName = Get-UserPrincipalName

# Inisiasi Path Registry yang akan Ditambahkan
$registryPath = "HKCU:\SOFTWARE\MICROSOFT\OFFICE\16.0\Lync\$userPrincipalName\Autodiscovery"

# Membuat Registry Jika Tidak Ada
if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force
}

# Mengubah ataupun Menambahkan Registry Pada Path yang Ditentukan
Set-ItemProperty -Path $registryPath -Name "InternalEwsUrl" -Value $internalEWSUrl
Set-ItemProperty -Path $registryPath -Name "InternalEcpUrl" -Value $internalECPUrl
Set-ItemProperty -Path $registryPath -Name "ExternalEwsUrl" -Value $externalEWSUrl
Set-ItemProperty -Path $registryPath -Name "ExternalEcpUrl" -Value $externalECPUrl

# Output pada Powershell
Write-Host "Registry values set successfully on '$registryPath' and for user '$userPrincipalName'."
