#tool "nuget:?package=GitVersion.CommandLine"

var target = Argument("target", "Default");
var outputDir = "./artifacts/";

Task("Clean")
    .Does(() => {
        if (DirectoryExists(outputDir))
        {
            DeleteDirectory(outputDir, new DeleteDirectorySettings {
                Recursive = true,
                Force = true
            });
        }
    });



GitVersion versionInfo = null;
Task("Version")
    .Does(() => {
        GitVersion(new GitVersionSettings{
            UpdateAssemblyInfo = false,
            OutputType = GitVersionOutput.BuildServer
        });
        versionInfo = GitVersion(new GitVersionSettings{ OutputType = GitVersionOutput.Json });
    });

Task("Restore")
    .IsDependentOn("Version")
    .Does(() => {
        DotNetCoreRestore("src", new DotNetCoreRestoreSettings() {
            ArgumentCustomization = args => args.Append("/p:Version=" + versionInfo.NuGetVersion)
        });
    });

Task("Build")
    .IsDependentOn("Clean")
    .IsDependentOn("Version")
    .IsDependentOn("Restore")
    .Does(() => {
        var settings =  new MSBuildSettings()
            .SetConfiguration("Release")
            .UseToolVersion(MSBuildToolVersion.VS2019)
            .WithProperty("Version", versionInfo.NuGetVersion)
            .WithProperty("PackageOutputPath", System.IO.Path.GetFullPath(outputDir))
            .WithTarget("Build")
            .WithTarget("Pack");

        MSBuild("./src/DBOps.sln", settings);
    });

Task("Test")
    .IsDependentOn("Build")
    .Does(() => {
         DotNetCoreTest("./src/dbops-tests/dbops-tests.csproj", new DotNetCoreTestSettings
        {
            Configuration = "Release",
            NoBuild = true
        });
    });

Task("Default")
    .IsDependentOn("Test");

RunTarget(target);