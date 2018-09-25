function Send-DBOMailMessage {
    <#
    .SYNOPSIS
    Sends a mail notification about the results of the deployment.
    .DESCRIPTION
    Sends a mail notification about the results of the deployment.
    Uses Send-MailMessage internally.
    .PARAMETER InputObject
    Output from any of the deployment related commands.
    .PARAMETER To
    Specifies the addresses to which the mail is sent. Enter names (optional) and the e-mail address, such as "Name
    <someone@example.com>".
    .PARAMETER Subject
    Specifies the subject of the e-mail message. Default is "DBOps deployment results"
    .PARAMETER SmtpServer
    Specifies the name of the SMTP server that sends the e-mail message.
    .PARAMETER From
    Specifies the address from which the mail is sent. Enter a name (optional) and e-mail address, such as "Name
    <someone@example.com>".
    .PARAMETER Cc
    Specifies the e-mail addresses to which a carbon copy (CC) of the e-mail message is sent. Enter names (optional) and the e-mail address, such as "Name <someone@example.com>".
    .PARAMETER Credential
    Specifies a user account that has permission to perform this action.
    .PARAMETER Port
    Specifies an alternate port on the SMTP server. The default value is 25, which is the default SMTP port.
    .PARAMETER Priority
    Specifies the priority of the e-mail message. The valid values for this are Normal, High, and Low. Normal is the default.
    .PARAMETER DeliveryNotificationOption
    Specifies the delivery notification options for the e-mail message. You can specify multiple values. "None" is the default value.  The alias for this parameter is "dno".
    The delivery notifications are sent in an e-mail message to the address specified in the value of the To parameter.
    Valid values are:
    .PARAMETER - None: No notification.
    .PARAMETER - OnSuccess: Notify if the delivery is successful.
    .PARAMETER - OnFailure: Notify if the delivery is unsuccessful.
    .PARAMETER - Delay: Notify if the delivery is delayed.
    .PARAMETER - Never: Never notify.
    .PARAMETER Bcc
    Specifies the e-mail addresses that receive a copy of the mail but are not listed as recipients of the message.
    Enter names (optional) and the e-mail address, such as "Name <someone@example.com>".
    .PARAMETER Attachments
    Specifies the path and file names of files to be attached to the e-mail message. You can use this parameter or pipe the paths and file names to Send-MailMessage.
    .PARAMETER Template
    Specifies the template of the email message body (content). By default, a template, built-in into the module, is used.
    .PARAMETER Encoding
    Specifies the encoding used for the body and subject. Valid values are ASCII, UTF8, UTF7, UTF32, Unicode,
    BigEndianUnicode, Default, and OEM. ASCII is the default.
    .PARAMETER UseSsl
    Uses the Secure Sockets Layer (SSL) protocol to establish a connection to the remote computer to send mail. By
    default, SSL is not used.
    .EXAMPLE
    #Runs package deployment and sends a mail message
    Install-DBOPackage -SqlInstance MyInstance -Database MyDB |
      Send-DBOMailMessage -To admin@my.local.site.io -From nobody@dbops.io -SmtpServer smtp.ad.local
#>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [object]$InputObject,
        [string[]]$To,
        [string]$From,
        [string]$Subject,
        [string]$Template,
        [string]$SmtpServer,
        [int]$Port,
        [ValidateSet('Normal', 'High', 'Low')]
        [string]$Priority,
        [string[]]$Attachments,
        [string[]]$Bcc,
        [string[]]$Cc,
        [PSCredential]$Credential,
        [ValidateSet('None', 'OnSuccess', 'OnFailure', 'Delay', 'Never')]
        [string]$DeliveryNotificationOption,
        [System.Text.Encoding]$Encoding,
        [switch]$UseSsl
    )
    begin {
    }
    process {
        if (Test-PSFParameterBinding -ParameterName Subject -Not) {
            $PSBoundParameters['Subject'] = Get-DBODefaultSetting -Name mail.Subject -Value
        }
        if (Test-PSFParameterBinding -ParameterName To -Not) {
            $PSBoundParameters['To'] = Get-DBODefaultSetting -Name mail.To -Value
        }

        if ($null -eq $PSBoundParameters['To']) {
            Stop-PSFFunction -Message "No recipient email address specified, exiting" -EnableException $true
        }
        if (Test-PSFParameterBinding -ParameterName smtpserver -Not) {
            $PSBoundParameters['smtpserver'] = Get-DBODefaultSetting -Name mail.smtpserver -Value
        }
        if (Test-PSFParameterBinding -ParameterName from -Not) {
            $PSBoundParameters['from'] = Get-DBODefaultSetting -Name mail.from -Value
        }
        if ($null -eq $PSBoundParameters['from']) {
            Stop-PSFFunction -Message "No sender email address specified, exiting" -EnableException $true
        }
        if ($InputObject -and $InputObject -isnot [DBOpsDeploymentStatus]) {
            Stop-PSFFunction -Message "Wrong object in the pipeline. Usable only with output from the deployment commands." -EnableException $true
        }
        #Get template from the parameter or read it from the default path
        if (Test-PSFParameterBinding -ParameterName Template) {
            $htmlTemplate = $Template
        }
        else {
            $htmlPath = $htmlFullPath = Get-DBODefaultSetting -Name mail.Template -Value
            if (!(Test-Path $htmlPath)) {
                $htmlFullPath = Join-Path "$PSScriptRoot\.." $htmlPath
            }
            if (!(Test-Path $htmlFullPath)) {
                Stop-PSFFunction -Message "Could not find the template file $htmlPath, exiting" -EnableException $true
            }
            $htmlTemplate = Get-Content $htmlFullPath -Raw -ErrorAction Stop
        }
        #Build token replacement hashtable
        $errorMessage = if ($InputObject.Error) { $InputObject.Error.ToString() } else { '' }
        $tokens = @{
            Server         = $InputObject.SqlInstance
            Database       = $InputObject.Database
            SourcePath     = $InputObject.SourcePath
            ConnectionType = $InputObject.ConnectionType
            Scripts        = $InputObject.Scripts.Name -join '<BR/>'
            Error          = $errorMessage
            Result         = switch ($InputObject.Successful) {
                $true { 'Successful' }
                $false { 'Failed' }
                default { 'Unknown' }
            }
            StartTime      = $InputObject.StartTime.ToString()
            EndTime        = $InputObject.EndTime.ToString()
            Duration       = $InputObject.Duration.ToString('hh\:mm\:ss')
            DeploymentLog  = $InputObject.DeploymentLog -join '<BR/>'
            Subject        = $PSBoundParameters['Subject']
        }

        # Get HTML variable
        $htmlbody = Resolve-VariableToken $htmlTemplate $tokens
        
        # Modify the params as required
        $null = $PSBoundParameters.Remove("InputObject")
        $null = $PSBoundParameters.Remove("Template")
        foreach ($p in (@('Subject', 'From', 'To', 'CC') | Where-Object { $_ -in $PSBoundParameters.Keys })) {
            $PSBoundParameters[$p] = Resolve-VariableToken $PSBoundParameters[$p] $tokens
        }
       
        try {
            Send-MailMessage -BodyAsHtml -Body $htmlbody -ErrorAction Stop @PSBoundParameters
        }
        catch {
            Stop-PSFFunction -Message "Failure in Send-MailMessage" -ErrorRecord $_ -EnableException $true
        }
    }
    end {
        if (!$InputObject) {
            Stop-PSFFunction -Message "InputObject is null. Make sure that the deployment returned an object."
        }
    }
}