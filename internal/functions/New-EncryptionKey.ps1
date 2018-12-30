function New-EncryptionKey {
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [ValidateSet(128, 192, 256)]
        [int]$Length = 256,
        [switch]$Force
    )
    $path = Get-DBODefaultSetting -Name security.encryptionkey -Value
    $byteLength = $Length / 8
    $key = [byte[]]::new($byteLength)
    0..($byteLength - 1) | ForEach-Object {
        $key[$_] = [byte](0..255 | Get-Random)
    }
    if (-Not (Test-Path $path) -or $Force) {
        if ($PSCmdlet.ShouldProcess($path, "Creating a new key file")) {
            Write-PSFMessage -Level Warning -Message "The key file does not exist. Creating a new key at $path."
            $file = New-Item -Path $path -ItemType File -Force:$Force
            [System.IO.File]::WriteAllBytes($file.FullName, $key)
        }
        return $key
    }
    else {
        Write-PSFMessage -Level Warning -Message "The key already exists. Specify -Force if you want to overwrite it."
    }
}