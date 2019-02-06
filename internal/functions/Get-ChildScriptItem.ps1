function Get-ChildScriptItem {
    [CmdletBinding()]
    Param (
        [object[]]$Path,
        [bool]$Absolute = $Absolute,
        [bool]$Relative = $Relative,
        [bool]$Recurse = (-not $NoRecurse),
        [string[]]$Filter = $Filter
    )
    Function Get-SourcePath {
        Param (
            [System.IO.FileSystemInfo]$Item,
            [int]$Depth = 0,
            [System.IO.FileSystemInfo]$Root = $Item
        )
        Write-PSFMessage -Level Debug -Message "Getting child items from $Item with current depth $Depth"
        foreach ($childItem in (Get-ChildItem $Item -Filter $Filter)) {
            if ($childItem.PSIsContainer -and $Recurse) {
                Get-SourcePath -Item (Get-Item $childItem.FullName) -Depth ($Depth + 1) -Root $Root
            }
            else {
                #Add-Member -InputObject $childItem -MemberType NoteProperty -Name Depth -Value $Depth
                if ($Relative) {
                    $srcPath = Resolve-Path $childItem.FullName -Relative
                }
                elseif ($Absolute) {
                    $srcPath = $childItem.FullName
                }
                elseif ($Root.PSIsContainer) {
                    $srcPath = $childItem.FullName -replace "^$($Item.FullName)", '.'
                }
                else {
                    $srcPath = $childItem.Name
                }
                [DBOpsScriptFile]::new($childItem, $srcPath)
                #Add-Member -InputObject $childItem -MemberType NoteProperty -Name SourcePath -Value $srcPath -PassThru
            }
        }
    }
    foreach ($p in $Path) {
        if ($p.GetType() -in @([System.IO.FileSystemInfo], [System.IO.FileInfo])) {
            Write-PSFMessage -Level Verbose -Message "Item $p ($($p.GetType())) is a File object"
            $stringPath = $p.FullName
            $isAbsolute = $true
        }
        else {
            Write-PSFMessage -Level Verbose -Message "Item $p ($($p.GetType())) will be treated as a string"
            $stringPath = [string]$p
            $isAbsolute = Split-Path -Path $stringPath -IsAbsolute
        }
        if (!(Test-Path $stringPath)) {
            Stop-PSFFunction -EnableException $true -Message "The following path is not valid: $stringPath"
            return
        }
        foreach ($currentItem in (Get-Item $stringPath)) {
            Get-SourcePath -Item $currentItem -Depth ([int]$currentItem.PSIsContainer)
        }
    }
}