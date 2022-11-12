Describe "Update-DBOPackage tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Force

        $null = New-DBOPackage -ScriptPath (Get-SourceScript -Version 1) -Name $packageName -Build 1.0 -Force -Slim
    }
    AfterAll {
        Remove-Workfolder
    }
    Context "Updating regular package" {
        It "updates prescripts" {
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.PreScripts.Scripts.FullName | Should -BeNullOrEmpty
            Update-DBOPackage -Path $packageName -PreScriptPath (Get-SourceScript -Version 2)
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.PreScripts.Scripts.FullName | Should -Be $script2
            $testResults.PreScripts.Scripts.PackagePath | Should -Be (Split-Path (Get-SourceScript -Version 2) -Leaf)
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\.dbops.prescripts\2.sql' | Should -BeIn $testResults.Path
        }
        It "updates postscripts" {
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.PostScripts.Scripts.FullName | Should -BeNullOrEmpty
            Update-DBOPackage -Path $packageName -PostScriptPath (Get-SourceScript -Version 2)
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.PostScripts.Scripts.FullName | Should -Be $script2
            $testResults.PostScripts.Scripts.PackagePath | Should -Be (Split-Path (Get-SourceScript -Version 2) -Leaf)
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\.dbops.prescripts\2.sql' | Should -BeIn $testResults.Path
        }
        # It "updates package version" {
        #     $testResults = Get-DBOPackage -Path $packageName
        #     $testResults.Version | Should -Be "1.0"
        #     Update-DBOPackage -Path $packageName -Version "13.37"
        #     $testResults = Get-DBOPackage -Path $packageName
        #     $testResults.Version | Should -Be "13.37"
        # }
        It "updates package slim parameter" {
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.Slim | Should -Be $true
            Update-DBOPackage -Path $packageName -Slim $false
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.Slim | Should -Be $false
        }
    }
    Context "Negative tests" {
        It "should throw when PreScript path does not exist" {
            { Update-DBOPackage -Path $packageName -PreScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' } | Should -Throw 'The following path is not valid*'
        }
        It "should throw when PostScript path does not exist" {
            { Update-DBOPackage -Path $packageName -PostScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' } | Should -Throw 'The following path is not valid*'
        }
        It "should throw when config item does not exist" {
            { Update-DBOPackage -Path $packageName -ConfigName NonexistingItem -Value '123' } | Should -Throw
        }
        # It "returns error when build version is null or empty" {
        #     { Update-DBOPackage -Name $packageName -Version $null } | Should -Throw 'Version not specified'
        #     { Update-DBOPackage -Name $packageName -Version "" } | Should -Throw 'Version not specified'
        # }
    }
}
