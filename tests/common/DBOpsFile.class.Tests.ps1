Describe "DBOpsFile class tests" -Tag UnitTests {
    BeforeAll {
        . $PSScriptRoot\fixtures.ps1

        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        . "$PSScriptRoot\..\..\internal\classes\DBOpsHelper.class.ps1"
        . "$PSScriptRoot\..\..\internal\classes\DBOps.class.ps1"

        New-Workfolder -Force

        $script1, $script2, $script3 = Get-SourceScript -Version 1, 2, 3

        $fileObject1, $fileObject2, $fileObject3 = Get-SourceScript -Version 1, 2, 3 | Get-Item
    }
    AfterAll {
        Reset-Workfolder
    }
    Context "tests DBOpsFile object creation" {
        AfterAll {
            Reset-Workfolder
        }
        It "Should create new DBOpsFile object" {
            $f = [DBOpsFile]::new('1.sql')
            $f.PackagePath | Should -Be '1.sql'
            $f.Length | Should -Be 0
            $f.Name | Should -BeNullOrEmpty
            $f.LastWriteTime | Should -BeNullOrEmpty
            $f.ByteArray | Should -BeNullOrEmpty
            $f.Hash | Should -BeNullOrEmpty
            $f.Parent | Should -BeNullOrEmpty
        }
        It "Should create new DBOpsFile object from fileobject" {
            $f = [DBOpsFile]::new($fileObject1, '1.sql')
            $f | Should -Not -BeNullOrEmpty
            $f.PackagePath | Should -Be '1.sql'
            $f.Length | Should -BeGreaterThan 0
            $f.Name | Should -Be '1.sql'
            $f.LastWriteTime | Should -Not -BeNullOrEmpty
            $f.ByteArray | Should -Not -BeNullOrEmpty
            $f.Hash | Should -BeNullOrEmpty
            $f.Parent | Should -BeNullOrEmpty
            #Negative tests
            { [DBOpsFile]::new(([System.IO.FileInfo]$null), $script1, '1.sql') } | Should -Throw '*empty*'
            { [DBOpsFile]::new($fileObject1, '') } | Should -Throw 'Path inside the package cannot be empty'
        }
        It "Should create new hash-protected DBOpsFile" {
            $f = [DBOpsFile]::new($fileObject1, '1.sql', $true)
            $f | Should -Not -BeNullOrEmpty
            $f.PackagePath | Should -Be '1.sql'
            $f.Length | Should -BeGreaterThan 0
            $f.Name | Should -Be '1.sql'
            $f.LastWriteTime | Should -Not -BeNullOrEmpty
            $f.ByteArray | Should -Not -BeNullOrEmpty
            $f.Hash | Should -Not -BeNullOrEmpty
            $f.Protected | Should -Be $true
            $f.Parent | Should -BeNullOrEmpty
        }
        It "Should create new hash-protected DBOpsFile and validate hash" {
            $hash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash([DBOpsHelper]::GetBinaryFile($script1)))
            $f = [DBOpsFile]::new($fileObject1, '1.sql', $hash)
            $f | Should -Not -BeNullOrEmpty
            $f.PackagePath | Should -Be '1.sql'
            $f.Length | Should -BeGreaterThan 0
            $f.Name | Should -Be '1.sql'
            $f.LastWriteTime | Should -Not -BeNullOrEmpty
            $f.ByteArray | Should -Not -BeNullOrEmpty
            $f.Hash | Should -Be $hash
            $f.Protected | Should -Be $true
            $f.Parent | Should -BeNullOrEmpty

            #Negative tests
            { [DBOpsFile]::new($fileObject1, '1.sql', '0xf00') } | Should -Throw 'File cannot be loaded, hash mismatch*'
            { [DBOpsFile]::new($fileObject1, '1.sql', '') } | Should -Throw 'File cannot be loaded, hash mismatch*'
            { [DBOpsFile]::new($fileObject1, '1.sql', 'foo') } | Should -Throw 'File cannot be loaded, hash mismatch*'
        }
        It "Should create new DBOpsFile object from zipfile using custom object" {
            $p = [DBOpsPackage]::new()
            $f1 = [DBOpsFile]::new($fileObject1, 'success\1.sql', $true)
            $p.NewBuild('1.0').AddScript($f1)
            $p.SaveToFile($packageName)
            #Open zip file stream
            $writeMode = [System.IO.FileMode]::Open
            try {
                $stream = [FileStream]::new($packageName, $writeMode)
                #Open zip file
                $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Read)
                try {
                    $zipEntry = $zip.Entries | Where-Object FullName -eq (Join-PSFPath -Normalize 'content\1.0\success\1.sql')
                    # testing unprotected files
                    $f = [DBOpsFile]::new($zipEntry, '1.sql')
                    $f | Should -Not -BeNullOrEmpty
                    $f.PackagePath | Should -Be '1.sql'
                    $f.Length | Should -BeGreaterThan 0
                    $f.Name | Should -Be '1.sql'
                    $f.LastWriteTime | Should -Not -BeNullOrEmpty
                    $f.ByteArray | Should -Not -BeNullOrEmpty
                    $f.Hash | Should -BeNullOrEmpty
                    $f.Parent | Should -BeNullOrEmpty
                    # testing protected files
                    $f = [DBOpsFile]::new($zipEntry, '1.sql', $f1.Hash)
                    $f | Should -Not -BeNullOrEmpty
                    $f.PackagePath | Should -Be '1.sql'
                    $f.Length | Should -BeGreaterThan 0
                    $f.Name | Should -Be '1.sql'
                    $f.LastWriteTime | Should -Not -BeNullOrEmpty
                    $f.ByteArray | Should -Not -BeNullOrEmpty
                    $f.Hash | Should -Be $f1.Hash
                    $f.Parent | Should -BeNullOrEmpty
                    # negative testing
                    { [DBOpsFile]::new($zipEntry, '1.sql', '0xf00') } | Should -Throw 'File cannot be loaded, hash mismatch*'
                    { [DBOpsFile]::new($zipEntry, '1.sql', '') } | Should -Throw 'File cannot be loaded, hash mismatch*'
                    { [DBOpsFile]::new($zipEntry, '1.sql', 'foo') } | Should -Throw 'File cannot be loaded, hash mismatch*'
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
        }
    }
    Context "tests other DBOpsFile methods" {
        BeforeEach {
            $pkg = [DBOpsPackage]::new()
            $pkg.Slim = $true
            $build = $pkg.NewBuild('1.0')
            $pkg.SaveToFile($packageName, $true)
            $file = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true)
            $cFile = [DBOpsFile]::new($fileObject1, 'whatever.sql')
            $build.AddFile($file, 'Scripts')
            $pkg.SetPreScripts($cfile)
            $pkg.Alter()
        }
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        It "should test ToString method" {
            $file.ToString() | Should -Be (Join-PSFPath -Normalize 'success\1.sql')
            $cfile.ToString() | Should -Be 'whatever.sql'
        }
        It "should test RebuildHash method" {
            $oldHash = $file.Hash
            $file.Hash = ''
            $file.RebuildHash()
            $file.Hash | Should -Be $oldHash
        }
        It "should test ValidateHash method" {
            $hash = $file.Hash
            { $file.ValidateHash('foo') } | Should -Throw 'File cannot be loaded, hash mismatch*'
            { $file.ValidateHash($hash) } | Should -Not -Throw
        }
        It "should test GetDeploymentPath method" {
            $file.GetDeploymentPath() | Should -Be '1.0\success\1.sql'
            $cFile.GetDeploymentPath() | Should -Be '.dbops.prescripts\whatever.sql'
        }
        It "should test GetPackagePath method" {
            $file.GetPackagePath() | Should -Be (Join-PSFPath -Normalize 'content\1.0\success\1.sql')
            $cFile.GetPackagePath() | Should -Be (Join-PSFPath -Normalize 'content\.dbops.prescripts\whatever.sql')
        }
        It "should test GetContent method" {
            $file.GetContent() | Should -BeLike 'CREATE TABLE a (a int)*'
            $cFile.GetContent() | Should -BeLike 'CREATE TABLE a (a int)*'
            #ToDo: add files with different encodings
        }
        It "should test SetContent method" {
            $oldData = $file.ByteArray
            $oldHash = $file.Hash
            $file.SetContent([DBOpsHelper]::GetBinaryFile($script2))
            $file.ByteArray | Should -Not -Be $oldData
            $file.ByteArray | Should -Not -BeNullOrEmpty
            $file.Hash | Should -Not -Be $oldHash
            $file.Hash | Should -Not -BeNullOrEmpty
        }
        It "should test ExportToJson method" {
            $j = $file.ExportToJson() | ConvertFrom-Json
            $j.PackagePath | Should -Be (Join-PSFPath -Normalize 'success\1.sql')
            $j.Hash | Should -Be ([DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash([DBOpsHelper]::GetBinaryFile($script1))))
        }
        It "should test Save method" {
            #Save old file parameters
            $oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq (Join-PSFPath -Normalize 'content\1.0\success\1.sql')
            $oldResults2 = Get-ArchiveItem $packageName | Where-Object Path -eq (Join-PSFPath -Normalize 'content\.dbops.prescripts\whatever.sql')
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
                    { $file.Save($zip) } | Should -Not -Throw
                    { $cFile.Save($zip) } | Should -Not -Throw
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
            $testResults = Get-ArchiveItem $packageName | Where-Object Path -eq (Join-PSFPath -Normalize 'content\1.0\success\1.sql')
            $oldResults.LastWriteTime -lt ($testResults | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should -Be $true
            $testResults = Get-ArchiveItem $packageName | Where-Object Path -eq (Join-PSFPath -Normalize 'content\.dbops.prescripts\whatever.sql')
            $oldResults2.LastWriteTime -lt ($testResults | Where-Object Path -eq $oldResults2.Path).LastWriteTime | Should -Be $true
            # { $p = [DBOpsPackage]::new($packageName) } | Should -Throw #Because of the hash mismatch - package file is not updated in Save()
        }
        It "should test Alter method" {
            #Save old file parameters
            $oldResults = Get-ArchiveItem $packageName | Where-Object Path -eq (Join-PSFPath -Normalize 'content\1.0\success\1.sql')
            $oldResults2 = Get-ArchiveItem $packageName | Where-Object Path -eq (Join-PSFPath -Normalize 'content\.dbops.prescripts\whatever.sql')
            #Sleep 2 seconds to ensure that modification date is changed
            Start-Sleep -Seconds 2
            #Modify file content
            $file.SetContent([DBOpsHelper]::GetBinaryFile($script2))
            { $file.Alter() } | Should -Not -Throw
            { $cFile.Alter() } | Should -Not -Throw
            $testResults = Get-ArchiveItem $packageName | Where-Object Path -eq (Join-PSFPath -Normalize 'content\1.0\success\1.sql')
            $oldResults.LastWriteTime -lt ($testResults | Where-Object Path -eq $oldResults.Path).LastWriteTime | Should -Be $true
            $testResults = Get-ArchiveItem $packageName | Where-Object Path -eq (Join-PSFPath -Normalize 'content\.dbops.prescripts\whatever.sql')
            $oldResults2.LastWriteTime -lt ($testResults | Where-Object Path -eq $oldResults2.Path).LastWriteTime | Should -Be $true
        }
    }
}