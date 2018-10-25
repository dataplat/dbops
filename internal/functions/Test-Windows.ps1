function Test-Windows {
    <#
        .SYNOPSIS
            Internal tool, used to detect non-Windows platforms

        .DESCRIPTION
            Some things don't work with Windows, this is an easy way to detect

        .EXAMPLE
            if (-not (Test-Windows)) { return }

            The calling function will stop if this function returns true.
    #>
    [CmdletBinding()]
    param (
        [switch]$Not
    )
    [bool]$result = -not (($PSVersionTable.Keys -contains "Platform") -and $psversiontable.Platform -ne "Win32NT")
    if ($Not) { $result = -not $result}
    return $result
}