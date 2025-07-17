# File Output
$outputFile = "ExchangeUserReport.csv"

# Memuat modul Exchange On-Premises
if (-not (Get-PSSnapin -Name Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction SilentlyContinue)) {
    Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn
}

# Dapatkan semua mailbox user
Write-Host "Mengambil data pengguna dari Exchange On-Premises..."
$mailboxUsers = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited

# List untuk menyimpan data user
$userData = @()

foreach ($mailbox in $mailboxUsers) {
    try {
        # Ambil informasi statistik mailbox
        $logonStats = Get-MailboxStatistics -Identity $mailbox.Alias -ErrorAction Stop
        $lastLogon = $logonStats.LastLogonTime
        $mailboxSize = [Math]::Round($logonStats.TotalItemSize.Value.ToMB(), 2)
        $itemCount = $logonStats.ItemCount
    } catch {
        # Jika mailbox belum pernah digunakan
        $lastLogon = "Belum pernah login"
        $mailboxSize = 0
        $itemCount = 0
    }

    # Ambil informasi Active Directory
    $adUser = Get-ADUser -Identity $mailbox.Alias -Properties LastLogonDate, Enabled, PasswordNeverExpires, Description, LogonHours, MemberOf -ErrorAction SilentlyContinue

    # Tentukan apakah akun adalah service account
    $isServiceAccount = $false

    # Indikator Service Account
    if ($adUser.PasswordNeverExpires -eq $true) {
        $isServiceAccount = $true
    }

    if ($adUser.Description -match "(?i)service|automation|system|account") {
        $isServiceAccount = $true
    }

    if ($adUser.LogonHours -eq "00000000000000000000000000000000000000000000000000000000000000000000000000000000") {
        $isServiceAccount = $true
    }

    if ($adUser.MemberOf -match "Service Accounts|Automation Group") {
        $isServiceAccount = $true
    }

    # Konversi LogonHours ke format yang lebih mudah dibaca
    $logonHoursReadable = if ($adUser.LogonHours) {
        $adUser.LogonHours -split '' -join ' ' # Tambahkan spasi agar lebih mudah dibaca
    } else {
        "Tidak diatur"
    }

    # Tentukan tipe akun
    $accountType = if ($isServiceAccount) { "Service Account" } else { "User Account" }

    # Menambahkan data ke list
    $userData += [PSCustomObject]@{
        DisplayName       = $mailbox.DisplayName
        UserPrincipalName = $mailbox.UserPrincipalName
        Alias             = $mailbox.Alias
        LastLogon         = $lastLogon
        LastLogonAD       = $adUser.LastLogonDate
        MailboxSizeMB     = $mailboxSize
        ItemCount         = $itemCount
        AccountStatus     = if ($adUser.Enabled) { "Enabled" } else { "Disabled" }
        AccountType       = $accountType
        PasswordNeverExpires = $adUser.PasswordNeverExpires
        LogonHours        = $logonHoursReadable
        Description       = $adUser.Description
        MemberOf          = ($adUser.MemberOf | ForEach-Object { $_ -replace '^CN=|,.*$', '' }) -join '; '
    }
}

# Ekspor data ke CSV
Write-Host "Mengekspor data ke file CSV..."
$userData | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "Proses selesai. File output disimpan di $outputFile"
