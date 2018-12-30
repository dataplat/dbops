function Initialize-ExternalLibrary {
    #Load external libraries for a specific RDBMS
    Param (
        [Parameter(Mandatory)]
        [string]$Type
    )
    $dependencies = Get-ExternalLibrary -Type $Type
    foreach ($dPackage in $dependencies) {
        $localPackage = Get-Package -Name $dPackage.Name -MinimumVersion $dPackage.Version -ErrorAction Stop
        foreach ($dPath in $dPackage.Path) {
            Add-Type -Path (Join-PSFPath -Normalize (Split-Path $localPackage.Source -Parent) $dPath)
        }
    }
}