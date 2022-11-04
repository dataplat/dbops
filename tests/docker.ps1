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
}
