using System;
using System.Data;
using DbUp;
using DbUp.Builder;
using DbUp.Engine.Transactions;
using DbUp.Engine.Output;
using MySql.Data.MySqlClient;

namespace DBOps.MySql

{
    public static class MySqlExtensions
    {
        /// <summary>
        /// Creates an upgrader for MySql databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionManager">The <see cref="MySqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <returns>
        /// A builder for a database upgrader designed for MySql databases.
        /// </returns>
        public static UpgradeEngineBuilder MySqlDatabase(this SupportedDatabases supported, IConnectionManager connectionManager)
            => MySqlDatabase(connectionManager);

        /// <summary>
        /// Creates an upgrader for MySql databases.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionManager">The <see cref="MySqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <param name="schema">The schema in which to check for changes</param>
        /// <returns>
        /// A builder for a database upgrader designed for MySql databases.
        /// </returns>
        public static UpgradeEngineBuilder MySqlDatabase(this SupportedDatabases supported, IConnectionManager connectionManager, string schema)
            => MySqlDatabase(connectionManager, schema);

        /// <summary>
        /// Creates an upgrader for MySql databases.
        /// </summary>
        /// <param name="connectionManager">The <see cref="MySqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <returns>
        /// A builder for a database upgrader designed for MySql databases.
        /// </returns>
        public static UpgradeEngineBuilder MySqlDatabase(IConnectionManager connectionManager)
            => MySqlDatabase(connectionManager, null);

        /// <summary>
        /// Creates an upgrader for MySql databases.
        /// </summary>
        /// <param name="connectionManager">The <see cref="MySqlConnectionManager"/> to be used during a database upgrade.</param>
        /// <param name="schema">The schema in which to check for changes</param>
        /// <returns>
        /// A builder for a database upgrader designed for MySql databases.
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

        /// <summary>
        /// Ensures that the database specified in the connection string exists.
        /// </summary>
        /// <param name="supported">Fluent helper type.</param>
        /// <param name="connectionString">The connection string.</param>
        /// <param name="logger">The <see cref="DbUp.Engine.Output.IUpgradeLog"/> used to record actions.</param>
        /// <returns></returns>
        public static void MySqlDatabase(this SupportedDatabasesForEnsureDatabase supported, string connectionString, IUpgradeLog logger)
        {
            if (supported == null) throw new ArgumentNullException("supported");

            if (string.IsNullOrEmpty(connectionString) || connectionString.Trim() == string.Empty)
            {
                throw new ArgumentNullException("connectionString");
            }

            if (logger == null) throw new ArgumentNullException("logger");

            var masterConnectionStringBuilder = new MySqlConnectionStringBuilder(connectionString);

            var databaseName = masterConnectionStringBuilder.Database;

            if (string.IsNullOrEmpty(databaseName) || databaseName.Trim() == string.Empty)
            {
                throw new InvalidOperationException("The connection string does not specify a database name.");
            }

            masterConnectionStringBuilder.Database = "sys";

            var logMasterConnectionStringBuilder = new MySqlConnectionStringBuilder(masterConnectionStringBuilder.ConnectionString);
            if (!string.IsNullOrEmpty(logMasterConnectionStringBuilder.Password))
            {
                logMasterConnectionStringBuilder.Password = String.Empty.PadRight(masterConnectionStringBuilder.Password.Length, '*');
            }

            logger.WriteInformation("Master ConnectionString => {0}", logMasterConnectionStringBuilder.ConnectionString);

            using (var connection = new MySqlConnection(masterConnectionStringBuilder.ConnectionString))
            {
                connection.Open();

                var sqlCommandText = string.Format
                    (
                        @"SELECT SCHEMA_NAME AS 'Database' FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '{0}'",
                        databaseName
                    );


                // check to see if the database already exists..
                using (var command = new MySqlCommand(sqlCommandText, connection)
                {
                    CommandType = CommandType.Text
                })
                {
                    var results = (int?)command.ExecuteScalar();

                    // if the database exists, we're done here...
                    if (results.HasValue && results.Value == 1)
                    {
                        return;
                    }
                }

                sqlCommandText = string.Format
                    (
                        "create database `{0}`",
                        databaseName
                    );

                // Create the database...
                using (var command = new MySqlCommand(sqlCommandText, connection)
                {
                    CommandType = CommandType.Text
                })
                {
                    command.ExecuteNonQuery();

                }

                logger.WriteInformation(@"Created database {0}", databaseName);
            }
        }
    }
}
