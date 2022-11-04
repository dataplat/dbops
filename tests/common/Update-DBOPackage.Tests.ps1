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



$workFolder = Join-PSFPath -Normalize "$here\etc" "$commandName.Tests.dbops"

$packageName = Join-Path $workFolder 'TempDeployment.zip'
$v1scripts = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\1.sql"
$v2scripts = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\2.sql"

Describe "Update-DBOPackage tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force -Slim
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    Context "Updating regular package" {
        It "updates prescripts" {
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.PreScripts.Scripts.FullName | Should -BeNullOrEmpty
            Update-DBOPackage -Path $packageName -PreScriptPath $v2scripts
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.PreScripts.Scripts.FullName | Should Be $script2
            $testResults.PreScripts.Scripts.PackagePath | Should Be (Get-Item $v2scripts).Name
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\.dbops.prescripts\2.sql' | Should BeIn $testResults.Path
        }
        It "updates postscripts" {
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.PostScripts.Scripts.FullName | Should -BeNullOrEmpty
            Update-DBOPackage -Path $packageName -PostScriptPath $v2scripts
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.PostScripts.Scripts.FullName | Should Be $script2
            $testResults.PostScripts.Scripts.PackagePath | Should Be (Get-Item $v2scripts).Name
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\.dbops.prescripts\2.sql' | Should BeIn $testResults.Path
        }
        # It "updates package version" {
        #     $testResults = Get-DBOPackage -Path $packageName
        #     $testResults.Version | Should Be "1.0"
        #     Update-DBOPackage -Path $packageName -Version "13.37"
        #     $testResults = Get-DBOPackage -Path $packageName
        #     $testResults.Version | Should Be "13.37"
        # }
        It "updates package slim parameter" {
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.Slim | Should Be $true
            Update-DBOPackage -Path $packageName -Slim $false
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.Slim | Should Be $false
        }
    }
    Context "Negative tests" {
        It "should throw when PreScript path does not exist" {
            { Update-DBOPackage -Path $packageName -PreScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' } | Should Throw 'The following path is not valid'
        }
        It "should throw when PostScript path does not exist" {
            { Update-DBOPackage -Path $packageName -PostScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' } | Should Throw 'The following path is not valid'
        }
        It "should throw when config item does not exist" {
            { Update-DBOPackage -Path $packageName -ConfigName NonexistingItem -Value '123' } | Should throw
        }
        # It "returns error when build version is null or empty" {
        #     { Update-DBOPackage -Name $packageName -Version $null } | Should Throw 'Version not specified'
        #     { Update-DBOPackage -Name $packageName -Version "" } | Should Throw 'Version not specified'
        # }
    }
}
