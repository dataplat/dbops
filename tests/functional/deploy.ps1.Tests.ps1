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

$workFolder = Join-PSFPath -Normalize "$here\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-PSFPath -Normalize $workFolder 'unpacked'
$logTable = "testdeploymenthistory"
$cleanupScript = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\Cleanup.sql"
$v1scripts = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\1.sql"
$v1Journal = Get-Item $v1scripts | ForEach-Object { '1.0\' + $_.Name }
$verificationScript = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\verification\select.sql"
$packageName = Join-PSFPath -Normalize $workFolder 'TempDeployment.zip'
$newDbName = "_test_$commandName"

Describe "deploy.ps1 integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        $packageName = New-DBOPackage -Path $packageName -ScriptPath $v1scripts -Build 1.0 -Force
        $null = Expand-Archive -Path $packageName -DestinationPath $workFolder -Force
        $dropDatabaseScript = 'IF EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{0}]; END' -f $newDbName
        $createDatabaseScript = 'IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN CREATE DATABASE [{0}]; END' -f $newDbName
        $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database master -Query $dropDatabaseScript
        $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database master -Query $createDatabaseScript
    }
    AfterAll {
        $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database master -Query $dropDatabaseScript
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    Context "testing deployment of extracted package" {
        BeforeEach {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy with a -Configuration parameter" {
            $deploymentConfig = @{
                SqlInstance        = $script:mssqlInstance
                Credential         = $script:mssqlCredential
                Database           = $newDbName
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            }
            $testResults = & $workFolder\deploy.ps1 -Configuration $deploymentConfig
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $workFolder
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy with a set of parameters" {
            $testResults = & $workFolder\deploy.ps1 -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $workFolder
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy with no components loaded" {
            $scriptBlock = {
                param (
                    $Path,
                    $DotSource,
                    $Database
                )
                . $DotSource
                $testResults = & $Path\deploy.ps1 -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $Database -Silent
                $testResults.Successful | Should -Be $true
                $testResults.Scripts.Name | Should -Not -BeNullOrEmpty
                $testResults.SqlInstance | Should -Be $script:mssqlInstance
                $testResults.Database | Should Be $Database
                $testResults.SourcePath | Should Be $Path
                $testResults.ConnectionType | Should Be 'SQLServer'
                $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
                $testResults.Error | Should BeNullOrEmpty
                $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
                $testResults.StartTime | Should -Not -BeNullOrEmpty
                $testResults.EndTime | Should -Not -BeNullOrEmpty
                $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
                Get-ChildItem function:\ | Where-Object Name -eq Invoke-Deployment | Should -BeNullOrEmpty
            }
            $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $workFolder, "$here\constants.ps1", $newDbName
            $job | Wait-Job | Receive-Job -ErrorAction Stop
            # # Get modules
            # $modules = Get-Module Pester | Select-Object -ExpandProperty Path
            # $sessionstate = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            # foreach ($modulePath in $modules) {
            #     $sessionstate.ImportPSModule($modulePath)
            # }
            # # Create runspace pool
            # $runspacepool = [runspacefactory]::CreateRunspacePool(1, 5, $sessionstate, $Host)
            # $runspacepool.Open()
            # $powershell = [powershell]::Create()
            # $params = @{
            #     Path       = $workFolder
            #     Instance   = $script:mssqlInstance
            #     Credential = $script:mssqlCredential
            #     Database   = $newDbName
            # }
            # [void]$powershell.AddScript($scriptBlock).AddParameters($params)
            # $powershell.RunspacePool = $runspacepool
            # try {
            #     $handle = $powershell.BeginInvoke()
            #     $cycles = 0
            #     do { Start-Sleep 1; $cycles++ } while (-not $handle.IsCompleted -and $cycles -lt 5)
            #     if ($powershell.Streams.Error.Count -gt 0) {
            #         throw $powershell.Streams.Error[0]
            #     }
            #     $powershell.EndInvoke($handle)
            # }
            # catch {
            #     throw $_
            # }
            # finally {
            #     $powershell.Dispose()
            #     $runspacepool.Close()
            # }
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
        }
        It "should deploy nothing" {
            $testResults = & $workFolder\deploy.ps1 -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -WhatIf
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $workFolder
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "No deployment performed - WhatIf mode." | Should BeIn $testResults.DeploymentLog
            $v1Journal | ForEach-Object { "$_ would have been executed - WhatIf mode." } | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
}
