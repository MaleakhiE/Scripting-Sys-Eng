# Path setup
$targetFolder = "$PSScriptRoot"  # UBAH INI MENJADI PATH FOLDER LOG YANG DIINGINKAN / TEMPAT ADD_TO_GROUPS* ITU BERADA
$logFile = "$PSScriptRoot\execution_log.log"

# Logging helper
function Log-Message {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $message"
    Add-Content -Path $logFile -Value $entry
    Write-Host $entry
}

# Start log
Log-Message "========== Starting batch run in current session =========="

# Find matching scripts
$scripts = Get-ChildItem -Path $targetFolder -Filter "*add_to_groups*.ps1" -Recurse

if ($scripts.Count -eq 0) {
    Log-Message "No scripts found matching 'add_to_groups*.ps1' in $targetFolder"
} else {
    foreach ($script in $scripts) {
        Log-Message "---- Running script: $($script.FullName) ----"
        try {
            # Save current output
            $scriptOutput = & {
                . $script.FullName 2>&1
            }
            foreach ($line in $scriptOutput) {
                Log-Message "OUTPUT: $line"
            }
            Log-Message "FINISHED: $($script.Name)`n"
        }
        catch {
            Log-Message "ERROR: Exception while running $($script.Name): $_"
        }
    }
}

Log-Message "========== All scripts executed =========="
