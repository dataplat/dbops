Describe "Remove-DBOBuild tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Unpacked -Force

        $packageNameTest = "$packageName.test.zip"
        $packageNoPkgFile = Join-Path $workFolder "pkg_nopkgfile.zip"

        $null = New-DBOPackage -ScriptPath (Get-SourceScript -Version 1) -Name $packageName -Build 1.0 -Force
        $null = Add-DBOBuild -ScriptPath (Get-SourceScript -Version 2) -Path $packageName -Build 2.0
    }
    AfterAll {
        Remove-Workfolder
    }

    Context "removing version 1.0 from existing package" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
        }
        It "should remove build from existing package" {
            { Remove-DBOBuild -Name $packageNameTest -Build 1.0 } | Should -Not -Throw
            Test-Path $packageNameTest | Should -Be $true
        }
        It "build 1.0 should not exist" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0' | Should -Not -BeIn $testResults.Path
        }
        It "build 2.0 should contain scripts from 2.0" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\2.0\2.sql' | Should -BeIn $testResults.Path
        }
        It "should contain module files" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should -BeIn $testResults.Path
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            $testResults = Get-ArchiveItem $packageNameTest
            'dbops.config.json' | Should -BeIn $testResults.Path
            'dbops.package.json' | Should -BeIn $testResults.Path
        }
    }
    Context "removing version 2.0 from existing package" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
        }
        It "should remove build from existing package" {
            { Remove-DBOBuild -Name $packageNameTest -Build 2.0 } | Should -Not -Throw
            Test-Path $packageNameTest | Should -Be $true
        }
        It "build 1.0 should contain scripts from 1.0" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $testResults.Path
        }
        It "build 2.0 should not exist" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\2.0' | Should -Not -BeIn $testResults.Path
        }
        It "should contain module files" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should -BeIn $testResults.Path
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            $testResults = Get-ArchiveItem $packageNameTest
            'dbops.config.json' | Should -BeIn $testResults.Path
            'dbops.package.json' | Should -BeIn $testResults.Path
        }
    }
    Context "removing all versions from existing package" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
        }
        It "should remove build from existing package" {
            { Remove-DBOBuild -Name $packageNameTest -Build "1.0", "2.0" } | Should -Not -Throw
            Test-Path $packageNameTest | Should -Be $true
        }
        It "build 1.0 should not exist" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0' | Should -Not -BeIn $testResults.Path
        }
        It "build 2.0 should not exist" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\2.0' | Should -Not -BeIn $testResults.Path
        }
        It "should contain module files" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should -BeIn $testResults.Path
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            $testResults = Get-ArchiveItem $packageNameTest
            'dbops.config.json' | Should -BeIn $testResults.Path
            'dbops.package.json' | Should -BeIn $testResults.Path
        }
    }
    Context "removing version 2.0 from existing package using pipeline" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
        }
        It "should remove build from existing package" {
            { $packageNameTest | Remove-DBOBuild -Build '2.0' } | Should -Not -Throw
            Test-Path $packageNameTest | Should -Be $true
        }
        It "build 1.0 should contain scripts from 1.0" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $testResults.Path
        }
        It "build 2.0 should not exist" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\2.0' | Should -Not -BeIn $testResults.Path
        }
        It "should contain module files" {
            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should -BeIn $testResults.Path
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            $testResults = Get-ArchiveItem $packageNameTest
            'dbops.config.json' | Should -BeIn $testResults.Path
            'dbops.package.json' | Should -BeIn $testResults.Path
        }
    }
    Context "negative tests" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
            $null = New-DBOPackage -Name $packageNoPkgFile -Build 1.0 -ScriptPath $scriptFolder
            $null = Remove-ArchiveItem -Path $packageNoPkgFile -Item 'dbops.package.json'
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
        }
        It "should throw error when package data file does not exist" {
            {
                Remove-DBOBuild -Name $packageNoPkgFile -Build 2.0
            } | Should -Throw '*Incorrect package format*'
        }
        It "should throw error when package zip does not exist" {
            { Remove-DBOBuild -Name ".\nonexistingpackage.zip" -Build 2.0 -ErrorAction Stop } | Should -Throw
        }
        It "should output warning when build does not exist" {
            $null = Remove-DBOBuild -Name $packageNameTest -Build 3.0 -WarningVariable errorResult 3>$null
            $errorResult.Message -join ';' | Should -BeLike '*not found in the package*'
        }
    }
}
