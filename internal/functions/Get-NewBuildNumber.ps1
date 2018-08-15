Function Get-NewBuildNumber {
	<#
	.SYNOPSIS
	Returns a new build number based on current date/time
	
	.DESCRIPTION
	Uses current date/time to generate a dot-separated string in the format: yyyy.mm.dd.hhmmss. This string is to be used as an internal build number when build hasn't been specified explicitly.
	
	.EXAMPLE
	$string = Get-NewBuildNumber
	
	.NOTES
	
	#>
	Param ()
	$currentDate = Get-Date
	[string]$currentDate.Year + '.' + ([string]$currentDate.Month).PadLeft(2, '0') + '.' + ([string]$currentDate.Day).PadLeft(2, '0') + '.' + ([string]$currentDate.Hour).PadLeft(2, '0') + ([string]$currentDate.Minute).PadLeft(2, '0') + ([string]$currentDate.Second).PadLeft(2, '0')
}