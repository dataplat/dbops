param (
    $Type = @('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')
)

Write-Host -ForegroundColor Cyan "Preparing functional tests for $($Type -join ', ')"

# install modules
. "$PSScriptRoot\pester.prep.ps1"

# import module and install libraries

. "$PSScriptRoot\install_dependencies.ps1" -Load -Type $Type
