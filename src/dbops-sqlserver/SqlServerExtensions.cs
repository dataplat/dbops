using DbUp.Builder;
using DbUp.Engine.Transactions;

namespace DBOps.SqlServer
{
    public static class SqlServerExtensions
    {
        public static UpgradeEngineBuilder SqlDatabase(this SupportedDatabases supported, string connectionString, string schema)
        {
            return SqlDatabase(new DbUp.SqlServer.SqlConnectionManager(connectionString), schema);
        }

        /// <summary>
        /// Creates an upgrader for SQL Server databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionManager">The <see cref="IConnectionManager"/> to be used during a database
        /// upgrade. See <see cref="SqlConnectionManager"/> for an example implementation</param>
        /// <param name="schema">The SQL schema name to use. Defaults to 'dbo'.</param>
        /// <returns>
        /// A builder for a database upgrader designed for SQL Server databases.
        /// </returns>
        public static UpgradeEngineBuilder SqlDatabase(this SupportedDatabases supported, IConnectionManager connectionManager, string schema = null)
            => SqlDatabase(connectionManager, schema);

        /// <summary>
        /// Creates an upgrader for SQL Server databases.
        /// </summary>
        /// <param name="connectionManager">The <see cref="IConnectionManager"/> to be used during a database
        /// upgrade. See <see cref="SqlConnectionManager"/> for an example implementation</param>
        /// <param name="schema">The SQL schema name to use. Defaults to 'dbo'.</param>
        /// <returns>
        /// A builder for a database upgrader designed for SQL Server databases.
        /// </returns>
        private static UpgradeEngineBuilder SqlDatabase(IConnectionManager connectionManager, string schema)
        {
            var builder = new UpgradeEngineBuilder();
            builder.Configure(c => c.ConnectionManager = connectionManager);
            builder.Configure(c => c.ScriptExecutor = new SqlScriptExecutor(() => c.ConnectionManager, () => c.Log, schema, () => c.VariablesEnabled, c.ScriptPreprocessors, () => c.Journal));
            builder.Configure(c => c.Journal = new SqlTableJournal(() => c.ConnectionManager, () => c.Log, schema, "SchemaVersions"));
            return builder;
        }

    }
}
