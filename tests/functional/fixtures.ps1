[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", '')]
param (
    [string]$CommandName = "DBOps",
    [ValidateSet('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')]
    [string]$Type = "SqlServer",
    [bool]$Batch = $false
)
if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$PSScriptRoot\..\..\dbops.psd1" -Force
    # Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $CommandName tests" -ForegroundColor Cyan
}
. "$PSScriptRoot\..\constants.ps1"

$buildFolder = New-Item -Path "$PSScriptRoot\..\build" -ItemType Directory -Force
$workFolder = Join-PSFPath -Normalize $buildFolder "dbops-test"
$unpackedFolder = Join-PSFPath -Normalize $workFolder 'unpacked'
$logTable = "testdeploymenthistory"
$packageName = Join-PSFPath -Normalize $workFolder 'TempDeployment.zip'
$newDbName = "dbops_test"
$outputFile = "$workFolder\log.txt"



switch ($Type) {
    SqlServer {
        $saConnectionParams = @{
            SqlInstance = $script:mssqlInstance
            Silent      = $true
            Credential  = $script:mssqlCredential
            Database    = "master"
        }
        $dbConnectionParams = @{
            SqlInstance = $script:mssqlInstance
            Silent      = $true
            Credential  = $script:mssqlCredential
            Database    = $newDbName
        }
        $etcFolder = "sqlserver-tests"
        $dropDatabaseScript = 'IF EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{0}]; END' -f $newDbName
        $createDatabaseScript = 'IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN CREATE DATABASE [{0}]; END' -f $newDbName
        $instance = $script:mssqlInstance
        $credential = $script:mssqlCredential
    }
    default {
        throw "Unknown server type $Type"
    }
}

$cleanupScript = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\Cleanup.sql"
$v1scripts = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\success\1.sql"
$v1Journal = Get-Item $v1scripts | ForEach-Object { '1.0\' + $_.Name }
$verificationScript = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\verification\select.sql"

# input data functions

function Get-PackageScript {
    param(
        [Parameter(Mandatory)]
        [int[]]$Version
    )
    return $Version | Foreach-Object { Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\success\$_.sql" }
}
function Get-JournalScript {
    param(
        [Parameter(Mandatory)]
        [int[]]$Version
    )
    foreach ($ver in $Version) {
        Get-Item (Get-PackageScript -Version $Version) | ForEach-Object { "$ver.0\" + $_.Name }
    }
}

# validation functions

function Test-DeploymentOutput {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [int]$Version,
        [switch]$WhatIf
    )
    $InputObject.Successful | Should -Be $true
    $InputObject.SqlInstance | Should -Be $instance
    $InputObject.Scripts.Name | Should -Be (Get-JournalScript -Version $Version)
    $InputObject.Database | Should -Be $newDbName
    $InputObject.ConnectionType | Should -Be $Type
    $InputObject.Error | Should -BeNullOrEmpty
    $InputObject.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
    $InputObject.StartTime | Should -Not -BeNullOrEmpty
    $InputObject.EndTime | Should -Not -BeNullOrEmpty
    $InputObject.EndTime | Should -BeGreaterOrEqual $InputObject.StartTime
    if ($WhatIf) {
        "No deployment performed - WhatIf mode." | Should -BeIn $testResults.DeploymentLog
    }
    else {
        'Upgrade successful' | Should -BeIn $InputObject.DeploymentLog
    }
}


function Test-DeploymentState {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [int]$Version,
        [switch]$HasJournal
    )
    $versionMap = @{
        0 = @()
        1 = @('a', 'b')
        2 = @('c', 'd')
    }

    #Verifying objects
    $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
    if ($HasJournal) {
        $logTable | Should -BeIn $testResults.name
    }
    else {
        $logTable | Should -Not -BeIn $testResults.name
    }
    foreach ($ver in 0..($versionMap.Keys.Count - 1)) {
        if ($Version -ge $ver) {
            foreach ($table in $versionMap[$ver]) {
                $table | Should -BeIn $testResults.name
            }
        }
        else {
            foreach ($table in $versionMap[$ver]) {
                $table | Should -Not -BeIn $testResults.name
            }
        }
    }
}

function Reset-TestDatabase {
    $null = Invoke-DBOQuery @dbConnectionParams -InputFile $cleanupScript
}