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

$workFolder = Join-PSFPath -Normalize "$testRoot\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-PSFPath -Normalize $workFolder 'unpacked'
$logTable = "DEPLOYHISTORY"
$v1scripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\success\1.sql"
$v1Journal = Get-Item $v1scripts | ForEach-Object { '1.0\' + $_.Name }
$verificationScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\verification\select.sql"
$packageName = Join-PSFPath -Normalize $workFolder 'TempDeployment.zip'
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

Describe "deploy.ps1 Oracle integration tests" -Tag $commandName, IntegrationTests {
    BeforeEach {

    }
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        $packageName = New-DBOPackage -Path $packageName -ScriptPath $v1scripts -Build 1.0 -Force
        $null = Expand-Archive -Path $packageName -DestinationPath $workFolder -Force
        $null = Invoke-DBOQuery @adminParams -Query $dropUserScript
        $null = Invoke-DBOQuery @adminParams -Query $createUserScript
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-DBOQuery @adminParams -Query $dropUserScript
    }
    Context "testing deployment of extracted package" {
        BeforeEach {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy with a -Configuration parameter" {
            $deploymentConfig = @{
                SqlInstance        = $script:oracleInstance
                Credential         = $testCredentials
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            }
            $testResults = & $workFolder\deploy.ps1 -Type Oracle -Configuration $deploymentConfig
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be $workFolder
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
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy with a set of parameters" {
            $testResults = & $workFolder\deploy.ps1 @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be $workFolder
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
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy nothing" {
            $testResults = & $workFolder\deploy.ps1 @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -WhatIf
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be $workFolder
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "No deployment performed - WhatIf mode." | Should BeIn $testResults.DeploymentLog
            $v1Journal | ForEach-Object { "$_ would have been executed - WhatIf mode." } | Should BeIn $testResults.DeploymentLog

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