using System;
using System.Data;
using DbUp.Engine;
using DbUp.Engine.Output;
using DbUp.Engine.Transactions;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace DBOps.MySql
{
    /// <summary>
    /// An child class of <see cref="DbUp.MySql.MySqlTableJournal"/> that adds custom fields to the 
    /// SchemaVersions table.
    /// </summary>
    public class MySqlTableJournal: DbUp.MySql.MySqlTableJournal
    {
        private readonly int maxTableVersion = 2;
        /// <summary>
        /// Creates a new MySql table journal.
        /// </summary>
        /// <param name="connectionManager">The MySql connection manager.</param>
        /// <param name="logger">The upgrade logger.</param>
        /// <param name="schema">The name of the schema the journal is stored in.</param>
        /// <param name="table">The name of the journal table.</param>
        public MySqlTableJournal(Func<IConnectionManager> connectionManager, Func<IUpgradeLog> logger, string schema, string table)
            : base(connectionManager, logger, schema, table)
        {
        }
        /// <summary>
        /// Upgrades Schema Table to the current version if necessary
        /// </summary>
        /// <param name="dbCommandFactory"></param>
        public void UpgradeJournalTable(Func<IDbCommand> dbCommandFactory)
        {
            var tableExists = DoesTableExist(dbCommandFactory);
            if (tableExists)
            {
                var currentTableVersion = GetTableVersion(dbCommandFactory);
                if (currentTableVersion < maxTableVersion)
                {
                    Log().WriteInformation("Upgrading schema version table...");
                    foreach (var sql in AlterSchemaTableSqlV2(currentTableVersion))
                    {
                        var command = dbCommandFactory();
                        command.CommandText = sql;
                        command.CommandType = CommandType.Text;
                        command.ExecuteNonQuery();
                    }
                }
            }
            else
            {
                var message = string.Format("Table {0} does not exist", FqSchemaTableName);
                Log().WriteError(message);
                throw new Exception(message);
            }
        }
        protected string GetInsertJournalEntrySql(string @scriptName, string @applied, string @checksum, string @executionTime)
        {
            return $"insert into {FqSchemaTableName} (ScriptName, Applied, CheckSum, AppliedBy, ExecutionTime) values ({@scriptName}, {@applied}, {@checksum}, SUBSTRING_INDEX(CURRENT_USER(), '@', 1), {@executionTime})";
        }

        protected override string CreateSchemaTableSql(string quotedPrimaryKeyName)
        {
            return
$@"CREATE TABLE {FqSchemaTableName} 
(
    `schemaversionid` INT NOT NULL AUTO_INCREMENT,
    `scriptname` VARCHAR(255) NOT NULL,
    `applied` TIMESTAMP NOT NULL,
    `checksum` VARCHAR(255),
    `appliedby` VARCHAR(255),
    `executiontime` BIGINT,
    PRIMARY KEY (`schemaversionid`)
);";
        }

        protected IDbCommand GetInsertScriptCommandV2(Func<IDbCommand> dbCommandFactory, SqlScript script)
        {
            var command = dbCommandFactory();

            var scriptNameParam = command.CreateParameter();
            scriptNameParam.ParameterName = "scriptName";
            scriptNameParam.Value = script.Name;
            command.Parameters.Add(scriptNameParam);

            var appliedParam = command.CreateParameter();
            appliedParam.ParameterName = "applied";
            appliedParam.Value = DateTime.Now;
            command.Parameters.Add(appliedParam);

            var checksumParam = command.CreateParameter();
            checksumParam.ParameterName = "checksum";
            checksumParam.Value = Helpers.CreateMD5(script.Contents);
            command.Parameters.Add(checksumParam);

            var etParam = command.CreateParameter();
            etParam.ParameterName = "executionTime";
            etParam.Value = script.ExecutionTime;
            command.Parameters.Add(etParam);


            command.CommandText = GetInsertJournalEntrySql("@scriptName", "@applied", "@checksum", "@executionTime");
            command.CommandType = CommandType.Text;
            return command;
        }

        protected List<String> AlterSchemaTableSqlV2(int currentTableVersion)
        {
            var sqlList = new List<String>();
            if (currentTableVersion == 1)
            {
                sqlList.Add($@"alter table {FqSchemaTableName}
    add `checksum` VARCHAR(255),
    add `appliedby` VARCHAR(255),
    add `executiontime` BIGINT");
            }
            return sqlList;

        }

        protected int GetTableVersion(Func<IDbCommand> dbCommandFactory)
        {
            var columns = new List<string>();
            using (var command = dbCommandFactory())
            {
                command.CommandText = GetTableVersionSql();
                command.CommandType = CommandType.Text;

                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                        columns.Add((string)reader[0]);
                }
            }
            if (columns.Contains("Checksum", StringComparer.OrdinalIgnoreCase))
            {
                return 2;
            }
            else
            {
                return 1;
            }
        }

        protected string GetTableVersionSql()
        {
            return string.Format("select COLUMN_NAME from INFORMATION_SCHEMA.COLUMNS where TABLE_NAME = '{0}'", UnquotedSchemaTableName) +
                (string.IsNullOrEmpty(SchemaTableSchema) ? "" : string.Format(" and TABLE_SCHEMA = '{0}'", SchemaTableSchema));
        }



        /// <summary>
        /// Records a database upgrade for a database specified in a given connection string.
        /// </summary>
        /// <param name="script">The script.</param>
        /// <param name="dbCommandFactory"></param>
        public override void StoreExecutedScript(DbUp.Engine.SqlScript script, Func<IDbCommand> dbCommandFactory)
        {
            EnsureTableExistsAndIsLatestVersion(dbCommandFactory);
            var tableVersion = GetTableVersion(dbCommandFactory);
            if (tableVersion == 2)
            {
                using (var command = GetInsertScriptCommandV2(dbCommandFactory, (SqlScript)script))
                {
                    command.ExecuteNonQuery();
                }
            }
            else if (tableVersion == 1)
            {
                using (var command = GetInsertScriptCommand(dbCommandFactory, script))
                {
                    command.ExecuteNonQuery();
                }
            }
        }
        protected override string DoesTableExistSql()
        {
            return string.IsNullOrEmpty(SchemaTableSchema)
                ? string.Format("select 1 from INFORMATION_SCHEMA.TABLES where TABLE_NAME = '{0}' and TABLE_SCHEMA = DATABASE()", UnquotedSchemaTableName)
                : string.Format("select 1 from INFORMATION_SCHEMA.TABLES where TABLE_NAME = '{0}' and TABLE_SCHEMA = '{1}'", UnquotedSchemaTableName, SchemaTableSchema);
        }
    }
    /// <summary>
    /// A child class of <see cref="MySqlTableJournal"/> that enables checksum validation.
    /// Use together with <see cref="ChecksumValidatingScriptFilter"/>.
    /// </summary>
    public class MySqlChecksumValidatingJournal : MySqlTableJournal
    {
        public MySqlChecksumValidatingJournal(Func<IConnectionManager> connectionManager, Func<IUpgradeLog> logger, string schema, string table)
            : base(connectionManager, logger, schema, table)
        {
        }
        protected override string GetJournalEntriesSql()
        {
            return $"select CONCAT(scriptname, '|', checksum) from {FqSchemaTableName} order by scriptname";
        }
    }
}
