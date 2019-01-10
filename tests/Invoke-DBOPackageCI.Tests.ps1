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

$workFolder = Join-Path "$here\etc" "$commandName.Tests.dbops"

$scriptFolder = Join-PSFPath -Normalize "$here\etc\sqlserver-tests"
$v1scripts = Join-Path $scriptFolder 'success'
$v2scripts = Join-Path $scriptFolder 'transactional-failure'
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$packageNameTest = "$packageName.test.zip"
$packageNoPkgFile = Join-Path $workFolder "pkg_nopkgfile.zip"

Describe "Invoke-DBOPackageCI tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    Context "Creating a new CI package version 1.0" {
        It "should add new build to existing package" {
            $testResults = Invoke-DBOPackageCI -ScriptPath $v1scripts -Name $packageName
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.Version | Should Be '1.0.1'
            Test-Path $packageName | Should Be $true
        }
        $testResults = Get-ArchiveItem $packageName
        It "build 1.0.1 should only contain scripts from 1.0" {
            Join-PSFPath -Normalize 'content\1.0.1\success\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\3.sql' | Should BeIn $testResults.Path
        }
        It "should contain module files" {
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'Modules\dbops\bin\dbup-core.dll' | Should BeIn $testResults.Path
        }
        It "should contain config files" {
            Join-PSFPath -Normalize 'dbops.config.json' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'dbops.package.json' | Should BeIn $testResults.Path
        }
    }
    Context "Adding new CI build on top of existing package" {
        It "should add new build to existing package" {
            $testResults = Invoke-DBOPackageCI -ScriptPath $v2scripts -Name $packageName -Version 1.0
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.Version | Should Be '1.0.2'
            Test-Path $packageName | Should Be $true
        }
        $testResults = Get-ArchiveItem $packageName
        It "build 1.0.1 should only contain scripts from 1.0.1" {
            Join-PSFPath -Normalize 'content\1.0.1\success\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\3.sql' | Should BeIn $testResults.Path
        }
        It "build 1.0.2 should only contain scripts from 1.0.2" {
            Join-PSFPath -Normalize 'content\1.0.2\transactional-failure\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.2\transactional-failure\2.sql' | Should BeIn $testResults.Path
        }
        It "should contain module files" {
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'Modules\dbops\bin\dbup-core.dll' | Should BeIn $testResults.Path
        }
        It "should contain config files" {
            Join-PSFPath -Normalize 'dbops.config.json' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'dbops.package.json' | Should BeIn $testResults.Path
        }
    }
    Context "adding new files redefining the version to 2.0" {
        It "should add new build to existing package" {
            $testResults = Invoke-DBOPackageCI -ScriptPath $scriptFolder -Name $packageName -Version 2.0
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.Version | Should Be '2.0.1'
            Test-Path $packageName | Should Be $true
        }
        $testResults = Get-ArchiveItem $packageName
        It "build 1.0.1 should only contain scripts from 1.0.1" {
            Join-PSFPath -Normalize 'content\1.0.1\success\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.1\success\3.sql' | Should BeIn $testResults.Path
        }
        It "build 1.0.2 should only contain scripts from 1.0.2" {
            Join-PSFPath -Normalize 'content\1.0.2\transactional-failure\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0.2\transactional-failure\2.sql' | Should BeIn $testResults.Path
        }
        It "build 2.0.1 should only contain scripts from 2.0.1" {
            Join-PSFPath -Normalize 'content\2.0.1\sqlserver-tests\success\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0.1\sqlserver-tests\success\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0.1\sqlserver-tests\success\3.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0.1\sqlserver-tests\transactional-failure\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0.1\sqlserver-tests\transactional-failure\2.sql' | Should BeIn $testResults.Path
        }
        It "should contain module files" {
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'Modules\dbops\bin\dbup-core.dll' | Should BeIn $testResults.Path
        }
        It "should contain config files" {
            Join-PSFPath -Normalize 'dbops.config.json' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'dbops.package.json' | Should BeIn $testResults.Path
        }
    }
    Context "negative tests" {
        BeforeAll {
            $null = New-DBOPackage -Name $packageNoPkgFile -Build 1.0 -ScriptPath $scriptFolder
            $null = Remove-ArchiveItem -Path $packageNoPkgFile -Item 'dbops.package.json'
        }
        It "should show warning when there are no new files" {
            $testResults = Invoke-DBOPackageCI -ScriptPath $scriptFolder -Name $packageName -Version 2.0 -WarningVariable warningResult 3>$null
            $warningResult.Message -join ';' | Should BeLike '*No scripts have been selected, the original file is unchanged.*'
        }
        It "should throw error when package data file does not exist" {
            try {
                $null = Invoke-DBOPackageCI -ScriptPath $scriptFolder -Name $packageNoPkgFile -Version 2.0
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike '*Incorrect package format*'
        }
    }
}
