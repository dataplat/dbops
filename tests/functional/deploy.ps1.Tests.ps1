Param (
    [switch]$Batch,
    [string]$Type = "SqlServer"
)
$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")

Describe "<command> deploy.ps1 integration tests" -Tag $commandName, IntegrationTests -ForEach @(
    @{ Batch = $Batch; $Type = $Type; Command = $commandName }
) {
    BeforeAll {
        . $PSScriptRoot\fixtures.ps1 -CommandName $Command -Type $Type -Batch $Batch

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
                . $DotSource -Type $Type -Batch $true
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
            $testResults = & $workFolder\deploy.ps1 @dbConnectionParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -WhatIf
            $testResults | Test-DeploymentOutput -Version 1 -WhatIf
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $v1Journal | ForEach-Object { "$_ would have been executed - WhatIf mode." } | Should -BeIn $testResults.DeploymentLog

            $testResults | Test-DeploymentState -Version 0
        }
    }
}