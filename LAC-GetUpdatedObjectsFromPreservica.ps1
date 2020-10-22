Clear-Host;
Set-PSDebug -Off;
#$Host.Version
Write-Host ""
$global:RUN_ONLINE=1;

if(!$RUN_ONLINE){ Write-Host "Running offline"; }

#Load Preservica API stuff and tools
Import-Module "$ScriptDir\LAC-DP-OPS_tools.psm1" -Force;
Import-Module "$ScriptDir\LAC-Preservica-API.psm1" -Force;

#initialization and working directory setup;
$workDir = Set-WorkingDirectory;
$global:TALLY_PATH = "$workDir\tally.txt";

$stopWatch = [System.Diagnostics.Stopwatch]::startNew();
$now = Get-Date;
$str = "API-Test started at $now"
Out-File -FilePath $global:TALLY_PATH  -InputObject $str -Force;

<#
#Proxy is needed + A token enabling access to Preservica
$proxyAddress = Get-LACProxy;
if($RUN_ONLINE){ 
    $token = Get-PreservicaToken $workDir; 
    $header = @{ 'Preservica-Access-Token' = "$token" };
}
#>

$soMap = Get-PreservicaStructure;

$structureObjectDictionary = @{};
$buffer = @{};

$i=0; $i_count = $soMap.count;
foreach($row in $soMap){
    $percent = ($i/$i_count)*100;
    Write-Progress -Activity $Myinvocation.Mycommand -Status "Processing structure data into HashMap... $i of $i_count" -PercentComplete $percent;
    $i++;
    $ref = $row.ref;
    $path = $row.path;
    if (!$structureObjectDictionary.ContainsKey($ref) -AND !$buffer.ContainsKey($ref)){
        $buffer += @{
            "$ref" = "$path"
        }
    }

    if($buffer.count -gt 500){
        $structureObjectDictionary += $buffer;
        $buffer = @{};
    }
}
$structureObjectDictionary += $buffer;
$buffer=$null;

Write-tallyTimeSpent -Note "Get-PreservicaStructure" -stopWatch $stopWatch;

#Get files that were updated since the specified date from Preservica
$date = "2020-06-01"
$updatedEntities = Get-PreservicaUpdatedObjects -sinceDate $date;

$x = $updatedEntities.count;
Write-tallyTimeSpent -Note "Get-PreservicaUpdatedObjects, objects found $x" -stopWatch $stopWatch;

#Improve files with fixity data
$updatedEntities = Get-PreservicaMetadataForObjects -arrayOfHashMaps $updatedEntities ; 
Write-tallyTimeSpent "Get-PreservicaMetadataForObjects" -stopWatch $stopWatch;

#$updatedEntities = Get-PreservicaParentDataForObjects -arrayOfHashMaps $updatedEntities -StructureObjectMap $structureObjectDictionary;

$null = Get-PreservicaObjects -arrayOfHashMaps $updatedEntities -sinceDate $date;

$stopWatch.Stop();
$now = Get-Date;
$str = "API-Test ended at $now"
Write-tallyTimeSpent -Note $str -stopWatch $stopWatch;

#Write-formatXML("$workDir\list_updated.xml");


