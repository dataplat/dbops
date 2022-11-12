BeforeDiscovery {
    . "$PSScriptRoot\..\detect_types.ps1"
}

Describe "<type> Invoke-DBOQuery integration tests" -Tag FunctionalTests -ForEach $types {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName -Type $Type

        New-Workfolder -Force
        New-TestDatabase -Force

        switch ($Type) {
            SqlServer {
                $separator = "GO"
                $loginError = '*Login failed*'
                $connectionError = "*The server was not found or was not accessible*"
                $unknownTableError = "*Invalid object name*"
                $conversionError = "*Conversion failed*"
            }
            MySQL {
                $separator = ";"
                $loginError = '*Access denied*'
                $connectionError = "*Unable to connect to any of the specified MySQL hosts*"
                $unknownTableError = "*Table * doesn't exist*"
            }
            PostgreSQL {
                $separator = ";"
                $loginError = '*No password has been provided*'
                $connectionError = switch ($isWindows) {
                    $false { '*Resource temporarily unavailable*' }
                    default { "*No such host is known*" }
                }
                $unknownTableError = "*relation * does not exist*"
            }
            Oracle {
                $separator = "`n/"
                $loginError = '*logon denied*'
                $connectionError = switch ($isWindows) {
                    $false { "*TNS:could not resolve*" }
                    default { "*Connection request timed out*" }
                }
                $unknownTableError = "*table or view does not exist*"
            }
        }
        $pathError = 'Cannot find path*'
    }
    AfterAll {
        Remove-TestDatabase
        Remove-Workfolder
    }
    Context "Regular tests" {
        BeforeAll {
            $file1 = Join-Path 'TestDrive:' 1.sql
            $file2 = Join-Path 'TestDrive:' 2.sql
            $query = switch ($Type) {
                Oracle { "SELECT 1 AS A, 2 AS B FROM DUAL" }
                Default { "SELECT 1 AS A, 2 AS B" }
            }
            $query | Out-File $file1 -Force
            $query = switch ($Type) {
                Oracle { "SELECT 3 AS A, 4 AS B FROM DUAL" }
                Default { "SELECT 3 AS A, 4 AS B" }
            }
            $query | Out-File $file2 -Force -Encoding bigendianunicode
        }
        It "should run the query" {
            $query = switch ($Type) {
                Oracle { "SELECT 1 AS A, 2 AS B FROM DUAL UNION ALL SELECT 3 AS A, 4 AS B FROM DUAL" }
                Default { "SELECT 1 AS A, 2 AS B UNION ALL SELECT 3 AS A, 4 AS B" }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -As DataTable
            $result.A | Should -Be 1, 3
            $result.B | Should -Be 2, 4
        }
        It "should select NULL" {
            $query = switch ($Type) {
                Oracle { "SELECT NULL FROM DUAL" }
                Default { "SELECT NULL" }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -As DataTable

            $query = switch ($Type) {
                Oracle { $result.NULL | Should -Be ([DBNull]::Value) }
                MySQL { $result.NULL | Should -Be ([DBNull]::Value) }
                Default { $result.Column1 | Should -Be ([DBNull]::Value) }
            }
        }
        It "should run the query with print and capture output" {
            if ($Type -ne 'SqlServer') {
                Set-ItResult -Skipped -Because "$Type doesn't support print statements"
            }
            $query = switch ($Type) {
                Default { "print ('Foo bar!')" }
            }
            $null = Invoke-DBOQuery -Query $query @dbConnectionParams -As DataTable -OutputFile $outputFile
            $outputFile | Should -FileContentMatch '^Foo bar!$'
        }
        It "should run the query with separator" {
            $query = switch ($Type) {
                Oracle {
                    "SELECT 1 AS A, 2 AS B FROM DUAL
            {0}
            SELECT 3 AS A, 4 AS B FROM DUAL"
                }
                Default {
                    "SELECT 1 AS A, 2 AS B
            {0}
            SELECT 3 AS A, 4 AS B"
                }
            }
            $result = Invoke-DBOQuery -Query ($query -f $separator) @dbConnectionParams -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query with separator as a dataset" {
            $query = switch ($Type) {
                Oracle {
                    "SELECT 1 AS A, 2 AS B FROM DUAL
            {0}
            SELECT 3 AS A, 4 AS B FROM DUAL"
                }
                Default {
                    "SELECT 1 AS A, 2 AS B
            {0}
            SELECT 3 AS A, 4 AS B"
                }
            }
            $result = Invoke-DBOQuery -Query ($query -f $separator) @dbConnectionParams -As Dataset
            $result.Tables[0].A | Should -Be 1
            $result.Tables[0].B | Should -Be 2
            $result.Tables[1].A | Should -Be 3
            $result.Tables[1].B | Should -Be 4
        }
        It "should run 2 queries with semicolon" {
            if ($Type -eq 'Oracle') {
                Set-ItResult -Skipped -Because "$Type doesn't support semicolon separators"
            }
            $query = switch ($Type) {
                Default {
                    "SELECT 1 AS A, 2 AS B;
            SELECT 3 AS A, 4 AS B"
                }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run 2 queries with semicolon and DDL in the middle" {
            if ($Type -eq 'Oracle') {
                Set-ItResult -Skipped -Because "$Type doesn't support semicolon separators"
            }
            $query = switch ($Type) {
                Default {
                    "SELECT 1 AS A, 2 AS B;
                    CREATE TABLE t (a int);
                    INSERT INTO t VALUES (1);
                    SELECT 3 AS A, 4 AS B"
                }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            switch ($Type) {
                MySQL {
                    $result[3].A | Should -Be 3
                    $result[3].B | Should -Be 4
                }
                Default {
                    $result[1].A | Should -Be 3
                    $result[1].B | Should -Be 4
                }
            }
        }
        It "should run the query with semicolon as Dataset" {
            if ($Type -eq 'Oracle') {
                Set-ItResult -Skipped -Because "$Type doesn't support semicolon separators"
            }
            $query = switch ($Type) {
                Default {
                    "SELECT 1 AS A, 2 AS B;
                    SELECT 3 AS A, 4 AS B"
                }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -As Dataset
            $result.Tables[0].A | Should -Be 1
            $result.Tables[0].B | Should -Be 2
            $result.Tables[1].A | Should -Be 3
            $result.Tables[1].B | Should -Be 4
        }
        It "should run the query as a PSObject" {
            $query = switch ($Type) {
                Oracle { "SELECT 1 AS A, 2 AS B FROM DUAL UNION ALL SELECT NULL AS A, 4 AS B FROM DUAL" }
                Default { "SELECT 1 AS A, 2 AS B UNION ALL SELECT NULL AS A, 4 AS B" }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -As PSObject
            $result.A | Should -Be 1, $null
            $result.B | Should -Be 2, 4
        }
        It "should run the query as a SingleValue" {
            $query = switch ($Type) {
                Oracle { "SELECT 1 AS A FROM DUAL" }
                Default { "SELECT 1 AS A" }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -As SingleValue
            $result | Should -Be 1
        }
        It "should run the query from InputFile" {
            $result = Invoke-DBOQuery -InputFile $file1, $file2 @dbConnectionParams -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query from InputObject" {
            $result = Get-Item $file1, $file2 | Invoke-DBOQuery @dbConnectionParams -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
            $result = $file1, $file2 | Invoke-DBOQuery @dbConnectionParams -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should address column names automatically" {
            $query = switch ($Type) {
                Oracle { "SELECT 1 AS A, 2, 3 FROM DUAL" }
                Default { "SELECT 1 AS A, 2, 3" }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -As DataTable
            switch ($Type) {
                MySQL {
                    $result.Columns.ColumnName | Should -Be @('A', '2', '3')
                    $result.A | Should -Be 1
                    $result.2 | Should -Be 2
                    $result.3 | Should -Be 3
                }
                Oracle {
                    $result.Columns.ColumnName | Should -Be @('A', '2', '3')
                    $result.A | Should -Be 1
                    $result.2 | Should -Be 2
                    $result.3 | Should -Be 3
                }
                Default {
                    $result.Columns.ColumnName | Should -Be @('A', 'Column1', 'Column2')
                    $result.A | Should -Be 1
                    $result.Column1 | Should -Be 2
                    $result.Column2 | Should -Be 3
                }
            }

        }
        It "should work with configurations" {
            $query = switch ($Type) {
                Oracle { 'SELECT 1 FROM DUAL' }
                Default { 'SELECT 1' }
            }
            $result = Invoke-DBOQuery -Type $Type -Query $query -Configuration @{ SqlInstance = $instance; Credential = $credential } -As SingleValue
            $result | Should -Be 1
        }
        It "should connect via connection string" {
            $query = switch ($Type) {
                Oracle { 'SELECT 1 FROM DUAL' }
                Default { 'SELECT 1' }
            }
            $result = Invoke-DBOQuery -Type $Type -Query $query -ConnectionString $connectionString -As SingleValue
            $result | Should -Be 1
        }
    }
    Context "Custom variables tests" {
        AfterEach {
            (Get-PSFConfig -FullName dbops.config.variabletoken).ResetValue()
        }
        It "should run the query with custom variables" {
            $query = switch ($Type) {
                Oracle { "SELECT '#{Test}' AS A, '#{Test2}' AS B FROM DUAL UNION ALL SELECT '3' AS A, '4' AS B FROM DUAL" }
                Default { "SELECT '#{Test}' AS A, '#{Test2}' AS B UNION ALL SELECT '3' AS A, '4' AS B" }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -As DataTable -Variables @{ Test = '1'; Test2 = '2' }
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be '2', '4'
        }
        It "should run the query with custom variables and custom token template" {
            Set-PSFConfig -FullName dbops.config.variabletoken -Value '\$(token)\$'
            $query = switch ($Type) {
                Oracle { "SELECT '`$Test`$' AS A, '`$Test_2.1-3`$' AS B FROM DUAL UNION ALL SELECT '3' AS A, '4' AS B FROM DUAL" }
                Default { "SELECT '`$Test`$' AS A, '`$Test_2.1-3`$' AS B UNION ALL SELECT '3' AS A, '4' AS B" }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -As DataTable -Variables @{ Test = '1'; "Test_2.1-3" = '2' }
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be '2', '4'
            (Get-PSFConfig -FullName dbops.config.variabletoken).ResetValue()
        }
        It "should connect to the server from a custom variable" {
            $query = switch ($Type) {
                Oracle { "SELECT '1' AS A, 2 AS B FROM DUAL UNION ALL SELECT '#{tst}' AS A, #{a.b-c} AS B FROM DUAL" }
                Default { "SELECT '1' AS A, 2 AS B UNION ALL SELECT '#{tst}' AS A, #{a.b-c} AS B" }
            }
            $result = Invoke-DBOQuery -Type $Type -Query $query -SqlInstance '#{srv}' -Credential $credential -Database $newDbName -As DataTable -Variables @{
                Srv     = $instance
                tst     = 3
                "a.b-c" = 4
            }
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be 2, 4
        }
        It "should run the query with custom parameters" {
            $query = switch ($Type) {
                Oracle { "SELECT :p1 AS A, :p2 AS B FROM DUAL" }
                Default { "SELECT @p1 AS A, @p2 AS B" }
            }
            $result = Invoke-DBOQuery -Query $query @dbConnectionParams -Parameter @{ p1 = '1'; p2 = 'string' }
            $result.A | Should -Be 1
            $result.B | Should -Be string
        }
    }
    Context "Negative tests" {
        It "should throw an unknown table error" {
            $query = switch ($Type) {
                Default { "SELECT * FROM nonexistent" }
            }
            { $null = Invoke-DBOQuery -Query $query @dbConnectionParams } | Should -Throw $unknownTableError
        }
        It "should throw a connection timeout error" {
            { $null = Invoke-DBOQuery -Type $Type -Query "foobar" -SqlInstance foobark:6493 -Credential $credential -ConnectionTimeout 2 } | Should -Throw $connectionError
        }
        It "should fail when parameters are of a wrong type" {
            if ($Type -eq 'MySQL') {
                Set-ItResult -Skipped -Because "$Type doesn't care about wrong types, it seems"
            }
            $query1 = switch ($Type) {
                Oracle { 'SELECT 1/@foo FROM DUAL' }
                Default { 'SELECT 1/@foo' }
            }
            $query2 = switch ($Type) {
                Oracle { 'SELECT ''bar'' + @foo FROM DUAL' }
                Default { 'SELECT ''bar'' + @foo' }
            }
            { Invoke-DBOQuery -Query $query1 @dbConnectionParams -Parameter @{ foo = 'bar' } } | Should -Throw $conversionError
            { Invoke-DBOQuery -Query $query2 @dbConnectionParams -Parameter @{ foo = 10 } } | Should -Throw $conversionError
            { Invoke-DBOQuery -Query $query2 @dbConnectionParams -Parameter @{ foo = Get-Date } } | Should -Throw $conversionError
        }
        It "should fail when credentials are wrong" {
            $query = switch ($Type) {
                Default { 'SELECT 1' }
            }
            { Invoke-DBOQuery -Type $Type -Query $query -SqlInstance $instance -Credential ([pscredential]::new('nontexistent', ([securestring]::new()))) } | Should -Throw $loginError
            { Invoke-DBOQuery -Type $Type -Query $query -SqlInstance $instance -UserName nontexistent -Password ([securestring]::new()) } | Should -Throw $loginError
        }
        It "should fail when input file is not found" {
            { Invoke-DBOQuery -InputFile '.\nonexistent' @dbConnectionParams } | Should -Throw $pathError
            { '.\nonexistent' | Invoke-DBOQuery @dbConnectionParams } | Should -Throw $pathError
        }
    }
}