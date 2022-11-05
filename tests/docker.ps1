param(
    [ValidateSet('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')]
    [string[]]$Type = 'SqlServer',
    [switch]$Force
)

. $PSScriptRoot\constants.ps1

function Test-Force {
    param (
        $Name
    )
    if ($Force) {
        docker stop $Name
        docker rm $Name
    }
}

switch ($Type) {
    SqlServer {
        $containerName = "dbops-mssql"
        Test-Force $containerName
        docker run -d --name $containerName -p 1433:1433 dbatools/sqlinstance
    }
    MySQL {
        $containerName = "dbops-mysql"
        Test-Force $containerName
        docker run -d --name $containerName -p 3306:3306 `
            -e "MYSQL_ROOT_PASSWORD=$($script:mysqlCredential.GetNetworkCredential().Password)" `
            --platform linux/amd64 mysql:5.7
    }
    PostgreSQL {
        $containerName = "dbops-postgresql"
        Test-Force $containerName
        docker run -d --name $containerName -p 5432:5432 `
            -e "POSTGRES_PASSWORD=$($script:postgresqlCredential.GetNetworkCredential().Password)" `
            postgres:14
    }
    Oracle {
        $containerName = "dbops-oracle"
        Test-Force $containerName
        docker run -d --name $containerName -p 1521:1521 `
            -e ORACLE_ALLOW_REMOTE=true wnameless/oracle-xe-11g-r2
    }
}
