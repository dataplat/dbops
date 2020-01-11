function Get-DbopsFile {
    [CmdletBinding()]
    Param (
        [object[]]$Path,
        [bool]$Absolute = ($Absolute -eq $true),
        [bool]$Relative = ($Relative -eq $true),
        [bool]$Recurse = ($NoRecurse -ne $true),
        [string[]]$Match = $Match
    )
    Function Select-DbopsFile {
        Param (
            [System.IO.FileSystemInfo]$Item,
            [System.IO.FileSystemInfo]$Root
        )
        Write-PSFMessage -Level Debug -Message "Getting child items from $Item; Root defined as $Root"
        $fileItems = Get-ChildItem $Item.FullName
        foreach ($childItem in $fileItems) {
            if ($childItem.PSIsContainer) {
                if ($Recurse) { Select-DbopsFile -Item (Get-Item $childItem.FullName) -Root $Root }
            }
            else {
                if ($Match -and $childItem.Name -notmatch ($Match -join '|')) { continue }
                if ($Relative) {
                    $pkgPath = Resolve-Path $childItem.FullName -Relative
                }
                elseif ($Absolute) {
                    $pkgPath = $childItem.FullName
                }
                elseif ($Root) {
                    $pkgPath = $childItem.FullName -replace "^$([Regex]::Escape($Root.FullName))", '.'
                }
                else {
                    $pkgPath = $childItem.Name
                }
                # replace ^.\ ^./ ^\\ and :
                $slash = [IO.Path]::DirectorySeparatorChar
                $slashRegex = [Regex]::Escape(".$slash")
                $pkgPath = $pkgPath -replace "^$slashRegex|^\\\\", ''
                [DBOpsFile]::new($childItem, $pkgPath, $true)
            }
        }
    }
    foreach ($p in $Path) {
        if ($p.GetType() -in @([System.IO.FileSystemInfo], [System.IO.FileInfo])) {
            Write-PSFMessage -Level Verbose -Message "Item $p ($($p.GetType())) is a File object"
            $stringPath = $p.FullName
        }
        else {
            Write-PSFMessage -Level Verbose -Message "Item $p ($($p.GetType())) will be treated as a string"
            $stringPath = [string]$p
        }
        if (!(Test-Path $stringPath)) {
            Stop-PSFFunction -EnableException $true -Message "The following path is not valid: $stringPath"
            return
        }
        $fileItems = Get-Item $stringPath -ErrorAction Stop
        foreach ($currentItem in $fileItems) {
            if ($currentItem.PSIsContainer) {
                Select-DbopsFile -Item $currentItem -Root $currentItem.Parent
            }
            else {
                Select-DbopsFile -Item $currentItem -Root $currentItem.Directory
            }
        }
    }
}