Describe "Get-DBOPackageArtifact tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Force

        $projectPath = Join-Path $workFolder 'TempDeployment'
        $null = New-Item $projectPath -ItemType Directory -Force
        $null = New-Item $projectPath\Current -ItemType Directory -Force
        $null = New-Item $projectPath\Versions -ItemType Directory -Force
        $null = New-Item $projectPath\Versions\1.0 -ItemType Directory -Force
        $null = New-Item $projectPath\Versions\2.0 -ItemType Directory -Force
        $null = New-DBOPackage -ScriptPath (Get-SourceScript -Version 1) -Name $packageName -Build 1.0 -Force
        Copy-Item -Path $packageName -Destination $projectPath\Versions\1.0
        $null = Add-DBOBuild -ScriptPath (Get-SourceScript -Version 2) -Path $packageName -Build 2.0
        Copy-Item -Path $packageName -Destination $projectPath\Versions\2.0
        $null = Add-DBOBuild -ScriptPath (Get-SourceScript -Version 3) -Path $packageName -Build 3.0
        Copy-Item -Path $packageName -Destination $projectPath\Current
    }
    AfterAll {
        Remove-Workfolder
    }
    Context "Regular tests" {
        It "should return the last version of the artifact" {
            $testResult = Get-DBOPackageArtifact -Repository $workFolder -Name TempDeployment
            Get-DBOPackage $testResult | Foreach-Object Version | Should -Be '3.0'
            $testResult.FullName | Should -Be (Join-PSFPath -Normalize "$projectPath\Current\TempDeployment.zip")
        }
        It "should return the custom version of the artifact" {
            $testResult = Get-DBOPackageArtifact -Repository $workFolder -Name TempDeployment -Version 2.0
            Get-DBOPackage $testResult | Foreach-Object Version | Should -Be '2.0'
            $testResult.FullName | Should -Be (Join-PSFPath -Normalize "$projectPath\Versions\2.0\TempDeployment.zip")
        }
        It "should return the artifact when project folder is specified" {
            $testResult = Get-DBOPackageArtifact -Repository $projectPath -Name TempDeployment
            Get-DBOPackage $testResult | Foreach-Object Version | Should -Be '3.0'
            $testResult.FullName | Should -Be (Join-PSFPath -Normalize "$projectPath\Current\TempDeployment.zip")
        }
    }
    Context "Negative tests" {
        It "should throw when folder not found" {
            { Get-DBOPackageArtifact -Repository .\nonexistingpath -Name TempDeployment } | Should -Throw
        }
        It "should return warning when folder has improper structure" {
            $null = Get-DBOPackageArtifact -Repository $scriptFolder -Name TempDeployment -WarningVariable warVar 3>$null
            $warVar | Should -BeLike '*incorrect structure of the repository*'
        }
        It "should return warning when version not found" {
            $null = Get-DBOPackageArtifact -Repository $workFolder -Name TempDeployment -Version 13.37 -WarningVariable warVar 3>$null
            $warVar | Should -BeLike '*Version 13.37 not found*'
        }
    }
}