# Import Active Directory module
Import-Module ActiveDirectory

# Define CSV file path
$csvFile = "C:\Path\To\Users.csv"

# Define default password (Change as needed)
$defaultPassword = "Password.1"

# Read users from CSV
$users = Import-Csv -Path $csvFile -Delimiter "`t"  # Assuming tab-separated CSV

foreach ($user in $users) {
    $samAccountName = $user.samAccountName
    $fullName = $user."Full Name"
    $firstName = $user."First Name"
    $lastName = if ($user."Last Name" -eq "") { $null } else { $user."Last Name" }
    $email = $user."STP Email"
    $upn = $user.UPN
    $ou = $user.OU -replace '"', ''  # Remove quotes if present

    # Validate required fields
    if (-not $samAccountName -or -not $fullName -or -not $email -or -not $upn) {
        Write-Host "⚠️ Skipping user $fullName (missing required fields)" -ForegroundColor Yellow
        continue
    }

    # Check if the user already exists in AD
    $existingUser = Get-ADUser -Filter {SamAccountName -eq $samAccountName} -ErrorAction SilentlyContinue

    if ($existingUser) {
        Write-Host "⚠️ User $samAccountName already exists, skipping..." -ForegroundColor Yellow
    } else {
        try {
            # Create new AD user
            New-ADUser -SamAccountName $samAccountName `
                       -UserPrincipalName $upn `
                       -Name $fullName `
                       -GivenName $firstName `
                       -Surname $lastName `
                       -EmailAddress $email `
                       -Path $ou `
                       -AccountPassword (ConvertTo-SecureString $defaultPassword -AsPlainText -Force) `
                       -Enabled $true `
                       -PassThru

            Write-Host "✅ Created user: $fullName ($samAccountName)" -ForegroundColor Green
        } catch {
            Write-Host "❌ Error creating user $samAccountName : $_" -ForegroundColor Red
        }
    }
}

Write-Host "`n🎉 Bulk user creation completed!" -ForegroundColor Cyan
