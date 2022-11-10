# "Get required modules"
Write-Host -Object "appveyor.prep: Install Pester" -ForegroundColor DarkGreen
Uninstall-Module -Name Pester -Force -AllVersions -ErrorAction SilentlyContinue | Out-Null
Install-Module -Name Pester -Repository PSGallery -Force -Scope CurrentUser -MinimumVersion 5.0 | Out-Null
Write-Host -Object "appveyor.prep: Install Assert" -ForegroundColor DarkGreen
Install-Module -Name Assert -Repository PSGallery -Force -Scope CurrentUser | Out-Null
Write-Host -Object "appveyor.prep: Install PSFramework" -ForegroundColor DarkGreen
Install-Module -Name PSFramework -Repository PSGallery -Force -Scope CurrentUser | Out-Null
Write-Host -Object "appveyor.prep: Install ziphelper" -ForegroundColor DarkGreen
Install-Module -Name ziphelper -Repository PSGallery -Force -Scope CurrentUser | Out-Null
Write-Host -Object "appveyor.prep: Install PSScriptAnalyzer" -ForegroundColor DarkGreen
Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Force -Scope CurrentUser | Out-Null

# Set logging parameters
Set-PSFConfig -FullName psframework.logging.filesystem.maxmessagefilebytes -Value (100 * 1024 * 1024) -PassThru | Register-PSFConfig
Set-PSFConfig -FullName psframework.logging.filesystem.maxtotalfoldersize -Value (500 * 1024 * 1024) -PassThru | Register-PSFConfig
