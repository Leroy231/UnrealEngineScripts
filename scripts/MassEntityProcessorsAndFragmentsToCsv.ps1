param (
    [string] $SlnPath,
    [string] $CppFileRegex = "Processors?\.cpp|Translator\.cpp|Trait\.cpp|Fragment\.cpp",
    [string] $CppFileRegexToIgnore = "(Houdini|Debug)",
    [string] $ProcessorNameRegexToIgnore = "(Debug)"
)

$global:fragmentIndices = @{}
$global:lastFragmentIndex = 0
$global:accessTypesToShortNames = @{
    "EMassFragmentAccess::ReadWrite" = "RW"
    "EMassFragmentAccess::ReadOnly" = "R"
    "EMassFragmentPresence::Optional" = ""
    "EMassFragmentAccess::None" = "N"
    "EMassFragmentPresence::All" = ""
    "EMassFragmentPresence::None" = ""
}
$global:processorsToProjects = @{}
$global:processorsToSuperclasses = @{}

function GetCompiledFiles([string]$VcxProjPath, [string]$Regex, [string]$RegexToIgnore)
{
    $workingDir = Split-Path -Path $VcxProjPath -Parent
    $xmldoc = New-Object System.Xml.XmlDocument
    $xmlString = Get-Content $VcxProjPath -Raw
    $xmldoc.LoadXml($xmlString)

    # Create an XmlNamespaceManager for resolving namespaces
    $nsmgr = New-Object System.Xml.XmlNamespaceManager($xmldoc.NameTable)
    $nsmgr.AddNamespace("vcx", "http://schemas.microsoft.com/developer/msbuild/2003")

    $root = $xmldoc.DocumentElement
    $nodes = $root.SelectNodes("//vcx:ClCompile", $nsmgr)

    $filteredFiles = @()
    foreach ($node in $nodes)
    {
        $relativePath = $node.Attributes["Include"].Value
        if(-not ($relativePath -match $Regex)) {
            continue
        }
        if ($relativePath -match $RegexToIgnore) {
            continue
        }
        $absPath = $relativePath
        if ($absPath -match "\.\.") {
            $absPath = Join-Path -Path $workingDir -ChildPath $relativePath -Resolve
        }
        $filteredFiles += $absPath
    }
    return ,$filteredFiles
}

function StringWithoutDuplicateChars([string]$string)
{
    $uniqueChars = $string.ToCharArray() | Sort-Object | Get-Unique
    $result = $uniqueChars -join ""
    return $result
}

function GetProcessorsForCppFile([string]$FilePath, [string]$processorNameRegexToIgnore, [string]$vcxProject)
{
    $processorsToFragments = @{}

    $configureQueriesMatches = Get-Content $FilePath -Raw | Select-String '(?smi) (\w+?)::ConfigureQueries\(.+?\}' -AllMatches |%{$_.Matches}

    foreach ($configureQueriesMatch in $configureQueriesMatches)
    {
        $processorName = $configureQueriesMatch.Groups[1].Value

        if ($processorName -match $processorNameRegexToIgnore) {
            continue
        }

        $processorFragments = @{}
        $processorsToFragments.Add($processorName, $processorFragments)
        $global:processorsToProjects.Add($processorName, $vcxProject)
        $superclass = GetProcessorSuperclass $processorName $FilePath
        $global:processorsToSuperclasses.Add($processorName, $superclass)
        $requirements = $configureQueriesMatch.Value | Select-String 'AddRequirement<(.+)>\((.+)\)' -AllMatches|%{$_.Matches}
        foreach ($req in $requirements)
        {
            $fragmentName = $req.Groups[1].Value
            if (!$global:fragmentIndices.Contains($fragmentName))
            {
                $global:fragmentIndices.Add($fragmentName, $global:lastFragmentIndex)
                $global:lastFragmentIndex += 1
            }

            $accesses = $req.Groups[2].Value -split ","
            $accessesShort = ""
            foreach($accessUntrimmed in $accesses)
            {
                $access = $accessUntrimmed.Trim()
                $accessShort = $global:accessTypesToShortNames[$access]
                if ($accessShort -eq $null)
                {
                    $error = "Invalid access type: " + $access + ", in file: " + $FilePath
                    throw $error
                }
                $accessesShort = StringWithoutDuplicateChars($accessesShort + $accessShort)
            }

            if ($processorFragments.Contains($fragmentName)) {
                $newAccessesShort = $processorFragments[$fragmentName] + $accessesShort
                $processorFragments[$fragmentName] = StringWithoutDuplicateChars($newAccessesShort)
            } else {
                $processorFragments.Add($fragmentName, $accessesShort)
            }
        }

    }
    return $processorsToFragments
}

function GetProcessorSuperclass([string]$processorName, [string]$FilePath)
{
    $headerPath = $FilePath.replace('.cpp','.h').replace('Private', 'Public')
    if (-not (Test-Path $headerPath -PathType Leaf)) {
        $headerPathSplit = $headerPath -split '\\'
        $headerFile = $headerPathSplit[-1]
        $lengthOfSource = 6
        $searchPath = $headerPath.Substring(0, $headerPath.IndexOf("Source")+$lengthOfSource)
        $headerPathInSearchPath = Get-ChildItem -Path $searchPath -Recurse -filter $headerFile -name
        $headerPath = Join-Path -Path $searchPath -ChildPath $headerPathInSearchPath
    }
    $superclass = Select-String -Path $headerPath -Pattern "$processorName : public (\w+)" | %{$_.Matches} |  %{$_.Groups[1]} | %{$_.Value}
    if ($superclass -eq "UMassProcessor") {
        return ""
    }
    return $superclass
}

function GetVcxProjectsFromSln([string]$slnPath)
{
    $slnDir = Split-Path -Path $slnPath -Parent
    return Select-String -Path $slnPath -Pattern ', "(.+?\.vcxproj)' -AllMatches | %{$_.Matches} | %{$_.Groups[1]} | %{$_.Value} | %{Join-Path -Path $slnDir -ChildPath $_ -Resolve}
}

function GetProcessorsForSln([string]$slnPath, [string]$cppFileRegex, [string]$cppFileRegexToIgnore, [string]$processorNameRegexToIgnore)
{
    $processors = @()
    $vcxProjects = GetVcxProjectsFromSln $slnPath
    foreach($vcxProject in $vcxProjects)
    {
        $files = GetCompiledFiles $vcxProject $cppFileRegex $cppFileRegexToIgnore
        foreach($file in $files)
        {
            $processors += GetProcessorsForCppFile $file $processorNameRegexToIgnore $vcxProject
        }
    }
    return $processors
}

function ConvertProcessorsToCsv($processors)
{
    $fragmentNames = [string[]]::new($global:fragmentIndices.Count)
    foreach ($fragmentNameAndIndex in $global:fragmentIndices.GetEnumerator())
    {
        $fragmentName = $fragmentNameAndIndex.Name
        $fragmentIndex = $fragmentNameAndIndex.Value
        $fragmentNames[$fragmentIndex] = $fragmentName
    }
    $fragmentNamesLine = $fragmentNames -join ","
    $fragmentNamesLine = "Project,Processor,Superclass," + $fragmentNamesLine
    write-output $fragmentNamesLine

    foreach ($processorsInFile in $processors)
    {
        foreach ($processorNameAndFragments in $processorsInFile.GetEnumerator())
        {
            $fixedColumnCount = 3
            $row = [string[]]::new($global:fragmentIndices.Count+$fixedColumnCount)
            $processorName = $processorNameAndFragments.Name
            $row[0] = GetProjectNameFromVxcPath $global:processorsToProjects[$processorName]
            $row[1] = $processorName
            $row[2] = $global:processorsToSuperclasses[$processorName]
            $fragmentNamesToAccess = $processorNameAndFragments.Value
            foreach ($fragmentNameAndIndex in $global:fragmentIndices.GetEnumerator())
            {
                $fragmentName = $fragmentNameAndIndex.Name
                $fragmentIndex = $fragmentNameAndIndex.Value
                $access = $fragmentNamesToAccess[$fragmentName]
                $row[$fragmentIndex+$fixedColumnCount] = $access
            }

            $rowString = $row -join ","
            write-output $rowString
        }
    }
}

function GetProjectNameFromVxcPath([string]$vcxPath)
{
    return echo $vcxPath | Select-String -Pattern '.+?(\w+)\.vcxproj' | %{$_.Matches} | %{$_.Groups[1]} | %{$_.Value}
}

function GetProcessorsCsvFromSln([string]$slnPath, [string]$cppFileRegex, [string]$cppFileRegexToIgnore, [string]$processorNameRegexToIgnore)
{
    $allProcessors = GetProcessorsForSln $slnPath $cppFileRegex $cppFileRegexToIgnore $processorNameRegexToIgnore
    return ConvertProcessorsToCsv $allProcessors
}

GetProcessorsCsvFromSln $SlnPath $CppFileRegex $CppFileRegexToIgnore $ProcessorNameRegexToIgnore
