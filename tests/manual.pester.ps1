Param
(
	[string[]]$Path = '.',
	[string[]]$Tag
	
)

#Explicitly import the module for testing
Import-Module "$PSScriptRoot\..\dbops.psd1" -Force
#Import ZipHelper
Import-Module ziphelper -Force

#Run each module function
$params = @{
	Script = @{
		Path = $Path
		Parameters = @{
			Batch = $true
		}
	}
}
if ($Tag) {
	$params += @{ Tag = $Tag}
}
Invoke-Pester @params