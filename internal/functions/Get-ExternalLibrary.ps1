function Get-ExternalLibrary {
    # Returns all external dependencies for RDBMS
    Param (
        [string]$Type
    )
    $d = Get-Content (Join-Path "$PSScriptRoot\.." "json\dbops.dependencies.json") -Raw | ConvertFrom-Json
    if ($Type) { $d.$Type }
    else { $d }
}