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

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$here\..\internal\classes\DBOpsHelper.class.ps1"
. "$here\..\internal\classes\DBOps.class.ps1"

$packageName = "$here\etc\$commandName.zip"
$script1 = "$here\etc\install-tests\success\1.sql"
$script2 = "$here\etc\install-tests\success\2.sql"
$script3 = "$here\etc\install-tests\success\3.sql"

Describe "DBOpsBuild class tests" -Tag $commandName, UnitTests, DBOpsBuild {
    Context "tests DBOpsBuild object creation" {
        It "Should create new DBOpsBuild object" {
            $b = [DBOpsBuild]::new('1.0')
            $b.Build | Should Be '1.0'
            $b.PackagePath | Should Be '1.0'
            ([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
        }
        It "Should create new DBOpsBuild object using custom object" {
            $obj = @{
                Build       = '2.0'
                PackagePath = '2.00'
                CreatedDate = (Get-Date).Date
            }
            $b = [DBOpsBuild]::new($obj)
            $b.Build | Should Be $obj.Build
            $b.PackagePath | Should Be $obj.PackagePath
            $b.CreatedDate | Should Be $obj.CreatedDate
        }
    }
    Context "tests DBOpsBuild file adding methods" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        BeforeAll {
        }
        BeforeEach {
            $pkg = [DBOpsPackage]::new()
            $pkg.SaveToFile($packageName, $true)
            $build = $pkg.NewBuild('1.0')
        }
        It "should test NewScript([psobject]) method" {
            $so = $build.NewScript(@{FullName = $script1; Depth = 1})
            #test build to contain the script
            '1.sql' | Should BeIn $build.Scripts.Name
            ($build.Scripts | Measure-Object).Count | Should Be 1
            #test the file returned to have all the necessary properties
            $so.SourcePath | Should Be $script1
            $so.PackagePath | Should Be 'success\1.sql'
            $so.Length -gt 0 | Should Be $true
            $so.Name | Should Be '1.sql'
            $so.LastWriteTime | Should Not BeNullOrEmpty
            $so.ByteArray | Should Not BeNullOrEmpty
            $so.Hash |Should Not BeNullOrEmpty
            $so.Parent.ToString() | Should Be '[Build: 1.0; Scripts: @{1.sql}]'
        }
        It "should test NewScript([string],[int]) method" {
            $so = $build.NewScript(@{FullName = $script1; Depth = 1})
            ($build.Scripts | Measure-Object).Count | Should Be 1
            $so.SourcePath | Should Be $script1
            $so.PackagePath | Should Be 'success\1.sql'
            $so.Length -gt 0 | Should Be $true
            $so.Name | Should Be '1.sql'
            $so.LastWriteTime | Should Not BeNullOrEmpty
            $so.ByteArray | Should Not BeNullOrEmpty
            $so.Hash |Should Not BeNullOrEmpty
            $so.Parent.ToString() | Should Be '[Build: 1.0; Scripts: @{1.sql}]'
            { $pkg.Alter() } | Should Not Throw
            #Negative tests
            { $build.NewScript($script1, 1) } | Should Throw
        }
        It "Should test AddScript([string]) method" {
            $f = [DBOpsFile]::new($script1, 'success\1.sql')
            $build.AddScript($f)
            #test build to contain the script
            '1.sql' | Should BeIn $build.Scripts.Name
            ($build.Scripts | Measure-Object).Count | Should Be 1
        }
        It "Should test AddScript([string],[bool]) method" {
            $f = [DBOpsFile]::new($script1, 'success\1.sql')
            $build.AddScript($f,$false)
            #test build to contain the script
            '1.sql' | Should BeIn $build.Scripts.Name
            ($build.Scripts | Measure-Object).Count | Should Be 1
            $f2 = [DBOpsFile]::new($script1, 'success\1a.sql')
            { $build.AddScript($f2, $false) } | Should Throw
            ($build.Scripts | Measure-Object).Count | Should Be 1
            $f3 = [DBOpsFile]::new($script1, 'success\1a.sql')
            $build.AddScript($f3, $true)
            ($build.Scripts | Measure-Object).Count | Should Be 2
        }
    }
    Context "tests other methods" {
        BeforeEach {
            $pkg = [DBOpsPackage]::new()
            $pkg.SaveToFile($packageName, $true)
            $build = $pkg.NewBuild('1.0')
            $f = [DBOpsScriptFile]::new($script1, 'success\1.sql')
            $build.AddScript($f)
        }
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        It "should test ToString method" {
            $build.ToString() | Should Be '[Build: 1.0; Scripts: @{1.sql}]'
        }
        It "should test HashExists method" {
            $f = [DBOpsScriptFile]::new(@{PackagePath = '1.sql'; SourcePath = '.\1.sql'; Hash = 'MyHash'})
            $build.AddScript($f, $true)
            $build.HashExists('MyHash') | Should Be $true
            $build.HashExists('MyHash2') | Should Be $false
            $build.HashExists('MyHash','.\1.sql') | Should Be $true
            $build.HashExists('MyHash','.\1a.sql') | Should Be $false
            $build.HashExists('MyHash2','.\1.sql') | Should Be $false
        }
        It "should test ScriptExists method" {
            $build.ScriptExists($script1) | Should Be $true
            $build.ScriptExists("$here\etc\install-tests\transactional-failure\1.sql") | Should Be $false
            { $build.ScriptExists("Nonexisting\path") } | Should Throw
        }
        It "should test ScriptModified method" {
            $build.ScriptModified($script1, $script1) | Should Be $false
            $build.ScriptModified($script2, $script1) | Should Be $true
            $build.ScriptModified($script2, $script2) | Should Be $false
        }
        It "should test SourcePathExists method" {
            $build.SourcePathExists($script1) | Should Be $true
            $build.SourcePathExists($script2) | Should Be $false
            $build.SourcePathExists('') | Should Be $false
        }
        It "should test PackagePathExists method" {
            $s1 = "success\1.sql"
            $s2 = "success\2.sql"
            $build.PackagePathExists($s1) | Should Be $true
            $build.PackagePathExists($s2) | Should Be $false
            #Overloads
            $build.PackagePathExists("a\$s1", 1) | Should Be $true
            $build.PackagePathExists("a\$s2", 1) | Should Be $false
        }
        It "should test GetPackagePath method" {
            $build.GetPackagePath() | Should Be 'content\1.0'
        }
        It "should test ExportToJson method" {
            $j = $build.ExportToJson() | ConvertFrom-Json
            $j.Scripts | Should Not BeNullOrEmpty
            $j.Build | Should Be '1.0'
            $j.PackagePath | Should Be '1.0'
            $j.CreatedDate | Should Not BeNullOrEmpty
        }
    }
    Context "tests Save/Alter methods" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
            if (Test-Path "$packageName.test.zip") { Remove-Item "$packageName.test.zip" }
        }
        BeforeAll {

        }
        It "should test Save method" {
            #Generate new package file
            $pkg = [DBOpsPackage]::new()
            $pkg.SaveToFile($packageName, $true)
            $build = $pkg.NewBuild('1.0')
            $f = [DBOpsScriptFile]::new($script1, 'success\1.sql')
            $build.AddScript($f)
            $f = [DBOpsScriptFile]::new($script2, 'success\2.sql')
            $build.AddScript($f)
            #Open zip file stream
            $writeMode = [System.IO.FileMode]::Open
            $stream = [FileStream]::new($packageName, $writeMode)
            try {
                #Open zip file
                $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
                try {
                    #Initiate saving
                    { $build.Save($zip) } | Should Not Throw
                }
                catch {
                    throw $_
                }
                finally {
                    #Close archive
                    $zip.Dispose()
                }
            }
            catch {
                throw $_
            }
            finally {
                #Close archive
                $stream.Dispose()
            }
            $results = Get-ArchiveItem $packageName
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-Path 'Modules\dbops' $file.Path | Should BeIn $results.Path
            }
            'dbops.config.json' | Should BeIn $results.Path
            'dbops.package.json' | Should BeIn $results.Path
            'Deploy.ps1' | Should BeIn $results.Path
            'content\1.0\success\1.sql' | Should BeIn $results.Path
            'content\1.0\success\2.sql' | Should BeIn $results.Path
        }
        It "Should load package successfully after saving it" {
            $p = [DBOpsPackage]::new($packageName)
            $p.Builds.Scripts.Name | Should Not Be @('1.sql','2.sql') #Build.Save method does not write to package file
        }
        It "Should save and reopen the package under a different name" {
            #Generate new package file
            $pkg = [DBOpsPackage]::new()
            $pkg.SaveToFile($packageName, $true)
            $b = $pkg.NewBuild('1.0')
            $f = [DBOpsScriptFile]::new($script1, 'success\1.sql')
            $b.AddScript($f)
            $f = [DBOpsScriptFile]::new($script2, 'success\2.sql')
            $b.AddScript($f)
            $pkg.SaveToFile("$packageName.test.zip")
            $pkg = [DBOpsPackage]::new("$packageName.test.zip")
            $pkg.GetBuild('1.0').Scripts.Name | Should Be @('1.sql','2.sql')
        }
        $oldResults = Get-ArchiveItem "$packageName.test.zip"
        #Sleep 1 second to ensure that modification date is changed
        Start-Sleep -Seconds 2
        It "should test Alter method" {
            $pkg = [DBOpsPackage]::new("$packageName.test.zip")
            $build = $pkg.GetBuild('1.0')
            $f = [DBOpsScriptFile]::new($script3, 'success\3.sql')
            $build.AddScript($f)
            { $build.Alter() } | Should Not Throw
            $results = Get-ArchiveItem "$packageName.test.zip"
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-Path 'Modules\dbops' $file.Path | Should BeIn $results.Path
            }
            'dbops.config.json' | Should BeIn $results.Path
            'dbops.package.json' | Should BeIn $results.Path
            'Deploy.ps1' | Should BeIn $results.Path
            'content\1.0\success\1.sql' | Should BeIn $results.Path
            'content\1.0\success\2.sql' | Should BeIn $results.Path
        }
        It "Should load package successfully after saving it" {
            $p = [DBOpsPackage]::new("$packageName.test.zip")
            $p.Builds.Scripts.Name | Should Be @('1.sql', '2.sql', '3.sql')
        }
        # Testing file contents to be updated by the Save method
        $results = Get-ArchiveItem "$packageName.test.zip"
        $saveTestsErrors = 0
        #should trigger file updates for build files and module files
        foreach ($result in ($oldResults | Where-Object { $_.Path -like 'content\1.0\success\*' -or $_.Path -like 'Modules\dbops\*'  } )) {
            if ($result.LastWriteTime -ge ($results | Where-Object Path -eq $result.Path).LastWriteTime) {
                It "Should have updated Modified date for file $($result.Path)" {
                    $result.LastWriteTime -lt ($results | Where-Object Path -eq $result.Path).LastWriteTime | Should Be $true
                }
                $saveTestsErrors++
            }
        }
        if ($saveTestsErrors -eq 0) {
            It "Ran silently $($oldResults.Length) file modification tests" {
                $saveTestsErrors | Should be 0
            }
        }
    }
}