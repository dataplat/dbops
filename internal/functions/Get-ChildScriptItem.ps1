function Get-ChildScriptItem {
    [CmdletBinding()]
    Param (
        [object[]]$Path
    )
    Function Get-ChildItemDepth ([System.IO.FileSystemInfo]$Item, [int]$Depth = 0, [bool]$IsAbsolute) {
        Write-Debug "Getting child items from $Item with current depth $Depth"
        foreach ($childItem in (Get-ChildItem $Item)) {
            if ($childItem.PSIsContainer) {
                Get-ChildItemDepth -Item (Get-Item $childItem.FullName) -Depth ($Depth + 1)
            }
            else {
                Add-Member -InputObject $childItem -MemberType NoteProperty -Name Depth -Value $Depth
                # if a relative path can be build to the file item, use relative paths, otherwise, use absolute
                if ($childItem.FullName -like "$(Get-Location)\*" -and !$IsAbsolute) {
                    $srcPath = Resolve-Path $childItem.FullName -Relative
                }
                else {
                    $srcPath = $childItem.FullName
                }
                Add-Member -InputObject $childItem -MemberType NoteProperty -Name SourcePath -Value $srcPath -PassThru
            }
        }
    }
    foreach ($p in $Path) {
        if ($p.GetType() -in @([System.IO.FileSystemInfo], [System.IO.FileInfo])) {
            Write-Verbose "Item $p ($($p.GetType())) is a File object"
            $stringPath = $p.FullName
            $isAbsolute = $true
        }
        else {
            Write-Verbose "Item $p ($($p.GetType())) will be treated as a string"
            $stringPath = [string]$p
            $isAbsolute = Split-Path -Path $stringPath -IsAbsolute
        }
        if (!(Test-Path $stringPath)) {
            throw "The following path is not valid: $stringPath"
        }
        foreach ($currentItem in (Get-Item $stringPath)) {
            Get-ChildItemDepth -Item $currentItem -Depth ([int]$currentItem.PSIsContainer) -IsAbsolute $isAbsolute
        }
    }
}