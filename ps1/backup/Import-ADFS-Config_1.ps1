$ImportPath = "C:\ADFS-Export-07-07-2025-1629"

param(
    [Parameter(Mandatory=$False)]
    [switch]$WhatIf,
    [switch]$Force,
    [switch]$Verbose,
    [switch]$SkipCertificates,
    [switch]$SkipSSLCertificate,
    [string[]]$ExcludeComponents = @()
)

# Function to write verbose output
function Write-VerboseOutput {
    param([string]$Message)
    if ($Verbose) {
        Write-Host $Message -ForegroundColor Cyan
    }
}

# Function to safely import data with error handling
function Import-SafeData {
    param(
        [string]$FilePath,
        [string]$Description,
        [scriptblock]$ImportCommand,
        [string]$Format = "json",
        [switch]$Required = $false
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            if ($Required) {
                Write-Warning "  ✗ Required file not found: $FilePath"
                return $null
            } else {
                Write-VerboseOutput "  ℹ Optional file not found: $FilePath"
                return $null
            }
        }

        Write-Host "Importing $Description..."
        
        if ($WhatIf) {
            Write-Host "  [WHATIF] Would import from: $FilePath" -ForegroundColor Yellow
            return $null
        }

        $data = switch ($Format.ToLower()) {
            "json" {
                Get-Content $FilePath -Raw | ConvertFrom-Json
            }
            "xml" {
                Import-Clixml $FilePath
            }
            "txt" {
                Get-Content $FilePath
            }
        }

        if ($data) {
            & $ImportCommand $data
            Write-VerboseOutput "  ✓ Successfully imported: $Description"
            return $data
        } else {
            Write-Warning "  ⚠ No data found in file: $FilePath"
            return $null
        }
    }
    catch {
        Write-Warning "  ✗ Failed to import $Description`: $($_.Exception.Message)"
        return $null
    }
}

# Function to backup existing configuration before import
function Backup-ExistingConfig {
    param([string]$BackupPath)
    
    Write-Host "Creating backup of existing configuration..." -ForegroundColor Yellow
    
    try {
        if (-not (Test-Path $BackupPath)) {
            New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        }
        
        # Backup critical components
        Get-AdfsRelyingPartyTrust | Export-Clixml "$BackupPath\existing-rp-trusts.xml"
        Get-AdfsClaimsProviderTrust | Export-Clixml "$BackupPath\existing-cp-trusts.xml"
        Get-AdfsProperties | ConvertTo-Json -Depth 10 | Out-File "$BackupPath\existing-properties.json"
        
        Write-Host "  ✓ Backup created at: $BackupPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create backup: $($_.Exception.Message)"
    }
}

# Validation function
function Test-ImportPath {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Error "Import path does not exist: $Path"
        return $false
    }
    
    $summaryFile = Join-Path $Path "export-summary.json"
    if (-not (Test-Path $summaryFile)) {
        Write-Warning "Export summary file not found. This may not be a valid ADFS export."
    }
    
    return $true
}

# Main import logic
Write-Host "=== ADFS Configuration Import ===" -ForegroundColor Green
Write-Host "Import Path: $ImportPath" -ForegroundColor Cyan
Write-Host "WhatIf Mode: $WhatIf" -ForegroundColor Cyan

# Validate import path
if (-not (Test-ImportPath -Path $ImportPath)) {
    exit 1
}

# Read export summary if available
$summaryPath = Join-Path $ImportPath "export-summary.json"
if (Test-Path $summaryPath) {
    $summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
    Write-Host "Export Date: $($summary.ExportDate)" -ForegroundColor Cyan
    Write-Host "Source ADFS: $($summary.ADFSProperties.Hostname)" -ForegroundColor Cyan
}

# Create backup of existing configuration
if (-not $WhatIf) {
    $backupPath = "C:\ADFS-Backup-$(Get-Date -Format 'dd-MM-yyyy-HHmm')"
    Backup-ExistingConfig -BackupPath $backupPath
}

# Confirm import unless Force is specified
if (-not $Force -and -not $WhatIf) {
    $confirm = Read-Host "Are you sure you want to import ADFS configuration? This will modify your current setup. (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Import cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`n=== IMPORTING CERTIFICATES ===" -ForegroundColor Yellow

if (-not ($ExcludeComponents -contains "Certificates") -and -not $SkipCertificates) {
    
    # Import SSL Certificate
    if (-not $SkipSSLCertificate) {
        $pfxPath = Join-Path $ImportPath "Service\Certificates\adfs-ssl-cert.pfx"
        $cerPath = Join-Path $ImportPath "Service\Certificates\adfs-ssl-cert.cer"
        
        if (Test-Path $pfxPath) {
            Write-Host "Importing SSL Certificate (PFX)..."
            if (-not $WhatIf) {
                $password = Read-Host -AsSecureString "Enter password for SSL certificate (.pfx)"
                try {
                    Import-PfxCertificate -FilePath $pfxPath -CertStoreLocation Cert:\LocalMachine\My -Password $password
                    Write-Host "  ✓ SSL Certificate imported successfully"
                } catch {
                    Write-Warning "  ✗ Failed to import SSL certificate: $($_.Exception.Message)"
                }
            }
        } elseif (Test-Path $cerPath) {
            Write-Host "Importing SSL Certificate (CER - public key only)..."
            if (-not $WhatIf) {
                try {
                    Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\LocalMachine\My
                    Write-Host "  ✓ SSL Certificate (public key) imported successfully"
                } catch {
                    Write-Warning "  ✗ Failed to import SSL certificate: $($_.Exception.Message)"
                }
            }
        }
    }
}

Write-Host "`n=== IMPORTING BASIC CONFIGURATION ===" -ForegroundColor Yellow

# Import Claim Descriptions first (dependency for other components)
if (-not ($ExcludeComponents -contains "ClaimDescriptions")) {
    Import-SafeData -FilePath "$ImportPath\Service\ClaimDescriptions\claim-descriptions.json" -Description "Claim Descriptions" -ImportCommand {
        param($data)
        foreach ($claim in $data) {
            try {
                $existing = Get-AdfsClaimDescription -Name $claim.Name -ErrorAction SilentlyContinue
                if ($existing) {
                    Write-VerboseOutput "    Claim description '$($claim.Name)' already exists, skipping"
                } else {
                    Add-AdfsClaimDescription `
                    -Name $claim.Name `
                    -ShortName $claim.ShortName `
                    -ClaimType $claim.ClaimType `
                    -IsAccepted:$($claim.IsAccepted) `
                    -IsOffered:$($claim.IsOffered) `
                    -IsRequired:$($claim.IsRequired) `
                    -Notes $claim.Notes
                    Write-VerboseOutput "    Added claim description: $($claim.Name)"
                }
            } catch {
                Write-Warning "    Failed to add claim description '$($claim.Name)': $($_.Exception.Message)"
            }
        }
    }
}

# Import Attribute Stores
if (-not ($ExcludeComponents -contains "AttributeStores")) {
    Import-SafeData -FilePath "$ImportPath\Service\AttributeStores\attribute-stores.json" -Description "Attribute Stores" -ImportCommand {
        param($data)
        foreach ($store in $data) {
            try {
                $existing = Get-AdfsAttributeStore -Name $store.Name -ErrorAction SilentlyContinue
                if ($existing) {
                    Write-VerboseOutput "    Attribute store '$($store.Name)' already exists, skipping"
                } else {
                    Add-AdfsAttributeStore `
                        -Name $store.Name `
                        -TypeQualifiedName $store.StoreTypeQualifiedName `
                        -Configuration $store.Configuration
                    Write-VerboseOutput "    Added attribute store: $($store.Name)"
                }
            } catch {
                Write-Warning "    Failed to add attribute store '$($store.Name)': $($_.Exception.Message)"
            }
        }
    }
}

Write-Host "`n=== IMPORTING ACCESS CONTROL POLICIES ===" -ForegroundColor Yellow

if (-not ($ExcludeComponents -contains "AccessControlPolicies")) {
    Import-SafeData -FilePath "$ImportPath\AccessControlPolicies\access-control-policies.json" -Description "Access Control Policies" -ImportCommand {
        param($data)
        foreach ($policy in $data) {
            try {
                $existing = Get-AdfsAccessControlPolicy -Name $policy.Name -ErrorAction SilentlyContinue
                if ($existing) {
                    Write-VerboseOutput "    Access control policy '$($policy.Name)' already exists, skipping"
                } else {
                    New-AdfsAccessControlPolicy -Name $policy.Name -PolicyMetadata $policy.PolicyMetadata -PolicyMetadataFile $policy.PolicyMetadataFile
                    Write-VerboseOutput "    Added access control policy: $($policy.Name)"
                }
            } catch {
                Write-Warning "    Failed to add access control policy '$($policy.Name)': $($_.Exception.Message)"
            }
        }
    }
}

Write-Host "`n=== IMPORTING CLAIMS PROVIDER TRUSTS ===" -ForegroundColor Yellow

if (-not ($ExcludeComponents -contains "ClaimsProviderTrusts")) {
    Import-SafeData -FilePath "$ImportPath\ClaimsProviderTrusts\claims-provider-trusts.xml" -Description "Claims Provider Trusts" -Format "xml" -ImportCommand {
        param($data)
        foreach ($cp in $data) {
            try {
                # Skip Active Directory (built-in)
                if ($cp.Name -eq "Active Directory") {
                    Write-VerboseOutput "    Skipping built-in Active Directory claims provider"
                    continue
                }
                
                $existing = Get-AdfsClaimsProviderTrust -Name $cp.Name -ErrorAction SilentlyContinue
                if ($existing) {
                    if ($Force) {
                        Remove-AdfsClaimsProviderTrust -TargetName $cp.Name -Confirm:$false
                        Write-VerboseOutput "    Removed existing claims provider trust: $($cp.Name)"
                    } else {
                        Write-VerboseOutput "    Claims provider trust '$($cp.Name)' already exists, skipping"
                        continue
                    }
                }
                
                $params = @{
                    Name = $cp.Name
                    Identifier = $cp.Identifier
                    MetadataUrl = $cp.MetadataUrl
                    AcceptanceTransformRules = $cp.AcceptanceTransformRules
                    Enabled = $cp.Enabled
                    Notes = $cp.Notes
                }
                
                # Remove null parameters
                $params = $params.GetEnumerator() | Where-Object { $_.Value -ne $null } | ForEach-Object { @{} } { $_[$_.Key] = $_.Value } { $_ }
                
                Add-AdfsClaimsProviderTrust @params
                Write-VerboseOutput "    Added claims provider trust: $($cp.Name)"
            } catch {
                Write-Warning "    Failed to add claims provider trust '$($cp.Name)': $($_.Exception.Message)"
            }
        }
    }
}

Write-Host "`n=== IMPORTING RELYING PARTY TRUSTS ===" -ForegroundColor Yellow

if (-not ($ExcludeComponents -contains "RelyingPartyTrusts")) {
    Import-SafeData -FilePath "$ImportPath\RelyingPartyTrusts\relying-party-trusts.xml" -Description "Relying Party Trusts" -Format "xml" -ImportCommand {
        param($data)
        foreach ($rp in $data) {
            try {
                $existing = Get-AdfsRelyingPartyTrust -Name $rp.Name -ErrorAction SilentlyContinue
                if ($existing) {
                    if ($Force) {
                        Remove-AdfsRelyingPartyTrust -TargetName $rp.Name -Confirm:$false
                        Write-VerboseOutput "    Removed existing relying party trust: $($rp.Name)"
                    } else {
                        Write-VerboseOutput "    Relying party trust '$($rp.Name)' already exists, skipping"
                        continue
                    }
                }

                # Build parameters
                $params = @{
                    Name = $rp.Name
                    Identifier = $rp.Identifier
                    WSfedEndpoint = $rp.WSFedEndpoint
                    IssuanceTransformRules = $rp.IssuanceTransformRules
                    IssuanceAuthorizationRules = $rp.IssuanceAuthorizationRules
                    DelegationAuthorizationRules = $rp.DelegationAuthorizationRules
                    AccessControlPolicyName = $rp.AccessControlPolicyName
                    Enabled = $rp.Enabled
                    Notes = $rp.Notes
                    MetadataUrl = $rp.MetadataUrl
                }

                # Remove empty/null
                $cleanParams = @{}
                foreach ($key in $params.Keys) {
                    if ($params[$key]) { $cleanParams[$key] = $params[$key] }
                }

                # Create relying party trust
                Add-AdfsRelyingPartyTrust @cleanParams
                Write-VerboseOutput "    Added relying party trust: $($rp.Name)"

                # Set encryption certificate
                if ($rp.EncryptionCertificate) {
                    Set-AdfsRelyingPartyTrust -TargetName $rp.Name -EncryptionCertificate $rp.EncryptionCertificate
                    Write-VerboseOutput "    Set encryption cert for: $($rp.Name)"
                }

                # Set signature certificates
                if ($rp.SignatureCertificates -and $rp.SignatureCertificates.Count -gt 0) {
                    Set-AdfsRelyingPartyTrust -TargetName $rp.Name -SignatureCertificate $rp.SignatureCertificates
                    Write-VerboseOutput "    Set signature certs for: $($rp.Name)"
                }

                # Set accepted claim types explicitly
                if ($rp.AcceptedClaimTypes -and $rp.AcceptedClaimTypes.Count -gt 0) {
                    Set-AdfsAcceptedClaimTypes -TargetName $rp.Name -AcceptedClaimType $rp.AcceptedClaimTypes
                    Write-VerboseOutput "    Set accepted claim types for: $($rp.Name)"
                }

                # Set monitoring explicitly (often missed in dumps)
                if ($rp.MonitoringEnabled -ne $null) {
                    Set-AdfsRelyingPartyTrust -TargetName $rp.Name -MonitoringEnabled $rp.MonitoringEnabled
                    Write-VerboseOutput "    Set monitoring for: $($rp.Name)"
                }

            } catch {
                Write-Warning "    Failed to import relying party trust '$($rp.Name)': $($_.Exception.Message)"
            }
        }
    }
}

Write-Host "`n=== IMPORTING APPLICATION GROUPS ===" -ForegroundColor Yellow

if (-not ($ExcludeComponents -contains "ApplicationGroups")) {
    # Import Application Groups
    Import-SafeData -FilePath "$ImportPath\ApplicationGroups\application-groups.json" -Description "Application Groups" -ImportCommand {
        param($data)
        foreach ($appGroup in $data) {
            try {
                $existing = Get-AdfsApplicationGroup -Name $appGroup.Name -ErrorAction SilentlyContinue
                if ($existing) {
                    if ($Force) {
                        Remove-AdfsApplicationGroup -TargetName $appGroup.Name -Confirm:$false
                        Write-VerboseOutput "    Removed existing application group: $($appGroup.Name)"
                    } else {
                        Write-VerboseOutput "    Application group '$($appGroup.Name)' already exists, skipping"
                        continue
                    }
                }
                
                New-AdfsApplicationGroup -Name $appGroup.Name -Description $appGroup.Description -ApplicationGroupIdentifier $appGroup.ApplicationGroupIdentifier
                Write-VerboseOutput "    Added application group: $($appGroup.Name)"
            } catch {
                Write-Warning "    Failed to add application group '$($appGroup.Name)': $($_.Exception.Message)"
            }
        }
    }
    
    # Import Native Client Applications
    Import-SafeData -FilePath "$ImportPath\ApplicationGroups\native-client-apps.json" -Description "Native Client Applications" -ImportCommand {
        param($data)
        foreach ($app in $data) {
            try {
                $existing = Get-AdfsNativeClientApplication -Name $app.Name -ErrorAction SilentlyContinue
                if ($existing) {
                    Write-VerboseOutput "    Native client app '$($app.Name)' already exists, skipping"
                    continue
                }
                
                Add-AdfsNativeClientApplication -Name $app.Name -ApplicationGroupIdentifier $app.ApplicationGroupIdentifier -ClientId $app.ClientId -RedirectUri $app.RedirectUri
                Write-VerboseOutput "    Added native client application: $($app.Name)"
            } catch {
                Write-Warning "    Failed to add native client application '$($app.Name)': $($_.Exception.Message)"
            }
        }
    }
    
    # Import Server Applications
    Import-SafeData -FilePath "$ImportPath\ApplicationGroups\server-applications.json" -Description "Server Applications" -ImportCommand {
        param($data)
        foreach ($app in $data) {
            try {
                $existing = Get-AdfsServerApplication -Name $app.Name -ErrorAction SilentlyContinue
                if ($existing) {
                    Write-VerboseOutput "    Server application '$($app.Name)' already exists, skipping"
                    continue
                }
                
                Add-AdfsServerApplication -Name $app.Name -ApplicationGroupIdentifier $app.ApplicationGroupIdentifier -ClientId $app.ClientId -RedirectUri $app.RedirectUri
                Write-VerboseOutput "    Added server application: $($app.Name)"
            } catch {
                Write-Warning "    Failed to add server application '$($app.Name)': $($_.Exception.Message)"
            }
        }
    }
    
    # Import Web API Applications
    Import-SafeData -FilePath "$ImportPath\ApplicationGroups\web-api-applications.json" -Description "Web API Applications" -ImportCommand {
        param($data)
        foreach ($app in $data) {
            try {
                $existing = Get-AdfsWebApiApplication -Name $app.Name -ErrorAction SilentlyContinue
                if ($existing) {
                    Write-VerboseOutput "    Web API application '$($app.Name)' already exists, skipping"
                    continue
                }
                
                Add-AdfsWebApiApplication -Name $app.Name -ApplicationGroupIdentifier $app.ApplicationGroupIdentifier -Identifier $app.Identifier -AccessControlPolicyName $app.AccessControlPolicyName
                Write-VerboseOutput "    Added Web API application: $($app.Name)"
            } catch {
                Write-Warning "    Failed to add Web API application '$($app.Name)': $($_.Exception.Message)"
            }
        }
    }
}

Write-Host "`n=== IMPORTING GLOBAL SETTINGS ===" -ForegroundColor Yellow

if (-not ($ExcludeComponents -contains "GlobalSettings")) {
    # Import Global Authentication Policy
    Import-SafeData -FilePath "$ImportPath\Service\Properties\global-auth-policy.json" -Description "Global Authentication Policy" -ImportCommand {
        param($data)
        try {
            $params = @{}
            
            if ($data.PrimaryIntranetAuthenticationProvider) { $params['PrimaryIntranetAuthenticationProvider'] = $data.PrimaryIntranetAuthenticationProvider }
            if ($data.PrimaryExtranetAuthenticationProvider) { $params['PrimaryExtranetAuthenticationProvider'] = $data.PrimaryExtranetAuthenticationProvider }
            if ($data.AdditionalAuthenticationProvider) { $params['AdditionalAuthenticationProvider'] = $data.AdditionalAuthenticationProvider }
            if ($data.WindowsIntegratedFallbackEnabled) { $params['WindowsIntegratedFallbackEnabled'] = $data.WindowsIntegratedFallbackEnabled }
            
            if ($params.Count -gt 0) {
                Set-AdfsGlobalAuthenticationPolicy @params
                Write-VerboseOutput "    Updated global authentication policy"
            }
        } catch {
            Write-Warning "    Failed to update global authentication policy: $($_.Exception.Message)"
        }
    }
}

Write-Host "`n=== IMPORT COMPLETE ===" -ForegroundColor Green

if ($WhatIf) {
    Write-Host "WhatIf mode completed. No changes were made." -ForegroundColor Yellow
} else {
    Write-Host "ADFS configuration import completed!" -ForegroundColor Green
    Write-Host "Please review the imported configuration and restart the ADFS service if needed." -ForegroundColor Yellow
    Write-Host "Backup of previous configuration saved to: $backupPath" -ForegroundColor Cyan
}

# Display any warnings or recommendations
Write-Host "`n=== POST-IMPORT RECOMMENDATIONS ===" -ForegroundColor Yellow
Write-Host "1. Verify all relying party trusts are working correctly"
Write-Host "2. Test authentication flows"
Write-Host "3. Check certificate bindings and validity"
Write-Host "4. Review access control policies"
Write-Host "5. Restart ADFS service: Restart-Service -Name ADFSSRV"
Write-Host "6. Check ADFS event logs for any errors" 
