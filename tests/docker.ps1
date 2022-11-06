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

function Start-Container {
    param (
        $Name,
        $Port,
        $Image,
        $Environment = @{},
        $ArgumentList
    )
    Test-Force $Name
    $envs = $Environment.GetEnumerator() | ForEach-Object { @("-e", "$($_.Name)=$($_.Value)")}
    $null = docker inspect $Name
    if ($?) {
        docker start $Name
    }
    else {
        docker run -d --name $Name -p "$Port`:$Port" $envs $ArgumentList $Image
    }
}

switch ($Type) {
    SqlServer {
        Start-Container -Name dbops-mssql -Port 1433 -Image dbatools/sqlinstance
    }
    MySQL {
        Start-Container -Name dbops-mysql -Port 3306 -Image mysql:5.7 -Environment @{
            MYSQL_ROOT_PASSWORD = $script:mysqlCredential.GetNetworkCredential().Password
        } -ArgumentList @("--platform linux/amd64")
    }
    PostgreSQL {
        Start-Container -Name dbops-postgresql -Port 5432 -Image postgres:14 -Environment @{
            POSTGRES_PASSWORD = $script:postgresqlCredential.GetNetworkCredential().Password
            PGOPTIONS = "-c log_connections=yes -c log_statement=all -c log_duration=0"
            POSTGRES_HOST_AUTH_METHOD = "md5"
        }
    }
    Oracle {
        Start-Container -Name dbops-oracle -Port 1521 -Image wnameless/oracle-xe-11g-r2 -Environment @{
            ORACLE_ALLOW_REMOTE = $true
        }
    }
}
