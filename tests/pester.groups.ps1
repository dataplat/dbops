# this files describes which tests to run on which environment of the build matrix

$TestsRunGroups = @{
    "all"        = @(
        "$ModuleBase\tests\*"
        "$ModuleBase\tests\mysql\*"
        "$ModuleBase\tests\postgresql\*"
        "$ModuleBase\tests\oracle\*"
    )
    "windows"    = @(
        "$ModuleBase\tests\*"
        "$ModuleBase\tests\mysql\*"
        "$ModuleBase\tests\postgresql\*"
    )
    "default"    = @(
        "$ModuleBase\tests\*"
    )
    "mysql"      = @(
        "$ModuleBase\tests\mysql\*"
    )
    "postgresql" = @(
        "$ModuleBase\tests\postgresql\*"
    )
    "oracle"     = @(
        "$ModuleBase\tests\oracle\*"
    )
    # do not run everywhere
    "disabled"   = @()
}