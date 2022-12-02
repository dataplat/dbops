Describe "Send-DBOMailMessage tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        . "$PSScriptRoot\..\..\internal\classes\DBOpsDeploymentStatus.class.ps1"

        $status = [DBOpsDeploymentStatus]::new()
        $status.StartTime = [datetime]::Now
        $status.SqlInstance = 'TestInstance'
        $status.Database = 'TestDatabase'
        $status.EndTime = [datetime]::Now.AddMinutes(10)
        $status.DeploymentLog = @('1', '2', '3')
        $status.Scripts += [DBOps.SqlScript]::new('1', '')
        $status.Scripts += [DBOps.SqlScript]::new('2', '')

        $mailParams = @{
            SmtpServer                 = 'test.smtp'
            From                       = 'from@smtp.local'
            To                         = 'to@smtp.local'
            CC                         = 'CC@smtp.local'
            Bcc                        = 'Bcc@smtp.local'
            DeliveryNotificationOption = 'Never'
            Encoding                   = [System.Text.Encoding]::ASCII
            Attachments                = 'myNewfile.ext'
            Port                       = 23456
            Priority                   = 'Low'
        }

        Mock -CommandName Send-MailMessage -MockWith { $null } -ModuleName dbops
    }
    Context "Testing parameters" {
        It "Should run successfully with all parameters" {
            $status | Send-DBOMailMessage @mailParams -Subject 'Test' -Template "<body>soHtml</body>"
            Should -Invoke Send-MailMessage -Exactly 1 -Scope It -ModuleName dbops
        }
        It "Should run return an object when used with -passthru" {
            $testResult = $status | Send-DBOMailMessage @mailParams -Passthru
            $testResult.SqlInstance | Should -Be $status.SqlInstance
            $testResult.Database | Should -Be $status.Database
            Should -Invoke Send-MailMessage -Exactly 1 -Scope It -ModuleName dbops
        }
        It "Should grab parameters from defaults" {
            Set-DBODefaultSetting -Temporary -Name mail.SmtpServer -Value 'test.local'
            Set-DBODefaultSetting -Temporary -Name mail.Subject -Value 'test'
            Set-DBODefaultSetting -Temporary -Name mail.To -Value 'test@local'
            Set-DBODefaultSetting -Temporary -Name mail.From -Value 'test@local'

            $status | Send-DBOMailMessage
            Should -Invoke Send-MailMessage -Exactly 1 -Scope It -ModuleName dbops
        }
    }
    Context "Negative Testing parameters" {
        BeforeEach {
            Set-DBODefaultSetting -Temporary -Name mail.SmtpServer -Value 'test.local'
            Set-DBODefaultSetting -Temporary -Name mail.Subject -Value 'test'
            Set-DBODefaultSetting -Temporary -Name mail.To -Value 'test@local'
            Set-DBODefaultSetting -Temporary -Name mail.From -Value 'test@local'
        }
        It "Should fail when smtpserver is empty" {
            Set-DBODefaultSetting -Temporary -Name mail.SmtpServer -Value ''
            { $status | Send-DBOMailMessage } | Should -Throw
        }
        It "Should fail when To is empty" {
            Set-DBODefaultSetting -Temporary -Name mail.To -Value ''
            { $status | Send-DBOMailMessage } | Should -Throw
        }
        It "Should fail when From is empty" {
            Set-DBODefaultSetting -Temporary -Name mail.From -Value ''
            { $status | Send-DBOMailMessage } | Should -Throw
        }
        It "Should fail when InputObject is incorrect" {
            { 'thisissowrong' | Send-DBOMailMessage } | Should -Throw
        }
        It "Should not call Send-MailMessage" {
            Should -Invoke Send-MailMessage -Exactly 0 -Scope Context -ModuleName dbops
        }
    }
}