# Import required modules
Import-Module GroupPolicy
Import-Module ActiveDirectory

# Output file path
$outputPath = "C:\GPO_Detailed_Report.csv"

# Create an empty array for results
$results = @()

function Get-PolicyDetails {
    param (
        [System.Xml.XmlElement]$extensionData
    )
    
    if (-not $extensionData) {
        return "N/A"
    }

    # Use ArrayList instead of fixed-size array
    $policyDetails = [System.Collections.ArrayList]@()
    
    # Recursive function to extract all policy details
    function Extract-PolicyInfo {
        param (
            [System.Xml.XmlNode]$node,
            [string]$parentName = ""
        )
        
        if ($node.HasChildNodes) {
            foreach ($child in $node.ChildNodes) {
                if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                    # Skip certain technical nodes
                    if ($child.Name -in @('Name', 'Status', 'LinkPath', 'FilterName')) {
                        continue
                    }

                    $nodeName = if ($parentName) {
                        "$parentName - $($child.Name)"
                    } else {
                        $child.Name
                    }

                    # Check if node has attributes or text content
                    if ($child.'#text' -or $child.Attributes.Count -gt 0) {
                        $value = if ($child.'#text') {
                            $child.'#text'.Trim()
                        } else {
                            $attrs = $child.Attributes | ForEach-Object { "$($_.Name): $($_.Value)" }
                            $attrs -join ', '
                        }

                        if ($value) {
                            [void]$policyDetails.Add("$nodeName`: $value")
                        }
                    }
                    
                    # Recursively process child nodes
                    Extract-PolicyInfo -node $child -parentName $nodeName
                }
            }
        }
    }

    foreach ($extension in $extensionData) {
        Extract-PolicyInfo -node $extension.Extension
    }

    if ($policyDetails.Count -eq 0) {
        return "No Policies Configured"
    }

    return ($policyDetails | Select-Object -Unique) -join "`n"
}

# Get all OUs in the domain
$OUs = Get-ADOrganizationalUnit -Filter * -Properties CanonicalName

# Loop through each OU
foreach ($OU in $OUs) {
    $ouPath = $OU.DistinguishedName
    $linkedGPOs = Get-GPInheritance -Target $ouPath
    
    if ($linkedGPOs.GpoLinks) {
        foreach ($gpoLink in $linkedGPOs.GpoLinks) {
            $gpoName = $gpoLink.DisplayName
            $enabled = $gpoLink.Enabled
            
            # Generate temporary GPO report
            $tempReportPath = "$env:TEMP\$($gpoName -replace '\s', '_').xml"
            Get-GPOReport -Name $gpoName -ReportType Xml -Path $tempReportPath
            
            # Load XML report
            [xml]$gpoReport = Get-Content $tempReportPath
            
            # Get Computer and User Policies using the new function
            $computerPolicies = Get-PolicyDetails -extensionData $gpoReport.GPO.Computer.ExtensionData
            $userPolicies = Get-PolicyDetails -extensionData $gpoReport.GPO.User.ExtensionData
            
            # Create result object
            $results += [PSCustomObject]@{
                'OU' = $OU.CanonicalName
                'GPOName' = $gpoName
                'Enabled' = if ($enabled) { "True" } else { "False" }
                'ComputerPolicies' = $computerPolicies
                'UserPolicies' = $userPolicies
            }
            
            # Cleanup temporary file
            Remove-Item $tempReportPath -Force
        }
    } else {
        # Add entry for OUs with no GPOs
        $results += [PSCustomObject]@{
            'OU' = $OU.CanonicalName
            'GPOName' = "No GPO Linked"
            'Enabled' = "N/A"
            'ComputerPolicies' = "N/A"
            'UserPolicies' = "N/A"
        }
    }
}

# Export to CSV with specific formatting
$results | Select-Object @{Name='OU';Expression={$_.OU}},
    @{Name='GPOName';Expression={$_.GPOName}},
    @{Name='Enabled';Expression={$_.Enabled}},
    @{Name='ComputerPolicies';Expression={$_.ComputerPolicies}},
    @{Name='UserPolicies';Expression={$_.UserPolicies}} |
    Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

Write-Host "GPO report exported to $outputPath"