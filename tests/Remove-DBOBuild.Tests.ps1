Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    Import-Module "$here\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

$workFolder = Join-PSFPath -Normalize "$here\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-Path $workFolder 'unpacked'

$scriptFolder = Join-PSFPath -Normalize "$here\etc\install-tests\success"
$v1scripts = Join-Path $scriptFolder "1.sql"
$v2scripts = Join-Path $scriptFolder "2.sql"
$packageName = Join-Path $workFolder "TempDeployment.zip"
$packageNameTest = "$packageName.test.zip"
$packageNoPkgFile = Join-Path $workFolder "pkg_nopkgfile.zip"

Describe "Remove-DBOBuild tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force
        $null = Add-DBOBuild -ScriptPath $v2scripts -Path $packageName -Build 2.0
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    Context "removing version 1.0 from existing package" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
        }
        It "should remove build from existing package" {
            { Remove-DBOBuild -Name $packageNameTest -Build 1.0 } | Should Not Throw
            Test-Path $packageNameTest | Should Be $true
        }
        $testResults = Get-ArchiveItem $packageNameTest
        It "build 1.0 should not exist" {
            Join-PSFPath -Normalize 'content\1.0' | Should Not BeIn $testResults.Path
        }
        It "build 2.0 should contain scripts from 2.0" {
            Join-PSFPath -Normalize 'content\2.0\2.sql' | Should BeIn $testResults.Path
        }
        It "should contain module files" {
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $testResults.Path
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
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
            { Remove-DBOBuild -Name $packageNameTest -Build 2.0 } | Should Not Throw
            Test-Path $packageNameTest | Should Be $true
        }
        $testResults = Get-ArchiveItem $packageNameTest
        It "build 1.0 should contain scripts from 1.0" {
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $testResults.Path
        }
        It "build 2.0 should not exist" {
            Join-PSFPath -Normalize 'content\2.0' | Should Not BeIn $testResults.Path
        }
        It "should contain module files" {
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $testResults.Path
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
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
            { Remove-DBOBuild -Name $packageNameTest -Build "1.0", "2.0"  } | Should Not Throw
            Test-Path $packageNameTest | Should Be $true
        }
        $testResults = Get-ArchiveItem $packageNameTest
        It "build 1.0 should not exist" {
            Join-PSFPath -Normalize 'content\1.0' | Should Not BeIn $testResults.Path
        }
        It "build 2.0 should not exist" {
            Join-PSFPath -Normalize 'content\2.0' | Should Not BeIn $testResults.Path
        }
        It "should contain module files" {
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $testResults.Path
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
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
            { $packageNameTest | Remove-DBOBuild -Build '2.0' } | Should Not Throw
            Test-Path $packageNameTest | Should Be $true
        }
        $testResults = Get-ArchiveItem $packageNameTest
        It "build 1.0 should contain scripts from 1.0" {
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $testResults.Path
        }
        It "build 2.0 should not exist" {
            Join-PSFPath -Normalize 'content\2.0' | Should Not BeIn $testResults.Path
        }
        It "should contain module files" {
            Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $testResults.Path
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
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
            try {
                $null = Remove-DBOBuild -Name $packageNoPkgFile -Build 2.0
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike '*Incorrect package format*'
        }
        It "should throw error when package zip does not exist" {
            { Remove-DBOBuild -Name ".\nonexistingpackage.zip" -Build 2.0 -ErrorAction Stop } | Should Throw
        }
        It "should output warning when build does not exist" {
            $null = Remove-DBOBuild -Name $packageNameTest -Build 3.0 -WarningVariable errorResult 3>$null
            $errorResult.Message -join ';' | Should BeLike '*not found in the package*'
        }
    }
}
