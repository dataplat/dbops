function Get-DbopsFile {
    [CmdletBinding()]
    Param (
        [object[]]$Path,
        [bool]$Absolute = $Absolute,
        [bool]$Relative = $Relative,
        [bool]$Recurse = (-not $NoRecurse),
        [string[]]$Match = $Match
    )
    Function Get-SourcePath {
        Param (
            [System.IO.FileSystemInfo]$Item,
            [System.IO.FileSystemInfo]$Root
        )
        Write-PSFMessage -Level Debug -Message "Getting child items from $Item; Root defined as $Root"
        $fileItems = Get-ChildItem $Item
        if ($Match) { $fileItems = $fileItems | Where-Object Name -match ($Match -join '|') }
        foreach ($childItem in $fileItems) {
            if ($childItem.PSIsContainer) {
                if ($Recurse) { Get-SourcePath -Item (Get-Item $childItem) -Root $Root }
            }
            else {
                if ($Relative) {
                    $srcPath = $pkgPath = Resolve-Path $childItem.FullName -Relative
                }
                elseif ($Absolute) {
                    $srcPath = $pkgPath = $childItem.FullName
                }
                elseif ($Root) {
                    $srcPath = $pkgPath = $childItem.FullName -replace "^$([Regex]::Escape($Root.FullName))", '.'
                }
                else {
                    $srcPath = $pkgPath = $childItem.Name
                }
                # replace some symbols here and there
                $srcPath = $srcPath -replace '^\.\\', ''
                $pkgPath = $pkgPath -replace '^\.\\|:', ''
                [DBOpsFile]::new($childItem, $srcPath, $pkgPath, $true)
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
                Get-SourcePath -Item $currentItem -Root $currentItem.Parent
            }
            else {
                Get-SourcePath -Item $currentItem -Root $currentItem.Directory
            }
        }
    }
}