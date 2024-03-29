BeforeDiscovery {
    $encodings = @(
        'ASCII'
        'Unicode'
        'BigEndianUnicode'
        'UTF32'
        'UTF7'
        'UTF8'
    )
    $encodedFiles = @(
        "1252.txt"
        "UTF8-BOM.txt"
        "UTF8-NoBOM.txt"
        "UTF16-BE.txt"
        "UTF16-LE.txt"
        "UTF16-NoBOM.txt"
    )
}

Describe "dbopsHelper class tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        . "$PSScriptRoot\..\..\internal\classes\DBOpsHelper.class.ps1"
        $script1, $script2 = Get-SourceScript -Version 1, 2

        New-Workfolder -Force

        $archiveName = Join-PSFPath -Normalize "$workfolder\dbopsHelper.zip"
        $sqlName = Join-PSFPath -Normalize "$workfolder\dbopsHelper.sql"
    }
    AfterAll {
        Remove-Workfolder
    }
    Context "tests SplitRelativePath method" {
        It "should validate positive tests" {
            [DBOpsHelper]::SplitRelativePath((Join-PSFPath -Normalize '3\2\1\file.txt'), 0) | Should -Be 'file.txt'
            [DBOpsHelper]::SplitRelativePath((Join-PSFPath -Normalize '3\2\1\file.txt'), 1) | Should -Be (Join-PSFPath -Normalize '1\file.txt')
            [DBOpsHelper]::SplitRelativePath((Join-PSFPath -Normalize '3\2\1\file.txt'), 3) | Should -Be (Join-PSFPath -Normalize '3\2\1\file.txt')
        }
        It "should validate negative tests" {
            { [DBOpsHelper]::SplitRelativePath((Join-PSFPath -Normalize '3\2\1\file.txt'), 4) } | Should -Throw
            { [DBOpsHelper]::SplitRelativePath($null, 1) } | Should -Throw
        }
    }
    Context "tests GetBinaryFile method" {
        It "should validate positive tests" {
            [DBOpsHelper]::GetBinaryFile($script1) | Should -Not -BeNullOrEmpty
            #Verifying that the threads are closed
            { [DBOpsHelper]::GetBinaryFile($script1) } | Should -Not -Throw
        }
        It "should validate negative tests" {
            { [DBOpsHelper]::GetBinaryFile((Join-PSFPath -Normalize 'nonexisting\path')) } | Should -Throw
            { [DBOpsHelper]::SplitRelativePath($null) } | Should -Throw
        }
    }
    Context "tests ReadDeflateStream method" {
        BeforeAll {
            #Create the archive
            Compress-Archive -Path $script1 -DestinationPath $archiveName
        }
        AfterAll {
            #Remove temporary file
            Remove-Item $archiveName
        }
        It "should validate positive tests" {
            $zip = [Zipfile]::OpenRead($archiveName)
            try {
                [DBOpsHelper]::ReadDeflateStream($zip.Entries[0].Open()) | Should -Not -BeNullOrEmpty
            }
            catch { throw $_ }
            finally { $zip.Dispose() }

            #Verifying that the threads are closed
            $zip = [Zipfile]::OpenRead($archiveName)
            try {
                { [DBOpsHelper]::ReadDeflateStream($zip.Entries[0].Open()) } | Should -Not -Throw
            }
            catch { throw $_ }
            finally { $zip.Dispose() }
        }
        It "should validate negative tests" {
            $zip = [Zipfile]::OpenRead($archiveName).Dispose()
            { [DBOpsHelper]::ReadDeflateStream($zip.Entries[0].Open()) } | Should -Throw
            { [DBOpsHelper]::ReadDeflateStream($null) } | Should -Throw
        }
    }
    Context "tests GetArchiveItems method" {
        BeforeAll {
            #Create the archive
            Compress-Archive -Path $script1, $script2 -DestinationPath $archiveName
        }
        AfterAll {
            #Remove temporary file
            Remove-Item $archiveName
        }
        It "should validate positive tests" {
            $testResults = [DBOpsHelper]::GetArchiveItems($archiveName)
            '1.sql' | Should -BeIn $testResults.FullName
            '2.sql' | Should -BeIn $testResults.FullName

            #Verifying that the threads are closed
            { [DBOpsHelper]::GetArchiveItems($archiveName) } | Should -Not -Throw
        }
        It "should validate negative tests" {
            { [DBOpsHelper]::GetArchiveItems($null) } | Should -Throw
            { [DBOpsHelper]::GetArchiveItems((Join-PSFPath -Normalize 'nonexisting\path')) } | Should -Throw
        }
    }
    Context "tests GetArchiveItem method" {
        BeforeAll {
            #Create the archive
            Compress-Archive -Path $script1, $script2 -DestinationPath $archiveName
        }
        AfterAll {
            #Remove temporary file
            Remove-Item $archiveName
        }
        It "should validate positive tests" {
            $testResults = [DBOpsHelper]::GetArchiveItem($archiveName, '1.sql')
            '1.sql' | Should -BeIn $testResults.FullName
            '2.sql' | Should -Not -BeIn $testResults.FullName
            foreach ($testResult in $testResults) {
                $testResult.ByteArray | Should -Not -BeNullOrEmpty
            }

            $testResults = [DBOpsHelper]::GetArchiveItem($archiveName, @('1.sql', '2.sql'))
            '1.sql' | Should -BeIn $testResults.FullName
            '2.sql' | Should -BeIn $testResults.FullName
            foreach ($testResult in $testResults) {
                $testResult.ByteArray | Should -Not -BeNullOrEmpty
            }
        }
        It "should validate negative tests" {
            { [DBOpsHelper]::GetArchiveItem($null, '1.sql') } | Should -Throw
            { [DBOpsHelper]::GetArchiveItem((Join-PSFPath -Normalize 'nonexisting\path'), '1.sql') } | Should -Throw
            [DBOpsHelper]::GetArchiveItem($archiveName, $null) | Should -BeNullOrEmpty
            [DBOpsHelper]::GetArchiveItem($archiveName, (Join-PSFPath -Normalize 'nonexisting\path')) | Should -BeNullOrEmpty
            [DBOpsHelper]::GetArchiveItem($archiveName, '') | Should -BeNullOrEmpty
        }
    }
    Context "tests WriteZipFile method" {
        AfterEach {
            #Remove temporary file
            Remove-Item $archiveName
        }
        It "should validate positive tests" {
            #Create the archive
            $content = [byte[]]@(66, 67, 68)#Open new file stream
            $writeMode = [System.IO.FileMode]::CreateNew
            $stream = [FileStream]::new($archiveName, $writeMode)
            try {
                #Open zip file
                $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Create)
                try {
                    [DBOpsHelper]::WriteZipFile($zip, 'asd.txt', $content)
                    [DBOpsHelper]::WriteZipFile($zip, (Join-PSFPath -Normalize 'folder\asd.txt'), $content)
                    [DBOpsHelper]::WriteZipFile($zip, (Join-PSFPath -Normalize 'folder1\folder2\null.txt'), [byte[]]::new(0))
                }
                catch { throw $_ }
                finally { $zip.Dispose() }
            }
            catch { throw $_ }
            finally { $stream.Dispose()	}
            $testResults = [DBOpsHelper]::GetArchiveItems($archiveName)
            'asd.txt' | Should -BeIn $testResults.FullName
            Join-PSFPath -Normalize 'folder\asd.txt' | Should -BeIn $testResults.FullName
            Join-PSFPath -Normalize 'folder1\folder2\null.txt' | Should -BeIn $testResults.FullName
        }
        It "should validate negative tests" {
            #Create the archive
            $content = [byte[]]@(66, 67, 68)#Open new file stream
            $writeMode = [System.IO.FileMode]::CreateNew
            $stream = [FileStream]::new($archiveName, $writeMode)
            try {
                #Open zip file
                $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Create)
                try {
                    [DBOpsHelper]::WriteZipFile($zip, 'asd.txt', $content)
                    { [DBOpsHelper]::WriteZipFile($zip, (Join-PSFPath -Normalize 'folder\asd.txt'), 'asd') } | Should -Throw
                    { [DBOpsHelper]::WriteZipFile($zip, 'null2.txt', $null) } | Should -Throw
                    { [DBOpsHelper]::WriteZipFile($zip, (Join-PSFPath -Normalize '..\2.txt'), $content) } | Should -Throw
                    { [DBOpsHelper]::WriteZipFile($zip, (Join-PSFPath -Normalize '.\2.txt'), $content) } | Should -Throw
                    { [DBOpsHelper]::WriteZipFile($zip, (Join-PSFPath -Normalize '\2.txt'), $content) } | Should -Throw
                }
                catch { throw $_ }
                finally { $zip.Dispose() }
            }
            catch { throw $_ }
            finally { $stream.Dispose()	}
            $testResults = [DBOpsHelper]::GetArchiveItems($archiveName)
            'asd.txt' | Should -BeIn $testResults.FullName
            Join-PSFPath -Normalize 'folder\asd.txt' | Should -Not -BeIn $testResults.FullName
            'null2.txt' | Should -BeIn $testResults.FullName #This is weird, but that's how it works
            '2.txt' | Should -Not -BeIn $testResults.FullName
            Join-PSFPath -Normalize '..\2.txt' | Should -Not -BeIn $testResults.FullName
            Join-PSFPath -Normalize '.\2.txt' | Should -Not -BeIn $testResults.FullName
            Join-PSFPath -Normalize '\2.txt' | Should -Not -BeIn $testResults.FullName
        }
    }
    Context "tests ToHexString method" {
        It "should validate positive tests" {
            [DBOpsHelper]::ToHexString('') | Should -Be '0x00'
            [DBOpsHelper]::ToHexString([byte[]]@(1, 2, 3, 4)) | Should -Be '0x01020304'
            [DBOpsHelper]::ToHexString($null) | Should -Be '0x00'
            [DBOpsHelper]::ToHexString('0xFF') | Should -Be '0xFF'
        }
        It "should validate negative tests" {
            { [DBOpsHelper]::ToHexString('0xAAAA') } | Should -Throw
            { [DBOpsHelper]::ToHexString('qwe') } | Should -Throw
        }
    }
    Context "tests DecodeBinaryText method" {
        BeforeAll {
            $string = 'SELECT foo FROM bar'
            $h = [DBOpsHelper]
            $enc = [System.Text.Encoding]
        }
        AfterAll {
            if (Test-Path $sqlName) { Remove-Item $sqlName }
        }

        It "should convert from binary string encoded as <_>" -Foreach $encodings {
            $h::DecodeBinaryText($enc::$_.GetPreamble() + $enc::$_.GetBytes($string)) | Should -BeExactly $string
        }
        It "should convert from file encoded as <_>" -Foreach $encodings {
            $string | Out-File $sqlName -Encoding $_ -Force -NoNewline
            $sqlName | Should -FileContentMatchExactly ([regex]::Escape($h::DecodeBinaryText($h::GetBinaryFile($sqlName))))
        }
        It "should read encoded file <_>" -Foreach $encodedFiles {
            $encodedFile = Join-PSFPath -Normalize "$etcFolder\encoding-tests" $_
            $h::DecodeBinaryText($h::GetBinaryFile($encodedFile)) | Should -BeExactly $string
            $encodedFile | Should -FileContentMatchExactly ([regex]::Escape($h::DecodeBinaryText($h::GetBinaryFile($encodedFile))))
        }
        It "Should return empty string when byte array is empty" {
            $h::DecodeBinaryText([byte[]]::new(0)) | Should -BeNullOrEmpty
            { $h::DecodeBinaryText([byte[]]::new(0)) } | Should -Not -Throw
        }
        It "should validate negative tests" {
            { $h::DecodeBinaryText('0xAAAA') } | Should -Throw
            { $h::DecodeBinaryText('NotAByte') } | Should -Throw
        }
    }
    Context "tests DataRowToPSObject method" {
        It "should process normal dataset with nulls" {
            $ds = [System.Data.DataSet]::new()
            $dt = [System.Data.DataTable]::new()
            $null = $dt.Columns.Add('a')
            1, 2, $null | ForEach-Object {
                $dr = $dt.NewRow()
                $dr['a'] = $_
                $null = $dt.Rows.Add($dr);
            }
            $null = $ds.Tables.Add($dt);
            $output = @()
            foreach ($row in $ds.Tables[0].Rows) {
                $output += [DBOpsHelper]::DataRowToPSObject($row)
            }
            $output.a | Should -Be 1, 2, $null
        }
        It "should process empty dataset" {
            $ds = [System.Data.DataSet]::new()
            $dt = [System.Data.DataTable]::new()
            $null = $dt.Columns.Add('a')
            $dr = $dt.NewRow()
            $output = [DBOpsHelper]::DataRowToPSObject($dr)
            $output | Should -BeNullOrEmpty
        }
        It "should process null" {
            $output = [DBOpsHelper]::DataRowToPSObject($null)
            $output | Should -BeNullOrEmpty
        }
    }
}