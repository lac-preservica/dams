function Get-LACproxy(){
    return 'http://10.254.1.16:8080'
}
function Trace-XmlToScreen ([xml]$xml)
{
	Write-Host "Tracing XML";
    $StringWriter = New-Object System.IO.StringWriter;
    $XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter;
    $XmlWriter.Formatting = "indented";
    $xml.WriteTo($XmlWriter);
	
    $XmlWriter.Flush();
    $StringWriter.Flush();
	return $StringWriter
}


function Write-formatXML([string]$filePath){

    $filePathOut = $filePath.replace(".", "-formatted.");

    $StringWriter = New-Object System.IO.StringWriter;
    $XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter;
    $XmlWriter.Formatting = "indented";

    $xml = New-Object System.Xml.XmlDocument;
    $xml.load($filePath);
    $xml.WriteContentTo($XmlWriter);

    $XmlWriter.Flush();
    $StringWriter.Flush();

    Out-File -FilePath $filePathOut -InputObject $StringWriter.ToString() -NoNewline -Force;

}

function Read-ArrayOfHashMapsToFile{
    param(
        [string]$filePath
    );
    $strData = Get-Content -Path $filePath;

    $rows = $strData.split("`r`n");
    $columnNames = $rows[0].split("`t");

    $result = @();
    $buffer = @();
    $r_count = $rows.count;
    #reads back a tab separated file into an ArrayOfHashMaps
    for($r=1; $r -lt $r_count; $r++){ #each rows
        $items = @{};
        $values = $rows[$r].split("`t");
        $percent = ($r / $r_count)*100;
        Write-Progress -Activity "Read-ArrayOfHashMapsToFile" -Status "Reading array from text... $r of $r_count" -PercentComplete $percent;

        for($c=0; $c -lt $columnNames.count; $c++){ #each rows column
            $value = $values[$c];
            $key = $columnNames[$c];
            #saved into an object
            $items += @{
                "$key" = "$value"
            }
        }
        #stored into the array;
        $buffer += @($items);
        if($buffer.count -gt 1000){
            $result += $buffer;
            $buffer=@();
        }
    }
    #commit buffer to result
    $result += $buffer;
    Write-Progress -Activity "Read-ArrayOfHashMapsToFile" -Completed;
    return $result;
}

function Trace-ArrayOfHashMapsToFile{
param(
    [array]$arrayOfHashMaps,
    [string]$savePath
);

    $displayOnce = $true;

    if ($null -eq $arrayOfHashMaps){ Write-Host "Trace-ArrayOfHashMapsToFile: Null array cannot be traced"; return; }
    
    $i_count = $arrayOfHashMaps.count;


    $str =''
    #Add in column names
    foreach($key in $arrayOfHashMaps[0].keys){
        $str += $key + "`t"
    }
    $str = $str.Substring(0,$str.Length-1) + "`r`n";

    #Add in values
    $i=0;
    foreach($row in $arrayOfHashMaps){
        $i++;
        $percent = ($i / $i_count)*100;
        Write-Progress -Activity "Trace-ArrayOfHashMapsToFile" -Status "Writing array to text...  $i of $i_count" -PercentComplete $percent;

        foreach($key in $row.keys){
            try{
                $str += ($row[$key]).ToString() + "`t"
            }catch{
                #on error - output blank
                if($displayOnce -eq $true){
                    Write-Host "Trace-ArrayOfHashMapsToFile: Null values were converted to space"
                    $displayOnce = $false;
                }
                $str +=  " `t"
            }
            
        }
        $str = $str.Substring(0,$str.Length-1) + "`r`n";
    }

    Out-File -FilePath $savePath -InputObject $str -Force;
    Write-Progress -Activity "Trace-ArrayOfHashMapsToFile" -Completed;
}

function Set-WorkingDirectory{

    $ScriptDir = Get-Location;
    $ScriptDir = $ScriptDir.toString().split(':')[-1];
    $workDir = "$ScriptDir\_work"
    $global:WORK_DIR = $workDir;
    Write-Host "Working Directory: $workDir";
    $null = New-Item -Path $workDir -ItemType Directory -Force;

    return $workDir;

}

function Write-tallyTimeSpent{
    param(
        [String]$Note,
        [System.Diagnostics.Stopwatch]$stopWatch
    );

    $timeSpent = $stopWatch.Elapsed.TotalMinutes.toString("0.00");
    $str = "Time spent (Minutes) $timeSpent / $note"
    Out-File -FilePath $global:TALLY_PATH -InputObject $str -Append;

}