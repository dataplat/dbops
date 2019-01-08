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
    Write-Host "Running MySQL $commandName tests" -ForegroundColor Cyan
}

. "$here\..\constants.ps1"
# install MySQL libs if needed
if (-not (Test-DBOSupportedSystem -Type MySQL)) {
    Install-DBOSupportLibrary -Type MySQL -Force -Scope CurrentUser 3>$null
}

Describe "Invoke-DBOQuery MySQL tests" -Tag $commandName, IntegrationTests {
    Context "Regular tests" {
        It "should run the query" {
            $query = "SELECT 1 AS A, 2 AS B UNION ALL SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -As DataTable
            $result.A | Should -Be 1, 3
            $result.B | Should -Be 2, 4
        }
        It "should run the query with semicolon" {
            $query = "SELECT 1 AS A, 2 AS B;
            SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query with GO as a dataset" {
            $query = "SELECT 1 AS A, 2 AS B;
            SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -As Dataset
            $result.Tables[0].A | Should -Be 1
            $result.Tables[0].B | Should -Be 2
            $result.Tables[1].A | Should -Be 3
            $result.Tables[1].B | Should -Be 4
        }
        It "should run the query as a PSObject" {
            $query = "SELECT 1 AS A, 2 AS B UNION ALL SELECT NULL AS A, 4 AS B"
            $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -As PSObject
            $result.A | Should -Be 1, $null
            $result.B | Should -Be 2, 4
        }
        It "should run the query as a SingleValue" {
            $query = "SELECT 1 AS A"
            $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -As SingleValue
            $result | Should -Be 1
        }
        It "should run the query from InputFile" {
            $file1 = Join-Path 'TestDrive:' 1.sql
            $file2 = Join-Path 'TestDrive:' 2.sql
            "SELECT 1 AS A, 2 AS B" | Out-File $file1 -Force
            "SELECT 3 AS A, 4 AS B" | Out-File $file2 -Force -Encoding bigendianunicode
            $result = Invoke-DBOQuery -Type MySQL -InputFile $file1, $file2 -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query from InputObject" {
            $file1 = Join-Path 'TestDrive:' 1.sql
            $file2 = Join-Path 'TestDrive:' 2.sql
            "SELECT 1 AS A, 2 AS B" | Out-File $file1 -Force
            "SELECT 3 AS A, 4 AS B" | Out-File $file2 -Force -Encoding bigendianunicode
            $result = Get-Item $file1, $file2 | Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
            $result = $file1, $file2 | Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query with custom variables" {
            $query = "SELECT '#{Test}' AS A, '#{Test2}' AS B UNION ALL SELECT '3' AS A, '4' AS B"
            $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -As DataTable -Variables @{ Test = '1'; Test2 = '2'}
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be '2', '4'
        }
        It "should connect to the server from a custom variable" {
            $query = "SELECT 1 AS A, 2 AS B UNION ALL SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance '#{srv}' -Credential $script:mysqlCredential -As DataTable -Variables @{ Srv = $script:mysqlInstance }
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be '2', '4'
        }
        It "should run the query with custom parameters" {
            $query = "SELECT @p1 AS A, @p2 AS B"
            $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Parameter @{ p1 = '1'; p2 = 'string'}
            $result.A | Should -Be 1
            $result.B | Should -Be string
        }
        It "should connect to a specific database" {
            $query = "SELECT db_name()"
            $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database mysql -As SingleValue
            $result | Should -Be tempdb
        }
        It "should address column names automatically" {
            $query = "SELECT 1 AS A, 2, 3"
            $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -As DataTable
            $result.Columns.ColumnName | Should -Be @('A', 'Column1', 'Column2')
            $result.A | Should Be 1
            $result.Column1 | Should Be 2
            $result.Column2 | Should Be 3
        }
    }
    Context "Negative tests" {
        It "should throw an unknown table error" {
            $query = "SELECT * FROM nonexistent"
            { $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential } | Should throw "Table does not exist"
        }
        It "should throw a connection timeout error" {
            $query = "SELECT 1/0"
            { $result = Invoke-DBOQuery -Type MySQL -Query $query -SqlInstance localhost:6493 -Credential $script:mysqlCredential -ConnectionTimeout 1} | Should throw "Unable to connect"
        }
        It "should fail when parameters are of a wrong type" {
            { Invoke-DBOQuery -Type MySQL -Query 'SELECT 1/@foo' -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Parameter @{ foo = 'bar' } } | Should throw 'Conversion failed'
            { Invoke-DBOQuery -Type MySQL -Query 'SELECT ''bar'' + @foo' -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Parameter @{ foo = 10 } } | Should throw 'Conversion failed'
            { Invoke-DBOQuery -Type MySQL -Query 'SELECT ''bar'' + @foo' -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Parameter @{ foo = Get-Date } } | Should throw 'Conversion failed'
        }
        It "should fail when credentials are wrong" {
            { Invoke-DBOQuery -Type MySQL -Query 'SELECT 1' -SqlInstance $script:mysqlInstance -Credential ([pscredential]::new('nontexistent', ([securestring]::new()))) } | Should throw 'Access denied'
            { Invoke-DBOQuery -Type MySQL -Query 'SELECT 1' -SqlInstance $script:mysqlInstance -UserName nontexistent -Password ([securestring]::new()) } | Should throw 'Access denied'
        }
        It "should fail when input file is not found" {
            { Invoke-DBOQuery -Type MySQL -InputFile '.\nonexistent' -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential } | Should throw 'Cannot find path'
            { '.\nonexistent' | Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential } | Should throw 'Cannot find path'
        }
    }
}