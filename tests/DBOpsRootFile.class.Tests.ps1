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

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$here\..\internal\classes\DBOpsHelper.class.ps1"
. "$here\..\internal\classes\DBOps.class.ps1"

$packageName = Join-PSFPath -Normalize "$here\etc\$commandName.zip"
$script1 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\1.sql"
$script2 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\2.sql"
$script3 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\3.sql"

Describe "DBOpsRootFile class tests" -Tag $commandName, UnitTests, DBOpsFile, DBOpsRootFile {
    AfterAll {
        if (Test-Path $packageName) { Remove-Item $packageName }
    }
    Context "tests DBOpsFile object creation" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        It "Should create new DBOpsRootFile object" {
            $f = [DBOpsRootFile]::new()
            # $f | Should Not BeNullOrEmpty
            $f.SourcePath | Should BeNullOrEmpty
            $f.PackagePath | Should BeNullOrEmpty
            $f.Length | Should Be 0
            $f.Name | Should BeNullOrEmpty
            $f.LastWriteTime | Should BeNullOrEmpty
            $f.ByteArray | Should BeNullOrEmpty
            $f.Hash | Should BeNullOrEmpty
            $f.Parent | Should BeNullOrEmpty
        }
        It "Should create new DBOpsRootFile object from path" {
            $f = [DBOpsRootFile]::new($script1, '1.sql')
            $f | Should Not BeNullOrEmpty
            $f.SourcePath | Should Be $script1
            $f.PackagePath | Should Be '1.sql'
            $f.Length -gt 0 | Should Be $true
            $f.Name | Should Be '1.sql'
            $f.LastWriteTime | Should Not BeNullOrEmpty
            $f.ByteArray | Should Not BeNullOrEmpty
            $f.Hash | Should BeNullOrEmpty
            $f.Parent | Should BeNullOrEmpty
            #Negative tests
            { [DBOpsRootFile]::new((Join-PSFPath -Normalize 'Nonexisting\path'), '1.sql') } | Should Throw
            { [DBOpsRootFile]::new($script1, '') } | Should Throw
            { [DBOpsRootFile]::new('', '1.sql') } | Should Throw
        }
        It "Should create new DBOpsRootFile object using custom object" {
            $obj = @{
                SourcePath  = $script1
                PackagePath = '1.sql'
                Hash        = 'MyHash'
            }
            $f = [DBOpsRootFile]::new($obj)
            $f | Should Not BeNullOrEmpty
            $f.SourcePath | Should Be $script1
            $f.PackagePath | Should Be '1.sql'
            $f.Length | Should Be 0
            $f.Name | Should BeNullOrEmpty
            $f.LastWriteTime | Should BeNullOrEmpty
            $f.ByteArray | Should BeNullOrEmpty
            $f.Hash | Should BeNullOrEmpty
            $f.Parent | Should BeNullOrEmpty

            #Negative tests
            $obj = @{ foo = 'bar'}
            { [DBOpsFile]::new($obj) } | Should Throw
        }
        It "Should create new DBOpsRootFile object from zipfile using custom object" {
            $p = [DBOpsPackage]::new()
            $null = $p.NewBuild('1.0').NewScript($script1, 1)
            $p.SaveToFile($packageName)
            #Open zip file stream
            $writeMode = [System.IO.FileMode]::Open
            try {
                $stream = [FileStream]::new($packageName, $writeMode)
                #Open zip file
                $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Read)
                try {
                    $zipEntry = $zip.Entries | Where-Object FullName -eq (Join-PSFPath -Normalize 'content\1.0\success\1.sql')
                    $obj = @{
                        SourcePath  = $script1
                        PackagePath = '1.sql'
                        Hash        = 'MyHash'
                    }
                    $f = [DBOpsRootFile]::new($obj, $zipEntry)
                    $f | Should Not BeNullOrEmpty
                    $f.SourcePath | Should Be $script1
                    $f.PackagePath | Should Be '1.sql'
                    $f.Length -gt 0 | Should Be $true
                    $f.Name | Should Be '1.sql'
                    $f.LastWriteTime | Should Not BeNullOrEmpty
                    $f.ByteArray | Should Not BeNullOrEmpty
                    $f.Hash | Should BeNullOrEmpty
                    $f.Parent | Should BeNullOrEmpty
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

            #Negative tests
            $badobj = @{ foo = 'bar'}
            { [DBOpsRootFile]::new($badobj, $zip) } | Should Throw #object is incorrect
            { [DBOpsRootFile]::new($obj, $zip) } | Should Throw #zip stream has been disposed
        }
    }
    Context "tests overloaded DBOpsRootFile methods" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        BeforeEach {
            $pkg = [DBOpsPackage]::new()
            $pkg.SaveToFile($packageName, $true)
            $file = $pkg.GetFile('Deploy.ps1', 'DeployFile')
        }
        It "should test SetContent method" {
            $oldData = $file.ByteArray
            $file.SetContent([DBOpsHelper]::GetBinaryFile($script2))
            $file.ByteArray | Should Not Be $oldData
            $file.ByteArray | Should Not BeNullOrEmpty
            $file.Hash | Should BeNullOrEmpty
        }
        It "should test ExportToJson method" {
            $j = $file.ExportToJson() | ConvertFrom-Json
            $j.PackagePath | Should Be 'Deploy.ps1'
            $j.SourcePath | Should Be (Get-DBOModuleFileList | Where-Object {$_.Type -eq 'Misc' -and $_.Name -eq 'Deploy.ps1'}).FullName
        }
        It "should test Save method" {
            #Save old file parameters
            $oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'Deploy.ps1'
            #Sleep 2 seconds to ensure that modification date is changed
            Start-Sleep -Seconds 2
            #Modify file content
            $file.SetContent([DBOpsHelper]::GetBinaryFile($script2))
            #Open zip file stream
            $writeMode = [System.IO.FileMode]::Open
            $stream = [FileStream]::new($packageName, $writeMode)
            try {
                #Open zip file
                $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
                try {
                    #Initiate saving
                    { $file.Save($zip) } | Should Not Throw
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
            $testResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'Deploy.ps1'
            $oldResults.LastWriteTime -lt ($testResults | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should Be $true
        }
        It "should test Alter method" {
            #Save old file parameters
            $oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'Deploy.ps1'
            #Sleep 2 seconds to ensure that modification date is changed
            Start-Sleep -Seconds 2
            #Modify file content
            $file.SetContent([DBOpsHelper]::GetBinaryFile($script2))
            { $file.Alter() } | Should Not Throw
            $testResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'Deploy.ps1'
            $oldResults.LastWriteTime -lt ($testResults | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should Be $true
        }
    }
}