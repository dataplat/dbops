param (
    $Type = @('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')
)
# install modules
. "$PSScriptRoot\pester.prep.ps1"

# import module and install libraries

. "$PSScriptRoot\install_dependencies.ps1" -Load -Type $Type
