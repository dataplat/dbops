Describe "Add-DBOBuild tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Unpacked -Force

        $packageNameTest = "$packageName.test.zip"
        $packageNoPkgFile = Join-Path $workFolder "pkg_nopkgfile.zip"

        $null = New-DBOPackage -ScriptPath (Get-SourceScript -Version 1) -Name $packageName -Build 1.0 -Force
    }
    AfterAll {
        Remove-Workfolder
    }
    Context "adding version 2.0 to existing package" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
        }
        It "should add new build to existing package" {
            $testResults = Add-DBOBuild -ScriptPath (Get-SourceScript -Version 2) -Name $packageNameTest -Build 2.0
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should -Be $true

            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0\2.sql' | Should -Not -BeIn $testResults.Path

            Join-PSFPath -Normalize 'content\2.0\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0\1.sql' | Should -Not -BeIn $testResults.Path

            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }
            'dbops.config.json' | Should -BeIn $testResults.Path
            'dbops.package.json' | Should -BeIn $testResults.Path
        }
    }
    Context "adding new files only based on source path (Type = New)" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
        }
        It "should add new build to existing package" {
            $testResults = Add-DBOBuild -ScriptPath $scriptFolder\* -Name $packageNameTest -Build 2.0 -Type 'New'
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageNameTest -Leaf)
            $testResults.Configuration | Should -Not -Be $null
            $testResults.Version | Should -Be '2.0'
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            $testResults.Builds | Where-Object Build -eq '1.0' | Should -Not -Be $null
            $testResults.Builds | Where-Object Build -eq '2.0' | Should -Not -Be $null
            $testResults.FullName | Should -Be $packageNameTest
            $testResults.Length -gt 0 | Should -Be $true
            Test-Path $packageNameTest | Should -Be $true

            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0\2.sql' | Should -Not -BeIn $testResults.Path

            Join-PSFPath -Normalize "content\2.0\2.sql" | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize "content\2.0\1.sql" | Should -Not -BeIn $testResults.Path

            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }

            'dbops.config.json' | Should -BeIn $testResults.Path
            'dbops.package.json' | Should -BeIn $testResults.Path
        }
    }
    Context "adding new files only based on hash (Type = Unique/Modified)" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
            $null = Copy-Item (Get-SourceScript -Version 1) "$workFolder\Test.sql"
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
            $null = Remove-Item "$workFolder\Test.sql"
        }
        It "should add new build to existing package" {
            $testResults = Add-DBOBuild -ScriptPath $scriptFolder\*, "$workFolder\Test.sql" -Name $packageNameTest -Build 2.0 -Type 'Unique'
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageNameTest -Leaf)
            $testResults.Configuration | Should -Not -Be $null
            $testResults.Version | Should -Be '2.0'
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            '1.0' | Should -BeIn $testResults.Builds.Build
            '2.0' | Should -BeIn $testResults.Builds.Build
            $testResults.FullName | Should -Be $packageNameTest
            $testResults.Length -gt 0 | Should -Be $true
            Test-Path $packageNameTest | Should -Be $true
        }
        It "should add new build to existing package based on changes in the file" {
            $null = Add-DBOBuild -ScriptPath "$workFolder\Test.sql" -Name $packageNameTest -Build 2.1
            "nope" | Out-File "$workFolder\Test.sql" -Append
            $testResults = Add-DBOBuild -ScriptPath $scriptFolder\*, "$workFolder\Test.sql" -Name $packageNameTest -Build 3.0 -Type 'Modified'
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageNameTest -Leaf)
            $testResults.Configuration | Should -Not -Be $null
            $testResults.Version | Should -Be '3.0'
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            '1.0' | Should -BeIn $testResults.Builds.Build
            '2.0' | Should -BeIn $testResults.Builds.Build
            '2.1' | Should -BeIn $testResults.Builds.Build
            '3.0' | Should -BeIn $testResults.Builds.Build
            $testResults.FullName | Should -Be $packageNameTest
            $testResults.Length -gt 0 | Should -Be $true
            Test-Path $packageNameTest | Should -Be $true

            $testResults = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0\2.sql' | Should -Not -BeIn $testResults.Path

            Join-PSFPath -Normalize "content\2.0\2.sql" | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize "content\2.0\1.sql" | Should -Not -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0\Test.sql' | Should -Not -BeIn $testResults.Path

            Join-PSFPath -Normalize 'content\3.0\Test.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize "content\3.0\2.sql" | Should -Not -BeIn $testResults.Path
            Join-PSFPath -Normalize "content\3.0\1.sql" | Should -Not -BeIn $testResults.Path

            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }

            'dbops.config.json' | Should -BeIn $testResults.Path
            'dbops.package.json' | Should -BeIn $testResults.Path
        }
    }
    Context "adding files with different root folders" {
        BeforeAll {
            Push-Location -Path $here
        }
        AfterAll {
            Pop-Location
        }
        BeforeEach {
            $null = Copy-Item $packageName $packageNameTest
            #$null = Copy-Item (Get-SourceScript -Version 1) "$workFolder\Test.sql"
        }
        AfterEach {
            $null = Remove-Item $packageNameTest
            #$null = Remove-Item "$workFolder\Test.sql"
        }
        It "should add new build to existing package as a relative path" {
            $testResults = Add-DBOBuild -ScriptPath (Get-SourceScript -Version 2) -Name $packageNameTest -Build 2.0 -Relative
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should -Be $true
            $scripts = $testResults.GetBuild('2.0').Scripts
            Join-PSFPath -Normalize 'content\2.0' ((Resolve-Path (Get-SourceScript -Version 2) -Relative) -replace '^\.\\|^\.\/', '') | Should -BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\1.sql' | Should -Not -BeIn $scripts.GetPackagePath()
            $items = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0' ((Resolve-Path (Get-SourceScript -Version 2) -Relative) -replace '^\.\\|^\.\/', '') | Should -BeIn $items.Path
        }
        It "should add new build to existing package as an absolute path" {
            $testResults = Add-DBOBuild -ScriptPath (Get-SourceScript -Version 2) -Name $packageNameTest -Build 2.0 -Absolute
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should -Be $true
            $scripts = $testResults.GetBuild('2.0').Scripts
            Join-PSFPath -Normalize 'content\2.0' ((Get-SourceScript -Version 2) -replace ':', '') | Should -BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\1.sql' | Should -Not -BeIn $scripts.GetPackagePath()
            $items = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0' ((Get-SourceScript -Version 2) -replace ':', '') | Should -BeIn $items.Path
        }
        It "should add new build without recursion" {
            $testResults = Add-DBOBuild -ScriptPath $etcScriptFolder -Name $packageNameTest -Build 2.0 -NoRecurse
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should -Be $true
            $scripts = $testResults.GetBuild('2.0').Scripts
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\Cleanup.sql' | Should -BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\1.sql' | Should -Not -BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\2.sql' | Should -Not -BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\3.sql' | Should -Not -BeIn $scripts.GetPackagePath()
            $items = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\Cleanup.sql' | Should -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\1.sql' | Should -Not -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\2.sql' | Should -Not -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\3.sql' | Should -Not -BeIn $items.Path
        }
        It "Should add only matched files" {
            $testResults = Add-DBOBuild -ScriptPath $scriptFolder\* -Name $packageNameTest -Build 2.0 -Match '2\.sql'
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should -Be $true
            $scripts = $testResults.GetBuild('2.0').Scripts
            Join-PSFPath -Normalize 'content\2.0\1.sql' | Should -Not -BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\2.sql' | Should -BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\3.sql' | Should -Not -BeIn $scripts.GetPackagePath()
            $items = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\1.sql' | Should -Not -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\2.sql' | Should -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\3.sql' | Should -Not -BeIn $items.Path
        }
        It "Should add only matched files from a recursive folder" {
            $testResults = Add-DBOBuild -ScriptPath $etcScriptFolder\* -Name $packageNameTest -Build 2.0 -Match '2\.sql'
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should -Be $true
            $scripts = $testResults.GetBuild('2.0').Scripts
            $scripts | Should -Not -BeNullOrEmpty
            Join-PSFPath -Normalize 'content\2.0\success\1.sql' | Should -Not -BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\success\2.sql' | Should -BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\success\3.sql' | Should -Not -BeIn $scripts.GetPackagePath()
            $items = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\success\1.sql' | Should -Not -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\success\2.sql' | Should -BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\success\3.sql' | Should -Not -BeIn $items.Path
        }
    }
    Context "negative tests" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
            $null = New-DBOPackage -Name $packageNoPkgFile -Build 1.0 -ScriptPath $scriptFolder
            $null = Remove-ArchiveItem -Path $packageNoPkgFile -Item 'dbops.package.json'
        }
        AfterAll {
            Remove-Item $packageNameTest
            Remove-Item $packageNoPkgFile
        }
        It "should show warning when there are no new files" {
            $null = Add-DBOBuild -Name $packageNameTest -ScriptPath (Get-SourceScript -Version 1) -Type 'Unique' -WarningVariable warningResult 3>$null
            $warningResult.Message -join ';' | Should -BeLike '*No scripts have been selected, the original file is unchanged.*'
        }
        It "should throw error when package data file does not exist" {
            {
                $null = Add-DBOBuild -Name $packageNoPkgFile -ScriptPath (Get-SourceScript -Version 2)
            } | Should -Throw '*Incorrect package format*'
        }
        It "should throw error when package zip does not exist" {
            {
                Add-DBOBuild -Name ".\nonexistingpackage.zip" -ScriptPath (Get-SourceScript -Version 1) -ErrorAction Stop
            } | Should -Throw
        }
        It "should throw error when path cannot be resolved" {
            {
                $null = Add-DBOBuild -Name $packageNameTest -ScriptPath ".\nonexistingsourcefiles.sql"
            } | Should -Throw '*The following path is not valid*'
        }
        It "should throw error when scripts with the same relative path is being added" {
            {
                $null = Add-DBOBuild -Name $packageNameTest -ScriptPath "$scriptFolder\*", "$scriptFolder\..\transactional-failure\*"
            } | Should -Throw 'File * already exists*'
        }
    }
}
