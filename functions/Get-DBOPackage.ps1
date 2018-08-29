Function Get-DBOPackage {
    <#
    .SYNOPSIS
    Shows information about the existin DBOps package
    
    .DESCRIPTION
    Reads DBOps package header and configuration files and returns an object with corresponding properties.
    
    .PARAMETER Path
    Path to the DBOps package

    Aliases: Name, FileName, Package
    
    .PARAMETER InputObject
    Pipeline implementation of Path. Can also accept a DBOpsPackage object.

    .PARAMETER Unpacked
    Mostly intended for internal use. Gets package information from extracted package.

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Returns information about the package myPackage.zip, only including infomartion about builds 1.1 and 1.2
    Get-DBOPackage -Path c:\temp\myPackage.zip -Build 1.1, 1.2
    
    .NOTES
    
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(Mandatory = $false, ParameterSetName = 'Default', Position = 1)]
        [Alias('FileName', 'Name', 'Package')]
        [string[]]$Path,
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        [object]$InputObject,
        [switch]$Unpacked
    )
    begin {

    }
    process {
        if ($PsCmdlet.ParameterSetName -eq 'Pipeline') {
            if ($InputObject) {
                if ($InputObject -is [DBOpsPackageBase]) {
                    Write-PSFMessage -Level Verbose -Message "Loading package file from pipelined object"
                    $InputObject
                }
                elseif ($InputObject -is [System.IO.FileInfo]) {
                    Write-PSFMessage -Level Verbose -Message "Loading package file from the archive $($InputObject.FullName)"
                    [DBOpsPackage]::new($InputObject.FullName)
                }
                elseif ($InputObject -is [String]) {
                    Write-PSFMessage -Level Verbose -Message "Loading package file from the archive $($InputObject)"
                    [DBOpsPackage]::new($InputObject)
                }
                else {
                    Stop-PSFFunction -EnableException $true -Message "The following object type is not supported: $($InputObject.GetType().Name). The only supported types are DBOpsPackage, FileInfo and String"
                    return
                }
            }
            else {
                Stop-PSFFunction -EnableException $true -Message "The object was not found"
                return
            }
        }
        elseif ($PsCmdlet.ParameterSetName -eq 'Default') {
            foreach ($pathItem in (Get-Item $Path -ErrorAction Stop)) {
                if ($Unpacked) {
                    if ($pathItem.PSIsContainer) {
                        $packageFileName = [DBOpsConfig]::GetPackageFileName()
                        $packageFile = Join-Path $pathItem.FullName $packageFileName
                        Write-PSFMessage -Level Verbose -Message "Loading package $packageFileName from folder $($pathItem.FullName)"
                        [DBOpsPackageFile]::new($packageFile)
                    }
                    else {
                        Write-PSFMessage -Level Verbose -Message "Loading package from the json file $pathItem"
                        [DBOpsPackageFile]::new($pathItem.FullName)
                    }
                }
                else {
                    Write-PSFMessage -Level Verbose -Message "Loading package file from the archive $pathItem"
                    [DBOpsPackage]::new($pathItem.FullName)
                }
            }
        }
        else {
            Write-PSFMessage -Level Verbose -Message "Creating new DBOps package $pFile"
            [DBOpsPackage]::new()
        }
    }
    end {

    }
}