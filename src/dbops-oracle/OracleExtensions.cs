using System.Linq;
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
            builder.Configure(c => c.ScriptFilter = new ScriptFilter());
            builder.WithPreprocessor(new DbUp.Oracle.OraclePreprocessor());
            return builder;
        }
        /// <summary>
        /// Creates an upgrader for Oracle databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionString">Oracle database connection string.</param>
        /// <param name="delimiter">Delimiter character</param>
        /// <returns>
        /// A builder for a database upgrader designed for Oracle databases.
        /// </returns>
        public static UpgradeEngineBuilder OracleDatabase(this SupportedDatabases supported, string connectionString, char delimiter)
        {
            foreach (var pair in connectionString.Split(';').Select(s => s.Split('=')).Where(pair => pair.Length == 2).Where(pair => pair[0].ToLower() == "database"))
            {
                return OracleDatabase(new DbUp.Oracle.OracleConnectionManager(connectionString, new DbUp.Oracle.OracleCommandSplitter(delimiter)), pair[1]);
            }

            return OracleDatabase(new DbUp.Oracle.OracleConnectionManager(connectionString, new DbUp.Oracle.OracleCommandSplitter(delimiter)));
        }

        /// <summary>
        /// Creates an upgrader for Oracle databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionString">Oracle database connection string.</param>
        /// <param name="schema">Which Oracle schema to check for changes</param>
        /// <param name="delimiter">Delimiter character</param>
        /// <returns>
        /// A builder for a database upgrader designed for Oracle databases.
        /// </returns>
        public static UpgradeEngineBuilder OracleDatabase(this SupportedDatabases supported, string connectionString, string schema, char delimiter)
        {
            return OracleDatabase(new DbUp.Oracle.OracleConnectionManager(connectionString, new DbUp.Oracle.OracleCommandSplitter(delimiter)), schema);
        }

    }
}
