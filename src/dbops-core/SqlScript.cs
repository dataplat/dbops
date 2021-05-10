using DbUp.Engine;

namespace DBOps
{
    public class SqlScript: DbUp.Engine.SqlScript
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="SqlScript"/> class.
        /// </summary>
        /// <param name="name">The name.</param>
        /// <param name="contents">The contents.</param>
        public SqlScript(string name, string contents) : base(name, contents)
        {
        }

        /// <summary>
        /// Initializes a new instance of the <see cref="SqlScript"/> class with a specific script type and a specific order
        /// </summary>
        /// <param name="name">The name.</param>
        /// <param name="contents">The contents.</param>
        /// <param name="sqlScriptOptions">The script options.</param>        
        public SqlScript(string name, string contents, SqlScriptOptions sqlScriptOptions) : base(name, contents, sqlScriptOptions)
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
