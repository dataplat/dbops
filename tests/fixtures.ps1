[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", '')]
param ()
# define test fixtures
$buildFolder = New-Item -Path "$PSScriptRoot\build" -ItemType Directory -Force
$workFolder = Join-PSFPath -Normalize $buildFolder "dbops-test"
$unpackedFolder = Join-PSFPath -Normalize $workFolder 'unpacked'
$logTable = "testdeploymenthistory"
$packageName = Join-PSFPath -Normalize $workFolder 'TempDeployment.zip'
$newDbName = "dbops_test"
$outputFile = "$workFolder\log.txt"
$slash = [IO.Path]::DirectorySeparatorChar
$testPassword = 'TestPassword'
$securePassword = $testPassword | ConvertTo-SecureString -Force -AsPlainText
$etcFolder = "$PSScriptRoot\etc"
$noRecurseFolder = Join-PSFPath -Normalize $etcFolder "sqlserver-tests"
$etcScriptFolder = Join-PSFPath -Normalize $etcFolder "sqlserver-tests"
$scriptFolder = Join-PSFPath -Normalize $etcScriptFolder "success"
$fullConfig = Join-PSFPath -Normalize $workFolder "tmp_full_config.json"
$fullConfigSource = Join-PSFPath -Normalize $etcFolder "full_config.json"

# for replacement
$packageNamev1 = Join-Path $workFolder "TempDeployment_v1.zip"

# support functions
function Get-SourceScript {
    param(
        [Parameter(Mandatory)]
        [int[]]$Version,
        [string]$EtcPath = $etcScriptFolder
    )
    return $Version | Foreach-Object { Join-PSFPath -Normalize (Resolve-Path "$EtcPath\success\$_.sql").Path }
}


function Remove-Workfolder {
    param(
        [switch]$Unpacked
    )
    if ($Unpacked) {
        $folder = $unpackedFolder
    }
    else {
        $folder = $workFolder
    }
    if ((Test-Path $folder) -and $workFolder -like '*dbops-test*') { Remove-Item $folder -Recurse }
}
function New-Workfolder {
    param(
        [switch]$Force,
        [switch]$Unpacked
    )
    if ($Force) {
        Remove-Workfolder -Unpacked:$Unpacked
    }
    if ($Unpacked) {
        New-Workfolder
        $folder = $unpackedFolder
    }
    else {
        $folder = $workFolder
    }
    $null = New-Item $folder -ItemType Directory -Force
}
