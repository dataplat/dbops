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
$logTable = "testdeploy"
$cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\Cleanup.sql"
$v1scripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\success\1.sql"
$v1Journal = Get-Item $v1scripts | ForEach-Object { '1.0\' + $_.Name }
$v2scripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\success\2.sql"
$v2Journal = Get-Item $v2scripts | ForEach-Object { '2.0\' + $_.Name }
$verificationScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\verification\select.sql"

Describe "Register-DBOPackage Oracle integration tests" -Tag $commandName, IntegrationTests {
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
    Context "testing registration of scripts" {
        BeforeAll {
            $p2 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv2" -Build 1.0 -Force
            $p2 = Add-DBOBuild -ScriptPath $v2scripts -Package $p2 -Build 2.0
            $outputFile = "$workFolder\log.txt"
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should register version 1.0 without creating any objects" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Register-DBOPackage -Package $p2 -Build 1.0 @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv2.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            $v1Journal | ForEach-Object { "$_ was registered in table $logtable" } | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 1)

            #Verifying SchemaVersions table
            $testResults = Invoke-DBOQuery @connParams -Query "SELECT * FROM $logTable ORDER BY SCHEMAVERSIONID"
            $testResults.scriptname | Should Be $v1Journal
        }
        It "should register version 1.0 + 2.0 without creating any objects" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Register-DBOPackage -Package $p2 @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv2.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            $v2Journal | ForEach-Object { "$_ was registered in table $logtable" } | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be $rowsBefore

            #Verifying SchemaVersions table
            $testResults = Invoke-DBOQuery @connParams -Query "SELECT * FROM $logTable ORDER BY SCHEMAVERSIONID"
            $testResults.scriptname | Should Be (@($v1Journal) + @($v2Journal))
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy nothing" {
            $testResults = Register-DBOPackage $p1 @connParams -SchemaVersionTable $logTable -WhatIf
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $p1.FullName
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "Running in WhatIf mode - no registration performed." | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
}
