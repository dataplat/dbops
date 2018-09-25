Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

. "$here\..\internal\classes\DBOpsDeploymentStatus.class.ps1"

Describe "Send-DBOMailMessage tests" -Tag $commandName, UnitTests {
    BeforeAll {
        $mailParams = @{
            SmtpServer = 'test.smtp'
            From       = 'from@smtp.local'
            To         = 'to@smtp.local'
            CC         = 'CC@smtp.local'
            Bcc         = 'Bcc@smtp.local'
            DeliveryNotificationOption = 'Never'
            Encoding                   = [System.Text.Encoding]::ASCII
            Attachments = 'myNewfile.ext'
            Port        = 23456
            Priority    = 'Low'
        }
        $status = [DBOpsDeploymentStatus]::new()
        $status.StartTime = [datetime]::Now
        $status.SqlInstance = 'TestInstance'
        $status.Database = 'TestDatabase'
        $status.EndTime = [datetime]::Now.AddMinutes(10)
        $status.DeploymentLog = @('1','2','3')
        $status.Scripts += [DbUp.Engine.SqlScript]::new('1', '')
        $status.Scripts += [DbUp.Engine.SqlScript]::new('2', '')

        Mock -CommandName Send-MailMessage -MockWith { $mailParams }
    }
    Context "Testing parameters" {
        It "Should run successfully with all parameters" {
            $mockedResult = $status | Send-DBOMailMessage @mailParams -Subject 'Test' -Template "<body>soHtml</body>"
            foreach ($key in $mailParams.Keys) {
                $mockedResult[$key] | Should Be $mailParams[$key]
            }
        }
        It "Should grab parameters from defaults" {
            Set-DBODefaultSetting -Temporary -Name mail.SmtpServer -Value 'test.local'
            Set-DBODefaultSetting -Temporary -Name mail.Subject -Value 'test'
            Set-DBODefaultSetting -Temporary -Name mail.To -Value 'test@local'
            Set-DBODefaultSetting -Temporary -Name mail.From -Value 'test@local'
            $mockedResult = $status | Send-DBOMailMessage # -To 'whatever@wherever.plz'
            foreach ($key in $mailParams.Keys) {
                $mockedResult[$key] | Should Be $mailParams[$key]
            }
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
            { $status | Send-DBOMailMessage } | Should throw
        }
        It "Should fail when Subject is empty" {
            Set-DBODefaultSetting -Temporary -Name mail.Subject -Value ''
            { $status | Send-DBOMailMessage } | Should throw
        }
        It "Should fail when To is empty" {
            Set-DBODefaultSetting -Temporary -Name mail.To -Value ''
            { $status | Send-DBOMailMessage } | Should throw
        }
        It "Should fail when From is empty" {
            Set-DBODefaultSetting -Temporary -Name mail.From -Value ''
            { $status | Send-DBOMailMessage } | Should throw
        }
    }
}