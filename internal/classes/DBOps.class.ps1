using namespace System.IO
using namespace System.IO.Compression

######################
# Root class DBOps #
######################

class DBOps {
    # globally setting all the properties to be exported by default
    hidden [array]$PropertiesToExport = @('*')

    # using PSF to properly throw and write messages
    hidden [void] ThrowException ([string]$Message, [string]$Category) {
        $callStack = (Get-PSCallStack)[1]
        $this.ThrowException($this, $Message, $Category, $null, $callStack)
    }
    hidden [void] ThrowException ([string]$Message, [System.Management.Automation.ErrorRecord]$ErrorRecord) {
        $callStack = (Get-PSCallStack)[1]
        $this.ThrowException($this, $Message, $null, $ErrorRecord, $callStack)
    }
    hidden [void] ThrowException ([object]$Target, [string]$Message, [string]$Category) {
        $callStack = (Get-PSCallStack)[1]
        $this.ThrowException($this, $Message, $Category, $null, $callStack)
    }
    hidden [void] ThrowException ([object]$Target, [string]$Message, [string]$Category, [System.Management.Automation.ErrorRecord]$ErrorRecord) {
        $callStack = (Get-PSCallStack)[1]
        $this.ThrowException($this, $Message, $Category, $ErrorRecord, $callStack)
    }
    hidden [void] ThrowException ([object]$Target, [string]$Message, [string]$Category, [System.Management.Automation.ErrorRecord]$ErrorRecord, [System.Management.Automation.CallStackFrame]$CallStack) {
        $splatParam = @{
            Tag             = 'DBOps', 'class', $this.GetType().Name
            FunctionName    = $this.GetType().Name
            ModuleName      = 'dbops'
            File            = $CallStack.Position.File
            Line            = $CallStack.Position.StartLineNumber
            Message         = $Message
            Target          = $Target
            ErrorRecord     = $ErrorRecord
            EnableException = $true
        }
        if ($Category) { $splatParam.Category = $Category }
        Stop-PSFFunction @splatParam
    }

    hidden [void] WriteVerbose ([string]$Message, [object]$Target) {
        $callStack = (Get-PSCallStack)[1]
        $splatParam = @{
            Tag          = 'DBOps', 'class', $this.GetType().Name
            FunctionName = $this.GetType().Name
            ModuleName   = 'dbops'
            File         = $callStack.Position.File
            Line         = $callStack.Position.StartLineNumber
            Message      = $Message
            Target       = $Target
            Level        = 'Verbose'
        }
        Write-PSFMessage @splatParam
    }

    hidden [void] WriteDebug ([string]$Message, [object]$Target) {
        $callStack = (Get-PSCallStack)[1]
        $splatParam = @{
            Tag          = 'DBOps', 'class', $this.GetType().Name
            FunctionName = $this.GetType().Name
            ModuleName   = 'dbops'
            File         = $callStack.Position.File
            Line         = $callStack.Position.StartLineNumber
            Message      = $Message
            Target       = $Target
            Level        = 'Debug'
        }
        Write-PSFMessage @splatParam
    }

    # hidden [DBOpsFile] NewFile ([string]$Name, [string]$PackagePath, [string]$CollectionName) {
    #     return $this.NewFile($Name, $PackagePath, $CollectionName, [DBOpsFile])
    # }
    # hidden [DBOpsFile] NewFile ([string]$Name, [string]$PackagePath, [string]$CollectionName, [type]$Type) {
    #     $f = $Type::new($Name, $PackagePath)
    #     $this.AddFile($f, $CollectionName)
    #     return $this.GetFile($PackagePath, $CollectionName)
    # }

    # managing files inside the collections
    hidden [void] AddFile ([DBOpsFile[]]$DBOpsFile, [string]$CollectionName) {
        foreach ($file in $DBOpsFile) {
            $file.Parent = $this
            if ($CollectionName -notin $this.PsObject.Properties.Name) {
                $this.ThrowException("$CollectionName is not a valid collection name", 'InvalidArgument')
            }
            foreach ($collectionItem in $this.$CollectionName) {
                if ($collectionItem.PackagePath -eq $file.PackagePath) {
                    $this.ThrowException("File $($file.PackagePath) already exists in $this.$CollectionName.", 'InvalidArgument')
                }
            }
            if (($this.PsObject.Properties | Where-Object Name -eq $CollectionName).TypeNameOfValue -like '*`[`]') {
                $this.$CollectionName += $file
            }
            elseif (($this.PsObject.Properties | Where-Object Name -eq $CollectionName).TypeNameOfValue -like 'System.Collections.Generic.List*') {
                $this.$CollectionName.Add($file)
            }
            else {
                $this.$CollectionName = $file
            }
        }
    }
    hidden [DBOpsFile]GetFile ([string]$PackagePath, [string]$CollectionName) {
        if (!$CollectionName) {
            $this.ThrowException("No collection name provided", 'InvalidArgument')
        }
        if (!$PackagePath) {
            $this.ThrowException('No path provided', 'InvalidArgument')
        }
        return $this.$CollectionName | Where-Object { $_.PackagePath -eq $PackagePath }
    }
    hidden [void] RemoveFile ([string[]]$PackagePath, [string]$CollectionName) {
        if ($this.$CollectionName) {
            foreach ($path in $PackagePath) {
                $this.RemoveFile($this.$CollectionName.GetFile($path, $CollectionName), $CollectionName)
            }
        }
    }
    hidden [void] RemoveFile ([DBOpsFile[]]$DBOpsFile, [string]$CollectionName) {
        if ($this.$CollectionName) {
            foreach ($file in $DBOpsFile) {
                if (($this.PsObject.Properties | Where-Object Name -eq $CollectionName).TypeNameOfValue -like 'System.Collections.Generic.List*') {
                    $null = $this.$CollectionName.Remove($file)
                }
                else {
                    $this.$CollectionName = $this.$CollectionName | Where-Object { $_.PackagePath -ne $file.PackagePath }
                }

            }
        }
    }
    hidden [void] UpdateFile ([DBOpsFile[]]$DBOpsFile, [string]$CollectionName) {
        foreach ($file in $DBOpsFile) {
            $this.RemoveFile($file.PackagePath, $CollectionName)
            $this.AddFile($file, $CollectionName)
        }
    }
}

############################
# DBOpsPackageBase class #
############################

class DBOpsPackageBase : DBOps {
    #Public properties
    [System.Collections.Generic.List[DBOpsBuild]]$Builds
    [string]$ScriptDirectory
    [DBOpsFile]$DeployFile
    [DBOpsFile]$PostDeployFile
    [DBOpsFile]$PreDeployFile
    [DBOpsFile]$ConfigurationFile
    [DBOpsConfig]$Configuration
    [string]$Version
    [System.Version]$ModuleVersion

    #Regular file properties
    [string]$PSPath
    [string]$PSParentPath
    [string]$PSChildName
    [string]$PSDrive
    [bool]$PSIsContainer
    [string]$Mode
    [string]$BaseName
    [string]$Name
    [int]$Length
    [string]$DirectoryName
    [System.IO.DirectoryInfo]$Directory
    [bool]$IsReadOnly
    [bool]$Exists
    [string]$FullName
    [string]$Extension
    [datetime]$CreationTime
    [datetime]$CreationTimeUtc
    [datetime]$LastAccessTime
    [datetime]$LastAccessTimeUtc
    [datetime]$LastWriteTime
    [datetime]$LastWriteTimeUtc
    [System.IO.FileAttributes]$Attributes

    #hidden properties
    hidden [string]$FileName
    hidden [string]$PackagePath
    hidden [array]$PropertiesToExport = @('ScriptDirectory', 'DeployFile', 'PreDeployFile', 'PostDeployFile', 'ConfigurationFile', 'Builds')

    DBOpsPackageBase () {
        $this.Builds = [System.Collections.Generic.List[DBOpsBuild]]::new()
    }

    #Methods
    [void] Init () {
        $this.ScriptDirectory = 'content'
        $this.Configuration = [DBOpsConfig]::new()
        $this.Configuration.Parent = $this
        $this.PackagePath = ""
    }
    [void] Init ([object]$jsonObject) {
        $this.Init()
        if ($jsonObject) {
            $this.ScriptDirectory = $jsonObject.ScriptDirectory
        }
    }
    [void] RefreshFileProperties() {
        if ($this.FileName) {
            $FileObject = Get-Item -LiteralPath $this.FileName -ErrorAction Stop
            $this.PSPath = $FileObject.PSPath.ToString()
            $this.PSParentPath = $FileObject.PSParentPath.ToString()
            $this.PSChildName = $FileObject.PSChildName.ToString()
            $this.PSDrive = $FileObject.PSDrive.ToString()
            $this.PSIsContainer = $FileObject.PSIsContainer
            $this.Mode = $FileObject.Mode
            $this.BaseName = $FileObject.BaseName
            $this.Name = $FileObject.Name
            $this.Length = $FileObject.Length
            $this.DirectoryName = $FileObject.DirectoryName
            if ($FileObject.Directory) {
                $this.Directory = $FileObject.Directory.ToString()
            }
            $this.IsReadOnly = $FileObject.IsReadOnly
            $this.Exists = $FileObject.Exists
            $this.FullName = $FileObject.FullName
            $this.Extension = $FileObject.Extension
            $this.CreationTime = $FileObject.CreationTime
            $this.CreationTimeUtc = $FileObject.CreationTimeUtc
            $this.LastAccessTime = $FileObject.LastAccessTime
            $this.LastAccessTimeUtc = $FileObject.LastAccessTimeUtc
            $this.LastWriteTime = $FileObject.LastWriteTime
            $this.LastWriteTimeUtc = $FileObject.LastWriteTimeUtc
            $this.Attributes = $FileObject.Attributes

            # Also refresh DBOps module version from the archive
            $this.RefreshModuleVersion()
        }
    }
    [DBOpsBuild[]] GetBuilds () {
        return $this.Builds
    }
    [DBOpsBuild] NewBuild ([string]$build) {
        if (!$build) {
            $this.ThrowException('Build name is not specified.', 'InvalidArgument')
            return $null
        }
        if ($this.builds | Where-Object { $_.build -eq $build }) {
            $this.ThrowException("Build $build already exists.", 'InvalidArgument')
            return $null
        }
        else {
            $newBuild = [DBOpsBuild]::new($build)
            $newBuild.Parent = $this
            $this.builds.Add($newBuild)
            $this.Version = $newBuild.Build
            return $newBuild
        }
    }

    [array] EnumBuilds () {
        return $this.builds.build
    }
    [string] GetVersion () {
        return $this.Version
    }

    [System.Collections.Generic.List[DBOpsBuild]] GetBuild ([string[]]$build) {
        if ($currentBuild = $this.builds | Where-Object { $_.build -in $build }) {
            return $currentBuild
        }
        else {
            return [System.Collections.Generic.List[DBOpsBuild]]::new()
        }
    }
    [void] AddBuild ([DBOpsBuild]$build) {
        if ($this.builds | Where-Object { $_.build -eq $build.build }) {
            $this.ThrowException("Build $build already exists.", 'InvalidArgument')
        }
        else {
            $build.Parent = $this
            $this.builds.Add($build)
            $this.Version = $build.Build
        }
    }

    [void] RemoveBuild ([System.Collections.Generic.List[DBOpsBuild]]$build) {
        foreach ($buildItem in $build) {
            $this.builds.Remove($buildItem)
        }
        if ($this.Builds.Count -gt 0) {
            $this.Version = $this.Builds[-1].Build
        }
        else {
            $this.Version = [NullString]::Value
        }
    }
    [void] RemoveBuild ([string[]]$build) {
        $this.RemoveBuild($this.GetBuild($build))
    }
    [bool] ScriptExists([string]$fileName) {
        if (!(Test-Path $fileName)) {
            $this.ThrowException("Path not found: $fileName", 'InvalidArgument')
        }
        $hash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash([DBOpsHelper]::GetBinaryFile($fileName)))
        foreach ($build in $this.builds) {
            if ($build.HashExists($hash)) {
                return $true
            }
        }
        return $false
    }
    [bool] ScriptModified([string]$fileName, [string]$sourcePath) {
        if (!(Test-Path $fileName)) {
            $this.ThrowException("Path not found: $fileName", 'InvalidArgument')
        }
        $hash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash([DBOpsHelper]::GetBinaryFile($fileName)))
        foreach ($build in $this.builds) {
            if ($build.SourcePathExists($sourcePath)) {
                if (!$build.HashExists($hash, $sourcePath)) {
                    return $true
                }
                break
            }
        }
        return $false
    }
    [bool] SourcePathExists([string]$path) {
        foreach ($build in $this.builds) {
            if ($build.SourcePathExists($path)) {
                return $true
            }
        }
        return $false
    }
    # [bool] PackagePathExists([string]$PackagePath) {
    # 	foreach ($build in $this.builds) {
    # 		if ($build.PackagePathExists($PackagePath)) {
    # 			return $true
    # 		}
    # 	}
    # 	return $false
    # }
    # [bool] PackagePathExists([string]$fileName, [int]$Depth) {
    # 	foreach ($build in $this.builds) {
    # 		if ($build.PackagePathExists($fileName, $Depth)) {
    # 			return $true
    # 		}
    # 	}
    # 	return $false
    # }
    [string] ExportToJson() {
        $exportObject = @{} | Select-Object -Property $this.PropertiesToExport
        foreach ($type in $exportObject.psobject.Properties.name) {
            $property = $this.PsObject.Properties | Where-Object Name -eq $type
            if ($this.$type -is [DBOps]) {
                $exportObject.$type = $this.$type.ExportToJson() | ConvertFrom-Json
            }
            elseif ($property.TypeNameOfValue -like '*`[`]' -or $property.TypeNameOfValue -like 'System.Collections.Generic.List*') {
                $collection = @()
                foreach ($collectionItem in $this.$type) {
                    if ($collectionItem -is [DBOps]) {
                        $collection += $collectionItem.ExportToJson() | ConvertFrom-Json
                    }
                    else {
                        $collection += $collectionItem
                    }
                }
                $exportObject.$type = $collection
            }
            else {
                $exportObject.$type = $this.$type
            }

        }
        return $exportObject | ConvertTo-Json -Depth 4
    }
    hidden [void] SavePackageFile([ZipArchive]$zipFile) {
        $pkgFileContent = [Text.Encoding]::ASCII.GetBytes($this.ExportToJson())
        [DBOpsHelper]::WriteZipFile($zipFile, ([DBOpsConfig]::GetPackageFileName()), $pkgFileContent)
    }
    [void] Alter() {
        $this.SaveToFile($this.FileName, $true)
    }
    [void] Save() {
        $this.SaveToFile($this.FileName, $true)
    }
    [void] SaveToFile([string]$fileName) {
        $this.SaveToFile($fileName, $false)
    }
    [void] SaveToFile([string]$fileName, [bool]$force) {
        $parentFolder = Split-Path $fileName -Parent
        if (!$parentFolder) {
            $parentFolder = (Get-Location).Path
        }
        else {
            $parentFolder = (Get-Item -LiteralPath $parentFolder -ErrorAction Stop).FullName
        }
        $currentFileName = Join-Path $parentFolder (Split-Path $filename -Leaf)
        #Open new file stream
        $writeMode = switch ($force) {
            $true { [System.IO.FileMode]::Create }
            default { [System.IO.FileMode]::CreateNew }
        }
        $stream = $null
        try {
            $stream = [FileStream]::new($currentFileName, $writeMode)
        }
        catch {
            $this.ThrowException("Failed to open filestream to $currentFileName with mode $writeMode", $_)
        }
        try {
            #Create zip file
            $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Create)
            try {
                #Change package file name in the object if it wasn't set before
                if (!$this.FileName) {
                    $this.FileName = $currentFileName
                }
                #Write package file
                $this.SavePackageFile($zip)
                #Write files
                foreach ($type in @('DeployFile', 'PreDeployFile', 'PostDeployFile', 'Builds')) {
                    foreach ($collectionItem in $this.$type) {
                        $collectionItem.Save($zip)
                    }
                }

                #Write configs
                $this.Configuration.Save($zip)

                #Write module
                $this.SaveModuleToFile($zip)
            }
            catch { throw $_ }
            finally { $zip.Dispose() }
        }
        catch {
            $this.ThrowException("Failed to complete the deflate operation against archive $currentFileName", $_)
        }
        finally { $stream.Dispose() }

        # Setting regular file properties
        $this.RefreshFileProperties()
    }

    hidden [void] SaveModuleToFile([ZipArchive]$zipArchive) {
        foreach ($file in (Get-DBOModuleFileList)) {
            [DBOpsHelper]::WriteZipFile($zipArchive, (Join-PSFPath -Normalize "Modules\dbops" $file.Path), [DBOpsHelper]::GetBinaryFile($file.FullName))
        }
    }
    #Returns root folder
    [string] GetPackagePath() {
        return ""
    }
    #Returns root folder
    [string] GetDeploymentPath() {
        return ""
    }
    #Returns content folder for scripts
    [string] GetContentPath() {
        return $this.ScriptDirectory
    }

    #Refresh module version from the module file inside the package
    [void] RefreshModuleVersion() {
        if ($this.FileName) {
            $manifestPackagePath = Join-PSFPath -Normalize 'Modules\dbops\dbops.psd1'
            $contents = ([DBOpsHelper]::GetArchiveItem($this.FileName, $manifestPackagePath)).ByteArray
            $scriptBlock = [scriptblock]::Create([DBOpsHelper]::DecodeBinaryText($contents))
            $moduleFile = Invoke-Command -ScriptBlock $scriptBlock
            $this.ModuleVersion = [System.Version]$moduleFile.ModuleVersion
        }
    }

    #Standard ToString() method
    [string] ToString () {
        if ($this.FullName) {
            return $this.FullName
        }
        else {
            return "[DBOpsPackage]"
        }
    }

    #Sets package configuration
    [void] SetConfiguration([DBOpsConfig]$config) {
        $this.Configuration = $config
        $config.Parent = $this
    }

    #Read json and adjust paths appropriately to the environment (Win/Linux)
    [object] ReadMetadata([string]$jsonString) {
        $jsonObject = ConvertFrom-Json $jsonString -ErrorAction Stop
        foreach ($build in $jsonObject.Builds) {
            foreach ($script in $build.Scripts) {
                $script.PackagePath = Join-PSFPath -Normalize $script.PackagePath
            }
        }
        return $jsonObject
    }
}
########################
# DBOpsPackage class #
########################

# Supports creating a package object from a zip file, working around a shared default constructor in a base class

class DBOpsPackage : DBOpsPackageBase {
    #Constructors
    DBOpsPackage () {

        $this.Init()
        # Processing deploy file
        $file = [DBOpsConfig]::GetDeployFile()
        # Adding root deploy file
        $deployFileObject = Get-Item $file.FullName -ErrorAction Stop
        $this.AddFile([DBOpsFile]::new($deployFileObject, $file.FullName, $file.Name), 'DeployFile')
        # Adding configuration file default contents
        $configFile = [DBOpsFile]::new([DBOpsConfig]::GetConfigurationFileName())
        $configContent = [Text.Encoding]::ASCII.GetBytes($this.Configuration.ExportToJson())
        $configFile.SetContent($configContent)
        $this.AddFile($configFile, 'ConfigurationFile')
    }

    DBOpsPackage ([string]$fileName) {

        if (!(Test-Path $fileName -PathType Leaf)) {
            throw "File $fileName not found. Aborting."
        }
        $this.FileName = $fileName
        # Setting regular file properties
        $this.RefreshFileProperties()
        # Reading zip file contents into memory
        $zip = [Zipfile]::OpenRead($fileName)
        try {
            # Processing package file
            $pkgFile = $zip.Entries | Where-Object FullName -eq ([DBOpsConfig]::GetPackageFileName())
            if ($pkgFile) {
                $pkgFileBin = [DBOpsHelper]::ReadDeflateStream($pkgFile.Open()).ToArray()
                $jsonObject = $this.ReadMetadata([DBOpsHelper]::DecodeBinaryText($pkgFileBin))
                $this.Init($jsonObject)
                # Processing builds
                foreach ($build in $jsonObject.builds) {
                    $newBuild = $this.NewBuild($build.build)
                    foreach ($script in $build.Scripts) {
                        $filePackagePath = Join-Path $newBuild.GetPackagePath() $script.packagePath
                        $scriptFile = $zip.Entries | Where-Object { (Join-PSFPath -Normalize $_.FullName) -eq $filePackagePath }
                        if (!$scriptFile) {
                            $this.ThrowException("File not found inside the package: $filePackagePath", 'InvalidArgument')
                        }
                        $newScript = [DBOpsFile]::new($scriptFile, $script.SourcePath, $script.PackagePath, $script.Hash)
                        $newBuild.AddScript($newScript, $true)
                    }
                }
                # Processing root files
                foreach ($file in @('DeployFile', 'PreDeployFile', 'PostDeployFile', 'ConfigurationFile')) {
                    $jsonFileObject = $jsonObject.$file
                    if ($jsonFileObject) {
                        $zipFileEntry = $zip.Entries | Where-Object { (Join-PSFPath -Normalize $_.FullName) -eq $jsonFileObject.packagePath }
                        if ($zipFileEntry) {
                            $newFile = [DBOpsFile]::new($zipFileEntry, $jsonFileObject.SourcePath, $jsonFileObject.PackagePath)
                            $this.AddFile($newFile, $file)
                        }
                        else {
                            $this.ThrowException("File $($jsonFileObject.packagePath) not found in the package", 'InvalidData')
                        }
                    }
                }
            }
            else {
                $this.ThrowException("Incorrect package format: $fileName", 'InvalidArgument')
            }

            # Processing configuration file
            if ($this.ConfigurationFile) {
                $this.Configuration = [DBOpsConfig]::new($this.ConfigurationFile.GetContent())
                $this.Configuration.Parent = $this
            }
        }
        catch {
            $this.ThrowException("Failed to complete the deflate operation against archive $fileName", $_)
        }
        finally {
            # Dispose of the reader
            $zip.Dispose()
        }
    }

}

############################
# DBOpsPackageFile class #
############################

# Supports creating a package object from an extracted zip - basically from a json file
class DBOpsPackageFile : DBOpsPackageBase {

    #Apparently, inheriting a class will run a default constructor anyways, DBOpsPackageBase is a new class that has no constructor

    DBOpsPackageFile ([string]$fileName) {
        if (!(Test-Path $fileName -PathType Leaf)) {
            $this.ThrowException($fileName, "File $fileName not found. Aborting.", 'ObjectNotFound')
        }
        # Processing package file
        $pkgFileBin = [DBOpsHelper]::GetBinaryFile($fileName)
        if ($pkgFileBin) {
            $jsonObject = $this.ReadMetadata([DBOpsHelper]::DecodeBinaryText($pkgFileBin))
            $this.Init($jsonObject)
            #Defining package path as a parent folder of the package file
            $folderPath = Split-Path $fileName -Parent
            $this.FileName = $folderPath
            # Setting regular file properties
            $this.RefreshFileProperties()

            $this.PackagePath = $folderPath
            # Processing builds
            foreach ($build in $jsonObject.builds) {
                $newBuild = $this.NewBuild($build.build)
                foreach ($script in $build.Scripts) {
                    $contentPath = Join-Path $folderPath $newBuild.GetPackagePath()
                    $filePackagePath = Join-Path $contentPath $script.packagePath
                    if (!(Test-Path $filePackagePath)) {
                        $this.ThrowException("File not found inside the package: $filePackagePath", 'InvalidArgument')
                    }
                    $fileObject = Get-Item -LiteralPath $filePackagePath -ErrorAction Stop
                    $newScript = [DBOpsFile]::new($fileObject, $script.SourcePath, $script.PackagePath, $script.Hash)
                    $newBuild.AddScript($newScript, $true)
                }
            }
            # Processing root files
            foreach ($fileType in @('DeployFile', 'PreDeployFile', 'PostDeployFile', 'ConfigurationFile')) {
                $jsonFileObject = $jsonObject.$fileType
                if ($jsonFileObject) {
                    $filePackagePath = Join-Path $folderPath $jsonFileObject.packagePath
                    if (!(Test-Path $filePackagePath)) {
                        $this.ThrowException("File not found inside the package: $filePackagePath", 'InvalidArgument')
                    }
                    $fileObject = Get-Item -LiteralPath $filePackagePath -ErrorAction Stop
                    $newFile = [DBOpsFile]::new($fileObject, $jsonFileObject.SourcePath, $jsonFileObject.PackagePath)
                    $this.AddFile($newFile, $fileType)
                }
            }
        }
        else {
            $this.ThrowException("Incorrect package format: $fileName", 'InvalidArgument')
        }

        # Processing configuration file
        if ($this.ConfigurationFile) {
            $this.Configuration = [DBOpsConfig]::new($this.ConfigurationFile.GetContent())
            $this.Configuration.Parent = $this
        }

    }

    #overloads to prefent unpacked packages from being saved
    [void] Alter() {
        $this.ThrowException("Unpacked package cannot be saved without compressing it first. Use SaveToFile('myfile') instead.", 'InvalidArgument')
    }
    [void] Save() {
        $this.Alter()
    }

    #Overload to read module file from the folder
    [void] RefreshModuleVersion() {
        if ($this.FileName) {
            $manifestPackagePath = Join-PSFPath -Normalize $this.FileName 'Modules\dbops\dbops.psd1'
            $contents = ([DBOpsHelper]::GetBinaryFile($manifestPackagePath))
            $scriptBlock = [scriptblock]::Create([DBOpsHelper]::DecodeBinaryText($contents))
            $moduleFile = Invoke-Command -ScriptBlock $scriptBlock
            $this.ModuleVersion = [System.Version]$moduleFile.ModuleVersion
        }
    }

}

######################
# DBOpsBuild class #
######################

class DBOpsBuild : DBOps {
    #Public properties
    [string]$Build
    [System.Collections.Generic.List[DBOpsFile]]$Scripts
    [string]$CreatedDate

    hidden [DBOpsPackageBase]$Parent
    hidden [string]$PackagePath
    hidden [array]$PropertiesToExport = @('Build', 'CreatedDate', 'PackagePath')

    #Constructors
    DBOpsBuild ([string]$build) {
        if (!$build) {
            $this.ThrowException('Build name cannot be empty', 'InvalidArgument');
        }
        $this.Build = $build
        $this.PackagePath = $build
        $this.CreatedDate = (Get-Date).Datetime
        $this.Scripts = [System.Collections.Generic.List[DBOpsFile]]::new()
    }

    hidden DBOpsBuild ([psobject]$object) {
        if (!$object.Build) {
            $this.ThrowException('Build name cannot be empty', 'InvalidArgument');
        }
        $this.Build = $object.Build
        $this.PackagePath = $object.PackagePath
        $this.CreatedDate = $object.CreatedDate
    }

    #Methods
    #Creates a new script and returns it as an object
    # [DBOpsFile[]] NewScript ([object[]]$FileObject) {
    #     [DBOpsFile[]]$output = @()
    #     foreach ($p in $FileObject) {
    #         if ($p.Depth) {
    #             $depth = $p.Depth
    #         }
    #         else {
    #             $depth = 0
    #         }
    #         if ($p.SourcePath) {
    #             $sourcePath = $p.SourcePath
    #         }
    #         else {
    #             $sourcePath = $p.FullName
    #         }
    #         $relativePath = [DBOpsHelper]::SplitRelativePath($sourcePath, $depth)
    #         $file = [DBOpsFile]::new()
    #         $output += $this.NewFile($sourcePath, $relativePath, 'Scripts', [DBOpsScriptFile])
    #     }
    #     return $output
    # }
    # [DBOpsFile] NewScript ([string]$FileName, [int]$Depth) {
    #     $relativePath = [DBOpsHelper]::SplitRelativePath($FileName, $Depth)
    #     if ($this.SourcePathExists($relativePath)) {
    #         $this.ThrowException("External script $($relativePath) already exists.", 'InvalidArgument')
    #     }
    #     return $this.NewFile($FileName, $relativePath, 'Scripts', [DBOpsScriptFile])
    # }
    # Adds script to the current build
    [void] AddScript ([DBOpsFile[]]$script) {
        $this.AddScript($script, $false)
    }
    [void] AddScript ([DBOpsFile[]]$script, [bool]$Force) {
        foreach ($s in $script) {
            if (!$Force -and $this.SourcePathExists($s.SourcePath)) {
                $this.ThrowException("External script $($s.SourcePath) already exists.", 'InvalidArgument')
            }
            else {
                $this.AddFile($s, 'Scripts')
            }
        }
    }
    [string] ToString() {
        return "[$($this.build)]"
    }
    #Searches for a certain hash value within the build
    hidden [bool] HashExists([string]$hash) {
        foreach ($script in $this.Scripts) {
            if ($hash -eq $script.hash) {
                return $true
            }
        }
        return $false
    }
    #Searches for a certain hash value within the build for a specific source file
    hidden [bool] HashExists([string]$hash, [string]$sourcePath) {
        foreach ($script in $this.Scripts) {
            if ($script.SourcePath -eq $sourcePath -and $hash -eq $script.hash) {
                return $true
            }
        }
        return $false
    }
    #Compares file hash and returns true if such has has been found within the build
    [bool] ScriptExists([string]$fileName) {
        if (!(Test-Path $fileName)) {
            $this.ThrowException("Path not found: $fileName", 'InvalidArgument')
        }
        $fileObject = Get-Item $fileName -ErrorAction Stop
        $hash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash([DBOpsHelper]::GetBinaryFile($fileObject.FullName)))
        return $this.HashExists($hash)
    }
    #Returns true if the file was modified since it last has been added to the build
    [bool] ScriptModified([string]$fileName, [string]$sourcePath) {
        if (!(Test-Path $fileName)) {
            $this.ThrowException("Path not found: $fileName", 'InvalidArgument')
        }
        $fileObject = Get-Item $fileName -ErrorAction Stop
        if ($this.SourcePathExists($sourcePath)) {
            $hash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash([DBOpsHelper]::GetBinaryFile($fileObject.FullName)))
            return -not $this.HashExists($hash, $sourcePath)
        }
        else {
            return $false
        }
    }
    #Verify if the file has already been added to the build
    [bool] SourcePathExists([string]$path) {
        foreach ($script in $this.Scripts) {
            if ($path -eq $script.sourcePath) {
                return $true
            }
        }
        return $false
    }
    #Verify if Package Path is already used by a different file
    [bool] PackagePathExists([string]$PackagePath) {
        foreach ($script in $this.Scripts) {
            if ($PackagePath -eq $script.PackagePath) {
                return $true
            }
        }
        return $false
    }
    #Get absolute path inside the package
    [string] GetPackagePath() {
        if ($this.Parent) {
            return Join-PSFPath $this.Parent.GetContentPath() $this.PackagePath
        }
        else {
            return $this.PackagePath
        }
    }
    #Get deployment path
    [string] GetDeploymentPath() {
        return $this.PackagePath
    }
    #Exports object to Json in the format in which it will be stored in the package file
    [string] ExportToJson() {
        $scriptCollection = @()
        foreach ($script in $this.Scripts) {
            $scriptCollection += $script.ExportToJson() | ConvertFrom-Json
        }
        $output = $this | Select-Object -Property $this.PropertiesToExport
        $output | Add-Member -MemberType NoteProperty -Name Scripts -Value $scriptCollection
        return $output | ConvertTo-Json -Depth 2
    }
    #Writes current build into the archive file
    hidden [void] Save([ZipArchive]$zipFile) {
        foreach ($script in $this.Scripts) {
            $script.Save($zipFile)
        }
    }
    #Alter build - includes module updates and scripts
    [void] Alter() {
        # check if parent exists
        if (-not $this.Parent) {
            $this.ThrowException("Parent of $this has not been defined", 'InvalidOperation')
        }
        #Open new file stream
        $writeMode = [System.IO.FileMode]::Open
        $stream = $null
        try {
            $stream = [FileStream]::new($this.Parent.FileName, $writeMode)
        }
        catch {
            $this.ThrowException("Failed to open filestream to $($this.Parent.FileName) with mode $writeMode", $_)
        }

        try {
            #Open zip file
            $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
            try {
                #Write package file
                $this.Parent.SavePackageFile($zip)
                #Write builds
                $this.Save($zip)
                #Write module
                $this.Parent.SaveModuleToFile($zip)
            }
            catch { throw $_ }
            finally { $zip.Dispose() }
        }
        catch {
            $this.ThrowException("Failed to modify archive $($this.Parent.FileName)", $_)
        }
        finally { $stream.Dispose()	}

        # Refreshing regular file properties for parent object
        $this.Parent.RefreshFileProperties()
    }
}

####################
# DBOpsFile class #
####################
class DBOpsFile : DBOps {
    #Public properties
    [string]$SourcePath
    [string]$PackagePath
    [string]$FullName
    [int]$Length
    [string]$Name
    [string]$LastWriteTime
    [byte[]]$ByteArray

    #Hidden properties
    hidden [string]$Hash
    hidden [bool]$Protected
    hidden [DBOps]$Parent
    hidden [array]$PropertiesToExport = @('PackagePath')

    #Constructors
    DBOpsFile ([string]$packagePath) {
        $this.Init($null, $packagePath)
        $this.Protected = $false
    }
    DBOpsFile ([System.IO.FileInfo]$file, [string]$sourcePath, [string]$packagePath) {
        #Set properties imported from package file
        $this.Init($sourcePath, $packagePath)
        $this.Protected = $false
        $this.InitFile($file)
    }
    DBOpsFile ([System.IO.FileInfo]$file, [string]$sourcePath, [string]$packagePath, [bool]$hashProtected) {
        #Set properties imported from package file
        $this.Init($sourcePath, $packagePath)
        $this.Protected = $hashProtected
        $this.InitFile($file)
    }
    DBOpsFile ([System.IO.FileInfo]$file, [string]$sourcePath, [string]$packagePath, [string]$hash) {
        #Set properties imported from package file
        $this.Init($sourcePath, $packagePath)
        $this.Protected = $true
        # read the file
        $this.InitFile($file)
        # validate the hash
        $this.ValidateHash($hash)
    }
    DBOpsFile ([ZipArchiveEntry]$zipFile, [string]$sourcePath, [string]$packagePath) {
        #Set properties imported from package file
        $this.Init($sourcePath, $packagePath)
        $this.Protected = $false
        #Set properties from Zip archive
        $this.InitZipFile($zipFile)
    }
    DBOpsFile ([ZipArchiveEntry]$zipFile, [string]$sourcePath, [string]$packagePath, [string]$hash) {
        #Set properties imported from package file
        $this.Init($sourcePath, $packagePath)
        $this.Protected = $true
        #Set properties from Zip archive
        $this.InitZipFile($zipFile)
        $this.ValidateHash($hash)
    }

    #Methods
    [void] Init ([string]$sourcePath, [string]$packagePath) {
        if (!$packagePath) {
            $this.ThrowException('Path inside the package cannot be empty', 'InvalidArgument')
        }
        if ($sourcePath) {
            $this.SourcePath = $sourcePath
            if ('SourcePath' -notin $this.PropertiesToExport) {
                $this.PropertiesToExport += 'SourcePath'
            }
        }
        $this.PackagePath = $packagePath
    }
    [void] InitFile ([System.IO.FileInfo]$file) {
        #Set properties from the file
        $this.Name = $file.Name
        $this.FullName = $file.FullName
        $this.LastWriteTime = $file.LastWriteTime
        # set contents
        $this.SetContent([DBOpsHelper]::GetBinaryFile($file.FullName))
    }
    [void] InitZipFile ([ZipArchiveEntry]$zipFile) {
        #Set properties from Zip archive
        $this.Name = $zipFile.Name
        $this.LastWriteTime = $zipFile.LastWriteTime

        #Read deflate stream and set other properties
        $stream = [DBOpsHelper]::ReadDeflateStream($zipFile.Open())
        try {
            $this.SetContent($stream.ToArray())
        }
        catch {
            $this.ThrowException("Failed to read deflate stream from $($zipFile.Name)", $_)
        }
        finally {
            $stream.Dispose()
        }
    }
    [string] ToString() {
        return "$($this.PackagePath)"
    }
    [string] GetContent() {
        return [DBOpsHelper]::DecodeBinaryText($this.ByteArray)
    }
    [string] GetPackagePath() {
        $pPath = $this.PackagePath
        if ($this.Parent) {
            if ($parentPath = $this.Parent.GetPackagePath()) {
                $pPath = Join-Path $this.Parent.GetPackagePath() $pPath
            }
        }
        return $pPath
    }
    [string] GetDeploymentPath () {
        $dPath = $this.PackagePath
        if ($this.Parent) {
            if ($parentPath = $this.Parent.GetDeploymentPath()) {
                $dPath = Join-Path $this.Parent.GetDeploymentPath() $dPath
            }
        }
        # always use backslashes during deployments regardless of the OS
        return $dPath.Replace('/', '\')
    }
    [string] ExportToJson() {
        return $this | Select-Object -Property $this.PropertiesToExport | ConvertTo-Json -Depth 1
    }
    #Writes current script into the archive file
    [void] Save([ZipArchive]$zipFile) {
        [DBOpsHelper]::WriteZipFile($zipFile, $this.GetPackagePath(), $this.ByteArray)
    }
    #Updates package content
    [void] SetContent([byte[]]$Array) {
        $this.ByteArray = $Array
        $this.Length = $Array.Length
        if ($this.Protected) {
            # calculate the hash
            $this.RebuildHash()
            # mark Hash as exportable property
            if ('Hash' -notin $this.PropertiesToExport) {
                $this.PropertiesToExport += 'Hash'
            }
        }
    }
    #Recalculates Hash
    [void] RebuildHash() {
        if ($this.Length -gt 0) {
            $this.Hash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash($this.ByteArray))
        }
    }
    #Verify that hash is valid
    [void] ValidateHash([string]$hash) {
        if ($this.hash -ne $hash) {
            $this.ThrowException("File cannot be loaded, hash mismatch: $($this.Name)", 'InvalidArgument')
        }
    }
    #Initiates package update saving the current file in the package
    [void] Alter() {
        #Open new file stream
        $writeMode = [System.IO.FileMode]::Open
        if ($this.Parent -is [DBOpsBuild]) {
            $pkgObj = $this.Parent.Parent
        }
        elseif ($this.Parent -is [DBOpsPackage]) {
            $pkgObj = $this.Parent
        }
        else {
            $pkgObj = $null
        }
        $stream = $null
        try {
            $stream = [FileStream]::new($pkgObj.FileName, $writeMode, [System.IO.FileAccess]::ReadWrite)
        }
        catch {
            $this.ThrowException("Failed to open filestream to $($pkgObj.FileName) with mode ReadWrite", $_)
        }
        try {
            #Open zip file
            $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
            try {
                #Write file
                $this.Save($zip)
                #Update package file
                $pkgObj.SavePackageFile($zip)
            }
            catch { throw $_ }
            finally { $zip.Dispose() }
        }
        catch {
            $this.ThrowException("Failed to modify archive $($pkgObj.FileName)", $_)
        }
        finally { $stream.Dispose()	}

        # Refreshing regular file properties for parent object
        if ($pkgObj) {
            $pkgObj.RefreshFileProperties()
        }
    }
}

# #####################
# # DBOpsFile class #
# #####################

# class DBOpsFile : DBOps {
#     #Public properties
#     [string]$SourcePath
#     [string]$PackagePath
#     [string]$FullName
#     [int]$Length
#     [string]$Name
#     [string]$LastWriteTime
#     [byte[]]$ByteArray

#     #Hidden properties
#     hidden [string]$Hash
#     hidden [DBOps]$Parent
#     hidden [array]$PropertiesToExport = @('SourcePath', 'Hash', 'PackagePath')

#     #Constructors
#     DBOpsFile () {}
#     DBOpsFile ([string]$SourcePath, [string]$PackagePath) {
#         if (!(Test-Path $SourcePath)) {
#             $this.ThrowException("Path not found: $SourcePath", 'InvalidArgument')
#         }
#         if (!$PackagePath) {
#             $this.ThrowException('Path inside the package cannot be empty', 'InvalidArgument')
#         }
#         $this.SourcePath = $SourcePath
#         $this.PackagePath = $PackagePath
#         $file = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
#         $this.Length = $file.Length
#         $this.Name = $file.Name
#         $this.LastWriteTime = $file.LastWriteTime
#         $this.ByteArray = [DBOpsHelper]::GetBinaryFile($file.FullName)
#     }

#     DBOpsFile ([psobject]$fileDescription) {
#         $this.Init($fileDescription)
#     }

#     DBOpsFile ([psobject]$fileDescription, [ZipArchiveEntry]$file) {
#         #Set properties imported from package file
#         $this.Init($fileDescription)

#         #Set properties from Zip archive
#         $this.Name = $file.Name
#         $this.LastWriteTime = $file.LastWriteTime

#         #Read deflate stream and set other properties
#         $stream = [DBOpsHelper]::ReadDeflateStream($file.Open())
#         try {
#             $this.ByteArray = $stream.ToArray()
#         }
#         catch {
#             Stop-PSFFunction -EnableException $true -Message "Failed to read deflate stream from $($file.Name)" -ErrorRecord $_ -FunctionName $this.GetType().Name
#         }
#         finally {
#             $stream.Dispose()
#         }

#         $this.Length = $this.ByteArray.Length
#     }
#     DBOpsFile ([System.IO.FileInfo]$file, [string]$sourcePath, [string]$packagePath) {
#         #Set properties imported from package file
#         $this.Init(@{
#                 SourcePath  = $sourcePath
#                 PackagePath = $packagePath
#             })
#         $this.InitFile($file)
#     }
#     DBOpsFile ([psobject]$fileDescription, [System.IO.FileInfo]$file) {
#         #Set properties imported from package file
#         $this.Init($fileDescription)
#         $this.InitFile($file)
#     }

#     #Methods
#     [void] Init ([psobject]$fileDescription) {
#         if (!$fileDescription.PackagePath) {
#             $this.ThrowException('Path inside the package cannot be empty', 'InvalidArgument')
#         }
#         $this.SourcePath = $fileDescription.SourcePath
#         $this.PackagePath = $fileDescription.PackagePath
#     }
#     [void] InitFile ([System.IO.FileInfo]$file) {
#         #Set properties from the file
#         $this.Name = $file.Name
#         $this.FullName = $file.FullName
#         $this.LastWriteTime = $file.LastWriteTime

#         $this.ByteArray = [DBOpsHelper]::GetBinaryFile($file.FullName)
#         $this.Length = $this.ByteArray.Length
#     }

#     [string] ToString() {
#         return "$($this.PackagePath)"
#     }
#     [string] GetContent() {
#         return [DBOpsHelper]::DecodeBinaryText($this.ByteArray)
#     }
#     [string] GetPackagePath() {
#         return Join-Path $this.Parent.GetPackagePath() $this.PackagePath
#     }
#     [string] ExportToJson() {
#         return $this | Select-Object -Property $this.PropertiesToExport | ConvertTo-Json -Depth 1
#     }
#     #Writes current script into the archive file
#     [void] Save([ZipArchive]$zipFile) {
#         [DBOpsHelper]::WriteZipFile($zipFile, $this.GetPackagePath(), $this.ByteArray)
#     }
#     #Updates package content
#     [void] SetContent([byte[]]$Array) {
#         $this.ByteArray = $Array
#     }
#     #Initiates package update saving the current file in the package
#     [void] Alter() {
#         #Open new file stream
#         $writeMode = [System.IO.FileMode]::Open
#         if ($this.Parent -is [DBOpsBuild]) {
#             $pkgObj = $this.Parent.Parent
#         }
#         elseif ($this.Parent -is [DBOpsPackage]) {
#             $pkgObj = $this.Parent
#         }
#         else {
#             $pkgObj = $null
#         }
#         $stream = $null
#         try {
#             $stream = [FileStream]::new($pkgObj.FileName, $writeMode, [System.IO.FileAccess]::ReadWrite)
#         }
#         catch {
#             Stop-PSFFunction -Message "Failed to open filestream to $($pkgObj.FileName) with mode ReadWrite" -EnableException $true -ErrorRecord $_ -ModuleName dbops -FunctionName $this.GetType().Name
#         }
#         try {
#             #Open zip file
#             $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
#             try {
#                 #Write file
#                 $this.Save($zip)
#                 #Update package file
#                 $pkgObj.SavePackageFile($zip)
#             }
#             catch { throw $_ }
#             finally { $zip.Dispose() }
#         }
#         catch {
#             Stop-PSFFunction -EnableException $true -Message "Failed to modify archive $($pkgObj.FileName)" -ErrorRecord $_ -FunctionName $this.GetType().Name
#         }
#         finally { $stream.Dispose()	}

#         # Refreshing regular file properties for parent object
#         if ($pkgObj) {
#             $pkgObj.RefreshFileProperties()
#         }
#     }
# }


#########################
# DBOpsRootFile class #
#########################

# #Ignores the parent package path

# class DBOpsRootFile : DBOpsFile {
#     #Mirroring base constructors
#     DBOpsRootFile () : base () { }
#     DBOpsRootFile ([string]$SourcePath, [string]$PackagePath) : base($SourcePath, $PackagePath) { }

#     DBOpsRootFile ([psobject]$fileDescription) : base($fileDescription) { }
#     DBOpsRootFile ([System.IO.FileInfo]$file, [string]$sourcePath, [string]$packagePath) : base($file, $sourcePath, $packagePath) { }

#     DBOpsRootFile ([psobject]$fileDescription, [ZipArchiveEntry]$file) : base($fileDescription, $file) { }

#     DBOpsRootFile ([psobject]$fileDescription, [System.IO.FileInfo]$file) : base($fileDescription, $file) { }

#     #Overloading GetPackagePath to ignore folders of the parent objects
#     [string] GetPackagePath() {
#         return $this.PackagePath
#     }
# }

# ###########################
# # DBOpsScriptFile class #
# ###########################

# #Keeps track of file hash and disallows its creation when hash does not match

# class DBOpsScriptFile : DBOpsFile {
#     #Mirroring base constructors adding Hash control pieces
#     DBOpsScriptFile () : base () { }
#     DBOpsScriptFile ([string]$SourcePath, [string]$PackagePath) : base($SourcePath, $PackagePath) {
#         $file = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
#         $this.Hash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash([DBOpsHelper]::GetBinaryFile($file.FullName)))
#     }

#     DBOpsScriptFile ([psobject]$fileDescription) : base($fileDescription) {
#         $this.Hash = $fileDescription.Hash
#     }

#     DBOpsScriptFile ([psobject]$fileDescription, [ZipArchiveEntry]$file) : base($fileDescription, $file) {
#         $this.Hash = $fileDescription.Hash
#         $fileHash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash($this.ByteArray))
#         # Verify file hash and throw an error if it doesn't match
#         $this.VerifyHash($fileHash)
#     }

#     DBOpsScriptFile ([psobject]$fileDescription, [System.IO.FileInfo]$file) : base($fileDescription, $file) {
#         $this.Hash = $fileDescription.Hash
#         $fileHash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash($this.ByteArray))
#         # Verify file hash and throw an error if it doesn't match
#         $this.VerifyHash($fileHash)
#     }
#     DBOpsScriptFile ([System.IO.FileInfo]$file, [string]$sourcePath, [string]$packagePath) : base($file, $sourcePath, $packagePath) {
#         $this.Hash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash($this.ByteArray))
#     }

#     #Updates file content - overloaded to handle Hashes
#     [void] SetContent([byte[]]$Array) {
#         $this.ByteArray = $Array
#         $this.Hash = [DBOpsHelper]::ToHexString([Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash($Array))
#     }
#     [void] VerifyHash([string]$Hash) {
#         if ($this.Hash -ne $Hash) {
#             $this.ThrowException("File cannot be loaded, hash mismatch: $($this.Name)", 'InvalidArgument')
#         }
#     }
#     [string] GetDeploymentPath () {
#         $dPath = $this.GetPackagePath()
#         #Recursively check parents and remove the top-level folder
#         $lastParent = $this
#         while ($lastParent.Parent) {
#             $lastParent = $lastParent.Parent
#         }
#         $dPath = $dPath -replace ('^' + [regex]::Escape($lastParent.GetPackagePath() + ([IO.Path]::DirectorySeparatorChar))), ''
#         return $dPath.Replace('/', '\')
#     }
# }

#######################
# DBOpsConfig class #
#######################

class DBOpsConfig : DBOps {
    #Properties
    [string]$ApplicationName
    [string]$SqlInstance
    [string]$Database
    [string]$DeploymentMethod
    [System.Nullable[int]]$ConnectionTimeout
    [System.Nullable[int]]$ExecutionTimeout
    [System.Nullable[bool]]$Encrypt
    [pscredential]$Credential
    [string]$Username
    [SecureString]$Password
    [string]$SchemaVersionTable
    [System.Nullable[bool]]$Silent
    [psobject]$Variables
    [string]$Schema
    [System.Nullable[bool]]$CreateDatabase
    [string]$ConnectionString
    [psobject]$ConnectionAttribute

    hidden [DBOpsPackageBase]$Parent

    #Constructors
    DBOpsConfig () {
        $this.Init()
    }
    DBOpsConfig ([string]$jsonString) {
        if (!$jsonString) {
            $this.ThrowException("Input string has not been defined", 'InvalidArgument')
        }
        $this.Init()

        $jsonConfig = $jsonString | ConvertFrom-Json -ErrorAction Stop

        foreach ($property in $jsonConfig.psobject.properties.Name) {
            if ($property -in [DBOpsConfig]::EnumProperties()) {
                $this.SetValue($property, $jsonConfig.$property)
            }
            else {
                $this.ThrowException("$property is not a valid configuration item", 'InvalidArgument')
            }
        }
    }
    #Hidden methods
    hidden [void] Init () {
        #Reading default values from PSF
        foreach ($prop in [DBOpsConfig]::EnumProperties()) {
            $configValue = Get-PSFConfigValue -FullName dbops.$prop
            $this.SetValue($prop, $configValue)
        }
    }

    #Methods
    [hashtable] AsHashtable () {
        $ht = @{}
        foreach ($property in $this.psobject.Properties.Name) {
            $ht += @{ $property = $this.$property }
        }
        return $ht
    }

    [void] SetValue ([string]$Property, [object]$Value) {
        if ([DBOpsConfig]::EnumProperties() -notcontains $Property) {
            $this.ThrowException("$property is not a valid configuration item", 'InvalidArgument')
        }
        #set proper NullString for String properties
        if ($null -eq $Value -and $Property -in ($this.PsObject.Properties | Where-Object TypeNameOfValue -like 'System.String*').Name) {
            $this.$Property = [NullString]::Value
        }
        elseif ($null -ne $Value -and $Property -eq 'Password') {
            if ($Value -is [SecureString]) {
                $this.$Property = $Value
            }
            else {
                $this.$Property = ConvertFrom-EncryptedString -String $Value
            }
        }
        elseif ($null -ne $Value -and $Property -eq 'Credential') {
            if ($Value -is [pscredential]) {
                $this.$Property = $Value
            }
            else {
                $this.$Property = [pscredential]::new($Value.UserName, (ConvertFrom-EncryptedString -String $Value.Password))
            }
        }
        else {
            $this.$Property = $Value
        }
    }
    # Returns a JSON string representin the object
    [string] ExportToJson() {
        $outObject = @{}
        foreach ($prop in [DBOpsConfig]::EnumProperties()) {
            if ($this.$prop -is [securestring]) {
                $outObject += @{ $prop = $this.$prop | ConvertTo-EncryptedString }
            }
            elseif ($this.$prop -is [pscredential]) {
                $outObject += @{
                    $prop = @{
                        UserName = $this.$prop.UserName
                        Password = $this.$prop.Password | ConvertTo-EncryptedString
                    }
                }
            }
            else { $outObject += @{ $prop = $this.$prop }
            }
        }
        return $outObject | ConvertTo-Json -Depth 3
    }
    # Save package to an opened zip file
    [void] Save([ZipArchive]$zipFile) {
        if (-not $this.Parent) {
            $this.ThrowException("Parent of $this has not been defined", 'InvalidOperation')
        }
        $fileContent = [Text.Encoding]::ASCII.GetBytes($this.ExportToJson())
        if ($this.Parent.ConfigurationFile) {
            $filePath = $this.Parent.ConfigurationFile.PackagePath
            $this.Parent.ConfigurationFile.SetContent($fileContent)
        }
        else {
            $filePath = [DBOpsConfig]::GetConfigurationFileName()
            $newFile = [DBOpsFile]::new($filePath)
            $newFile.SetContent($fileContent)
            $this.Parent.AddFile($newFile, 'ConfigurationFile')
        }
        [DBOpsHelper]::WriteZipFile($zipFile, $filePath, $fileContent)
    }
    #Initiates package update saving the configuration file in the package
    [void] Alter() {
        #only do something if it's a part of a package
        if ($this.Parent -is [DBOpsPackageBase]) {
            #Open new file stream
            $writeMode = [System.IO.FileMode]::Open
            $stream = $null
            try {
                $stream = [FileStream]::new($this.Parent.FileName, $writeMode, [System.IO.FileAccess]::ReadWrite)
            }
            catch {
                $this.ThrowException("Failed to open filestream to $($this.Parent.FileName) with mode $writeMode", $_)
            }
            try {
                #Open zip file
                $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
                try {
                    #Write file
                    $this.Save($zip)
                }
                catch { throw $_ }
                finally { $zip.Dispose() }
            }
            catch {
                $this.ThrowException("Failed to modify archive $($this.Parent.FileName)", $_)
            }
            finally { $stream.Dispose()	}

            # Refreshing regular file properties for parent object
            $this.Parent.RefreshFileProperties()
        }
    }
    #Merge two configurations
    [void] Merge([DBOpsConfig]$config) {
        $this.Merge($config.AsHashtable())
    }
    [void] Merge([hashtable]$config) {
        foreach ($key in $config.Keys) {
            if ($key -eq 'Variables') {
                # create new hashtable with all the existing variables
                $hashVar = @{}
                foreach ($variable in $this.Variables.psobject.Properties.Name) {
                    $hashVar += @{
                        $variable = $this.Variables.$variable
                    }
                }
                # now merge in each incoming value
                if ($config.$key) {
                    if ($config.$key -is [hashtable]) { $variableList = $config.$key.Keys }
                    else { $variableList = $config.$key.psobject.Properties.Name }
                    foreach ($variable in $variableList) {
                        $hashVar.$variable = $config.$key.$variable
                    }
                }
                # lastly, convert back to psobject and re-assign
                $this.SetValue($key, ([pscustomobject]$hashVar))
            }
            else {
                $this.SetValue($key, $config.$key)
            }
        }
    }

    #Save configuration to a file
    [void] SaveToFile([string]$fileName) {
        $this.ExportToJson() | Out-File -FilePath $fileName -Encoding unicode
    }

    #Static Methods
    static [DBOpsConfig] FromJsonString ([string]$jsonString) {
        return [DBOpsConfig]::new($jsonString)
    }
    static [DBOpsConfig] FromFile ([string]$path) {
        if (!(Test-Path $path)) {
            Stop-PSFFunction -EnableException $true -Message "Config file $path not found. Aborting." -FunctionName 'DBOps'
        }
        return [DBOpsConfig]::FromJsonString((Get-Content $path -Raw -ErrorAction Stop))
    }

    static [string] GetPackageFileName () {
        return 'dbops.package.json'
    }

    static [string] GetConfigurationFileName () {
        return 'dbops.config.json'
    }

    static [string[]] EnumProperties () {
        return [DBOps.ConfigProperty].GetEnumNames()
    }

    #Returns deploy file name
    static [object]GetDeployFile() {
        return (Get-DBOModuleFileList | Where-Object { $_.Type -eq 'Misc' -and $_.Name -eq "Deploy.ps1"})
    }
}
