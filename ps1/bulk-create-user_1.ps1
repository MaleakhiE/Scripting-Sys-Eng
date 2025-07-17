$CSVPath = "C:\Temp\MutasiProtelindo.csv"
$Users = Import-Csv -Path $CSVPath -Delimiter ";"
$GroupName = "All Jakarta Employee"

try {
    $group = Get-ADGroup -Identity $GroupName -ErrorAction Stop
    Write-Host "Group '$GroupName' found. Proceeding with user creation." -ForegroundColor Green
} catch {
    Write-Host "WARNING: Group '$GroupName' not found. Creating users but they won't be added to the group." -ForegroundColor Yellow
}

foreach ($User in $Users) {
    try {
        Write-Host "Processing: $($User."Full Name")" -ForegroundColor Cyan
        
        $OUPath = $User.OU -replace '"{3}', '' -replace '"{2}', '' -replace '"', ''
        Write-Host "Using OU path: $OUPath" -ForegroundColor Gray
        
        try {
            $ouExists = Get-ADOrganizationalUnit -Identity $OUPath -ErrorAction Stop
            Write-Host "OU verified: $OUPath" -ForegroundColor Gray
        } catch {
            Write-Host "WARNING: OU does not exist or is inaccessible: $OUPath" -ForegroundColor Yellow
            throw "OU path is invalid or inaccessible"
        }
        
        $SecurePassword = ConvertTo-SecureString -String $User.Password -AsPlainText -Force
        
        $NewUserParams = @{
            Name = $User.samAccountName
            GivenName = $User."First Name"
            DisplayName = $User."Full Name"
            SamAccountName = $User.samAccountName
            UserPrincipalName = $User.UPN
            EmailAddress = $User.Email
            Path = $OUPath
            AccountPassword = $SecurePassword
            Enabled = $true
            ChangePasswordAtLogon = $false
            Surname = $User."Last Name"
            Description = $User.Description
            Title = $User.JobTitle
        }
        
        New-ADUser @NewUserParams
        Write-Host "User account created: $($User.samAccountName)" -ForegroundColor Green
        
        Start-Sleep -Seconds 2
        
        try {
            Get-ADUser -Identity $User.samAccountName -ErrorAction Stop
            Write-Host "User verified: $($User.samAccountName)" -ForegroundColor Gray
            
            try {
                Add-ADGroupMember -Identity $GroupName -Members $User.samAccountName -ErrorAction Stop
                Write-Host "Added to group: $GroupName" -ForegroundColor Green
            } catch {
                Write-Host "Failed to add to group: $_" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "User not found after creation: $($User.samAccountName)" -ForegroundColor Yellow
        }
        
        Write-Host "✓ Successfully processed: $($User."Full Name")" -ForegroundColor Green
        Write-Host "-------------------------------------------------" -ForegroundColor Gray
    }
    catch {
        Write-Host "✗ FAILED to process user $($User."Full Name")" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host "-------------------------------------------------" -ForegroundColor Gray
    }
}

Write-Host "Script completed. Please check the output for any errors." -ForegroundColor Cyan