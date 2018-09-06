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

Describe "DBOpsFile class tests" -Tag $commandName, UnitTests, DBOpsFile {
    AfterAll {
        if (Test-Path $packageName) { Remove-Item $packageName }
    }
    Context "tests DBOpsFile object creation" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        It "Should create new DBOpsFile object" {
            $f = [DBOpsFile]::new()
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
        It "Should create new DBOpsFile object from path" {
            $f = [DBOpsFile]::new($script1, '1.sql')
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
            { [DBOpsFile]::new('Nonexisting\path', '1.sql') } | Should Throw
            { [DBOpsFile]::new($script1, '') } | Should Throw
            { [DBOpsFile]::new('', '1.sql') } | Should Throw
        }
        It "Should create new DBOpsFile object using custom object" {
            $obj = @{
                SourcePath  = $script1
                packagePath = '1.sql'
                Hash        = 'MyHash'
            }
            $f = [DBOpsFile]::new($obj)
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
        It "Should create new DBOpsFile object from zipfile using custom object" {
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
                    $zipEntry = $zip.Entries | Where-Object FullName -eq 'content\1.0\success\1.sql'
                    $obj = @{
                        SourcePath  = $script1
                        packagePath = '1.sql'
                        Hash        = 'MyHash'
                    }
                    # { [DBOpsFile]::new($obj, $zipEntry) } | Should Throw #hash is invalid
                    # $obj.Hash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([DBOpsHelper]::GetBinaryFile($script1)))
                    $f = [DBOpsFile]::new($obj, $zipEntry)
                    $f | Should Not BeNullOrEmpty
                    $f.SourcePath | Should Be $script1
                    $f.PackagePath | Should Be '1.sql'
                    $f.Length -gt 0 | Should Be $true
                    $f.Name | Should Be '1.sql'
                    $f.LastWriteTime | Should Not BeNullOrEmpty
                    $f.ByteArray | Should Not BeNullOrEmpty
                    # $f.Hash | Should Be $obj.Hash
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
            { [DBOpsFile]::new($badobj, $zip) } | Should Throw #object is incorrect
            { [DBOpsFile]::new($obj, $zip) } | Should Throw #zip stream has been disposed
        }
    }
    Context "tests other DBOpsFile methods" {
        BeforeEach {
            $pkg = [DBOpsPackage]::new()
            $build = $pkg.NewBuild('1.0')
            $pkg.SaveToFile($packageName, $true)
            $file = $build.NewFile($script1, 'success\1.sql', 'Scripts')
            $build.Alter()
        }
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        It "should test ToString method" {
            $file.ToString() | Should Be 'success\1.sql'
        }
        It "should test GetContent method" {
            $file.GetContent() | Should BeLike 'CREATE TABLE a (a int)*'
            #ToDo: add files with different encodings
        }
        It "should test SetContent method" {
            $oldData = $file.ByteArray
            $file.SetContent([DBOpsHelper]::GetBinaryFile($script2))
            $file.ByteArray | Should Not Be $oldData
            $file.ByteArray | Should Not BeNullOrEmpty
        }
        It "should test ExportToJson method" {
            $j = $file.ExportToJson() | ConvertFrom-Json
            $j.PackagePath | Should Be 'success\1.sql'
            # $j.Hash | Should Be ([DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create( "MD5" ).ComputeHash([DBOpsHelper]::GetBinaryFile($script1))))
            $j.SourcePath | Should Be $script1
        }
        It "should test Save method" {
            #Save old file parameters
            $oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
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
            $results = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
            $oldResults.LastWriteTime -lt ($results | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should Be $true
            # { $p = [DBOpsPackage]::new($packageName) } | Should Throw #Because of the hash mismatch - package file is not updated in Save()
        }
        It "should test Alter method" {
            #Save old file parameters
            $oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
            #Sleep 2 seconds to ensure that modification date is changed
            Start-Sleep -Seconds 2
            #Modify file content
            $file.SetContent([DBOpsHelper]::GetBinaryFile($script2))
            { $file.Alter() } | Should Not Throw
            $results = Get-ArchiveItem $packageName | Where-Object Path -eq 'content\1.0\success\1.sql'
            $oldResults.LastWriteTime -lt ($results | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should Be $true
        }
    }
}