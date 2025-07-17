param (
    [string]$LogoPath,
    [string]$ConfigFilePath = "C:\ProgramData\Resilio\Connect Server\resilio-connect-server.conf",
    [string]$DestinationLogoPath = "C:\ProgramData\Resilio\Connect Server\images\logo.svg"
)

# Ensure the logo file exists
if (!(Test-Path $LogoPath)) {
    Write-Host "ERROR: Logo file not found at $LogoPath"
    exit 1
}

# Ensure the configuration file exists
if (!(Test-Path $ConfigFilePath)) {
    Write-Host "ERROR: Configuration file not found at $ConfigFilePath"
    exit 1
}

# Create the destination directory if it doesn't exist
$DestinationLogoDir = [System.IO.Path]::GetDirectoryName($DestinationLogoPath)
if (!(Test-Path $DestinationLogoDir)) {
    New-Item -Path $DestinationLogoDir -ItemType Directory -Force
}

# Copy the logo file to the destination path
Copy-Item -Path $LogoPath -Destination $DestinationLogoPath -Force
Write-Host "Copied logo to $DestinationLogoPath"

# Read the existing configuration file
$configContent = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json

# Add or update the branding configuration
if (-not $configContent.branding) {
    $configContent | Add-Member -MemberType NoteProperty -Name branding -Value @{}
}
$configContent.branding.icon = $DestinationLogoPath

# Write the updated configuration back to the file
$configContent | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFilePath -Force
Write-Host "Updated configuration file at $ConfigFilePath"

Write-Host "Management Console logo updated successfully."