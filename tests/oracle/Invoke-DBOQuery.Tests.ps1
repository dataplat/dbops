Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running Oracle $commandName tests" -ForegroundColor Cyan
}

. "$here\..\constants.ps1"
# install Oracle libs if needed
if (-not (Test-DBOSupportedSystem -Type Oracle)) {
    Install-DBOSupportLibrary -Type Oracle -Force -Scope CurrentUser 3>$null
}

$newDbName = 'test_dbops_invokedboquery'
$connParams = @{
    SqlInstance = $script:oracleInstance
    Credential  = $script:oracleCredential
    Type        = 'Oracle'
    Silent      = $true
    ConnectionAttribute = @{
        'DBA Privilege' = 'SYSDBA'
    }
}

Describe "Invoke-DBOQuery Oracle tests" -Tag $commandName, IntegrationTests {
    Context "Regular tests" {
        It "should run the query" {
            $query = "SELECT 1 AS A, 2 AS B FROM DUAL UNION ALL SELECT NULL AS A, 4 AS B FROM DUAL"
            $result = Invoke-DBOQuery -Query $query @connParams -As DataTable
            $result.Columns.ColumnName | Should -Be @('A','B')
            $result.A | Should -Be 1, ([DBNull]::Value)
            $result.B | Should -Be 2, 4
        }
        It "should select NULL" {
            $query = "SELECT NULL FROM DUAL"
            $result = Invoke-DBOQuery -Query $query @connParams -As DataTable
            $result.Columns.ColumnName | Should -Be @('NULL')
            $result.NULL | Should -Be ([DBNull]::Value)
        }
        It "should run the query with semicolon" {
            $query = "SELECT 1 AS A, 2 AS B FROM DUAL;
            SELECT 3 AS A, 4 AS B FROM DUAL"
            $result = Invoke-DBOQuery -Query $query @connParams -As DataTable
            $result[0].Columns.ColumnName | Should -Be @('A','B')
            $result[1].Columns.ColumnName | Should -Be @('A','B')
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query with semicolon as a dataset" {
            $query = "SELECT 1 AS A, 2 AS B FROM DUAL;
            SELECT 3 AS A, 4 AS B FROM DUAL"
            $result = Invoke-DBOQuery -Query $query @connParams -As Dataset
            $result.Tables[0].Columns.ColumnName | Should Be @('A','B')
            $result.Tables[1].Columns.ColumnName | Should Be @('A','B')
            $result.Tables[0].A | Should -Be 1
            $result.Tables[0].B | Should -Be 2
            $result.Tables[1].A | Should -Be 3
            $result.Tables[1].B | Should -Be 4
        }
        It "should run the query as a PSObject" {
            $query = "SELECT 1 AS A, 2 AS B FROM DUAL UNION ALL SELECT NULL AS A, 4 AS B FROM DUAL"
            $result = Invoke-DBOQuery -Query $query @connParams -As PSObject
            $result[0].psobject.properties.Name | Should -Be @('A','B')
            $result.A | Should -Be 1, $null
            $result.B | Should -Be 2, 4
        }
        It "should run the query as a SingleValue" {
            $query = "SELECT 1 AS A FROM DUAL"
            $result = Invoke-DBOQuery -Query $query @connParams -As SingleValue
            $result | Should -Be 1
        }
        It "should run the query from InputFile" {
            $file1 = Join-Path 'TestDrive:' 1.sql
            $file2 = Join-Path 'TestDrive:' 2.sql
            "SELECT 1 AS A, 2 AS B FROM DUAL" | Out-File $file1 -Force
            "SELECT 3 AS A, 4 AS B FROM DUAL" | Out-File $file2 -Force -Encoding bigendianunicode
            $result = Invoke-DBOQuery -InputFile $file1, $file2 @connParams -As DataTable
            $result[0].Columns.ColumnName | Should -Be @('A','B')
            $result[1].Columns.ColumnName | Should -Be @('A','B')
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query from InputObject" {
            $file1 = Join-Path 'TestDrive:' 1.sql
            $file2 = Join-Path 'TestDrive:' 2.sql
            "SELECT 1 AS A, 2 AS B FROM DUAL" | Out-File $file1 -Force
            "SELECT 3 AS A, 4 AS B FROM DUAL" | Out-File $file2 -Force -Encoding bigendianunicode
            $result = Get-Item $file1, $file2 | Invoke-DBOQuery @connParams -As DataTable
            $result[0].Columns.ColumnName | Should -Be @('A','B')
            $result[1].Columns.ColumnName | Should -Be @('A','B')
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
            $result = $file1, $file2 | Invoke-DBOQuery @connParams -As DataTable
            $result[0].Columns.ColumnName | Should -Be @('A','B')
            $result[1].Columns.ColumnName | Should -Be @('A','B')
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query with custom variables" {
            $query = "SELECT '#{Test}' AS A, '#{Test2}' AS B FROM DUAL UNION ALL SELECT '3' AS A, '4' AS B FROM DUAL"
            $result = Invoke-DBOQuery -Query $query @connParams -As DataTable -Variables @{ Test = '1'; Test2 = '2'}
            $result.Columns.ColumnName | Should -Be @('A','B')
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be '2', '4'
        }
        It "should connect to the server from a custom variable" {
            $query = "SELECT 1 AS A, 2 AS B FROM DUAL UNION ALL SELECT 3 AS A, 4 AS B FROM DUAL"
            $result = Invoke-DBOQuery -Type Oracle -Query $query -SqlInstance '#{srv}' -Credential $script:oracleCredential -As DataTable -Variables @{ srv = $script:oracleInstance } -ConnectionAttribute @{
                'DBA Privilege' = 'SYSDBA'
            }
            $result.Columns.ColumnName | Should -Be @('A','B')
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be '2', '4'
        }
        It "should run the query with custom parameters" {
            $query = "SELECT :p1 AS A, :p2 AS B FROM DUAL"
            $result = Invoke-DBOQuery -Query $query @connParams -Parameter @{ p1 = '1'; p2 = 'string'}
            $result.A | Should -Be 1
            $result.B | Should -Be string
        }
        It "should address column names automatically" {
            $query = "SELECT 1 AS A, 2, 3 FROM DUAL"
            $result = Invoke-DBOQuery -Query $query @connParams -As DataTable
            $result.Columns.ColumnName | Should -Be @('A', '2', '3')
            $result.A | Should Be 1
            $result.2 | Should Be 2
            $result.3 | Should Be 3
        }
    }
    Context "Negative tests" {
        It "should throw an unknown table error" {
            $query = "SELECT * FROM nonexistent"
            { $null = Invoke-DBOQuery -Query $query @connParams } | Should throw 'table or view does not exist'
        }
        It "should throw a connection timeout error" {
            $query = "SELECT 1/0 FROM DUAL"
            try { $null = Invoke-DBOQuery -Type Oracle -Query $query -SqlInstance localhost:6493 -Credential $script:oracleCredential -ConnectionTimeout 1}
            catch { $errVar = $_ }
            $errVar.Exception.Message | Should -Match "Connection request timed out"
        }
        It "should fail when credentials are wrong" {
            try { Invoke-DBOQuery -Type Oracle -Query 'SELECT 1 FROM DUAL' -SqlInstance $script:oracleInstance -Credential ([pscredential]::new('nontexistent', ([securestring]::new()))) }
            catch {$errVar = $_ }
            $errVar.Exception.Message | Should -Match 'null password given; logon denied'
            try { Invoke-DBOQuery -Type Oracle -Query 'SELECT 1 FROM DUAL' -SqlInstance $script:oracleInstance -UserName nontexistent -Password (ConvertTo-SecureString 'foo' -AsPlainText -Force) }
            catch {$errVar = $_ }
            $errVar.Exception.Message | Should -Match 'invalid username/password; logon denied'
        }
        It "should fail when input file is not found" {
            { Invoke-DBOQuery -InputFile '.\nonexistent' @connParams } | Should throw 'Cannot find path'
            { '.\nonexistent' | Invoke-DBOQuery @connParams } | Should throw 'Cannot find path'
        }
    }
}