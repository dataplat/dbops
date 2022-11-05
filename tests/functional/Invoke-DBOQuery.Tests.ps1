Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

. "$here\constants.ps1"

$workFolder = Join-Path "$here\etc" "$commandName.Tests.dbops"
$connParams = @{ SqlInstance = $script:mssqlInstance; Credential = $script:mssqlCredential }

Describe "Invoke-DBOQuery tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    Context "Regular tests" {
        It "should run the query" {
            $query = "SELECT 1 AS A, 2 AS B UNION ALL SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As DataTable
            $result.A | Should -Be 1, 3
            $result.B | Should -Be 2, 4
        }
        It "should select NULL" {
            $query = "SELECT NULL"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As DataTable
            $result.Column1 | Should -Be ([DBNull]::Value)
        }
        It "should run the query with print and capture output" {
            $query = "print ('Foo bar!')"
            $null = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As DataTable -Silent -OutputFile $workFolder\out.txt
            "$workFolder\out.txt" | Should -FileContentMatch '^Foo bar!$'
        }
        It "should run the query with GO" {
            $query = "SELECT 1 AS A, 2 AS B
            GO
            SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query with GO as a dataset" {
            $query = "SELECT 1 AS A, 2 AS B
            GO
            SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As Dataset
            $result.Tables[0].A | Should -Be 1
            $result.Tables[0].B | Should -Be 2
            $result.Tables[1].A | Should -Be 3
            $result.Tables[1].B | Should -Be 4
        }
        It "should run 2 queries with semicolon" {
            $query = "SELECT 1 AS A, 2 AS B;
            SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run 2 queries with semicolon and DDL in the middle" {
            $query = "SELECT 1 AS A, 2 AS B;
            CREATE TABLE #t (a int);
            INSERT INTO #t VALUES (1);
            SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query with semicolon as Dataset" {
            $query = "SELECT 1 AS A, 2 AS B;
            SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As Dataset
            $result.Tables[0].A | Should -Be 1
            $result.Tables[0].B | Should -Be 2
            $result.Tables[1].A | Should -Be 3
            $result.Tables[1].B | Should -Be 4
        }
        It "should run the query as a PSObject" {
            $query = "SELECT 1 AS A, 2 AS B UNION ALL SELECT NULL AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As PSObject
            $result.A | Should -Be 1, $null
            $result.B | Should -Be 2, 4
        }
        It "should run the query as a SingleValue" {
            $query = "SELECT 1 AS A"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As SingleValue
            $result | Should -Be 1
        }
        It "should run the query from InputFile" {
            $file1 = Join-Path $workFolder 1.sql
            $file2 = Join-Path $workFolder 2.sql
            "SELECT 1 AS A, 2 AS B" | Out-File $file1 -Force
            "SELECT 3 AS A, 4 AS B" | Out-File $file2 -Force -Encoding bigendianunicode
            $result = Invoke-DBOQuery -InputFile $file1, $file2 -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query from InputObject" {
            $file1 = Join-Path $workFolder 1.sql
            $file2 = Join-Path $workFolder 2.sql
            "SELECT 1 AS A, 2 AS B" | Out-File $file1 -Force
            "SELECT 3 AS A, 4 AS B" | Out-File $file2 -Force -Encoding bigendianunicode
            $result = Get-Item $file1, $file2 | Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
            $result = $file1, $file2 | Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query with custom variables" {
            $query = "SELECT '#{Test}' AS A, '#{Test2}' AS B UNION ALL SELECT '3' AS A, '4' AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As DataTable -Variables @{ Test = '1'; Test2 = '2' }
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be '2', '4'
        }
        It "should run the query with custom variables and custom token template" {
            Set-PSFConfig -FullName dbops.config.variabletoken -Value '\$(token)\$'
            $query = "SELECT '`$Test`$' AS A, '`$Test_2.1-3`$' AS B UNION ALL SELECT '3' AS A, '4' AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As DataTable -Variables @{ Test = '1'; "Test_2.1-3" = '2' }
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be '2', '4'
            (Get-PSFConfig -FullName dbops.config.variabletoken).ResetValue()
        }
        It "should connect to the server from a custom variable" {
            $query = "SELECT 1 AS A, 2 AS B UNION ALL SELECT '#{tst}' AS A, #{a.b-c} AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance '#{srv}' -Credential $script:mssqlCredential -As DataTable -Variables @{
                Srv     = $script:mssqlInstance
                tst     = 3
                "a.b-c" = 4
            }
            $result.A | Should -Be 1, '3'
            $result.B | Should -Be 2, 4
        }
        It "should run the query with custom parameters" {
            $query = "SELECT @p1 AS A, @p2 AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Parameter @{ p1 = '1'; p2 = 'string' }
            $result.A | Should -Be 1
            $result.B | Should -Be string
        }
        It "should run the query with Type specified" {
            $query = "SELECT 1 AS A, 2 AS B UNION ALL SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Type SQLServer
            $result.A | Should -Be 1, 3
            $result.B | Should -Be 2, 4
        }
        It "should connect to a specific database" {
            $query = "SELECT db_name()"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database tempdb -As SingleValue
            $result | Should -Be tempdb
        }
        It "should address column names automatically" {
            $query = "SELECT 1 AS A, 2, 3"
            $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -As DataTable
            $result.Columns.ColumnName | Should -Be @('A', 'Column1', 'Column2')
            $result.A | Should -Be 1
            $result.Column1 | Should -Be 2
            $result.Column2 | Should -Be 3
        }
        It "should work with configurations" {
            $result = Invoke-DBOQuery -Query 'SELECT 1' -Configuration @{ SqlInstance = $script:mssqlInstance; Credential = $script:mssqlCredential } -As SingleValue
            $result | Should -Be 1
        }
        It "should connect via connection string" {
            $cString = "Data Source=$script:mssqlInstance"
            if ($script:mssqlCredential) {
                $cString += ";User ID=$($script:mssqlCredential.UserName); Password=$($script:mssqlCredential.GetNetworkCredential().Password)"
            }
            else {
                $cString += ";Integrated Security=True"
            }
            $result = Invoke-DBOQuery -Query 'SELECT 1' -ConnectionString $cString -As SingleValue
            $result | Should -Be 1
        }
    }
    Context "Negative tests" {
        It "should throw a zero division error" {
            $query = "SELECT 1/0"
            { $result = Invoke-DBOQuery -Query $query -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Silent } | Should throw "Divide by zero"
        }
        It "should throw a connection timeout error" {
            $query = "SELECT 1/0"
            { $result = Invoke-DBOQuery -Query $query -SqlInstance localhost:6493 -Credential $script:mssqlCredential -ConnectionTimeout 2 } | Should throw "The server was not found or was not accessible"
        }
        It "should fail when parameters are of a wrong type" {
            { Invoke-DBOQuery -Query 'SELECT 1/@foo' -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Parameter @{ foo = 'bar' } -Silent } | Should throw 'Conversion failed'
            { Invoke-DBOQuery -Query 'SELECT ''bar'' + @foo' -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Parameter @{ foo = 10 } -Silent } | Should throw 'Conversion failed'
            { Invoke-DBOQuery -Query 'SELECT ''bar'' + @foo' -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Parameter @{ foo = Get-Date } -Silent } | Should throw 'Conversion failed'
        }
        It "should fail when credentials are wrong" {
            { Invoke-DBOQuery -Query 'SELECT 1' -SqlInstance $script:mssqlInstance -Credential ([pscredential]::new('nontexistent', ([securestring]::new()))) } | Should throw 'Login failed'
            { Invoke-DBOQuery -Query 'SELECT 1' -SqlInstance $script:mssqlInstance -UserName nontexistent -Password ([securestring]::new()) } | Should throw 'Login failed'
        }
        It "should fail when input file is not found" {
            { Invoke-DBOQuery -InputFile '.\nonexistent' -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential } | Should throw 'Cannot find path'
            { '.\nonexistent' | Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential } | Should throw 'Cannot find path'
        }
    }
}