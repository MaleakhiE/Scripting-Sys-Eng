#Requires -RunAsAdministrator
#Requires -Modules ADFS

<#
.SYNOPSIS
    ADFS Configuration Assessment and Export Script
.DESCRIPTION
    Script untuk mengumpulkan dan export semua konfigurasi ADFS termasuk:
    - ADFS Farm Information
    - ADFS Properties & Settings
    - Relying Party Trusts
    - Claims Provider Trusts
    - Claim Descriptions
    - Certificates
    - Endpoints
    - Authentication Policies
    - Web Themes & Customization
    - Access Control Policies
.NOTES
    Author: IT Infrastructure Team
    Version: 1.0
    Date: 2026-01-08
    Requires: ADFS PowerShell Module, Run as Administrator on ADFS Server
.EXAMPLE
    .\getAssessmentADFS.ps1
    .\getAssessmentADFS.ps1 -OutputPath "C:\ADFSExport"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\ADFS_Assessment_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    
    [Parameter(Mandatory=$false)]
    [switch]$ExportToCSV,
    
    [Parameter(Mandatory=$false)]
    [switch]$ExportToXML,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeSensitive
)

#region Functions
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(switch($Level) { "ERROR" { "Red" } "WARNING" { "Yellow" } "SUCCESS" { "Green" } default { "White" } })
    Add-Content -Path "$OutputPath\ADFS_Assessment.log" -Value $logMessage
}

function Export-ToFile {
    param($Data, $FileName, $Description)
    try {
        if ($Data) {
            $Data | Export-Clixml -Path "$OutputPath\XML\$FileName.xml" -Force
            if ($ExportToCSV -and $Data -is [array]) {
                $Data | Export-Csv -Path "$OutputPath\CSV\$FileName.csv" -NoTypeInformation -Force
            }
            Write-Log "$Description exported successfully" "SUCCESS"
        } else {
            Write-Log "$Description - No data found" "WARNING"
        }
    } catch {
        Write-Log "Failed to export $Description : $_" "ERROR"
    }
}
#endregion

#region Initialization
Write-Host "`n" -NoNewline
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         ADFS Configuration Assessment Script                 ║" -ForegroundColor Cyan
Write-Host "║                    Version 1.0                               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "`n"

# Create output directories
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
New-Item -ItemType Directory -Path "$OutputPath\XML" -Force | Out-Null
New-Item -ItemType Directory -Path "$OutputPath\CSV" -Force | Out-Null
New-Item -ItemType Directory -Path "$OutputPath\HTML" -Force | Out-Null

Write-Log "Output directory: $OutputPath"
Write-Log "Starting ADFS Assessment..."

# Check ADFS Module
if (-not (Get-Module -ListAvailable -Name ADFS)) {
    Write-Log "ADFS PowerShell module not found. Please run on ADFS server." "ERROR"
    exit 1
}
Import-Module ADFS -ErrorAction Stop
#endregion

#region 1. ADFS Farm Information
Write-Log "Collecting ADFS Farm Information..."
try {
    $adfsFarmInfo = Get-AdfsFarmInformation
    Export-ToFile -Data $adfsFarmInfo -FileName "ADFS_FarmInformation" -Description "ADFS Farm Information"
    
    # Farm Summary
    $farmSummary = [PSCustomObject]@{
        CurrentFarmBehavior = $adfsFarmInfo.CurrentFarmBehavior
        FarmNodes = ($adfsFarmInfo.FarmNodes | ForEach-Object { $_.FQDN }) -join ", "
        NodeCount = $adfsFarmInfo.FarmNodes.Count
    }
    $farmSummary | Format-List | Out-File "$OutputPath\01_FarmSummary.txt"
} catch {
    Write-Log "Failed to get Farm Information: $_" "ERROR"
}
#endregion

#region 2. ADFS Properties
Write-Log "Collecting ADFS Properties..."
try {
    $adfsProperties = Get-AdfsProperties
    Export-ToFile -Data $adfsProperties -FileName "ADFS_Properties" -Description "ADFS Properties"
    
    # Properties Summary
    $propSummary = [PSCustomObject]@{
        HostName = $adfsProperties.HostName
        Identifier = $adfsProperties.Identifier
        DisplayName = $adfsProperties.DisplayName
        HttpPort = $adfsProperties.HttpPort
        HttpsPort = $adfsProperties.HttpsPort
        TlsClientPort = $adfsProperties.TlsClientPort
        IdTokenIssuer = $adfsProperties.IdTokenIssuer
        SSOLifetime = $adfsProperties.SsoLifetime
        PersistentSSOLifetimeMins = $adfsProperties.PersistentSsoLifetimeMins
        EnablePersistentSSO = $adfsProperties.EnablePersistentSso
        EnableKmsi = $adfsProperties.EnableKmsi
        KmsiLifetimeMins = $adfsProperties.KmsiLifetimeMins
        DeviceUsageWindowInDays = $adfsProperties.DeviceUsageWindowInDays
        EnableOAuthDeviceFlow = $adfsProperties.EnableOAuthDeviceFlow
        EnableIdPInitiatedSignonPage = $adfsProperties.EnableIdPInitiatedSignonPage
        IgnoreTokenBinding = $adfsProperties.IgnoreTokenBinding
        EnableExtranetLockout = $adfsProperties.EnableExtranetLockout
        ExtranetLockoutThreshold = $adfsProperties.ExtranetLockoutThreshold
        ExtranetObservationWindow = $adfsProperties.ExtranetObservationWindow
        ExtranetLockoutMode = $adfsProperties.ExtranetLockoutMode
    }
    $propSummary | Format-List | Out-File "$OutputPath\02_PropertiesSummary.txt"
} catch {
    Write-Log "Failed to get ADFS Properties: $_" "ERROR"
}
#endregion

#region 3. ADFS Sync Properties
Write-Log "Collecting ADFS Sync Properties..."
try {
    $adfsSyncProperties = Get-AdfsSyncProperties
    Export-ToFile -Data $adfsSyncProperties -FileName "ADFS_SyncProperties" -Description "ADFS Sync Properties"
} catch {
    Write-Log "Failed to get Sync Properties: $_" "ERROR"
}
#endregion

#region 4. Relying Party Trusts
Write-Log "Collecting Relying Party Trusts..."
try {
    $relyingParties = Get-AdfsRelyingPartyTrust
    Export-ToFile -Data $relyingParties -FileName "ADFS_RelyingPartyTrusts" -Description "Relying Party Trusts"
    
    # RP Summary
    $rpSummary = $relyingParties | Select-Object @{N='Name';E={$_.Name}},
        @{N='Identifier';E={$_.Identifier -join ", "}},
        @{N='Enabled';E={$_.Enabled}},
        @{N='WSFedEndpoint';E={$_.WSFedEndpoint}},
        @{N='SamlEndpoints';E={($_.SamlEndpoints | ForEach-Object { $_.Location }) -join "; "}},
        @{N='EncryptClaims';E={$_.EncryptClaims}},
        @{N='SignedSamlRequestsRequired';E={$_.SignedSamlRequestsRequired}},
        @{N='TokenLifetime';E={$_.TokenLifetime}},
        @{N='IssuanceTransformRulesCount';E={($_.IssuanceTransformRules -split "`n" | Where-Object {$_ -match "@RuleTemplate"}).Count}},
        @{N='AccessControlPolicyName';E={$_.AccessControlPolicyName}},
        @{N='Notes';E={$_.Notes}}
    
    $rpSummary | Export-Csv -Path "$OutputPath\CSV\ADFS_RelyingPartyTrusts_Summary.csv" -NoTypeInformation
    $rpSummary | Format-Table -AutoSize | Out-File "$OutputPath\03_RelyingPartyTrusts_Summary.txt" -Width 300
    
    # Export individual RP claim rules
    New-Item -ItemType Directory -Path "$OutputPath\RelyingPartyRules" -Force | Out-Null
    foreach ($rp in $relyingParties) {
        $safeName = $rp.Name -replace '[\\/:*?"<>|]', '_'
        $rpDetail = [PSCustomObject]@{
            Name = $rp.Name
            Identifier = $rp.Identifier -join "`n"
            Enabled = $rp.Enabled
            WSFedEndpoint = $rp.WSFedEndpoint
            IssuanceTransformRules = $rp.IssuanceTransformRules
            IssuanceAuthorizationRules = $rp.IssuanceAuthorizationRules
            DelegationAuthorizationRules = $rp.DelegationAuthorizationRules
            ImpersonationAuthorizationRules = $rp.ImpersonationAuthorizationRules
            AdditionalAuthenticationRules = $rp.AdditionalAuthenticationRules
        }
        $rpDetail | Out-File "$OutputPath\RelyingPartyRules\$safeName.txt"
    }
    
    Write-Log "Total Relying Party Trusts: $($relyingParties.Count)" "SUCCESS"
} catch {
    Write-Log "Failed to get Relying Party Trusts: $_" "ERROR"
}
#endregion

#region 5. Claims Provider Trusts
Write-Log "Collecting Claims Provider Trusts..."
try {
    $claimsProviders = Get-AdfsClaimsProviderTrust
    Export-ToFile -Data $claimsProviders -FileName "ADFS_ClaimsProviderTrusts" -Description "Claims Provider Trusts"
    
    $cpSummary = $claimsProviders | Select-Object Name, Identifier, Enabled, 
        @{N='AcceptanceTransformRulesCount';E={($_.AcceptanceTransformRules -split "`n" | Where-Object {$_ -match "@RuleTemplate"}).Count}}
    $cpSummary | Format-Table -AutoSize | Out-File "$OutputPath\04_ClaimsProviderTrusts_Summary.txt"
    
    Write-Log "Total Claims Provider Trusts: $($claimsProviders.Count)" "SUCCESS"
} catch {
    Write-Log "Failed to get Claims Provider Trusts: $_" "ERROR"
}
#endregion

#region 6. Claim Descriptions
Write-Log "Collecting Claim Descriptions..."
try {
    $claimDescriptions = Get-AdfsClaimDescription
    Export-ToFile -Data $claimDescriptions -FileName "ADFS_ClaimDescriptions" -Description "Claim Descriptions"
    
    $claimDescriptions | Select-Object Name, ClaimType, ShortName, IsAccepted, IsOffered, IsRequired |
        Export-Csv -Path "$OutputPath\CSV\ADFS_ClaimDescriptions.csv" -NoTypeInformation
    
    Write-Log "Total Claim Descriptions: $($claimDescriptions.Count)" "SUCCESS"
} catch {
    Write-Log "Failed to get Claim Descriptions: $_" "ERROR"
}
#endregion

#region 7. Certificates
Write-Log "Collecting Certificate Information..."
try {
    # Token Signing Certificate
    $tokenSigningCert = Get-AdfsCertificate -CertificateType Token-Signing
    Export-ToFile -Data $tokenSigningCert -FileName "ADFS_Certificate_TokenSigning" -Description "Token Signing Certificate"
    
    # Token Decrypting Certificate
    $tokenDecryptCert = Get-AdfsCertificate -CertificateType Token-Decrypting
    Export-ToFile -Data $tokenDecryptCert -FileName "ADFS_Certificate_TokenDecrypting" -Description "Token Decrypting Certificate"
    
    # Service Communications Certificate
    $serviceCommCert = Get-AdfsCertificate -CertificateType Service-Communications
    Export-ToFile -Data $serviceCommCert -FileName "ADFS_Certificate_ServiceCommunications" -Description "Service Communications Certificate"
    
    # All Certificates Summary
    $allCerts = Get-AdfsCertificate
    $certSummary = $allCerts | Select-Object @{N='CertificateType';E={$_.CertificateType}},
        @{N='Thumbprint';E={$_.Thumbprint}},
        @{N='Subject';E={$_.Certificate.Subject}},
        @{N='Issuer';E={$_.Certificate.Issuer}},
        @{N='NotBefore';E={$_.Certificate.NotBefore}},
        @{N='NotAfter';E={$_.Certificate.NotAfter}},
        @{N='DaysUntilExpiry';E={[math]::Round(($_.Certificate.NotAfter - (Get-Date)).TotalDays)}},
        @{N='IsPrimary';E={$_.IsPrimary}}
    
    $certSummary | Export-Csv -Path "$OutputPath\CSV\ADFS_Certificates_Summary.csv" -NoTypeInformation
    $certSummary | Format-Table -AutoSize | Out-File "$OutputPath\05_Certificates_Summary.txt" -Width 200
    
    # Certificate Expiry Warning
    $expiringCerts = $certSummary | Where-Object { $_.DaysUntilExpiry -lt 90 }
    if ($expiringCerts) {
        Write-Log "WARNING: Certificates expiring within 90 days found!" "WARNING"
        $expiringCerts | Format-Table | Out-File "$OutputPath\CERTIFICATE_EXPIRY_WARNING.txt"
    }
} catch {
    Write-Log "Failed to get Certificates: $_" "ERROR"
}
#endregion

#region 8. Endpoints
Write-Log "Collecting ADFS Endpoints..."
try {
    $endpoints = Get-AdfsEndpoint
    Export-ToFile -Data $endpoints -FileName "ADFS_Endpoints" -Description "ADFS Endpoints"
    
    $endpointSummary = $endpoints | Select-Object @{N='AddressPath';E={$_.AddressPath}},
        @{N='Protocol';E={$_.Protocol}},
        @{N='Enabled';E={$_.Enabled}},
        @{N='Proxy';E={$_.Proxy}},
        @{N='ClientCredentialType';E={$_.ClientCredentialType}},
        @{N='SecurityMode';E={$_.SecurityMode}}
    
    $endpointSummary | Export-Csv -Path "$OutputPath\CSV\ADFS_Endpoints.csv" -NoTypeInformation
    $endpointSummary | Format-Table -AutoSize | Out-File "$OutputPath\06_Endpoints_Summary.txt" -Width 200
    
    Write-Log "Total Endpoints: $($endpoints.Count)" "SUCCESS"
} catch {
    Write-Log "Failed to get Endpoints: $_" "ERROR"
}
#endregion

#region 9. Authentication Policies
Write-Log "Collecting Authentication Policies..."
try {
    # Global Authentication Policy
    $globalAuthPolicy = Get-AdfsGlobalAuthenticationPolicy
    Export-ToFile -Data $globalAuthPolicy -FileName "ADFS_GlobalAuthenticationPolicy" -Description "Global Authentication Policy"
    
    $authPolicySummary = [PSCustomObject]@{
        PrimaryIntranetAuthenticationProvider = $globalAuthPolicy.PrimaryIntranetAuthenticationProvider -join ", "
        PrimaryExtranetAuthenticationProvider = $globalAuthPolicy.PrimaryExtranetAuthenticationProvider -join ", "
        AdditionalAuthenticationProvider = $globalAuthPolicy.AdditionalAuthenticationProvider -join ", "
        DeviceAuthenticationEnabled = $globalAuthPolicy.DeviceAuthenticationEnabled
        DeviceAuthenticationMethod = $globalAuthPolicy.DeviceAuthenticationMethod
        WindowsIntegratedFallbackEnabled = $globalAuthPolicy.WindowsIntegratedFallbackEnabled
    }
    $authPolicySummary | Format-List | Out-File "$OutputPath\07_AuthenticationPolicy_Summary.txt"
    
    # Additional Authentication Rules
    $additionalAuthRules = Get-AdfsAdditionalAuthenticationRule -ErrorAction SilentlyContinue
    if ($additionalAuthRules) {
        Export-ToFile -Data $additionalAuthRules -FileName "ADFS_AdditionalAuthenticationRules" -Description "Additional Authentication Rules"
    }
} catch {
    Write-Log "Failed to get Authentication Policies: $_" "ERROR"
}
#endregion

#region 10. Access Control Policies
Write-Log "Collecting Access Control Policies..."
try {
    $accessControlPolicies = Get-AdfsAccessControlPolicy
    Export-ToFile -Data $accessControlPolicies -FileName "ADFS_AccessControlPolicies" -Description "Access Control Policies"
    
    $acpSummary = $accessControlPolicies | Select-Object Name, Identifier, IsBuiltIn, Description
    $acpSummary | Export-Csv -Path "$OutputPath\CSV\ADFS_AccessControlPolicies.csv" -NoTypeInformation
    $acpSummary | Format-Table -AutoSize | Out-File "$OutputPath\08_AccessControlPolicies_Summary.txt" -Width 200
    
    Write-Log "Total Access Control Policies: $($accessControlPolicies.Count)" "SUCCESS"
} catch {
    Write-Log "Failed to get Access Control Policies: $_" "ERROR"
}
#endregion

#region 11. Web Themes
Write-Log "Collecting Web Themes..."
try {
    $webThemes = Get-AdfsWebTheme
    Export-ToFile -Data $webThemes -FileName "ADFS_WebThemes" -Description "Web Themes"
    
    $webThemes | Select-Object Name, IsBuiltinTheme, StyleSheet | 
        Format-Table -AutoSize | Out-File "$OutputPath\09_WebThemes_Summary.txt"
    
    # Active Theme
    $webConfig = Get-AdfsWebConfig
    Export-ToFile -Data $webConfig -FileName "ADFS_WebConfig" -Description "Web Config"
    
    Write-Log "Active Theme: $($webConfig.ActiveThemeName)" "SUCCESS"
} catch {
    Write-Log "Failed to get Web Themes: $_" "ERROR"
}
#endregion

#region 12. Global Web Content
Write-Log "Collecting Global Web Content..."
try {
    $globalWebContent = Get-AdfsGlobalWebContent
    Export-ToFile -Data $globalWebContent -FileName "ADFS_GlobalWebContent" -Description "Global Web Content"
    
    $webContentSummary = [PSCustomObject]@{
        CompanyName = $globalWebContent.CompanyName
        HelpDeskLink = $globalWebContent.HelpDeskLink
        HelpDeskLinkText = $globalWebContent.HelpDeskLinkText
        HomeLink = $globalWebContent.HomeLink
        HomeLinkText = $globalWebContent.HomeLinkText
        PrivacyLink = $globalWebContent.PrivacyLink
        PrivacyLinkText = $globalWebContent.PrivacyLinkText
        SignInPageDescriptionText = $globalWebContent.SignInPageDescriptionText
        SignOutPageDescriptionText = $globalWebContent.SignOutPageDescriptionText
        ErrorPageDescriptionText = $globalWebContent.ErrorPageDescriptionText
        UpdatePasswordPageDescriptionText = $globalWebContent.UpdatePasswordPageDescriptionText
    }
    $webContentSummary | Format-List | Out-File "$OutputPath\10_GlobalWebContent_Summary.txt"
} catch {
    Write-Log "Failed to get Global Web Content: $_" "ERROR"
}
#endregion

#region 13. Client Access Policies
Write-Log "Collecting Client Access Policies..."
try {
    $clientAccessPolicy = Get-AdfsClient -ErrorAction SilentlyContinue
    if ($clientAccessPolicy) {
        Export-ToFile -Data $clientAccessPolicy -FileName "ADFS_Clients" -Description "ADFS Clients (OAuth)"
        
        $clientAccessPolicy | Select-Object Name, ClientId, Enabled, Description |
            Export-Csv -Path "$OutputPath\CSV\ADFS_Clients.csv" -NoTypeInformation
        
        Write-Log "Total OAuth Clients: $($clientAccessPolicy.Count)" "SUCCESS"
    }
} catch {
    Write-Log "Failed to get Client Access Policies: $_" "ERROR"
}
#endregion

#region 14. Application Groups (OAuth/OIDC)
Write-Log "Collecting Application Groups..."
try {
    $appGroups = Get-AdfsApplicationGroup -ErrorAction SilentlyContinue
    if ($appGroups) {
        Export-ToFile -Data $appGroups -FileName "ADFS_ApplicationGroups" -Description "Application Groups"
        
        $appGroups | Select-Object Name, ApplicationGroupIdentifier, Enabled, Description |
            Export-Csv -Path "$OutputPath\CSV\ADFS_ApplicationGroups.csv" -NoTypeInformation
        
        # Get applications within each group
        New-Item -ItemType Directory -Path "$OutputPath\ApplicationGroups" -Force | Out-Null
        foreach ($group in $appGroups) {
            $apps = Get-AdfsApplication -ApplicationGroupIdentifier $group.ApplicationGroupIdentifier -ErrorAction SilentlyContinue
            if ($apps) {
                $safeName = $group.Name -replace '[\\/:*?"<>|]', '_'
                $apps | Export-Clixml -Path "$OutputPath\ApplicationGroups\$safeName.xml"
            }
        }
        
        Write-Log "Total Application Groups: $($appGroups.Count)" "SUCCESS"
    }
} catch {
    Write-Log "Failed to get Application Groups: $_" "ERROR"
}
#endregion

#region 15. Attribute Stores
Write-Log "Collecting Attribute Stores..."
try {
    $attributeStores = Get-AdfsAttributeStore
    Export-ToFile -Data $attributeStores -FileName "ADFS_AttributeStores" -Description "Attribute Stores"
    
    $attributeStores | Select-Object Name, StoreType, Configuration |
        Format-Table -AutoSize | Out-File "$OutputPath\11_AttributeStores_Summary.txt" -Width 200
    
    Write-Log "Total Attribute Stores: $($attributeStores.Count)" "SUCCESS"
} catch {
    Write-Log "Failed to get Attribute Stores: $_" "ERROR"
}
#endregion

#region 16. Device Registration
Write-Log "Collecting Device Registration Settings..."
try {
    $deviceRegistration = Get-AdfsDeviceRegistration -ErrorAction SilentlyContinue
    if ($deviceRegistration) {
        Export-ToFile -Data $deviceRegistration -FileName "ADFS_DeviceRegistration" -Description "Device Registration"
        
        $deviceRegistration | Format-List | Out-File "$OutputPath\12_DeviceRegistration_Summary.txt"
    }
} catch {
    Write-Log "Failed to get Device Registration: $_" "ERROR"
}
#endregion

#region 17. Non-Claims Aware Relying Party Trusts
Write-Log "Collecting Non-Claims Aware Relying Party Trusts..."
try {
    $nonClaimsRP = Get-AdfsNonClaimsAwareRelyingPartyTrust -ErrorAction SilentlyContinue
    if ($nonClaimsRP) {
        Export-ToFile -Data $nonClaimsRP -FileName "ADFS_NonClaimsAwareRelyingPartyTrusts" -Description "Non-Claims Aware RP Trusts"
        
        Write-Log "Total Non-Claims Aware RP Trusts: $($nonClaimsRP.Count)" "SUCCESS"
    }
} catch {
    Write-Log "Failed to get Non-Claims Aware RP Trusts: $_" "ERROR"
}
#endregion

#region 18. Scope Descriptions (OAuth)
Write-Log "Collecting Scope Descriptions..."
try {
    $scopeDescriptions = Get-AdfsScopeDescription -ErrorAction SilentlyContinue
    if ($scopeDescriptions) {
        Export-ToFile -Data $scopeDescriptions -FileName "ADFS_ScopeDescriptions" -Description "Scope Descriptions"
        
        $scopeDescriptions | Select-Object Name, Description |
            Export-Csv -Path "$OutputPath\CSV\ADFS_ScopeDescriptions.csv" -NoTypeInformation
    }
} catch {
    Write-Log "Failed to get Scope Descriptions: $_" "ERROR"
}
#endregion

#region 19. Local Claims Provider Trust
Write-Log "Collecting Local Claims Provider Trust..."
try {
    $localClaimsProvider = Get-AdfsLocalClaimsProviderTrust -ErrorAction SilentlyContinue
    if ($localClaimsProvider) {
        Export-ToFile -Data $localClaimsProvider -FileName "ADFS_LocalClaimsProviderTrust" -Description "Local Claims Provider Trust"
    }
} catch {
    Write-Log "Failed to get Local Claims Provider Trust: $_" "ERROR"
}
#endregion

#region 20. Relying Party Web Theme
Write-Log "Collecting Relying Party Web Themes..."
try {
    $rpWebThemes = Get-AdfsRelyingPartyWebTheme -ErrorAction SilentlyContinue
    if ($rpWebThemes) {
        Export-ToFile -Data $rpWebThemes -FileName "ADFS_RelyingPartyWebThemes" -Description "Relying Party Web Themes"
    }
} catch {
    Write-Log "Failed to get Relying Party Web Themes: $_" "ERROR"
}
#endregion

#region 21. ADFS Service Account
Write-Log "Collecting Service Account Information..."
try {
    $serviceAccount = (Get-WmiObject Win32_Service -Filter "Name='adfssrv'").StartName
    $serviceAccountInfo = [PSCustomObject]@{
        ServiceName = "adfssrv"
        ServiceAccount = $serviceAccount
        ServiceStatus = (Get-Service adfssrv).Status
        StartType = (Get-Service adfssrv).StartType
    }
    $serviceAccountInfo | Format-List | Out-File "$OutputPath\13_ServiceAccount_Summary.txt"
    Export-ToFile -Data $serviceAccountInfo -FileName "ADFS_ServiceAccount" -Description "Service Account"
} catch {
    Write-Log "Failed to get Service Account: $_" "ERROR"
}
#endregion

#region 22. SSL Bindings
Write-Log "Collecting SSL Bindings..."
try {
    $sslBindings = Get-AdfsSslCertificate
    Export-ToFile -Data $sslBindings -FileName "ADFS_SslCertificates" -Description "SSL Certificates"
    
    $sslBindings | Select-Object HostName, PortNumber, CertificateHash |
        Format-Table -AutoSize | Out-File "$OutputPath\14_SslBindings_Summary.txt"
} catch {
    Write-Log "Failed to get SSL Bindings: $_" "ERROR"
}
#endregion

#region 23. ADFS Audit Settings
Write-Log "Collecting Audit Settings..."
try {
    $auditSettings = auditpol /get /subcategory:"Application Generated" 2>$null
    $auditSettings | Out-File "$OutputPath\15_AuditSettings.txt"
    
    # Check if ADFS auditing is enabled
    $adfsAuditLevel = (Get-AdfsProperties).AuditLevel
    "ADFS Audit Level: $adfsAuditLevel" | Out-File "$OutputPath\15_AuditSettings.txt" -Append
} catch {
    Write-Log "Failed to get Audit Settings: $_" "ERROR"
}
#endregion

#region 24. ADFS Event Logs (Recent)
Write-Log "Collecting Recent ADFS Event Logs..."
try {
    # Admin Events (Last 100)
    $adminEvents = Get-WinEvent -LogName "AD FS/Admin" -MaxEvents 100 -ErrorAction SilentlyContinue
    if ($adminEvents) {
        $adminEvents | Select-Object TimeCreated, Id, LevelDisplayName, Message |
            Export-Csv -Path "$OutputPath\CSV\ADFS_AdminEvents_Recent.csv" -NoTypeInformation
    }
    
    # Error Events Only
    $errorEvents = Get-WinEvent -LogName "AD FS/Admin" -MaxEvents 500 -ErrorAction SilentlyContinue | 
        Where-Object { $_.Level -eq 2 }
    if ($errorEvents) {
        $errorEvents | Select-Object TimeCreated, Id, Message |
            Export-Csv -Path "$OutputPath\CSV\ADFS_ErrorEvents.csv" -NoTypeInformation
        Write-Log "Found $($errorEvents.Count) error events" "WARNING"
    }
} catch {
    Write-Log "Failed to get Event Logs: $_" "ERROR"
}
#endregion

#region 25. Web Application Proxy (if exists)
Write-Log "Checking for Web Application Proxy..."
try {
    $wapConfig = Get-WebApplicationProxyConfiguration -ErrorAction SilentlyContinue
    if ($wapConfig) {
        Export-ToFile -Data $wapConfig -FileName "WAP_Configuration" -Description "WAP Configuration"
        
        $wapApps = Get-WebApplicationProxyApplication -ErrorAction SilentlyContinue
        if ($wapApps) {
            Export-ToFile -Data $wapApps -FileName "WAP_Applications" -Description "WAP Applications"
            $wapApps | Select-Object Name, ExternalUrl, BackendServerUrl, ExternalPreauthentication |
                Export-Csv -Path "$OutputPath\CSV\WAP_Applications.csv" -NoTypeInformation
        }
        
        Write-Log "WAP Configuration collected" "SUCCESS"
    } else {
        Write-Log "Web Application Proxy not configured on this server" "INFO"
    }
} catch {
    Write-Log "WAP not installed or not accessible: $_" "WARNING"
}
#endregion

#region Generate HTML Report
Write-Log "Generating HTML Report..."
try {
$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>ADFS Assessment Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #106ebe; margin-top: 30px; }
        h3 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; background-color: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        tr:hover { background-color: #e8f4fc; }
        .summary-box { background-color: white; padding: 20px; margin: 10px 0; border-radius: 5px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .warning { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 10px; margin: 10px 0; }
        .error { background-color: #f8d7da; border-left: 4px solid #dc3545; padding: 10px; margin: 10px 0; }
        .success { background-color: #d4edda; border-left: 4px solid #28a745; padding: 10px; margin: 10px 0; }
        .info { background-color: #d1ecf1; border-left: 4px solid #17a2b8; padding: 10px; margin: 10px 0; }
        .timestamp { color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>🔐 ADFS Configuration Assessment Report</h1>
    <p class="timestamp">Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    <p class="timestamp">Server: $env:COMPUTERNAME</p>
    
    <div class="summary-box">
        <h2>📊 Executive Summary</h2>
        <table>
            <tr><th>Item</th><th>Value</th></tr>
            <tr><td>ADFS Host Name</td><td>$($adfsProperties.HostName)</td></tr>
            <tr><td>Federation Service Name</td><td>$($adfsProperties.Identifier)</td></tr>
            <tr><td>Total Relying Party Trusts</td><td>$($relyingParties.Count)</td></tr>
            <tr><td>Total Claims Provider Trusts</td><td>$($claimsProviders.Count)</td></tr>
            <tr><td>Farm Nodes</td><td>$($adfsFarmInfo.FarmNodes.Count)</td></tr>
            <tr><td>Active Web Theme</td><td>$($webConfig.ActiveThemeName)</td></tr>
        </table>
    </div>
    
    <h2>🖥️ Farm Information</h2>
    <div class="summary-box">
        <table>
            <tr><th>Node FQDN</th><th>Status</th></tr>
            $(foreach ($node in $adfsFarmInfo.FarmNodes) {
                "<tr><td>$($node.FQDN)</td><td>Active</td></tr>"
            })
        </table>
    </div>
    
    <h2>📜 Certificates</h2>
    <div class="summary-box">
        <table>
            <tr><th>Type</th><th>Subject</th><th>Expiry</th><th>Days Until Expiry</th></tr>
            $(foreach ($cert in $certSummary) {
                $expiryClass = if ($cert.DaysUntilExpiry -lt 30) { "error" } elseif ($cert.DaysUntilExpiry -lt 90) { "warning" } else { "" }
                "<tr class='$expiryClass'><td>$($cert.CertificateType)</td><td>$($cert.Subject)</td><td>$($cert.NotAfter)</td><td>$($cert.DaysUntilExpiry)</td></tr>"
            })
        </table>
    </div>
    
    <h2>🔗 Relying Party Trusts</h2>
    <div class="summary-box">
        <table>
            <tr><th>Name</th><th>Enabled</th><th>Identifier</th><th>Token Lifetime</th></tr>
            $(foreach ($rp in $relyingParties) {
                $enabledClass = if ($rp.Enabled) { "" } else { "warning" }
                "<tr class='$enabledClass'><td>$($rp.Name)</td><td>$($rp.Enabled)</td><td>$($rp.Identifier -join ', ')</td><td>$($rp.TokenLifetime)</td></tr>"
            })
        </table>
    </div>
    
    <h2>🔌 Endpoints</h2>
    <div class="summary-box">
        <table>
            <tr><th>Path</th><th>Protocol</th><th>Enabled</th><th>Proxy</th></tr>
            $(foreach ($ep in $endpoints | Where-Object { $_.Enabled }) {
                "<tr><td>$($ep.AddressPath)</td><td>$($ep.Protocol)</td><td>$($ep.Enabled)</td><td>$($ep.Proxy)</td></tr>"
            })
        </table>
    </div>
    
    <h2>🔒 Authentication Policy</h2>
    <div class="summary-box">
        <table>
            <tr><th>Setting</th><th>Value</th></tr>
            <tr><td>Primary Intranet Provider</td><td>$($globalAuthPolicy.PrimaryIntranetAuthenticationProvider -join ', ')</td></tr>
            <tr><td>Primary Extranet Provider</td><td>$($globalAuthPolicy.PrimaryExtranetAuthenticationProvider -join ', ')</td></tr>
            <tr><td>Device Authentication</td><td>$($globalAuthPolicy.DeviceAuthenticationEnabled)</td></tr>
        </table>
    </div>
    
    <hr>
    <p class="timestamp">Report generated by ADFS Assessment Script v1.0</p>
</body>
</html>
"@

$htmlReport | Out-File "$OutputPath\HTML\ADFS_Assessment_Report.html" -Encoding UTF8
Write-Log "HTML Report generated" "SUCCESS"
} catch {
    Write-Log "Failed to generate HTML Report: $_" "ERROR"
}
#endregion

#region Generate Summary Report
Write-Log "Generating Summary Report..."
try {
$summaryReport = @"
================================================================================
                    ADFS CONFIGURATION ASSESSMENT SUMMARY
================================================================================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Server: $env:COMPUTERNAME
Output Path: $OutputPath
================================================================================

1. ADFS FARM INFORMATION
------------------------
Host Name: $($adfsProperties.HostName)
Identifier: $($adfsProperties.Identifier)
Display Name: $($adfsProperties.DisplayName)
Farm Behavior Level: $($adfsFarmInfo.CurrentFarmBehavior)
Number of Farm Nodes: $($adfsFarmInfo.FarmNodes.Count)
Farm Nodes: $(($adfsFarmInfo.FarmNodes | ForEach-Object { $_.FQDN }) -join ", ")

2. ADFS PROPERTIES
------------------
HTTP Port: $($adfsProperties.HttpPort)
HTTPS Port: $($adfsProperties.HttpsPort)
SSO Lifetime (minutes): $($adfsProperties.SsoLifetime)
Persistent SSO Enabled: $($adfsProperties.EnablePersistentSso)
KMSI Enabled: $($adfsProperties.EnableKmsi)
IdP Initiated Signon Page: $($adfsProperties.EnableIdPInitiatedSignonPage)
Extranet Lockout Enabled: $($adfsProperties.EnableExtranetLockout)
Extranet Lockout Threshold: $($adfsProperties.ExtranetLockoutThreshold)

3. CERTIFICATES SUMMARY
-----------------------
$(foreach ($cert in $certSummary) {
"Type: $($cert.CertificateType)
  Subject: $($cert.Subject)
  Expires: $($cert.NotAfter)
  Days Until Expiry: $($cert.DaysUntilExpiry)
  Is Primary: $($cert.IsPrimary)
"
})

4. RELYING PARTY TRUSTS
-----------------------
Total Count: $($relyingParties.Count)
Enabled: $(($relyingParties | Where-Object { $_.Enabled }).Count)
Disabled: $(($relyingParties | Where-Object { -not $_.Enabled }).Count)

List of Relying Parties:
$(foreach ($rp in $relyingParties) {
"  - $($rp.Name) [Enabled: $($rp.Enabled)]"
})

5. CLAIMS PROVIDER TRUSTS
-------------------------
Total Count: $($claimsProviders.Count)
$(foreach ($cp in $claimsProviders) {
"  - $($cp.Name) [Enabled: $($cp.Enabled)]"
})

6. AUTHENTICATION POLICY
------------------------
Primary Intranet: $($globalAuthPolicy.PrimaryIntranetAuthenticationProvider -join ", ")
Primary Extranet: $($globalAuthPolicy.PrimaryExtranetAuthenticationProvider -join ", ")
Additional Providers: $($globalAuthPolicy.AdditionalAuthenticationProvider -join ", ")
Device Authentication: $($globalAuthPolicy.DeviceAuthenticationEnabled)

7. WEB CONFIGURATION
--------------------
Active Theme: $($webConfig.ActiveThemeName)
Company Name: $($globalWebContent.CompanyName)

8. ENDPOINTS (Enabled)
----------------------
$(foreach ($ep in ($endpoints | Where-Object { $_.Enabled })) {
"  - $($ep.AddressPath) [$($ep.Protocol)]"
})

9. SERVICE ACCOUNT
------------------
Account: $serviceAccount
Service Status: $((Get-Service adfssrv).Status)

================================================================================
                              FILES GENERATED
================================================================================
XML Exports: $OutputPath\XML\
CSV Exports: $OutputPath\CSV\
HTML Report: $OutputPath\HTML\ADFS_Assessment_Report.html
Relying Party Rules: $OutputPath\RelyingPartyRules\

================================================================================
                           ASSESSMENT COMPLETE
================================================================================
"@

$summaryReport | Out-File "$OutputPath\ADFS_Assessment_Summary.txt" -Encoding UTF8
Write-Host $summaryReport
} catch {
    Write-Log "Failed to generate Summary Report: $_" "ERROR"
}
#endregion

#region Completion
Write-Host "`n" -NoNewline
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              ADFS Assessment Completed Successfully          ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host "`n"
Write-Log "Assessment completed. Output saved to: $OutputPath" "SUCCESS"
Write-Host "Open HTML Report: $OutputPath\HTML\ADFS_Assessment_Report.html" -ForegroundColor Cyan
#endregion
