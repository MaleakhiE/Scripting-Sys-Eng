param(
    [string]$ExportPath = "C:\ADFS-Export-$(Get-Date -Format 'dd-MM-yyyy-HHmm')",
    [switch]$IncludePrivateKeys = $false,
    [switch]$Verbose = $false
)

# Function to write verbose output
function Write-VerboseOutput {
    param([string]$Message)
    if ($Verbose) {
        Write-Host $Message -ForegroundColor Cyan
    }
}

# Function to safely export data with error handling
function Export-SafeData {
    param(
        [scriptblock]$Command,
        [string]$FilePath,
        [string]$Description,
        [string]$Format = "json"
    )
    
    try {
        Write-Host "Exporting $Description..."
        $data = & $Command
        
        if ($data) {
            switch ($Format.ToLower()) {
                "json" {
                    $data | ConvertTo-Json -Depth 10 | Out-File $FilePath -Encoding UTF8
                }
                "xml" {
                    $data | Export-Clixml $FilePath
                }
                "txt" {
                    $data | Format-List | Out-File $FilePath -Encoding UTF8
                }
            }
            Write-VerboseOutput "  ✓ Exported to: $FilePath"
        } else {
            Write-Warning "  ⚠ No data found for $Description"
        }
    }
    catch {
        Write-Warning "  ✗ Failed to export $Description`: $($_.Exception.Message)"
    }
}

# Create export directory structure
$folders = @(
    "$ExportPath\Service\Properties",
    "$ExportPath\Service\AttributeStores",
    "$ExportPath\Service\AuthenticationMethods",
    "$ExportPath\Service\Certificates",
    "$ExportPath\Service\ClaimDescriptions",
    "$ExportPath\Service\DeviceRegistration",
    "$ExportPath\Service\Endpoints",
    "$ExportPath\Service\ScopeDescriptions",
    "$ExportPath\Service\WebApplicationProxy",
    "$ExportPath\AccessControlPolicies",
    "$ExportPath\RelyingPartyTrusts",
    "$ExportPath\ClaimsProviderTrusts",
    "$ExportPath\ApplicationGroups",
    "$ExportPath\Logs"
)

Write-Host "Creating export directory structure..." -ForegroundColor Green
foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
}

Write-Host "`n=== ADFS SERVICE CONFIGURATION ===" -ForegroundColor Yellow

# Service Properties
Export-SafeData -Command { Get-AdfsProperties } -FilePath "$ExportPath\Service\Properties\adfs-properties.json" -Description "ADFS Properties"

Export-SafeData -Command { Get-AdfsGlobalAuthenticationPolicy } -FilePath "$ExportPath\Service\Properties\global-auth-policy.json" -Description "Global Authentication Policy"

# Export Additional Authentication Rules (MFA Rules)
try {
    $mfaRules = Get-AdfsGlobalAuthenticationPolicy | Select-Object AdditionalAuthenticationRules
    if ($mfaRules.AdditionalAuthenticationRules) {
        Export-SafeData -Command { Get-AdfsGlobalAuthenticationPolicy | Select-Object AdditionalAuthenticationRules } -FilePath "$ExportPath\Service\Properties\additional-auth-rules.json" -Description "Additional Authentication Rules (MFA)"
    } else {
        Write-VerboseOutput "  ℹ No Additional Authentication Rules configured"
    }
} catch {
    Write-VerboseOutput "  ℹ Additional Authentication Rules not available"
}

# Attribute Stores
Export-SafeData -Command { Get-AdfsAttributeStore } -FilePath "$ExportPath\Service\AttributeStores\attribute-stores.json" -Description "Attribute Stores"

# Authentication Methods
Export-SafeData -Command { Get-AdfsAuthenticationProvider } -FilePath "$ExportPath\Service\AuthenticationMethods\auth-providers.json" -Description "Authentication Providers"

Export-SafeData -Command { Get-AdfsGlobalAuthenticationPolicy } -FilePath "$ExportPath\Service\AuthenticationMethods\global-auth-policy.json" -Description "Global Authentication Policy Details"

# Certificates
Export-SafeData -Command { Get-AdfsCertificate } -FilePath "$ExportPath\Service\Certificates\adfs-certificates.txt" -Description "ADFS Certificates" -Format "txt"

# Claim Descriptions
Export-SafeData -Command { Get-AdfsClaimDescription } -FilePath "$ExportPath\Service\ClaimDescriptions\claim-descriptions.json" -Description "Claim Descriptions"

# Device Registration
Export-SafeData -Command { Get-AdfsDeviceRegistration } -FilePath "$ExportPath\Service\DeviceRegistration\device-registration.json" -Description "Device Registration Settings"

# Device Registration Hosts (if available)
try {
    $deviceRegHosts = Get-AdfsDeviceRegistration | Select-Object DeviceRegistrationServiceInternalUrl, DeviceRegistrationServiceExternalUrl
    if ($deviceRegHosts) {
        Export-SafeData -Command { Get-AdfsDeviceRegistration | Select-Object DeviceRegistrationServiceInternalUrl, DeviceRegistrationServiceExternalUrl } -FilePath "$ExportPath\Service\DeviceRegistration\registration-hosts.json" -Description "Device Registration Hosts"
    }
} catch {
    Write-VerboseOutput "  ℹ Device Registration Hosts not available (may not be configured)"
}

# Endpoints
Export-SafeData -Command { Get-AdfsEndpoint } -FilePath "$ExportPath\Service\Endpoints\endpoints.json" -Description "ADFS Endpoints"

# Scope Descriptions (OAuth/OpenID Connect)
try {
    Export-SafeData -Command { Get-AdfsWebApiApplication | Select-Object -ExpandProperty AllowedClientTypes -ErrorAction SilentlyContinue } -FilePath "$ExportPath\Service\ScopeDescriptions\api-scopes.json" -Description "Web API Scopes"
} catch {
    Write-VerboseOutput "  ℹ OAuth Scopes not available (may not be configured)"
}

# Web Application Proxy (if configured)
try {
    Export-SafeData -Command { Get-AdfsWebApplicationProxyRelyingPartyTrust } -FilePath "$ExportPath\Service\WebApplicationProxy\wap-trusts.json" -Description "Web Application Proxy Trusts"
} catch {
    Write-VerboseOutput "  ℹ Web Application Proxy not configured"
}

Write-Host "`n=== ACCESS CONTROL POLICIES ===" -ForegroundColor Yellow
Export-SafeData -Command { Get-AdfsAccessControlPolicy } -FilePath "$ExportPath\AccessControlPolicies\access-control-policies.json" -Description "Access Control Policies"

Write-Host "`n=== RELYING PARTY TRUSTS ===" -ForegroundColor Yellow
Export-SafeData -Command { Get-AdfsRelyingPartyTrust } -FilePath "$ExportPath\RelyingPartyTrusts\relying-party-trusts.xml" -Description "Relying Party Trusts" -Format "xml"

# Export individual RP trust details
try {
    $rpTrusts = Get-AdfsRelyingPartyTrust
    foreach ($rp in $rpTrusts) {
        $safeName = $rp.Name -replace '[\\\/:*?"<>|]', '_'
        
        # Export claim rules
        Export-SafeData -Command { Get-AdfsRelyingPartyTrust -Name $rp.Name | Select-Object IssuanceTransformRules, IssuanceAuthorizationRules, DelegationAuthorizationRules } -FilePath "$ExportPath\RelyingPartyTrusts\$safeName-claim-rules.json" -Description "Claim Rules for $($rp.Name)"
        
        # Export authentication policy
        try {
            Export-SafeData -Command { Get-AdfsRelyingPartyTrust -Name $rp.Name | Get-AdfsRelyingPartyWebContent } -FilePath "$ExportPath\RelyingPartyTrusts\$safeName-web-content.json" -Description "Web Content for $($rp.Name)"
        } catch {
            Write-VerboseOutput "  ℹ No web content for $($rp.Name)"
        }
    }
} catch {
    Write-Warning "Failed to export individual RP trust details"
}

Write-Host "`n=== CLAIMS PROVIDER TRUSTS ===" -ForegroundColor Yellow
Export-SafeData -Command { Get-AdfsClaimsProviderTrust } -FilePath "$ExportPath\ClaimsProviderTrusts\claims-provider-trusts.xml" -Description "Claims Provider Trusts" -Format "xml"

# Export individual CP trust details
try {
    $cpTrusts = Get-AdfsClaimsProviderTrust
    foreach ($cp in $cpTrusts) {
        $safeName = $cp.Name -replace '[\\\/:*?"<>|]', '_'
        Export-SafeData -Command { Get-AdfsClaimsProviderTrust -Name $cp.Name | Select-Object AcceptanceTransformRules, OrganizationalAccountSuffix } -FilePath "$ExportPath\ClaimsProviderTrusts\$safeName-details.json" -Description "Details for $($cp.Name)"
    }
} catch {
    Write-Warning "Failed to export individual CP trust details"
}

Write-Host "`n=== APPLICATION GROUPS ===" -ForegroundColor Yellow
Export-SafeData -Command { Get-AdfsApplicationGroup } -FilePath "$ExportPath\ApplicationGroups\application-groups.json" -Description "Application Groups"

# Export Native Client Applications
Export-SafeData -Command { Get-AdfsNativeClientApplication } -FilePath "$ExportPath\ApplicationGroups\native-client-apps.json" -Description "Native Client Applications"

# Export Server Applications
Export-SafeData -Command { Get-AdfsServerApplication } -FilePath "$ExportPath\ApplicationGroups\server-applications.json" -Description "Server Applications"

# Export Web API Applications
Export-SafeData -Command { Get-AdfsWebApiApplication } -FilePath "$ExportPath\ApplicationGroups\web-api-applications.json" -Description "Web API Applications"

# Export OAuth Clients
Export-SafeData -Command { Get-AdfsClient } -FilePath "$ExportPath\ApplicationGroups\oauth-clients.json" -Description "OAuth Clients"

Write-Host "`n=== SSL CERTIFICATE EXPORT ===" -ForegroundColor Yellow
try {
    $federationServiceName = (Get-AdfsProperties).Hostname
    $cert = Get-ChildItem -Path Cert:\LocalMachine\My |
        Where-Object { $_.Subject -like "*$federationServiceName*" } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    if ($cert) {
        Write-Host "Found SSL certificate: $($cert.Subject)"
        if ($IncludePrivateKeys) {
            $password = Read-Host -AsSecureString "Enter password to export SSL certificate (.pfx)"
            $pfxPath = "$ExportPath\Service\Certificates\adfs-ssl-cert.pfx"
            $cert | Export-PfxCertificate -FilePath $pfxPath -Password $password
            Write-Host "Exported SSL certificate with private key to $pfxPath"
        } else {
            # Export public key only
            $cerPath = "$ExportPath\Service\Certificates\adfs-ssl-cert.cer"
            $cert | Export-Certificate -FilePath $cerPath
            Write-Host "Exported SSL certificate (public key only) to $cerPath"
        }
    } else {
        Write-Warning "Could not find SSL certificate for ADFS with subject containing '$federationServiceName'"
    }
} catch {
    Write-Warning "Failed to export SSL certificate: $($_.Exception.Message)"
}

Write-Host "`n=== ADDITIONAL CONFIGURATION ===" -ForegroundColor Yellow

# Export local claims
try {
    Export-SafeData -Command { Get-AdfsLocalClaimsProviderTrust } -FilePath "$ExportPath\Service\Properties\local-claims-provider.json" -Description "Local Claims Provider Trust"
} catch {
    Write-VerboseOutput "  ℹ Local Claims Provider Trust not available"
}

# Export web themes
try {
    Export-SafeData -Command { Get-AdfsWebTheme } -FilePath "$ExportPath\Service\Properties\web-themes.json" -Description "Web Themes"
} catch {
    Write-VerboseOutput "  ℹ Web Themes not available"
}

# Export custom web content
try {
    Export-SafeData -Command { Get-AdfsGlobalWebContent } -FilePath "$ExportPath\Service\Properties\global-web-content.json" -Description "Global Web Content"
} catch {
    Write-VerboseOutput "  ℹ Global Web Content not available"
}

Write-Host "`n=== CREATING EXPORT SUMMARY ===" -ForegroundColor Yellow

# Create export summary
$summary = @{
    ExportDate = Get-Date
    ExportPath = $ExportPath
    ADFSProperties = (Get-AdfsProperties | Select-Object Hostname, DisplayName, FederationServiceName)
    ExportedComponents = @(
        "ADFS Properties",
        "Global Authentication Policy",
        "Attribute Stores",
        "Authentication Providers",
        "Certificates",
        "Claim Descriptions",
        "Device Registration",
        "Endpoints",
        "Access Control Policies",
        "Relying Party Trusts",
        "Claims Provider Trusts",
        "Application Groups",
        "OAuth Clients",
        "SSL Certificate"
    )
    Notes = "Complete ADFS configuration export including all service components"
}

$summary | ConvertTo-Json -Depth 5 | Out-File "$ExportPath\export-summary.json" -Encoding UTF8

Write-Host "`n=== EXPORT COMPLETE ===" -ForegroundColor Green
Write-Host "All ADFS configuration exported to: $ExportPath" -ForegroundColor Green
Write-Host "Export summary saved to: $ExportPath\export-summary.json" -ForegroundColor Green

# Display folder structure
Write-Host "`nExported folder structure:" -ForegroundColor Cyan
Get-ChildItem -Path $ExportPath -Recurse -Directory | ForEach-Object {
    $indent = "  " * (($_.FullName.Split('\').Count) - ($ExportPath.Split('\').Count))
    Write-Host "$indent$($_.Name)" -ForegroundColor DarkCyan
}