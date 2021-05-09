using DbUp.Builder;
using DbUp.Engine.Transactions;

namespace DBOps.MySql

{
    public static class MySqlExtensions
    {
        /// <summary>
        /// Creates an upgrader for PostgreSQL databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionManager">The <see cref="PostgresqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <returns>
        /// A builder for a database upgrader designed for PostgreSQL databases.
        /// </returns>
        public static UpgradeEngineBuilder MySqlDatabase(this SupportedDatabases supported, IConnectionManager connectionManager)
            => MySqlDatabase(connectionManager);

        /// <summary>
        /// Creates an upgrader for PostgreSQL databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionManager">The <see cref="PostgresqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <param name="schema">The schema in which to check for changes</param>
        /// <returns>
        /// A builder for a database upgrader designed for PostgreSQL databases.
        /// </returns>
        public static UpgradeEngineBuilder MySqlDatabase(this SupportedDatabases supported, IConnectionManager connectionManager, string schema)
            => MySqlDatabase(connectionManager, schema);

        /// <summary>
        /// Creates an upgrader for PostgreSQL databases.
        /// </summary>
        /// <param name="connectionManager">The <see cref="PostgresqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <returns>
        /// A builder for a database upgrader designed for PostgreSQL databases.
        /// </returns>
        public static UpgradeEngineBuilder MySqlDatabase(IConnectionManager connectionManager)
            => MySqlDatabase(connectionManager, null);

        /// <summary>
        /// Creates an upgrader for PostgreSQL databases.
        /// </summary>
        /// <param name="connectionManager">The <see cref="PostgresqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <param name="schema">The schema in which to check for changes</param>
        /// <returns>
        /// A builder for a database upgrader designed for PostgreSQL databases.
        /// </returns>
        public static UpgradeEngineBuilder MySqlDatabase(IConnectionManager connectionManager, string schema)
        {
            var builder = new UpgradeEngineBuilder();
            builder.Configure(c => c.ConnectionManager = connectionManager);
            builder.Configure(c => c.ScriptExecutor = new MySqlScriptExecutor(() => c.ConnectionManager, () => c.Log, schema, () => c.VariablesEnabled, c.ScriptPreprocessors, () => c.Journal));
            builder.Configure(c => c.Journal = new MySqlTableJournal(() => c.ConnectionManager, () => c.Log, schema, "schemaversions"));
            builder.WithPreprocessor(new DbUp.MySql.MySqlPreprocessor());
            return builder;
        }

    }
}
