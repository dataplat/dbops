BeforeDiscovery {
    . "$PSScriptRoot\..\import.ps1"
    $includedNames = (Get-ChildItem "$PSScriptRoot\..\..\functions" | Where-Object Name -like "*.ps1" ).BaseName
    $commands = Get-Command -Module (Get-Module dbops) -CommandType Cmdlet, Function | Where-Object Name -in $includedNames
    $commonParameters = 'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable', 'OutBuffer', 'OutVariable',
    'PipelineVariable', 'Verbose', 'WarningAction', 'WarningVariable'
    $testCases = $commands | ForEach-Object {
        if ($global:FunctionHelpTestExceptions -contains $_.Name) { continue }
        @{ Command = $_; CommandName = $_.Name; Help = Get-Help $_.Name -ErrorAction SilentlyContinue; Common = $commonParameters }
    }

}
## When testing help, remember that help is cached at the beginning of each session.
## To test, restart session.


Describe "Test help for $commandName" -Tag ComplianceTests -Foreach $testCases {
    Context "Help topics for <CommandName>" {
        It "<CommandName> help should not be auto-generated" {
            # If help is not found, synopsis in auto-generated help is the syntax diagram
            $Help.Synopsis | Should -Not -BeLike '*`[`<CommonParameters`>`]*'

        }
        It "gets description for <CommandName>" {
            $Help.Description | Should -Not -BeNullOrEmpty
        }
        It "gets example code from <CommandName>" {
            ($Help.Examples.Example | Select-Object -First 1).Code | Should -Not -BeNullOrEmpty
        }

        It "gets example description from <CommandName>" {
            $Help.Examples.Example.code | Select-Object -First 1 | Should -Not -BeNullOrEmpty
        }
    }

    Context "Test parameter help for <CommandName>" {
        BeforeDiscovery {
            $parameterSets = $Command.ParameterSets | Sort-Object -Property Name -Unique | Where-Object Parameters.Name -notin $Common
            $parameterSetTestCases = $parameterSets | Foreach-Object {
                @{ ParameterSet = $_ }
            }
            $helpParameterNames = $Help.Parameters.Parameter.Name | Sort-Object -Unique
            $helpParameterNamesTestCases = $helpParameterNames | Foreach-Object {
                @{ HelpParameterName = $_; ParameterSets = $parameterSets }
            }
        }
        Context "Test parameterset <ParameterSet>" -Foreach $parameterSetTestCases {
            BeforeDiscovery {
                $parameters = $ParameterSet.Parameters | Sort-Object -Property Name -Unique | Where-Object Name -notin $Common
                $parameterTestCases = $parameters | ForEach-Object {
                    @{ Parameter = $_; ParameterName = $_.Name; ParameterHelp = $Help.parameters.parameter | Where-Object Name -eq $_.Name }
                }
            }
            It "gets description for parameter <ParameterName> : in <CommandName>" -Foreach $parameterTestCases {
                $ParameterHelp.Description.Text | Should -Not -BeNullOrEmpty
            }

            It "help for <ParameterName> parameter in <CommandName> has correct Mandatory value" -Foreach $parameterTestCases {
                if ($ParameterSet.IsDefault) {
                    #This test only valid for the default parameter set, but might fail on others if mandatory settings are different
                    $codeMandatory = $parameter.IsMandatory.toString()
                    if ($parameterHelp.Required -ne $codeMandatory) {
                        # Required value in Help should match IsMandatory property of parameter
                        $parameterHelp.Required | Should -Be $codeMandatory
                    }
                }
            }

            It "help for <CommandName> has correct parameter type for <ParameterName>"  -Foreach $parameterTestCases {
                $codeType = $parameter.ParameterType.Name

                if ($parameter.ParameterType.IsEnum) {
                    # Enumerations often have issues with the typename not being reliably available
                    $names = $parameter.ParameterType::GetNames($parameter.ParameterType)
                    if ($parameterHelp.parameterValueGroup.parameterValue -ne $names) {
                        # Parameter type in Help should match code
                        $parameterHelp.parameterValueGroup.parameterValue | Should -Be $names
                    }
                }
                #removing the [] in the end to properly identify enums
                elseif ((Invoke-Expression "[$($parameter.ParameterType.FullName.Trim('[]'))]").IsEnum) {
                    # Enumerations often have issues with the typename not being reliably available
                    $names = [Enum]::GetNames($parameter.ParameterType.DeclaredMembers[0].ReturnType)
                    if ($parameterHelp.parameterValueGroup.parameterValue -ne $names) {
                        # Parameter type in Help should match code
                        $parameterHelp.parameterValueGroup.parameterValue | Should -Be $names
                    }
                }
                else {
                    # To avoid calling Trim method on a null object.
                    $helpType = if ($parameterHelp.parameterValue) { $parameterHelp.parameterValue.Trim() }
                    if ($helpType -ne $codeType ) {
                        # Parameter type in Help should match code
                        $helpType | Should -Be $codeType
                    }
                }
            }
        }
        Context "Test help names" {
            It "finds <HelpParameterName> help parameter in code" -Foreach $helpParameterNamesTestCases {
                $HelpParameterName | Should -BeIn $ParameterSets.Parameters.Name
            }
        }
    }
}
