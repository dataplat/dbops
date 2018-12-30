Function Get-DBOModuleFileList {
    <#
.SYNOPSIS
Returns all module files based on json file in the module root

.DESCRIPTION
Returns objects from internal\json\dbops.json. Is used internally to load files into the package.

.PARAMETER Type
Type of the module files to display

.EXAMPLE
# Returns module files
Get-DBOModuleFileList
#>
    Param (
        [string[]]$Type
    )
    Function ModuleFile {
        Param (
            $Path,
            $Type
        )
        $slash = [IO.Path]::DirectorySeparatorChar
        $obj = @{} | Select-Object Path, Name, FullName, Type, Directory
        $obj.Path = $Path.Replace('\', $slash)
        $obj.Directory = Split-Path $Path -Parent
        $obj.Type = $Type
        $file = Get-Item -Path (Join-Path (Get-Item $PSScriptRoot).Parent.FullName $Path)
        $obj.FullName = $file.FullName
        $obj.Name = $file.Name
        $obj
    }
    $slash = [IO.Path]::DirectorySeparatorChar
    $moduleCatalog = Get-Content (Join-Path (Get-Item $PSScriptRoot).Parent.FullName "internal\json\dbops.json".Replace('\', $slash)) -Raw | ConvertFrom-Json
    foreach ($property in $moduleCatalog.psobject.properties.Name) {
        if (!$Type -or $property -in $Type) {
            foreach ($file in $moduleCatalog.$property) {
                ModuleFile $file $property
            }
        }
    }
}
