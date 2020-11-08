using DbUp.Builder;
using DbUp.Engine.Transactions;

namespace DBOps.Extensions
{
    public static class PostgresqlExtensions
    {
        /// <summary>
        /// Creates an upgrader for PostgreSQL databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionManager">The <see cref="PostgresqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <returns>
        /// A builder for a database upgrader designed for PostgreSQL databases.
        /// </returns>
        public static UpgradeEngineBuilder PostgresqlDatabase(this SupportedDatabases supported, IConnectionManager connectionManager)
            => PostgresqlDatabase(connectionManager);

        /// <summary>
        /// Creates an upgrader for PostgreSQL databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionManager">The <see cref="PostgresqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <param name="schema">The schema in which to check for changes</param>
        /// <returns>
        /// A builder for a database upgrader designed for PostgreSQL databases.
        /// </returns>
        public static UpgradeEngineBuilder PostgresqlDatabase(this SupportedDatabases supported, IConnectionManager connectionManager, string schema)
            => PostgresqlDatabase(connectionManager, schema);

        /// <summary>
        /// Creates an upgrader for PostgreSQL databases.
        /// </summary>
        /// <param name="connectionManager">The <see cref="PostgresqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <returns>
        /// A builder for a database upgrader designed for PostgreSQL databases.
        /// </returns>
        public static UpgradeEngineBuilder PostgresqlDatabase(IConnectionManager connectionManager)
            => PostgresqlDatabase(connectionManager, null);

        /// <summary>
        /// Creates an upgrader for PostgreSQL databases.
        /// </summary>
        /// <param name="connectionManager">The <see cref="PostgresqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <param name="schema">The schema in which to check for changes</param>
        /// <returns>
        /// A builder for a database upgrader designed for PostgreSQL databases.
        /// </returns>
        public static UpgradeEngineBuilder PostgresqlDatabase(IConnectionManager connectionManager, string schema)
        {
            var builder = new UpgradeEngineBuilder();
            builder.Configure(c => c.ConnectionManager = connectionManager);
            builder.Configure(c => c.ScriptExecutor = new PostgresqlScriptExecutor(() => c.ConnectionManager, () => c.Log, schema, () => c.VariablesEnabled, c.ScriptPreprocessors, () => c.Journal));
            builder.Configure(c => c.Journal = new PostgresqlTableJournal(() => c.ConnectionManager, () => c.Log, schema, "schemaversions"));
            builder.WithPreprocessor(new DbUp.Postgresql.PostgresqlPreprocessor());
            return builder;
        }

    }
}
