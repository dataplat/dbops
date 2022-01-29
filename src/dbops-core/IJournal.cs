using System;
using System.Data;

namespace DBOps
{
    /// <summary>
    /// This interface is provided to allow different projects to store version information differently.
    /// </summary>
    public interface IJournal : DbUp.Engine.IJournal
    {
        /// <summary>
        /// Recalls the version number of the database.
        /// </summary>
        /// <returns></returns>
        new ExecutedScript[] GetExecutedScripts();
    }
}

