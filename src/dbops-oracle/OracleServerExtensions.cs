using DbUp.Builder;
using DbUp.Engine.Transactions;

namespace DBOps.Oracle

{
    public static class OracleExtensions
    {
        /// <summary>
        /// Creates an upgrader for Oracle databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionManager">The <see cref="OracleConnectionManager"/> to be used during a database upgrade.</param>
        /// <returns>
        /// A builder for a database upgrader designed for Oracle databases.
        /// </returns>
        public static UpgradeEngineBuilder OracleDatabase(this SupportedDatabases supported, IConnectionManager connectionManager)
            => OracleDatabase(connectionManager);

        /// <summary>
        /// Creates an upgrader for Oracle databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionManager">The <see cref="OracleConnectionManager"/> to be used during a database upgrade.</param>
        /// <param name="schema">The schema in which to check for changes</param>
        /// <returns>
        /// A builder for a database upgrader designed for Oracle databases.
        /// </returns>
        public static UpgradeEngineBuilder OracleDatabase(this SupportedDatabases supported, IConnectionManager connectionManager, string schema)
            => OracleDatabase(connectionManager, schema);

        /// <summary>
        /// Creates an upgrader for Oracle databases.
        /// </summary>
        /// <param name="connectionManager">The <see cref="OracleConnectionManager"/> to be used during a database upgrade.</param>
        /// <returns>
        /// A builder for a database upgrader designed for Oracle databases.
        /// </returns>
        public static UpgradeEngineBuilder OracleDatabase(IConnectionManager connectionManager)
            => OracleDatabase(connectionManager, null);

        /// <summary>
        /// Creates an upgrader for Oracle databases.
        /// </summary>
        /// <param name="connectionManager">The <see cref="OracleConnectionManager"/> to be used during a database upgrade.</param>
        /// <param name="schema">The schema in which to check for changes</param>
        /// <returns>
        /// A builder for a database upgrader designed for Oracle databases.
        /// </returns>
        public static UpgradeEngineBuilder OracleDatabase(IConnectionManager connectionManager, string schema)
        {
            var builder = new UpgradeEngineBuilder();
            builder.Configure(c => c.ConnectionManager = connectionManager);
            builder.Configure(c => c.ScriptExecutor = new OracleScriptExecutor(() => c.ConnectionManager, () => c.Log, schema, () => c.VariablesEnabled, c.ScriptPreprocessors, () => c.Journal));
            builder.Configure(c => c.Journal = new OracleTableJournal(() => c.ConnectionManager, () => c.Log, schema, "schemaversions"));
            builder.WithPreprocessor(new DbUp.Oracle.OraclePreprocessor());
            return builder;
        }

    }
}
