Param
(
    [string[]]$Path = '.',
    [string[]]$Tag

)
$params = @{
    Path = $Path | ForEach-Object {
        $item = switch -regex ($_) {
            '\.Tests\.ps1' { $_ }
            default { $_.Replace('.ps1', '.Tests.ps1') }
        }
        Get-Item $item
    }
}
if ($Tag) {
    $params += @{ Tag = $Tag}
}
& $PSScriptRoot\manual.pester.ps1 @params