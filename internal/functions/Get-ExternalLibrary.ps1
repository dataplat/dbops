function Get-ExternalLibrary {
    # Returns all external dependencies for RDBMS
    Param (
        [string]$Type
    )
    $slash = [IO.Path]::DirectorySeparatorChar
    $d = Get-Content (Join-Path (Get-Item $PSScriptRoot).Parent.FullName "json\dbops.dependencies.json".Replace('\', $slash)) -Raw | ConvertFrom-Json
    if ($Type) { $d.$Type }
    else { $d }
}