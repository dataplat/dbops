using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using DBOps.Tests.TestInfrastructure;
using NSubstitute;
using Shouldly;
using Xunit;
using TestStack.BDDfy;
using System.IO.Compression;

namespace DBOps.Tests
{
    public class SqlScriptTests
    {
        SqlScript script;
        string filePath;
        static string scriptName = "test.sql";
        [Theory]
        [InlineData("1252")]
        [InlineData("UTF16-BE")]
        [InlineData("UTF16-LE")]
        [InlineData("UTF16-NoBOM")]
        [InlineData("UTF8-BOM")]
        [InlineData("UTF8-NoBOM")]
        public void VerifyScriptEncoding(string encoding)
        {
            this
                .Given(_ => EncodedFile(encoding))
                .When(_ => ScriptCreatedFromFile())
                .Then(_ => ScriptHasContent())
                .BDDfy();

            this
                .Given(_ => EncodedFile(encoding))
                .When(_ => ScriptCreatedFromArchive())
                .Then(_ => ScriptHasContent())
                .BDDfy();
        }
        void EncodedFile(string encoding)
        {

            filePath = $"TestScripts\\EncodingTests\\{encoding}.txt";

        }
        void ScriptCreatedFromFile()
        {
            script = new SqlScript(new FileInfo(filePath), scriptName);

        }
        void ScriptCreatedFromArchive()
        {
            var archiveFile = "test.zip";
            using (var zipFileStream = new FileStream(archiveFile, FileMode.Create))
            {
                using (var zip = new ZipArchive(zipFileStream, ZipArchiveMode.Create))
                {
                    var entry = zip.CreateEntry(scriptName);
                    using (var writer = entry.Open())
                    {
                        using (var fileStream = File.Open(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                        {
                            fileStream.CopyTo(writer);
                        }
                        writer.Close();
                    }
                }
            }
            using (var zipFile = ZipFile.OpenRead(archiveFile))
            {
                script = new SqlScript(zipFile.Entries[0], scriptName);
            }

        }
        void ScriptHasContent()
        {
            script.Name.ShouldBe("test.sql");
            script.Contents.ShouldBe("SELECT foo FROM bar");
        }
    }
}
