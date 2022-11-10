param (
    [switch]$Internal
)
Import-Module "$PSScriptRoot\..\dbops.psd1" -Force
if ($Internal) {
    Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}