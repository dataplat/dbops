Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

. "$here\constants.ps1"

$workFolder = Join-Path "$here\etc" "$commandName.Tests.dbops"
$scriptFolder = Join-Path $here 'etc\install-tests\success'
$v1scripts = Join-Path $scriptFolder '1.sql'
$v2scripts = Join-Path $scriptFolder '2.sql'
$v3scripts = Join-Path $scriptFolder '3.sql'
$query = "SELECT 1 AS A, 2 AS B --UNION ALL SELECT 3 AS A, 4 AS B"

Describe "Invoke-DBOQuery tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        
    }
    AfterAll {
        
    }
    Context "Regular tests" {
        It "should run the query" {
           $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential
           $result.A | Should -Be 1
           $result.B | Should -Be 2
        }
    }
}