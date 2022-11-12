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
function Reset-Workfolder {
    param(
        [switch]$Unpacked
    )
    if ($Unpacked) {
        $folder = $unpackedFolder
    }
    else {
        $folder = $workFolder
    }
    if ((Test-Path $folder) -and $workFolder -like '*dbops-test*') {
        if (Test-Path $folder\*) { Remove-Item $folder\* -Recurse }
    }
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

function Set-NewScopeInitConfigValue {
    param(
        [parameter(Mandatory)][string]$Name,
        [parameter(Mandatory)][object]$Value
    )
    $scriptBlock = {
        param ($Name, $Value)
        Import-Module PSFramework
        Set-PSFConfig -FullName dbops.$Name -Value $Value -Initialize
        Get-PSFConfigValue -FullName dbops.$Name
    }
    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $Name, $Value
    $result = $job | Wait-Job | Receive-Job
    $job | Remove-Job
    return $result
}

function Uninstall-Dependencies {
    param (
        $Type = @('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')
    )
    . "$PSScriptRoot\..\internal\functions\Get-ExternalLibrary.ps1"
    foreach ($t in $Type) {
        foreach ($lib in (Get-ExternalLibrary -Type $t)) {
            $package = Uninstall-Package -Name $lib.Name -Confirm:$false -Scope CurrentUser
        }
    }
}
