Add-Pssnapin Microsoft.Exchange.Management.PowerShell.Setup

function Test-AndTune-PerfCounters {
    Write-Host "Validating Exchange performance counters..." -ForegroundColor Cyan
    $countersToCheck = @(
        @{ Name = 'DB Reads Latency'; Path = '\MSExchange Database(*)\I/O Database Reads Average Latency'; Threshold = 20 },
        @{ Name = 'Log Writes Latency'; Path = '\MSExchange Database(*)\I/O Log Writes Average Latency'; Threshold = 10 },
        @{ Name = 'Log Record Stalls/sec'; Path = '\MSExchange Database ==> Instances(*)\Log Record Stalls/sec'; Threshold = 5 }
    )
    $needsRepair = $false
    foreach ($counter in $countersToCheck) {
        Write-Host "Checking [$($counter.Name)]..."
        try {
            $result = Get-Counter -Counter $counter.Path -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
            foreach ($sample in $result.CounterSamples) {
                $instance = $sample.InstanceName
                $value = [math]::Round($sample.CookedValue, 2)
                $status = if ($value -gt $counter.Threshold) { "High" } else { "OK" }
                Write-Host "  [$instance] = $value ms → $status"
            }
        } catch {
            Write-Warning "Failed to read: $($counter.Path)"
            $needsRepair = $true
        }
    }
    if ($needsRepair) {
        Write-Host "`n🔧 Attempting to repair Exchange performance counters..." -ForegroundColor Magenta
        Write-Host "Running 'lodctr /r' to restore perf registry backup..." -ForegroundColor Gray
        Start-Process -FilePath "lodctr.exe" -ArgumentList "/r" -Wait -NoNewWindow
        
        $perfFolder = "C:\Program Files\Microsoft\Exchange Server\V15\Setup\Perf"
        if (Test-Path $perfFolder) {
            $xmlFiles = Get-ChildItem -Path $perfFolder -Filter *.xml
            if ($xmlFiles.Count -eq 0) {
                Write-Warning "No XML files found in $perfFolder for performance counter registration."
            } else {
                $i = 0
                foreach ($xml in $xmlFiles) {
                    $i++
                    Write-Host "`n[$i] Registering perf counter from: $($xml.Name)" -ForegroundColor DarkGray
                    try {
                        # Use proper Start-Process to ensure XML registration works correctly
                        $result = Start-Process -FilePath "lodctr.exe" -ArgumentList "/m:""$($xml.FullName)""" -Wait -NoNewWindow -PassThru
                        if ($result.ExitCode -eq 0) {
                            Write-Host "  Successfully registered $($xml.Name)" -ForegroundColor Green
                        } else {
                            Write-Warning "  Failed to register $($xml.Name) with exit code: $($result.ExitCode)"
                        }
                    } catch {
                        Write-Warning "  Error registering $($xml.Name): $($_.Exception.Message)"
                    }
                }
                Write-Host "Re-registration of perf counters completed."
                
                # Resync performance counters after registration
                Write-Host "Resyncing performance counters..." -ForegroundColor Gray
                Start-Process -FilePath "winmgmt.exe" -ArgumentList "/resyncperf" -Wait -NoNewWindow
            }
        } else {
            Write-Warning "Perf folder not found: $perfFolder"
        }
        Write-Host "`nPlease RESTART the server for changes to take full effect." -ForegroundColor Yellow
    } else {
        Write-Host "`nAll performance counters are accessible. Values evaluated for tuning." -ForegroundColor Green
    }
}

function Check-ExchangeDatabaseHealth {
    Write-Host "`nChecking Exchange mailbox database health..." -ForegroundColor Cyan
    $databases = Get-MailboxDatabase -Status
    foreach ($db in $databases) {
        $copyStatus = Get-MailboxDatabaseCopyStatus -Identity $db.Name
        foreach ($copy in $copyStatus) {
            Write-Host "`nDatabase: $($copy.Name)" -ForegroundColor Yellow
            Write-Host "  Active Copy: $($copy.ActiveDatabaseCopy)"
            Write-Host "  Status     : $($copy.Status)"
            Write-Host "  CopyQueue  : $($copy.CopyQueueLength)"
            Write-Host "  ReplayQueue: $($copy.ReplayQueueLength)"
            Write-Host "  LastInspectedLogTime: $($copy.LastInspectedLogTime)"
        }
    }
}

# === MAIN EXECUTION ===
# Ensure script runs with administrative privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script requires administrative privileges. Please run as Administrator."
    exit
}

Test-AndTune-PerfCounters
Check-ExchangeDatabaseHealth