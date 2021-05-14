Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }
$testRoot = (Get-Item $here\.. ).FullName

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$testRoot\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running Oracle $commandName tests" -ForegroundColor Cyan
}

. "$testRoot\constants.ps1"

$oraUserName = 'DBOPSDEPLOYPS1'
$oraPassword = 'S3cur_pAss'
$testCredentials = [pscredential]::new($oraUserName, (ConvertTo-SecureString $oraPassword -AsPlainText -Force))
$connParams = @{
    Type        = 'Oracle'
    SqlInstance = $script:oracleInstance
    Silent      = $true
    Credential  = $testCredentials
}
$adminParams = @{
    Type                = 'Oracle'
    SqlInstance         = $script:oracleInstance
    Silent              = $true
    Credential          = $script:oracleCredential
    ConnectionAttribute = @{
        'DBA Privilege' = 'SYSDBA'
    }
}
$createUserScript = "CREATE USER $oraUserName IDENTIFIED BY $oraPassword/
GRANT CONNECT, RESOURCE, CREATE ANY TABLE TO $oraUserName/
GRANT EXECUTE on dbms_lock to $oraUserName"
$dropUserScript = "
    BEGIN
        FOR ln_cur IN (SELECT sid, serial# FROM v`$session WHERE username = '$oraUserName')
        LOOP
            EXECUTE IMMEDIATE ('ALTER SYSTEM KILL SESSION ''' || ln_cur.sid || ',' || ln_cur.serial# || ''' IMMEDIATE');
        END LOOP;
        FOR x IN ( SELECT count(*) cnt
            FROM DUAL
            WHERE EXISTS (SELECT * FROM DBA_USERS WHERE USERNAME = '$oraUserName')
        )
        LOOP
            IF ( x.cnt = 1 ) THEN
                EXECUTE IMMEDIATE 'DROP USER $oraUserName CASCADE';
            END IF;
        END LOOP;
    END;
    /"
$dropObjectsScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\verification\drop.sql"

$workFolder = Join-PSFPath -Normalize "$testRoot\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-PSFPath -Normalize $workFolder 'unpacked'
$logTable = "TESTDEPLOY"
$cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\Cleanup.sql"
$tranFailScripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\transactional-failure"
$v1scripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\success\1.sql"
$v2scripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\success\2.sql"
$verificationScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\verification\select.sql"
$packageFileName = Join-PSFPath -Normalize $workFolder "dbops.package.json"
$cleanupPackageName = Join-PSFPath -Normalize "$testRoot\etc\TempCleanup.zip"
$outFile = Join-PSFPath -Normalize "$testRoot\etc\outLog.txt"


Describe "Install-DBOScript Oracle integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = Invoke-DBOQuery @adminParams -Query $dropUserScript
        $null = Invoke-DBOQuery @adminParams -Query $createUserScript
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-DBOQuery @adminParams -Query $dropUserScript
    }
    Context "testing regular deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOScript @connParams -ScriptPath $v1scripts -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Get-Item $v1scripts).Name
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.NAME
            'a' | Should BeIn $testResults.NAME
            'b' | Should BeIn $testResults.NAME
            'c' | Should Not BeIn $testResults.NAME
            'd' | Should Not BeIn $testResults.NAME

            #Validating schema version table
            $svResults = Invoke-DBOQuery @connParams -Query "SELECT * FROM $logTable"
            $svResults.CHECKSUM | Should -Not -BeNullOrEmpty
            $svResults.ExecutionTime | Should -BeGreaterOrEqual 0
            $svResults.APPLIEDBY | Should -Be $oraUserName
        }
    }
    Context "testing transactional deployment of scripts" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "Should throw an error and not create any objects" {
            #Running package
            { $null = Install-DBOScript -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction } | Should throw 'name is already used by an existing object'
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            # oracle has implicit commit, sorry folks
            $logTable | Should -BeIn $testResults.NAME
            'a' | Should -BeIn $testResults.NAME
            'b' | Should -Not -BeIn $testResults.NAME
            'c' | Should -Not -BeIn $testResults.NAME
            'd' | Should -Not -BeIn $testResults.NAME
        }
    }
    Context "testing non transactional deployment of scripts" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "Should throw an error and create one object" {
            #Running package
            { $null = Install-DBOScript -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction } | Should throw 'name is already used by an existing object'
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.NAME
            'a' | Should BeIn $testResults.NAME
            'b' | Should Not BeIn $testResults.NAME
            'c' | Should Not BeIn $testResults.NAME
            'd' | Should Not BeIn $testResults.NAME
        }
    }
    Context "testing script deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Get-Item $v1scripts).Name
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.NAME
            'a' | Should BeIn $testResults.NAME
            'b' | Should BeIn $testResults.NAME
            'c' | Should Not BeIn $testResults.NAME
            'd' | Should Not BeIn $testResults.NAME
        }
        It "should deploy version 2.0" {
            $testResults = Install-DBOScript -ScriptPath $v2scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Get-Item $v2scripts).Name
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v2scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.NAME
            'a' | Should BeIn $testResults.NAME
            'b' | Should BeIn $testResults.NAME
            'c' | Should BeIn $testResults.NAME
            'd' | Should BeIn $testResults.NAME
        }
    }
    Context "testing deployment order" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy 2.sql before 1.sql" {
            $testResults = Install-DBOScript -ScriptPath $v2scripts, $v1scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Get-Item $v2scripts, $v1scripts).Name
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be @($v2scripts, $v1scripts)
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.NAME
            'a' | Should BeIn $testResults.NAME
            'b' | Should BeIn $testResults.NAME
            'c' | Should BeIn $testResults.NAME
            'd' | Should BeIn $testResults.NAME
            #Verifying order
            $r1 = Invoke-DBOQuery @connParams -Query "SELECT scriptname FROM $logtable ORDER BY SCHEMAVERSIONID"
            $r1.SCRIPTNAME | Should Be (Get-Item $v2scripts, $v1scripts).Name
        }
    }
    # Context "testing timeouts" {
    #     BeforeAll {
    #         $content = '
    #             DECLARE
    #                 in_time number := 3;
    #             BEGIN
    #                 DBMS_LOCK.sleep(in_time);
    #             END;'
    #         $file = Join-PSFPath -Normalize "$workFolder\delay.sql"
    #         $content | Set-Content $file
    #         $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
    #     }
    #     AfterEach {
    #         $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
    #     }
    #     It "should throw timeout error" {
    #         { $null = Install-DBOScript -ScriptPath "$workFolder\delay.sql" @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 2 } | Should throw 'user requested cancel of current operation'
    #         $output = Get-Content "$workFolder\log.txt" -Raw
    #         $output | Should BeLike "*user requested cancel of current operation*"
    #     }
    #     It "should successfully run within specified timeout" {
    #         $testResults = Install-DBOScript -ScriptPath "$workFolder\delay.sql" @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 6
    #         $testResults.Successful | Should Be $true
    #         $testResults.Scripts.Name | Should Be "delay.sql"
    #         $testResults.SqlInstance | Should Be $script:oracleInstance
    #         $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
    #         $testResults.ConnectionType | Should Be 'Oracle'
    #         $testResults.Configuration.SchemaVersionTable | Should Be $logTable
    #         $testResults.Error | Should BeNullOrEmpty
    #         $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
    #         $testResults.StartTime | Should Not BeNullOrEmpty
    #         $testResults.EndTime | Should Not BeNullOrEmpty
    #         $testResults.EndTime | Should -BeGreaterThan $testResults.StartTime

    #         $output = Get-Content "$workFolder\log.txt" -Raw
    #         $output | Should Not BeLike '*user requested cancel of current operation*'
    #     }
    #     It "should successfully run with infinite timeout" {
    #         $testResults = Install-DBOScript -ScriptPath "$workFolder\delay.sql" @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 0
    #         $testResults.Successful | Should Be $true
    #         $testResults.Scripts.Name | Should Be "delay.sql"
    #         $testResults.SqlInstance | Should Be $script:oracleInstance
    #         $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
    #         $testResults.ConnectionType | Should Be 'Oracle'
    #         $testResults.Configuration.SchemaVersionTable | Should Be $logTable
    #         $testResults.Error | Should BeNullOrEmpty
    #         $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
    #         $testResults.StartTime | Should Not BeNullOrEmpty
    #         $testResults.EndTime | Should Not BeNullOrEmpty
    #         $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
    #         'Upgrade successful' | Should BeIn $testResults.DeploymentLog

    #         $output = Get-Content "$workFolder\log.txt" -Raw
    #         $output | Should Not BeLike "*user requested cancel of current operation*"
    #     }
    # }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy nothing" {
            $testResults = Install-DBOScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $logTable -WhatIf
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Get-Item $v1scripts).Name
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "No deployment performed - WhatIf mode." | Should BeIn $testResults.DeploymentLog
            "$((Get-Item $v1scripts).Name) would have been executed - WhatIf mode." | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.NAME
            'a' | Should Not BeIn $testResults.NAME
            'b' | Should Not BeIn $testResults.NAME
            'c' | Should Not BeIn $testResults.NAME
            'd' | Should Not BeIn $testResults.NAME
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOScript -ScriptPath $v1scripts @connParams
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Get-Item $v1scripts).Name
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'SchemaVersions' | Should BeIn $testResults.NAME
            'a' | Should BeIn $testResults.NAME
            'b' | Should BeIn $testResults.NAME
            'c' | Should Not BeIn $testResults.NAME
            'd' | Should Not BeIn $testResults.NAME
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
        It "should deploy version 2.0" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOScript -ScriptPath $v2scripts @connParams
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Get-Item $v2scripts).Name
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v2scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'SchemaVersions' | Should BeIn $testResults.NAME
            'a' | Should BeIn $testResults.NAME
            'b' | Should BeIn $testResults.NAME
            'c' | Should BeIn $testResults.NAME
            'd' | Should BeIn $testResults.NAME
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 2)
        }
    }
    Context "testing deployment with no history`: SchemaVersion is null" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $null
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Get-Item $v1scripts).Name
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should BeNullOrEmpty
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog
            'Checking whether journal table exists..' | Should Not BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'SchemaVersions' | Should Not BeIn $testResults.NAME
            'a' | Should BeIn $testResults.NAME
            'b' | Should BeIn $testResults.NAME
            'c' | Should Not BeIn $testResults.NAME
            'd' | Should Not BeIn $testResults.NAME
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 2)
        }
    }
    Context "testing deployments to the native DbUp SchemaVersion table" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "Should deploy version 1 to an older schemaversion table" {
            # create old SchemaVersion table
            $query = @"
            CREATE TABLE $logTable (
                schemaversionid NUMBER(10),
                scriptname VARCHAR2(255) NOT NULL,
                applied TIMESTAMP NOT NULL,
                CONSTRAINT PK_$logTable PRIMARY KEY (schemaversionid)
            )
            /
            CREATE SEQUENCE $($logTable)_sequence
            /
            CREATE OR REPLACE TRIGGER $($logTable)_on_insert
            BEFORE INSERT ON $logTable
            FOR EACH ROW
            BEGIN
                SELECT $($logTable)_sequence.nextval
                INTO :new.schemaversionid
                FROM dual;
            END;
"@
            $null = Invoke-DBOQuery @connParams -Query $query
            $testResults = Install-DBOScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-Item $v1scripts).Name
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
            $schemaTableColumns = Invoke-DBOQuery @connParams -Query "select c.COLUMN_NAME from USER_TAB_COLUMNS c JOIN USER_TABLES t ON c.TABLE_NAME = t.TABLE_NAME where c.TABLE_NAME = '$logTable'"
            $schemaTableColumns.COLUMN_NAME | Should -Be @("schemaversionid", "scriptname", "applied")
            $schemaTableContents = Invoke-DBOQuery @connParams -Query "select scriptname from $logTable"
            $schemaTableContents.SCRIPTNAME | Should -Be (Get-Item $v1scripts).Name
        }
    }
    Context "deployments with errors should throw terminating errors" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
            $null = Install-DBOScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $null
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "Should return terminating error when object exists" {
            #Running package
            { $null = Install-DBOScript -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction } | Should throw 'name is already used by an existing object'
        }
        It "should not deploy anything after throwing an error" {
            #Running package
            try {
                $testResults = $null
                $null = Install-DBOScript -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction
                $testResults = Install-DBOScript -ScriptPath $v2scripts @connParams -SchemaVersionTable $logTable
            }
            catch {
                $errorObject = $_
            }
            $testResults | Should Be $null
            $errorObject | Should Not BeNullOrEmpty
            $errorObject.Exception.Message | Should -BeLike '*name is already used by an existing object'
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'a' | Should BeIn $testResults.NAME
            'b' | Should BeIn $testResults.NAME
            'c' | Should Not BeIn $testResults.NAME
            'd' | Should Not BeIn $testResults.NAME
        }
    }
}
