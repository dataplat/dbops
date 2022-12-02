using DbUp.Engine;
using System.IO;
using System.IO.Compression;

namespace DBOps
{
    public class SqlScript: DbUp.Engine.SqlScript
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="SqlScript"/> class.
        /// </summary>
        /// <param name="name">Script name</param>
        /// <param name="contents">Script contents</param>
        public SqlScript(string name, string contents) : base(name, contents)
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="SqlScript"/> class with a specific script type and a specific order
        /// </summary>
        /// <param name="name">Script name</param>
        /// <param name="contents">Script contents</param>
        /// <param name="sqlScriptOptions">Script options</param>        
        public SqlScript(string name, string contents, SqlScriptOptions sqlScriptOptions) : base(name, contents, sqlScriptOptions)
        {
        }
        /// <summary>
        /// Initializes a new instance of the <see cref="SqlScript"/> class from a file system object
        /// </summary>
        /// <param name="fileObject">File system object</param>
        /// <param name="name">Script name</param>
        public SqlScript(FileInfo fileObject, string name) : base(name, Helpers.GetFileContents(fileObject))
        {
        }
        /// <summary>
        /// Initializes a new instance of the <see cref="SqlScript"/> class from a file system object with a specific script type and a specific order
        /// </summary>
        /// <param name="fileObject">File system object</param>
        /// <param name="name">Script name</param>
        /// <param name="sqlScriptOptions">Script options</param>       
        public SqlScript(FileInfo fileObject, string name, SqlScriptOptions sqlScriptOptions) : base(name, Helpers.GetFileContents(fileObject), sqlScriptOptions)
        {
        }
        /// <summary>
        /// Initializes a new instance of the <see cref="SqlScript"/> class from an archived file entry
        /// </summary>
        /// <param name="zipEntry">Archived file entry object</param>
        /// <param name="name">Script name</param>
        public SqlScript(ZipArchiveEntry zipEntry, string name) : base(zipEntry.Name, Helpers.GetZipEntryContents(zipEntry))
        {
        }
        /// <summary>
        /// Initializes a new instance of the <see cref="SqlScript"/> class from an archived file entryt with a specific script type and a specific order
        /// </summary>
        /// <param name="zipEntry">Archived file entry object</param>
        /// <param name="name">Script name</param>
        /// <param name="sqlScriptOptions">Script options</param>  
        public SqlScript(ZipArchiveEntry zipEntry, string name, SqlScriptOptions sqlScriptOptions) : base(zipEntry.Name, Helpers.GetZipEntryContents(zipEntry), sqlScriptOptions)
        {
        }
        /// <summary>
        /// Execution time of the script in milliseconds.
        /// </summary>
        /// <value></value>
        public long _ExecutionTime = -1;
        /// <summary>
        /// Execution time of the script in milliseconds.
        /// </summary>
        /// <value></value>
        public long ExecutionTime => _ExecutionTime;
        /// <summary>
        /// Sets execution duration.
        /// </summary>
        /// <value></value>
        public void SetExecutionTime(long milliseconds)
        {
            _ExecutionTime = milliseconds;
        }   
    }
}
