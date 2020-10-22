
function Get-PreservicaMetadataForObjects{
    Param(
        [array]$arrayOfHashMaps
    );

    $functionName = $MyInvocation.MyCommand;

    $proxyAddress= Get-LACproxy;
    $workDir = "$global:WORK_DIR\$($functionName)";

    if($RUN_ONLINE){
        Write-Host "$($functionName): ONLINE mode clearing previous results...";
        Remove-Item –path $workDir -Force -Recurse
    }

    $token = Get-PreservicaToken;
    $header = @{ 'Preservica-Access-Token' = "$token" }

    #create function working folder
    $null = New-Item -Path $workDir -ItemType Directory -Force;

    $i_count = $arrayOfHashMaps.count;
    for($i=0; $i -lt $i_count; $i++){
        Write-Progress -Activity "$($functionName)" -Status "Enhancing object metadata... $i out of $i_count" 

        $row = $arrayOfHashMaps[$i];
        $ref = $row.ref;
        $url = "https://lac.preservica.com/api/entity/content-objects/$($ref)/generations/1/bitstreams/1";
        
        $savePath = "$($workDir)\file_$($i).xml";
        if($global:RUN_ONLINE){
            $xmlStr = Invoke-RestMethod -Method 'Get' -Headers $header -Uri $url -Proxy $proxyAddress -ProxyUseDefaultCredentials;
        }
        
        [xml]$xml = New-Object -TypeName System.Xml.XmlDocument;
        $xml.LoadXml($xmlStr.OuterXml);

        if($i -eq 0){
            #debug view
            Out-File -FilePath $savePath -InputObject $xmlStr.OuterXml;
            Write-FormatXml($savePath);
        }

        $fileName = $xml.BitstreamResponse['xip:Bitstream']['xip:Filename'].innerText;
        $fileSize = $xml.BitstreamResponse['xip:Bitstream']['xip:FileSize'].innerText;
        $fixityAlgortihm = $xml.BitstreamResponse['xip:Bitstream']['xip:Fixities']['xip:Fixity']['xip:FixityAlgorithmRef'].innerText;
        $fixityValue = $xml.BitstreamResponse['xip:Bitstream']['xip:Fixities']['xip:Fixity']['xip:FixityValue'].innerText;
        $downloadURL = $xml.BitstreamResponse.AdditionalInformation.Content;


        $row += @{
            'fileName' = $fileName
            'fileSize' = $fileSize
            'fixityAlgorithm' = $fixityAlgortihm
            'fixityValue' = $fixityValue
            'path' = $path
            'content' = $downloadURL
        }

        
        $arrayOfHashMaps[$i] = $row;
    }

    Trace-ArrayOfHashMapsToFile -arrayOfHashMaps $arrayOfHashMaps -savePath "$workDir\array_debug.txt"
    Write-Progress -Activity "$($functionName)" -Completed;
    return $arrayOfHashMaps;
}


function Get-PreservicaStructure{

    $functionNAme = $MyInvocation.MyCommand;
    $debug_stop = [double]::PositiveInfinity;
    $debug_stop = 10; #Comment this line to disable debugging stop condition;
    
    $workDir = "$global:WORK_DIR\$($functionName)";
    $null = New-Item -Path $workDir -ItemType Directory -Force;

    $saveCachePath = "$workDir\save-cache.txt";

    if([System.IO.File]::Exists($saveCachePath)){
        #if a cache file exist, load it instead and leave Preservica alone...
        $results = Read-ArrayOfHashMapsToFile -filePath $saveCachePath;
        return $results;
    }

    #Maps Preservica structure into a hash table
    $proxyAddress= Get-LACproxy;
   
    
   

    $token = Get-PreservicaToken;
    $header = @{ 'Preservica-Access-Token' = "$token" }
    $i =0;
    
    $url = "https://lac.preservica.com/api/entity/root/children";
    $body = @{
        'start' = 0
        'max' = 1000
    }
    $level=0;
    $seq=0;
    $savePath = "$($workDir)\file_$($level)_$($seq).xml";

    #if($global:RUN_ONLINE){
    $xmlStr = Invoke-RestMethod -Method 'Get' -Headers $header -body $body -Uri $url -Proxy $proxyAddress -ProxyUseDefaultCredentials;
    #}

   
    Out-File -FilePath $savePath -InputObject $xmlStr.OuterXml;
    Write-FormatXml($savePath);
 
    $SO_scan_queue = New-Object -TypeName System.Collections.Generic.List[System.Collections.Hashtable];
    #read XML, retrieve Structure Object ID and assign a level, store in a sequence for future evaluation;
    [xml]$xml = New-Object -TypeName System.Xml.XmlDocument;
    $xml.LoadXml($xmlStr.OuterXml);
    $childs = $xml.ChildrenResponse.Children.childNodes;



    $scannedStructureObjects = New-Object -TypeName System.Collections.Generic.List[System.Collections.Hashtable];;

    foreach ($child in $childs){
        $item = @{
            'title' = $child.getAttribute('title')
            'ref' = $child.getAttribute('ref')
            'path' = 'ROOT'
            'level' = $level
        }
       $null= $SO_scan_queue.Add($item);
       $scannedStructureObjects.Add($item);
    }


    $total_count =$childs.count;
    do{ #recursive loop of childs of children
        $i=0;
        
        $scanObj = $SO_scan_queue[0];
        $null = $SO_scan_queue.removeAt(0);

        $ref = $scanObj.ref;
        $level = $scanObj.level+1;
        $seq++;

      

        $url = "https://lac.preservica.com/api/entity/structural-objects/$($ref)/children";
        $savePath = "$($workDir)\file_$($level)_$($seq).xml";

        #$null = Invoke-RestMethod -OutFile $savePath -Method 'Get' -Headers $header -body $body -Uri $url -Proxy $proxyAddress -ProxyUseDefaultCredentials;
        #Write-FormatXml($savePath);
        #[xml]$xml= Get-Content $savePath;
        $nextCall = $url;

        do{ #Loop for Next pages of results when there are more than 1,000

            $url = $nextCall;
            $body.start = $i;
            try{
                $xmlStr= Invoke-RestMethod -Method 'Get' -Headers $header -body $body -Uri $url -Proxy $proxyAddress -ProxyUseDefaultCredentials;
            }catch{
                Write-Host $_;
                #token error most of the time
                $token = Get-PreservicaToken -Force;
                $header = @{ 'Preservica-Access-Token' = "$token" }
                $xmlStr= Invoke-RestMethod -Method 'Get' -Headers $header -body $body -Uri $url -Proxy $proxyAddress -ProxyUseDefaultCredentials;
            }
         
         [xml]$xml.loadXml($xmlStr.OuterXml);
         $childs = $xml.ChildrenResponse.Children.childNodes
         $nextCall = $xml.ChildrenResponse.Paging.Next;
         
        foreach ($child in $childs){
            Write-Progress -Activity "$($functionName)" -Status "Retrieving structure from Preservica... $($i) of $($total_count) discovered so far..."
            $i++;
            $title = $child.getAttribute('title')
            $type = $child.getAttribute('type');
            if ($type -ne 'SO') { continue; } #Skip what is not a SO object
            $total_count++;

            $item = @{
                'title' = $title
                'ref' = $child.getAttribute('ref')
                'path' = "$($scanObj.title)/$($title)"
                'level' = $level+1
            }
           $null= $SO_scan_queue.Add($item);
           $scannedStructureObjects.Add($item);
        }
        
        if ($seq -gt $debug_stop ){ Write-Host "Debug stop @ $seq items"; break;  }
    }while($null -ne $nextCall);
        if ($seq -gt $debug_stop ){ Write-Host "Debug stop @ $seq items"; break;  }
    }while($SO_scan_queue.count -gt 0);

    Write-Progress -Activity "$($functionName)" -Completed
    $results = $scannedStructureObjects.ToArray();
    Trace-ArrayOfHashMapsToFile -arrayOfHashMaps $results -savePath $saveCachePath
}

function Get-PreservicaToken{
    param(
        [Switch]$Force
    );
    $functionNAme = $MyInvocation.MyCommand;
    $workDir = $global:WORK_DIR;

  
    $tokenFilePath = "$workDir\$($functionName)_token.txt";
    $proxyAddress = Get-LACproxy;

    #attempt to reuse the previous token if found under the _work folder;
    if (Test-Path $tokenFilePath -PathType leaf)
        {
			Write-Host "$($functionName): Token file found"
			
            #token file exist, can we reuse it?
            $token = Get-Content -Path $tokenFilePath;
            if(!$RUN_ONLINE -And !$Force){
                Write-Host "$($functionName): OFFLINE mode, token will not be refreshed";
                return $token;
            }

            #Test token for success
            $headers = @{ 'Preservica-Access-Token' = "$token" }
            $url = "https://lac.preservica.com/api/entity/root";
			
			try{
				
				$result = Invoke-RestMethod -OutFile "$workDir\$($functionName)_tokenTest.xml" -Method 'Get' -Headers $headers -Uri $url -Proxy $proxyAddress -ProxyUseDefaultCredentials;
				Write-Host "$($functionName): Token is still valid and will be used again."

				return $token;
				
			} catch {
				#Error occured?
				Write-Host "$($functionName): Token error, renewing hand shake..."
			}
			
        }



    #Login to Preservica
    $url = 'https://lac.preservica.com/api/accesstoken/login'

    #PROD
    $postParamsProd = @{
        username = 'maxime.champagne@canada.ca';
        password = 'Totala10';
        tenant   = 'lac';
        }

    #TEST
    $postParams = @{
        username = 'maxime.champagne@bac-lac.gc.ca';
        password = 'Totala10';
        tenant   = 'lactest';
        }

    $result = Invoke-RestMethod -Method 'Post'  -Uri $url -body $postParams -Proxy $proxyAddress -ProxyUseDefaultCredentials;

    $token = $result.token;
    $success = $result.success;

    #in case of failure stop the script.
    if(!$success){ Exit; }else{
        Write-Host "$($functionName): Connexion to Preservica successful - new token retrieved"
    }

    #Save token to be reused
    Out-File -FilePath $tokenFilePath -InputObject $token -NoNewline;
    return $token;
}

function Get-PreservicaUpdatedObjects{
    Param(
        [string]$sinceDate
    );

    $functionNAme = $MyInvocation.MyCommand;


    $proxyAddress = Get-LACproxy;
    $workDir = "$global:WORK_DIR\$($functionName)";
   
    
    $token = Get-PreservicaToken; 
    $url = "https://lac.preservica.com/api/entity/entities/updated-since";
    $i=0;
    $keepCount=0;

    if($RUN_ONLINE){
        Write-Host "$($functionName): ONLINE mode clearing previous results...";
        Remove-Item –path $workDir -Force -Recurse
    }

    $null = New-Item -Path $workDir -ItemType Directory -Force;
    
    $result = @();
    $header = @{ 'Preservica-Access-Token' = "$token" }
    $body = @{
        'date' = "$($sinceDate)T00:00:00.000+0500"
        'start' = "$i"
        'max' = '1000'
    }

    Do{
        $filePath = "$workDir\File_$($i).xml"
        if($RUN_ONLINE){
                $body.start = $i;
                Invoke-RestMethod -OutFile $filePath -Method 'Get' -Headers $header -Body $body -Uri $url -Proxy $proxyAddress -ProxyUseDefaultCredentials;
                Write-formatXML -FilePath $filePath;
        }else{
            Write-Host "$($functionName): OFFLINE MODE Re-using XML files created during the previous session. ""$($functionName)_xmlList_$($i).xml""";
        }



        [xml]$xml = Get-Content $filePath;
        $rows = $xml.EntitiesResponse.Entities.childnodes;
        $i_count = $xml.EntitiesResponse.Paging.TotalResults;
        $nextCall = $xml.EntitiesResponse.Paging.Next;

        $url = $nextCall;

        Foreach($row in $rows)
        {
            $title = $row.getAttribute("title");
            $ref = $row.getAttribute("ref");
            $type = $row.getAttribute("type");

            #only keep Information objects, removing Content Objects (not sure?) and Structure Objects (folders)
            $i++;
            Write-Progress -Activity "$($functionName)" -Status "Retrieving xml... $i out of $i_count" 
            
            if ($type -ne 'CO') { continue ;}

            $keepCount++;
            $result += @(
                @{
                'title' = $title
                'ref' = $ref
                'type' = $type
                }
            )    
            
           
        }
    }While($null -ne $nextCall);

    Write-Progress -Activity "$($functionName)" -Completed;
    Write-Host "$($functionName): $keepCount information objects retrieved out of $i_count updated objects.";
    Trace-ArrayOfHashMapsToFile -arrayOfHashMaps $result -savePath "$workDir\array_debug.txt"
    return $result;

}



function Get-PreservicaParentDataForObjects{
    Param(
        [Array]$arrayOfHashMaps,
        [HashTable]$StructureObjectMap
    );
    $functionName = $MyInvocation.MyCommand;
    <#
        Get parent object information,
        A list of content object is provided, fold back to the parent Information Object + Structure object
    #>
    $workDir = "$global:WORK_DIR\$($functionName)";
    $null = New-Item -Path $workDir -ItemType Directory -Force;
    $proxyAddress= Get-LACproxy;
    $token = Get-PreservicaToken;
    $header = @{ 'Preservica-Access-Token' = "$token" }
   
    for($i=0; $i -lt $arrayOfHashMaps.count; $i++){  
        $row = $arrayOfHashMaps[$i];
        $co_ref = $row.ref;  
        #Maps Preservica structure into a hash table
        $url = "https://lac.preservica.com/api/entity/content-objects/$co_ref";
        $xmlStr = Invoke-RestMethod -Method 'Get' -Headers $header -Uri $url -Proxy $proxyAddress -ProxyUseDefaultCredentials;
    
        if($i -eq 0){ #debug peek;
            $savePath = "$workDir\ContentObject-data.xml";
            Out-File -FilePath $savePath -InputObject $xmlStr.OuterXml;
            Write-FormatXml($savePath);
        }

        [xml]$xml = New-Object -TypeName System.Xml.XmlDocument;
        $xml.LoadXml($xmlStr.OuterXml);

        $io_ref = $xml.EntityResponse['xip:ContentObject']['xip:Parent'].innerText;
        $securityTag = $xml.EntityResponse['xip:ContentObject']['xip:SecurityTag'].innerText;
        
        #get Information Object data
        $url = "https://lac.preservica.com/api/entity​/information-objects​/$io_ref";
        $xmlStr = Invoke-RestMethod -Method 'Get' -Headers $header -Uri $url -Proxy $proxyAddress -ProxyUseDefaultCredentials;

        if($i -eq 0){ #debug peek;
            $savePath = "$workDir\InfoObject-data.xml";
            Out-File -FilePath $savePath -InputObject $xmlStr.OuterXml;
            Write-FormatXml($savePath);
        }

        [xml]$xml = New-Object -TypeName System.Xml.XmlDocument;
        $xml.LoadXml($xmlStr.OuterXml);

        $path = $StructureObjectMap["$so_ref"];
        
        $row += @{
            'io_ref' = $io_ref
            'securityTag' = $securityTag
            'so_ref' = $so_ref
            'path' = $path
        }
        $arrayOfHashMaps[$i] = $row;

        $i++;
    }
    Trace-ArrayOfHashMapsToFile -arrayOfHashMaps $arrayOfHashMaps -savePath "$workDir\array_debug.txt"
    return $arrayOfHashMaps;
}

function Get-PreservicaObjects{
    param(
        [Array]$arrayOfHashMaps,
        [String]$sinceDate
        );
    $functionName = $MyInvocation.MyCommand;
    $todayStr = Get-Date -Format "yyyy-MM-dd"
    $dateRange = "$sinceDate to $todayStr";

    $workDir = "$global:WORK_DIR\$($functionName)\$($dateRange)";
    $null = New-Item -Path $workDir -ItemType Directory -Force;

    $proxyAddress= Get-LACproxy;
    $token = Get-PreservicaToken;
    $header = @{ 'Preservica-Access-Token' = "$token" }

    $i=0;
    $i_count = $arrayOfHashMaps.count

    foreach($item in $arrayOfHashMaps){
        $i++;
        Write-Progress -Activity $functionName -Status "Downloading files into folder '$($dateRange)'... $i out of $i_count";
        $fileName = $item.fileName;
        $outputPath = "$workDir\$fileName";
        $downloadURL = $item.content;
        try{
            $null = Invoke-RestMethod -Method 'Get' -OutFile $outputPath -Headers $header -Uri $downloadURL -Proxy $proxyAddress -ProxyUseDefaultCredentials;

        }catch{
            Write-Host "$($functionName): Token expired - renewing..."
            #Errors are often caused by an expired Token
            #Get new token, try again, resume
            $token = Get-PreservicaToken;
            $header = @{ 'Preservica-Access-Token' = "$token" }
            $null = Invoke-RestMethod -Method 'Get' -OutFile $outputPath -Headers $header -Uri $downloadURL -Proxy $proxyAddress -ProxyUseDefaultCredentials;
        }
        

    }

    Write-Progress -Activity $functionName -Completed;


}

