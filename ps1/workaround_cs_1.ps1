takeown /f "C:\Windows\System32\drivers\CrowdStrike\C-00000291*.sys"

icacls C:\Windows\System32\drivers\CrowdStrike\C-00000291*.sys /grant Administrators:F /T


#Path CS
Set-Location -Path "C:\Windows\System32\drivers\CrowdStrike"


Remove-Item -Path "C-00000291*.sys" -Force 