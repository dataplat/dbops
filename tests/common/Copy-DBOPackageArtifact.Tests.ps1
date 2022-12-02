Describe "ConvertFrom-EncryptedString tests" -Tag UnitTests {
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
        It "should copy the last version of the artifact" {
            $testResult = Copy-DBOPackageArtifact -Repository $workFolder -Name TempDeployment -Passthru -Destination $workFolder
            Get-DBOPackage $testResult | Foreach-Object Version | Should -Be '3.0'
            $testResult.FullName | Should -Be (Join-PSFPath -Normalize $workFolder TempDeployment.zip)
        }
        It "should copy the custom version of the artifact" {
            $testResult = Copy-DBOPackageArtifact -Repository $workFolder -Name TempDeployment -Version 2.0 -Passthru -Destination $workFolder
            Get-DBOPackage $testResult | Foreach-Object Version | Should -Be '2.0'
            $testResult.FullName | Should -Be (Join-PSFPath -Normalize $workFolder TempDeployment.zip)
        }
        It "should copy the artifact when project folder is specified" {
            $testResult = Copy-DBOPackageArtifact -Repository $projectPath -Name TempDeployment -Passthru -Destination $workFolder
            Get-DBOPackage $testResult | Foreach-Object Version | Should -Be '3.0'
            $testResult.FullName | Should -Be (Join-PSFPath -Normalize $workFolder TempDeployment.zip)
        }
    }
    Context "Negative tests" {
        It "should throw when folder not found" {
            { Copy-DBOPackageArtifact -Repository .\nonexistingpath -Name TempDeployment -Destination $workFolder } | Should -Throw
        }
        It "should return warning when folder has improper structure" {
            $null = Copy-DBOPackageArtifact -Repository $scriptFolder -Name TempDeployment -Destination $workFolder -WarningVariable warVar 3>$null
            $warVar | Should -BeLike '*incorrect structure of the repository*'
        }
        It "should return warning when version not found" {
            $null = Copy-DBOPackageArtifact -Repository $workFolder -Name TempDeployment -Version 13.37 -Destination $workFolder -WarningVariable warVar 3>$null
            $warVar | Should -BeLike '*Version 13.37 not found*'
        }
    }
}