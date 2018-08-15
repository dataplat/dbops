Param (
	[switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
	# Is not a part of the global batch => import module
	#Explicitly import the module for testing
	Import-Module "$here\..\dbops.psd1" -Force
}
else {
	# Is a part of a batch, output some eye-catching happiness
	Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

$workFolder = Join-Path "$here\etc" "$commandName.Tests.dbops"

$scriptFolder = "$here\etc\install-tests"
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
            $results = Invoke-DBOPackageCI -ScriptPath $v1scripts -Name $packageName
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
			$results.Version | Should Be '1.0.1'
            Test-Path $packageName | Should Be $true
        }
        $results = Get-ArchiveItem $packageName
        It "build 1.0.1 should only contain scripts from 1.0" {
            'content\1.0.1\success\1.sql' | Should BeIn $results.Path
			'content\1.0.1\success\2.sql' | Should BeIn $results.Path
			'content\1.0.1\success\3.sql' | Should BeIn $results.Path
        }
        It "should contain module files" {
            'Modules\dbops\dbops.psd1' | Should BeIn $results.Path
            'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $results.Path
            'Modules\dbops\bin\dbup-core.dll' | Should BeIn $results.Path
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $results.Path
            'dbops.package.json' | Should BeIn $results.Path
        }
    }
	Context "Adding new CI build on top of existing package" {
        It "should add new build to existing package" {
            $results = Invoke-DBOPackageCI -ScriptPath $v2scripts -Name $packageName -Version 1.0
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
            $results.Version | Should Be '1.0.2'
            Test-Path $packageName | Should Be $true
        }
        $results = Get-ArchiveItem $packageName
		It "build 1.0.1 should only contain scripts from 1.0.1" {
            'content\1.0.1\success\1.sql' | Should BeIn $results.Path
			'content\1.0.1\success\2.sql' | Should BeIn $results.Path
			'content\1.0.1\success\3.sql' | Should BeIn $results.Path
		}
		It "build 1.0.2 should only contain scripts from 1.0.2" {
            'content\1.0.2\transactional-failure\1.sql' | Should BeIn $results.Path
            'content\1.0.2\transactional-failure\2.sql' | Should BeIn $results.Path
		}
		It "should contain module files" {
			'Modules\dbops\dbops.psd1' | Should BeIn $results.Path
			'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $results.Path
            'Modules\dbops\bin\dbup-core.dll' | Should BeIn $results.Path
		}
		It "should contain config files" {
			'dbops.config.json' | Should BeIn $results.Path
			'dbops.package.json' | Should BeIn $results.Path
		}
	}
	Context "adding new files redefining the version to 2.0" {
        It "should add new build to existing package" {
            $results = Invoke-DBOPackageCI -ScriptPath $scriptFolder -Name $packageName -Version 2.0
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
            $results.Version | Should Be '2.0.1'
            Test-Path $packageName | Should Be $true
        }
        $results = Get-ArchiveItem $packageName
        It "build 1.0.1 should only contain scripts from 1.0.1" {
            'content\1.0.1\success\1.sql' | Should BeIn $results.Path
            'content\1.0.1\success\2.sql' | Should BeIn $results.Path
            'content\1.0.1\success\3.sql' | Should BeIn $results.Path
        }
        It "build 1.0.2 should only contain scripts from 1.0.2" {
            'content\1.0.2\transactional-failure\1.sql' | Should BeIn $results.Path
            'content\1.0.2\transactional-failure\2.sql' | Should BeIn $results.Path
        }
        It "build 2.0.1 should only contain scripts from 2.0.1" {
            'content\2.0.1\install-tests\success\1.sql' | Should BeIn $results.Path
            'content\2.0.1\install-tests\success\2.sql' | Should BeIn $results.Path
            'content\2.0.1\install-tests\success\3.sql' | Should BeIn $results.Path
            'content\2.0.1\install-tests\transactional-failure\1.sql' | Should BeIn $results.Path
            'content\2.0.1\install-tests\transactional-failure\2.sql' | Should BeIn $results.Path
        }
        It "should contain module files" {
            'Modules\dbops\dbops.psd1' | Should BeIn $results.Path
            'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $results.Path
            'Modules\dbops\bin\dbup-core.dll' | Should BeIn $results.Path
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $results.Path
            'dbops.package.json' | Should BeIn $results.Path
        }
	}
    Context "negative tests" {
        BeforeAll {
            $null = New-DBOPackage -Name $packageNoPkgFile -Build 1.0 -ScriptPath $scriptFolder
            $null = Remove-ArchiveItem -Path $packageNoPkgFile -Item 'dbops.package.json'
        }
        It "should show warning when there are no new files" {
            $results = Invoke-DBOPackageCI -ScriptPath $scriptFolder -Name $packageName -Version 2.0 -WarningVariable warningResult 3>$null
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
