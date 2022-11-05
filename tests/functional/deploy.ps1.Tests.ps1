Describe "<type> deploy.ps1 integration tests" -Tag IntegrationTests -ForEach @(
    @{ Type = "SqlServer" }
    @{ Type = "MySQL" }
    @{ Type = "Postgresql" }
    @{ Type = "Oracle" }
) {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName -Type $Type

        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        $packageName = New-DBOPackage -Path $packageName -ScriptPath $v1scripts -Build 1.0 -Force
        $null = Expand-Archive -Path $packageName -DestinationPath $workFolder -Force
        New-TestDatabase -Force
    }
    AfterAll {
        Remove-TestDatabase
        Remove-Workfolder
    }
    BeforeEach {
        $Type | Test-IsSkipped
    }
    Context "testing deployment of extracted package" {
        BeforeEach {
            Reset-TestDatabase
        }
        It "should deploy with a -Configuration parameter" {
            $deploymentConfig = @{
                SchemaVersionTable = $logTable
                DeploymentMethod   = 'NoTransaction'
                SqlInstance        = $dbConnectionParams.SqlInstance
                Silent             = $dbConnectionParams.Silent
                Credential         = $dbConnectionParams.Credential
                Database           = $dbConnectionParams.Database
            }
            $testResults = & $workFolder\deploy.ps1 -Configuration $deploymentConfig -Type $Type
            $testResults.SourcePath | Should -Be $workFolder
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $testResults | Test-DeploymentOutput -Version 1
            $testResults | Test-DeploymentState -Version 1 -HasJournal
        }
        It "should deploy with a set of parameters" {
            $testResults = & $workFolder\deploy.ps1 @dbConnectionParams -SchemaVersionTable $logTable
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $testResults | Test-DeploymentOutput -Version 1
            $testResults | Test-DeploymentState -Version 1 -HasJournal
        }
        It "should deploy with no components loaded" {
            $scriptBlock = {
                param (
                    $Path,
                    $DotSource,
                    $Type,
                    $Database
                )
                . $DotSource -Type $Type -Batch
                $testResults = & $Path\deploy.ps1 @dbConnectionParams
                $testResults | Test-DeploymentOutput -Version 1
                $testResults.Configuration.SchemaVersionTable | Should -Be 'SchemaVersions'
                $testResults.SourcePath | Should -Be $Path
                Get-ChildItem function:\ | Where-Object Name -eq Invoke-Deployment | Should -BeNullOrEmpty
            }
            $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $workFolder, "$PSScriptRoot\fixtures.ps1", $Type, $newDbName
            $job | Wait-Job | Receive-Job -ErrorAction Stop
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            Reset-TestDatabase
        }
        It "should deploy nothing" {
            $testResults = & $workFolder\deploy.ps1 @dbConnectionParams -SchemaVersionTable $logTable -WhatIf
            $testResults | Test-DeploymentOutput -Version 1 -WhatIf
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $v1Journal | ForEach-Object { "$_ would have been executed - WhatIf mode." } | Should -BeIn $testResults.DeploymentLog

            $testResults | Test-DeploymentState -Version 0
        }
    }
}