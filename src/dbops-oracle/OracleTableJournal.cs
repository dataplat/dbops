using System;
using System.Data;
using DbUp.Engine;
using DbUp.Engine.Output;
using DbUp.Engine.Transactions;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace DBOps.Oracle
{
    /// <summary>
    /// An child class of <see cref="DbUp.Oracle.OracleTableJournal"/> that adds custom fields to the 
    /// SchemaVersions table.
    /// </summary>
    public class OracleTableJournal: DbUp.Oracle.OracleTableJournal
    {
        private readonly int maxTableVersion = 2;
        public OracleTableJournal(Func<IConnectionManager> connectionManager, Func<IUpgradeLog> logger, string schema, string table)
            : base(connectionManager, logger, schema, table)
        {
        }

        /// <summary>
        /// Get uppercase version of the schema table name
        /// </summary>
        private string UpperSchemaTableName => UnquotedSchemaTableName.ToUpper(English);
        /// <summary>
        /// Get uppercase version of the schema table name
        /// </summary>
        private string UpperSchemaTableSchema => SchemaTableSchema.ToUpper(English);
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
            return $"insert into {UpperSchemaTableName} (scriptname, applied, checksum, appliedby, executiontime) values ({@scriptName}, {@applied}, {@checksum}, USER, {@executionTime})";
        }

        protected override string CreateSchemaTableSql(string quotedPrimaryKeyName)
        {
            return $@"CREATE TABLE {UpperSchemaTableName}
(
    schemaversionid NUMBER(10),
    scriptname VARCHAR2(255) NOT NULL,
    applied TIMESTAMP NOT NULL,
    checksum VARCHAR2(255),
    appliedby VARCHAR2(255),
    executiontime NUMBER(19),
    CONSTRAINT PK_{UpperSchemaTableName} PRIMARY KEY (schemaversionid)
)";
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


            command.CommandText = GetInsertJournalEntrySql(":scriptName", ":applied", ":checksum", ":executionTime");
            command.CommandType = CommandType.Text;
            return command;
        }

        protected List<String> AlterSchemaTableSqlV2(int currentTableVersion)
        {
            var sqlList = new List<String>();
            if (currentTableVersion == 1)
            {
                sqlList.Add($@"alter table {UpperSchemaTableName} ADD (
    checksum VARCHAR2(255),
    appliedby VARCHAR2(255),
    executiontime NUMBER(19)
)");
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
            return string.Format("select c.COLUMN_NAME from USER_TAB_COLUMNS c JOIN USER_TABLES t ON c.TABLE_NAME = t.TABLE_NAME where c.TABLE_NAME = '{0}'", UpperSchemaTableName) +
                (string.IsNullOrEmpty(SchemaTableSchema) ? "" : string.Format(" and t.OWNER = '{0}'", UpperSchemaTableSchema));
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
    }
}
