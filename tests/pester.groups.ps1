# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
    # run on scenario MSSQL
    "MSSQL" = @(
        'Install-DBOPackage',
        'Add-DBOBuild',
        'Get-DBOConfig',
        'New-DBOPackage',
        'Remove-DBOBuild',
        'Get-DBOPackage',
        'Update-DBOConfig'
    )
    # do not run everywhere
    "disabled" = @()
}