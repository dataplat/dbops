Function Get-DBOModuleFileList {
    <#
.SYNOPSIS
Returns all module files based on json file in the module root

.DESCRIPTION
Returns objects from internal\json\dbops.json. Is used internally to load files into the package.

.PARAMETER Type
Type of the module files to display

.PARAMETER Edition
Select only libraries relevant to the current edition of Powershell

.EXAMPLE
# Returns module files
Get-DBOModuleFileList

.EXAMPLE
# Returns only function files
Get-DBOModuleFileList -Type Functions
#>
    Param (
        [string[]]$Type,
        [string[]]$Edition = @('Desktop', 'Core')
    )
    Function ModuleFile {
        Param (
            $Path,
            $Type
        )
        $Path = Join-PSFPath -Normalize $Path
        $obj = @{} | Select-Object Path, Name, FullName, Type, Directory
        $obj.Path = $Path
        $obj.Directory = Split-Path $Path -Parent
        $obj.Type = $Type
        $file = Get-Item -Path (Join-Path (Get-Item $PSScriptRoot).Parent.FullName $Path)
        $obj.FullName = $file.FullName
        $obj.Name = $file.Name
        $obj
    }
    $slash = [IO.Path]::DirectorySeparatorChar
    $moduleCatalog = Get-Content (Join-PSFPath -Normalize (Get-Item $PSScriptRoot).Parent.FullName "internal\json\dbops.json") -Raw | ConvertFrom-Json
    foreach ($property in $moduleCatalog.psobject.properties.Name) {
        if (!$Type -or $property -in $Type) {
            if ($property -eq 'Libraries') {
                $files = @()
                foreach ($e in $Edition) {
                    $files += $moduleCatalog.$property.$e
                }
            }
            else {
                $files = $moduleCatalog.$property
            }
            foreach ($file in $files) {
                ModuleFile -Path $file -Type $property
            }
        }
    }
}
