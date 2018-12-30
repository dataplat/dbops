function Get-EncryptionKey {
    [CmdletBinding(SupportsShouldProcess)]
    $path = Get-DBODefaultSetting -Name security.encryptionkey -Value
    if (-Not (Test-Path $path)) {
        return $null
    }
    else {
        $file = Get-Item -Path $path -Force -ErrorAction Stop
        return [System.IO.File]::ReadAllBytes($file.FullName)
    }
}