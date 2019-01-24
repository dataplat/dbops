# constants
. "$PSScriptRoot\..\internal\functions\Test-Windows.ps1"
if (Test-Path "$PSScriptRoot\constants.local.ps1") {
    Write-Verbose "tests\constants.local.ps1 found."
    . "$PSScriptRoot\constants.local.ps1"
}
else {
    # default appveyor password
    $appveyorPassword = ConvertTo-SecureString 'Password12!' -AsPlainText -Force

    # SqlServer
    $script:mssqlInstance = $env:mssql_instance
    if (Test-Windows) {
        $script:mssqlCredential = $null
    }
    else {
        $script:mssqlCredential = [pscredential]::new('sa', $appveyorPassword)
    }

    # MySQL
    $script:mysqlInstance = 'localhost:3306'
    $script:mysqlCredential = [pscredential]::new('root', $appveyorPassword)

    # PostgreSQL
    $script:postgresqlInstance = 'localhost'
    $script:postgresqlCredential = [pscredential]::new('sa', $appveyorPassword)

    # Oracle
    $script:oracleInstance = 'localhost'
    $script:oracleCredential = [pscredential]::new('sys', (ConvertTo-SecureString 'oracle' -AsPlainText -Force))
}