BeforeDiscovery {
    $moduleName = 'dbops'
    $modulePath = (Get-Item $PSScriptRoot).Parent.Parent.FullName
    $allFiles = Get-ChildItem -Path $ModulePath -File -Recurse  -Filter '*.ps*1'
    $settings = @{
        ExcludeRules = @(
            'PSUseShouldProcessForStateChangingFunctions'
        )
    }
    $analyzerErrors = @{
        function = Invoke-ScriptAnalyzer -Path "$ModulePath\functions" -Severity Warning -Settings $settings
        internal = Invoke-ScriptAnalyzer -Path "$ModulePath\internal\functions" -Severity Error -Settings $settings
        module   = Invoke-ScriptAnalyzer -Path "$ModulePath\$ModuleName.psm1" -Severity Error -Settings $settings
    }
}


Describe "<ModuleName> indentation" -Tag ComplianceTests -Foreach @(
    @{AllFiles = $allFiles; ModuleName = $moduleName }
) {
    Context "Leading tabs" {
        It "ensures <_> is not indented with tabs" -ForEach $AllFiles {
            $LeadingTabs = Select-String -Path $_ -Pattern '^[\t]+'
            $LeadingTabs.Count | Should -Be 0
        }
    }
    Context "Trailing spaces" {
        It "ensures <_> has no trailing spaces" -ForEach $AllFiles {
            $TrailingSpaces = Select-String -Path $_ -Pattern '([^ \t\r\n])[ \t]+$'
            $TrailingSpaces.Count | Should -Be 0
        }
    }
}

Describe "<ModuleName> ScriptAnalyzerErrors" -Tag ComplianceTests -Foreach @(
    @{AnalyzerErrors = $analyzerErrors; ModuleName = $moduleName }
) {
    Context "<_> errors" -ForEach @(
        @{AnalyzerErrors = $AnalyzerErrors; Type = "functions" }
        @{AnalyzerErrors = $AnalyzerErrors; Type = "internal" }
        @{AnalyzerErrors = $AnalyzerErrors; Type = "module" }
    ) {
        It "<_.scriptName> has Error(s) : <_.RuleName>" -Foreach $AnalyzerErrors.$Type {
            $_.Message | Should -Be $null
        }
    }
    Context "Overall success" -ForEach @(
        @{AnalyzerErrors = $AnalyzerErrors; Type = "functions" }
        @{AnalyzerErrors = $AnalyzerErrors; Type = "internal" }
        @{AnalyzerErrors = $AnalyzerErrors; Type = "module" }
    ) {
        It "should successfully pass all <Type> tests" {
            $AnalyzerErrors.$Type | Should -BeNullOrEmpty
        }
    }
}