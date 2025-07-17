add-pssnapin Microsoft.Exchange.Management.PowerShell.Setup

$path = "C:\Program Files\Microsoft\Exchange Server\V15\Setup\Perf"
$items = Get-ChildItem -Recurse $path
$files = $items | ?{$_.extension -eq ".xml"}
Write-Host "Registering all perfmon counters in $path"
Write-Host
$count = 0;
foreach ($i in $files)
{
   $count++ 
   $f = $i.directory, "\", $i.name -join ""
Write-Host $count $f
New-PerfCounters -DefinitionFileName $f
}
 