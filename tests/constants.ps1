# constants
. "$PSScriptRoot\..\internal\functions\Test-Windows.ps1"
if (Test-Path "$PSScriptRoot\constants.local.ps1") {
    Write-Verbose "tests\constants.local.ps1 found."
    . "$PSScriptRoot\constants.local.ps1"
}
else {
    # default appveyor password
    $appveyorPassword = ConvertTo-SecureString 'Password12!' -AsPlainText -Force
    $dbatoolsSaPassword = ConvertTo-SecureString 'dbatools.IO' -AsPlainText -Force

    # SqlServer
    if ($env:GITHUB_ACTION) {
        $script:mssqlInstance = "localhost"
    }
    else {
        $script:mssqlInstance = $env:mssql_instance
    }
    if (Test-Windows) {
        $script:mssqlCredential = $null
    }
    else {
        if ($env:GITHUB_ACTION) {
            $script:mssqlCredential = [pscredential]::new('sqladmin', $dbatoolsSaPassword)
        }
        else {
            $script:mssqlCredential = [pscredential]::new('sa', $appveyorPassword)
        }
    }

    # MySQL
    $script:mysqlInstance = 'localhost:3306'
    $script:mysqlCredential = [pscredential]::new('root', $appveyorPassword)

    # PostgreSQL
    $script:postgresqlInstance = 'localhost'
    $script:postgresqlCredential = [pscredential]::new('postgres', $appveyorPassword)

    # Oracle
    $script:oracleInstance = 'localhost'
    $script:oracleCredential = [pscredential]::new('sys', (ConvertTo-SecureString 'oracle' -AsPlainText -Force))
}