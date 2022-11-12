# Release notes for v0.8.1:
- ### Wrapper around dotnet call to filter output (#148) by @nvarscar
# Release notes for v0.8.0:
- ### Hotfix: Nuget downloads now use lowercase filename in the URL (#139) by @nvarscar
- ### Feature: Allow ErrorAction to properly handle errors (#140) by @nvarscar
- ### Setting default encoding to UTF8 (#142) by @nvarscar
# Release notes for v0.7.1:
- ### Adding support for underscore char in tokens (#130) by @nvarscar
# Release notes for v0.7.0:
- ### Improving schema history table - new columns (#124) by @nvarscar
# Release notes for v0.6.4:
- ### Forcing the string datatype onto columns when -ReturnAsText is used (#115) by @nvarscar
# Release notes for v0.6.3:
- ### Adding hyphen to the variable token symbols (#112) by @nvarscar
# Release notes for v0.6.2:
- ### Ensuring deploy.ps1 only uses public functions (#108) by @nvarscar
# Release notes for v0.6.1:
- ### Files in subfolders are not being added when -Match is used (#104) by @nvarscar
   ------
   * Folders are no longer filtered out by the -Match regex string
# Release notes for v0.6.0:
- ### Adding prescripts and postscripts (#91) by @nvarscar
   ------
   Two new parameters:

   - PreScriptPath

   - PostScriptPath



   And one new function:

   Update-DBOPackage that will allow to modify some of the package parameters once it's created.
- ### Adding return as text switch to Invoke-DBOQuery (#92) by @nvarscar
- ### Adding nuget package downloader (#93) by @nvarscar
- ### Fixing Set and Reset-DBODefaultSetting on Linux (#94) by @nvarscar
   ------
   scope for linux was chosen incorrectly. Now it's chosen dynamically based on OS.
- ### Re-introducing Oracle tests (#97) by @nvarscar
   ------
   Switching to "/" as a batch separator - this is a breaking change.

   Tests have been updated to support that change.


- ### Renaming Install-DBOSqlScript to Install-DBOScript (#98) by @nvarscar
- ### Flexible nuget package versioning (#99) by @nvarscar
   ------
   Requirements now allow Minimum/Maximum Versions where appropriate, as well as it's possible to target a specific .net framework
