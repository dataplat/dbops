Param
(
    [string[]]$Path = '.',
    [string[]]$Tag

)

$ModuleBase = Split-Path -Path $PSScriptRoot -Parent
#removes previously imported dbatools, if any
Remove-Module dbops -ErrorAction Ignore
#imports the module making sure DLL is loaded ok
Import-Module "$ModuleBase\dbops.psd1" -DisableNameChecking
#import internal commands
Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
#Import ZipHelper
Import-Module ziphelper -Force

#Run each module function
$params = @{
    Script = @{
        Path       = $Path
        Parameters = @{
            Batch = $true
        }
    }
}
if ($Tag) {
    $params += @{ Tag = $Tag}
}
Invoke-Pester @params