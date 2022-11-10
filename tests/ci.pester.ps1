﻿Param
(
    [string[]]$Path = "$PSScriptRoot\**\*.Tests.ps1",
    [ValidateSet('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')]
    [string[]]$Type = @('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL'),
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
    $env:DBOPS_TEST_DB_TYPE = $Type | Join-String -Separator " "
}
Invoke-Pester -Configuration $config