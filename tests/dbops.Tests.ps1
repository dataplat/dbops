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

Describe "$ModuleName Aliases" -tag Build , Aliases {
    ## Get the Aliases that should be set from the psm1 file

    $psm1 = Get-Content $here\..\$ModuleName.psm1 -Verbose
    $Matches = [regex]::Matches($psm1, "AliasName`"\s=\s`"(\w*-\w*)`"")
    $Aliases = $Matches.ForEach{$_.Groups[1].Value}

    foreach ($Alias in $Aliases) {
        Context "Testing $Alias Alias" {
            $Definition = (Get-Alias $Alias).Definition
            It "$Alias Alias should exist" {
                Get-Alias $Alias| Should Not BeNullOrEmpty
            }
            It "$Alias Aliased Command $Definition Should Exist" {
                Get-Command $Definition -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            }
        }
    }
}

Describe "$ModuleName indentation" -Tag 'Compliance' {
    $AllFiles = Get-ChildItem -Path $ModulePath -File -Recurse  -Filter '*.ps*1'

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
    $ScriptAnalyzerErrors = @()
    $ScriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\functions" -Severity Error
    $ScriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\internal\functions" -Severity Error
    $ScriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\$ModuleName.psm1" -Severity Error
    if ($ScriptAnalyzerErrors.Count -gt 0) {
        foreach ($err in $ScriptAnalyzerErrors) {
            It "$($err.scriptName) has Error(s) : $($err.RuleName)" {
                $err.Message | Should Be $null
            }
        }
    }
}