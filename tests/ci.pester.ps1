Param
(
    [string[]]$Path = "$PSScriptRoot\**\*.Tests.ps1",
    [ValidateSet('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')]
    [string[]]$Type = @('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL'),
    [ValidateSet('UnitTests', 'FunctionalTests', 'ComplianceTests', 'IntegrationTests')]
    [string[]]$Tag

)

# pester parameters
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
    $env:DBOPS_TEST_DB_TYPE = $Type -join " "
}
Invoke-Pester -Configuration $config -CI