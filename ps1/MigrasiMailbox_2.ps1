Set-AdServerSettings -ViewEntireForest $true

$csvPath = "C:\Temp\Mailbox_Visionet.csv"
$today = Get-Date -Format "yyyyMMdd"

if (-Not (Test-Path -Path $csvPath)) {
    Write-Error "File CSV tidak ditemukan di path : $csvPath"
    exit
}

$mailboxes = Import-Csv -Path $csvPath


foreach ($mb in $mailboxes) {
    $upn = $mb.UserPrincipalName
    $currentDb = $mb.Database
    $destinationDb = "DB4-DOWNGRADE04"

    if ([string]::IsNullOrWhiteSpace($destinationDb)) {
        Write-Warning "Mailbox $upn tidak memiliki DestinationDB. Lewati."
        continue
    }

    try {
        Write-Host "Migrasi mailbox: $upn dari $currentDb ke $destinationDb ..." -ForegroundColor Cyan
        New-MoveRequest -Identity $upn `
                        -TargetDatabase $destinationDb `
                        -ArchiveTargetDatabase $destinationDb `
                        -BatchName "Migration_$($destinationDb)_$today" `
                        -RemoteHostName $null `
                        -ErrorAction Stop
        Write-Host "Berhasil submit migrasi untuk: $upn" -ForegroundColor Green
    }
    catch {
        Write-Warning "Gagal memigrasi $upn : $($_.Exception.Message)"
    }
}

Write-Host "`nGunakan perintah berikut untuk memantau status migrasi:" -ForegroundColor Yellow
Write-Host "Get-MoveRequest | Get-MoveRequestStatistics | Select DisplayName,Status,PercentComplete" -ForegroundColor Gray
