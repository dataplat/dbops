Describe "Invoke-DBOPackageCI tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Force

        $v1scripts = Join-Path $etcScriptFolder 'success'
        $v2scripts = Join-Path $etcScriptFolder 'transactional-failure'
        $packageNoPkgFile = Join-Path $workFolder "pkg_nopkgfile.zip"
    }
    AfterAll {
        Remove-Workfolder
    }
    Context "Creating a new CI package version 1.0" {
        It "should add new build to existing package" {
            $testResults = Invoke-DBOPackageCI -ScriptPath $v1scripts -Name $packageName
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.Version | Should -Be '1.0.1'
            Test-Path $packageName | Should -Be $true
        }
        It "build 1.0.1 should only contain scripts from 1.0" {
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\1.0.1\success\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\3.sql' | Should -BeIn $testResults.Path
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }
            Join-PSFPath -Normalize 'dbops.config.json' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'dbops.package.json' | Should -BeIn $testResults.Path
        }
    }
    Context "Adding new CI build on top of existing package" {
        It "should add new build to existing package" {
            $testResults = Invoke-DBOPackageCI -ScriptPath $v2scripts -Name $packageName -Version 1.0
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.Version | Should -Be '1.0.2'
            Test-Path $packageName | Should -Be $true
        }
        It "build 1.0.1 should only contain scripts from 1.0.1" {
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\1.0.1\success\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\3.sql' | Should -BeIn $testResults.Path
        }
        It "build 1.0.2 should only contain scripts from 1.0.2" {
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\1.0.2\transactional-failure\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.2\transactional-failure\2.sql' | Should -BeIn $testResults.Path
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }
            Join-PSFPath -Normalize 'dbops.config.json' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'dbops.package.json' | Should -BeIn $testResults.Path
        }
    }
    Context "adding new files redefining the version to 2.0" {
        It "should add new build to existing package" {
            $testResults = Invoke-DBOPackageCI -ScriptPath $etcScriptFolder -Name $packageName -Version 2.0
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.Version | Should -Be '2.0.1'
            Test-Path $packageName | Should -Be $true
        }
        It "build 1.0.1 should only contain scripts from 1.0.1" {
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\1.0.1\success\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\3.sql' | Should -BeIn $testResults.Path
        }
        It "build 1.0.2 should only contain scripts from 1.0.2" {
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\1.0.2\transactional-failure\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.2\transactional-failure\2.sql' | Should -BeIn $testResults.Path
        }
        It "build 2.0.1 should only contain scripts from 2.0.1" {
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\2.0.1\sqlserver-tests\success\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0.1\sqlserver-tests\success\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0.1\sqlserver-tests\success\3.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0.1\sqlserver-tests\transactional-failure\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0.1\sqlserver-tests\transactional-failure\2.sql' | Should -BeIn $testResults.Path
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }
            Join-PSFPath -Normalize 'dbops.config.json' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'dbops.package.json' | Should -BeIn $testResults.Path
        }
    }
    Context "negative tests" {
        BeforeAll {
            $null = New-DBOPackage -Name $packageNoPkgFile -Build 1.0 -ScriptPath $etcScriptFolder
            $null = Remove-ArchiveItem -Path $packageNoPkgFile -Item 'dbops.package.json'
        }
        It "should show warning when there are no new files" {
            $null = Invoke-DBOPackageCI -ScriptPath $etcScriptFolder -Name $packageName -Version 2.0 -WarningVariable warningResult 3>$null
            $warningResult.Message -join ';' | Should -BeLike '*No scripts have been selected, the original file is unchanged.*'
        }
        It "should throw error when package data file does not exist" {
            {
                $null = Invoke-DBOPackageCI -ScriptPath $etcScriptFolder -Name $packageNoPkgFile -Version 2.0
            } | Should -Throw '*Incorrect package format*'
        }
    }
}
