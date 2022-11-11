$filter = @(if ($env:DBOPS_TEST_DB_TYPE) {
        $env:DBOPS_TEST_DB_TYPE.split(" ")
    })
$types = @(
    "SqlServer"
    "MySQL"
    "Postgresql"
    "Oracle"
) | Where-Object { $filter.Count -eq 0 -or $_ -in $filter } | ForEach-Object { @{ Type = $_ } }