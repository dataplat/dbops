using namespace System.IO.Compression

class ZipReader {
	[ZipFileContents[]]$Entries
	ZipReader ([string]$Path) {
		$zip = [Zipfile]::OpenRead($Path)
		foreach ($entry in $zip.Entries) {
			$this.Entries += [ZipFileContents]::new($entry)
		}
		$zip.Dispose()
	}
}
class ZipFileContents {
	[string]$Path
	[byte[]]$ByteArray
	[int]$Length
	[string]$Name
	[System.DateTimeOffset]$LastWriteTime
	#[string]$Content
	[string]$Hash

	ZipFileContents([object]$Entry) {
		$this.Path = $Entry.FullName
		$this.Name = $Entry.Name
		$this.LastWriteTime = $Entry.LastWriteTime
		$stream = [System.IO.MemoryStream]::new()
		$Entry.Open().CopyTo($stream)
		$this.ByteArray = $stream.ToArray()
		#$this.Content = [ZipFileContents]::GetString($this.ByteArray)
		$this.Length = $this.ByteArray.Length
		$this.Hash = (Get-FileHash -InputStream $stream).Hash
		$stream.Close()
	}

	# static [string] GetString([byte[]]$Array) {
	# 	# EF BB BF (UTF8)
	# 	if ( $Array[0] -eq 0xef -and $Array[1] -eq 0xbb -and $Array[2] -eq 0xbf ) {
	# 		$encoding = [System.Text.Encoding]::UTF8
	# 	}
	# 	# FE FF  (UTF-16 Big-Endian)
	# 	elseif ($Array[0] -eq 0xfe -and $Array[1] -eq 0xff) {
	# 		$encoding = [System.Text.Encoding]::BigEndianUnicode
	# 	}
	# 	# FF FE  (UTF-16 Little-Endian)
	# 	elseif ($Array[0] -eq 0xff -and $Array[1] -eq 0xfe) {
	# 		$encoding = [System.Text.Encoding]::Unicode
	# 	}
	# 	# 00 00 FE FF (UTF32 Big-Endian)
	# 	elseif ($Array[0] -eq 0 -and $Array[1] -eq 0 -and $Array[2] -eq 0xfe -and $Array[3] -eq 0xff) {
	# 		$encoding = [System.Text.Encoding]::UTF32
	# 	}
	# 	# FE FF 00 00 (UTF32 Little-Endian)
	# 	elseif ($Array[0] -eq 0xfe -and $Array[1] -eq 0xff -and $Array[2] -eq 0 -and $Array[3] -eq 0) {
	# 		$encoding = [System.Text.Encoding]::UTF32
	# 	}
	# 	elseif ($Array[0] -eq 0x2b -and $Array[1] -eq 0x2f -and $Array[2] -eq 0x76 -and ($Array[3] -eq 0x38 -or $Array[3] -eq 0x39 -or $Array[3] -eq 0x2b -or $Array[3] -eq 0x2f)) {
	# 		$encoding = [System.Text.Encoding]::UTF7
	# 	}
	# 	else {
	# 		$encoding = [System.Text.Encoding]::ASCII
	# 	}
	# 	return $encoding.GetString($Array)
	# }
	[string] ToString() {
		return $this.FullName
	}
}

# $file = New-Object System.IO.FileStream "C:\Temp\Entries.log.gz", ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
# $type = [System.IO.Compression.CompressionMode]::Decompress
# $stream = new-object -TypeName System.IO.MemoryStream
# $GZipStream = New-object -TypeName System.IO.Compression.GZipStream -ArgumentList $file, $type
# $buffer = New-Object byte[](1024)
# $count = 0
# do
#     {
#         $count = $gzipstream.Read($buffer, 0, 1024)
#         if ($count -gt 0)
#             {
#                 $Stream.Write($buffer, 0, $count)
#             }
#     }
# While ($count -gt 0)
# $array = $stream.ToArray()
# $GZipStream.Close()
# $stream.Close()
# $file.Close()