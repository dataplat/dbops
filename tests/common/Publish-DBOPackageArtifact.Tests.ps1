Describe "Publish-DBOPackageArtifact tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Force

        $v1scripts, $v2scripts, $v3scripts = Get-SourceScript -Version 1, 2, 3
        $projectPath = Join-Path $workFolder 'TempDeployment'

        $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force
    }
    AfterAll {
        Remove-Workfolder
    }
    It "should save the first version of the artifact" {
        $testResult = Publish-DBOPackageArtifact -Repository $workFolder -Path $packageName
        Get-DBOPackage $testResult | Foreach-Object Version | Should -Be '1.0'
        $testResult.FullName | Should -Be (Join-PSFPath -Normalize "$projectPath\Current\TempDeployment.zip")
        Test-Path "$projectPath\Current\TempDeployment.zip" | Should -Be $true
        Test-Path "$projectPath\Versions\1.0\TempDeployment.zip" | Should -Be $true
        Get-DBOPackage "$projectPath\Versions\1.0\TempDeployment.zip" | Foreach-Object Version | Should -Be '1.0'
    }
    It "should save a 2.0 version of the artifact using pipeline" {
        $pkg = Add-DBOBuild -ScriptPath $v2scripts -Path $packageName -Build 2.0
        $testResult = $pkg | Publish-DBOPackageArtifact -Repository $workFolder
        Get-DBOPackage $testResult | Foreach-Object Version | Should -Be '2.0'
        $testResult.FullName | Should -Be (Join-PSFPath -Normalize "$projectPath\Current\TempDeployment.zip")
        Test-Path "$projectPath\Current\TempDeployment.zip" | Should -Be $true
        Test-Path "$projectPath\Versions\1.0\TempDeployment.zip" | Should -Be $true
        Get-DBOPackage "$projectPath\Versions\1.0\TempDeployment.zip" | Foreach-Object Version | Should -Be '1.0'
        Test-Path "$projectPath\Versions\2.0\TempDeployment.zip" | Should -Be $true
        Get-DBOPackage "$projectPath\Versions\2.0\TempDeployment.zip" | Foreach-Object Version | Should -Be '2.0'
    }
    It "should save a 3.0 version of the artifact without changing current version" {
        $null = Add-DBOBuild -ScriptPath $v3scripts -Path $packageName -Build 3.0
        $testResult = Publish-DBOPackageArtifact -Repository $workFolder -Path $packageName -VersionOnly
        Get-DBOPackage $testResult | Foreach-Object Version | Should -Be '3.0'
        $testResult.FullName | Should -Be (Join-PSFPath -Normalize "$projectPath\Versions\3.0\TempDeployment.zip")
        Test-Path "$projectPath\Current\TempDeployment.zip" | Should -Be $true
        Get-DBOPackage "$projectPath\Current\TempDeployment.zip" | Foreach-Object Version | Should -Be '2.0'
        Test-Path "$projectPath\Versions\1.0\TempDeployment.zip" | Should -Be $true
        Get-DBOPackage "$projectPath\Versions\1.0\TempDeployment.zip" | Foreach-Object Version | Should -Be '1.0'
        Test-Path "$projectPath\Versions\2.0\TempDeployment.zip" | Should -Be $true
        Get-DBOPackage "$projectPath\Versions\2.0\TempDeployment.zip" | Foreach-Object Version | Should -Be '2.0'
        Test-Path "$projectPath\Versions\3.0\TempDeployment.zip" | Should -Be $true
        Get-DBOPackage "$projectPath\Versions\3.0\TempDeployment.zip" | Foreach-Object Version | Should -Be '3.0'
    }
    It "should throw when -Repository is not a folder" {
        { $null = Publish-DBOPackageArtifact -Repository .\nonexistentpath -Path $packageName } | Should -Throw
        { $null = Publish-DBOPackageArtifact -Repository $v1scripts -Path $packageName } | Should -Throw
    }
    It "should throw when package is not a proper dbops package" {
        { $null = Publish-DBOPackageArtifact -Repository $workFolder -Path .\nonexistentpath } | Should -Throw
        { $null = Publish-DBOPackageArtifact -Repository $workFolder -Path $v1scripts } | Should -Throw
    }
}