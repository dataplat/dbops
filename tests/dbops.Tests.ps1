Param (
    [switch]$Batch
)

$commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
$here = if ($PSScriptRoot) { $PSScriptRoot } else {	(Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

$ModuleName = 'dbops'
$ModulePath = (Get-Item $here).Parent.FullName

Describe "$ModuleName indentation" -Tag 'Compliance' {
    $AllFiles = Get-ChildItem -Path $ModulePath -File -Recurse  -Filter '*.ps*1'
    It "should test $($AllFiles.Count) files" {
        $AllFiles.Count | Should BeGreaterThan 0
    }
    foreach ($f in $AllFiles) {
        $LeadingTabs = Select-String -Path $f -Pattern '^[\t]+'
        if ($LeadingTabs.Count -gt 0) {
            It "$f is not indented with tabs (line(s) $($LeadingTabs.LineNumber -join ','))" {
                $LeadingTabs.Count | Should Be 0
            }
        }
        $TrailingSpaces = Select-String -Path $f -Pattern '([^ \t\r\n])[ \t]+$'
        if ($TrailingSpaces.Count -gt 0) {
            It "$f has no trailing spaces (line(s) $($TrailingSpaces.LineNumber -join ','))" {
                $TrailingSpaces.Count | Should Be 0
            }
        }
    }
}

Describe "$ModuleName ScriptAnalyzerErrors" -Tag 'Compliance' {
    $functionErrors = Invoke-ScriptAnalyzer -Path "$ModulePath\functions" -Severity Warning
    $internalErrors = Invoke-ScriptAnalyzer -Path "$ModulePath\internal\functions" -Severity Error
    $moduleErrors = Invoke-ScriptAnalyzer -Path "$ModulePath\$ModuleName.psm1" -Severity Error
    foreach ($scriptAnalyzerErrors in @($functionErrors, $internalErrors, $moduleErrors)) {
        foreach ($err in $scriptAnalyzerErrors) {
            It "$($err.scriptName) has Error(s) : $($err.RuleName)" {
                $err.Message | Should Be $null
            }
        }
    }
    It "should successfully pass all the tests" {
        $functionErrors | Should BeNullOrEmpty
        $internalErrors | Should BeNullOrEmpty
        $moduleErrors | Should BeNullOrEmpty
    }
}