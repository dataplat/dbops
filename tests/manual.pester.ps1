Param
(
    [string[]]$Path = '.\*.Tests.ps1',
    [ValidateSet('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')]
    [string[]]$Type = @(),
    [ValidateSet('UnitTests', 'FunctionalTests', 'ComplianceTests', 'IntegrationTests')]
    [string[]]$Tag

)

$ModuleBase = Split-Path -Path $PSScriptRoot -Parent
# removes previously imported module
Remove-Module dbops -ErrorAction Ignore
# imports the module making sure DLL is loaded ok
Import-Module "$ModuleBase\dbops.psd1" -DisableNameChecking
# import internal commands
# Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
# import helper modules
Import-Module ziphelper -Force

# pester parameters$params =
$conf = @{
    Run    = @{
        Path = $Path
    }
    Output = @{
        Verbosity = "Detailed"
    }
}
if ($Tag) {
    $conf.Filter = @{
        Tag = $Tag
    }
}
$config = New-PesterConfiguration -Hashtable $conf
# set environment vars to limit DB types
if ($Type.Count -gt 0) {
    $env:DBOPS_TEST_DB_TYPE = $Type | Join-String -Separator " "
}
Invoke-Pester -Configuration $config