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
if ($SkipHelpTest) { return }
$includedNames = (Get-ChildItem "$here\..\functions" | Where-Object Name -like "*.ps1" ).BaseName
$commands = Get-Command -Module (Get-Module dbops) -CommandType Cmdlet, Function, Workflow | Where-Object Name -in $includedNames

## When testing help, remember that help is cached at the beginning of each session.
## To test, restart session.


foreach ($command in $commands) {
    $commandName = $command.Name

    # Skip all functions that are on the exclusions list
    if ($global:FunctionHelpTestExceptions -contains $commandName) { continue }

    # The module-qualified command fails on Microsoft.PowerShell.Archive cmdlets
    $Help = Get-Help $commandName -ErrorAction SilentlyContinue
    $testhelperrors = 0
    $testhelpall = 0
    Describe "Test help for $commandName" {

        $testhelpall += 1
        if ($Help.Synopsis -like '*`[`<CommonParameters`>`]*') {
            # If help is not found, synopsis in auto-generated help is the syntax diagram
            It "should not be auto-generated" {
                $Help.Synopsis | Should Not BeLike '*`[`<CommonParameters`>`]*'
            }
            $testhelperrors += 1
        }

        $testhelpall += 1
        if ([String]::IsNullOrEmpty($Help.Description.Text)) {
            # Should be a description for every function
            It "gets description for $commandName" {
                $Help.Description | Should Not BeNullOrEmpty
            }
            $testhelperrors += 1
        }

        $testhelpall += 1
        if ([String]::IsNullOrEmpty(($Help.Examples.Example | Select-Object -First 1).Code)) {
            # Should be at least one example
            It "gets example code from $commandName" {
                ($Help.Examples.Example | Select-Object -First 1).Code | Should Not BeNullOrEmpty
            }
            $testhelperrors += 1
        }

        $testhelpall += 1
        if ([String]::IsNullOrEmpty(($Help.Examples.Example.Remarks | Select-Object -First 1).Text)) {
            # Should be at least one example description
            It "gets example help from $commandName" {
                ($Help.Examples.Example.Remarks | Select-Object -First 1).Text | Should Not BeNullOrEmpty
            }
            $testhelperrors += 1
        }

        if ($testhelperrors -eq 0) {
            It "Ran silently $testhelpall tests" {
                $testhelperrors | Should be 0
            }
        }

        $testparamsall = 0
        $testparamserrors = 0
        Context "Test parameter help for $commandName" {

            $Common = 'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable', 'OutBuffer', 'OutVariable',
            'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable'

            $parameterSets = $command.ParameterSets | Sort-Object -Property Name -Unique | Where-Object Parameters.Name -notin $common
            foreach ($parameterSet in $parameterSets) {
                $parameters = $parameterSet.Parameters | Sort-Object -Property Name -Unique | Where-Object Name -notin $common
                $HelpParameterNames = $Help.Parameters.Parameter.Name | Sort-Object -Unique
                foreach ($parameter in $parameters) {
                    $parameterName = $parameter.Name
                    $parameterHelp = $Help.parameters.parameter | Where-Object Name -EQ $parameterName

                    $testparamsall += 1
                    if ([String]::IsNullOrEmpty($parameterHelp.Description.Text)) {
                        # Should be a description for every parameter
                        It "gets help for parameter: $parameterName : in $commandName" {
                            $parameterHelp.Description.Text | Should Not BeNullOrEmpty
                        }
                        $testparamserrors += 1
                    }

                    $testparamsall += 1
                    if ($parameterSet.IsDefault) {
                        #This test only valid for the default parameter set, but might fail on others if mandatory settings are different
                        $codeMandatory = $parameter.IsMandatory.toString()
                        if ($parameterHelp.Required -ne $codeMandatory) {
                            # Required value in Help should match IsMandatory property of parameter
                            It "help for $parameterName parameter in $commandName has correct Mandatory value" {
                                $parameterHelp.Required | Should Be $codeMandatory
                            }
                            $testparamserrors += 1
                        }
                    }

                    #if ($HelpTestSkipParameterType[$commandName] -contains $parameterName) { continue }

                    $codeType = $parameter.ParameterType.Name

                    $testparamsall += 1
                    if ($parameter.ParameterType.IsEnum) {
                        # Enumerations often have issues with the typename not being reliably available
                        $names = $parameter.ParameterType::GetNames($parameter.ParameterType)
                        if ($parameterHelp.parameterValueGroup.parameterValue -ne $names) {
                            # Parameter type in Help should match code
                            It "help for $commandName has correct parameter type for $parameterName" {
                                $parameterHelp.parameterValueGroup.parameterValue | Should be $names
                            }
                            $testparamserrors += 1
                        }
                    }
                    elseif ($parameter.ParameterType.FullName -in $HelpTestEnumeratedArrays) {
                        # Enumerations often have issues with the typename not being reliably available
                        $names = [Enum]::GetNames($parameter.ParameterType.DeclaredMembers[0].ReturnType)
                        if ($parameterHelp.parameterValueGroup.parameterValue -ne $names) {
                            # Parameter type in Help should match code
                            It "help for $commandName has correct parameter type for $parameterName" {
                                $parameterHelp.parameterValueGroup.parameterValue | Should be $names
                            }
                            $testparamserrors += 1
                        }
                    }
                    else {
                        # To avoid calling Trim method on a null object.
                        $helpType = if ($parameterHelp.parameterValue) { $parameterHelp.parameterValue.Trim() }
                        if ($helpType -ne $codeType ) {
                            # Parameter type in Help should match code
                            It "help for $commandName has correct parameter type for $parameterName" {
                                $helpType | Should be $codeType
                            }
                            $testparamserrors += 1
                        }
                    }
                }
            }
            foreach ($helpParm in $HelpParameterNames) {
                $testparamsall += 1
                if ($helpParm -notin $parameterSets.Parameters.Name) {
                    # Shouldn't find extra parameters in help.
                    It "finds help parameter in code: $helpParm" {
                        $helpParm -in $parameterSets.Parameters.Name | Should Be $true
                    }
                    $testparamserrors += 1
                }
            }
            if ($testparamserrors -eq 0) {
                It "Ran silently $testparamsall tests" {
                    $testparamserrors | Should be 0
                }
            }
        }
    }
}
