using System;
using System.Data;
using DbUp.Engine;
using DbUp.Engine.Output;
using DbUp.Engine.Transactions;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace DBOps.Extensions
{
    public class SqlTableJournal: DbUp.SqlServer.SqlTableJournal
    {
        bool journalExists;
        Version tableVersion = new Version("2.0");
        public SqlTableJournal(Func<IConnectionManager> connectionManager, Func<IUpgradeLog> logger, string schema, string table)
            : base(connectionManager, logger, schema, table)
        {
        }
        public override void EnsureTableExistsAndIsLatestVersion(Func<IDbCommand> dbCommandFactory)
        {
            var tableExists = DoesTableExist(dbCommandFactory);
            if (!journalExists && !tableExists)
            {
                if (tableExists)
                {
                    var currentTableVersion = GetTableVersion(dbCommandFactory);
                    if (currentTableVersion < tableVersion)
                    {
                        Log().WriteInformation("Upgrading schema version table...");
                        foreach (var sql in AlterSchemaTableSql(currentTableVersion))
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
                    Log().WriteInformation(string.Format("Creating the {0} table", FqSchemaTableName));
                    using (var command = GetCreateTableCommand(dbCommandFactory))
                    {
                        command.ExecuteNonQuery();
                    }

                    Log().WriteInformation(string.Format("The {0} table has been created", FqSchemaTableName));

                    OnTableCreated(dbCommandFactory);
                }
            }

            journalExists = true;
        }
        protected string GetInsertJournalEntrySql(string @scriptName, string @applied, string @checksum, string @executionTime)
        {
            return $"insert into {FqSchemaTableName} (ScriptName, Applied, CheckSum, ExecutionTime) values ({@scriptName}, {@applied}, {@checksum}, {@executionTime})";
        }

        protected override string CreateSchemaTableSql(string quotedPrimaryKeyName)
        {
            return
$@"create table {FqSchemaTableName} (
    [Id] int identity(1,1) not null constraint {quotedPrimaryKeyName} primary key,
    [ScriptName] nvarchar(512) not null,
    [Applied] datetime not null,
    [Checksum] nvarchar(255),
    [AppliedBy] nvarchar(255) DEFAULT USER_NAME(),
    [ExecutionTime] bigint,
    [Success] bit DEFAULT 1
)";
        }

        protected IDbCommand GetInsertScriptCommand(Func<IDbCommand> dbCommandFactory, SqlScript script)
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
            checksumParam.Value = CreateMD5(script.Contents);
            command.Parameters.Add(checksumParam);

            var etParam = command.CreateParameter();
            etParam.ParameterName = "executionTime";
            etParam.Value = script.ExecutionTime;
            command.Parameters.Add(etParam);


            command.CommandText = GetInsertJournalEntrySql("@scriptName", "@applied", "@checksum", "@executionTime");
            command.CommandType = CommandType.Text;
            return command;
        }

        protected List<String> AlterSchemaTableSql(Version currentTableVersion)
        {
            var sqlList = new List<String>();
            if (currentTableVersion.Major == 1)
            {
                sqlList.Add($@"alter table {FqSchemaTableName} add 
    [Checksum] nvarchar(255),
    [AppliedBy] nvarchar(255) DEFAULT USER_NAME(),
    [ExecutionTime] int,
    [Success] bit DEFAULT 1");
                sqlList.Add($@"UPDATE {FqSchemaTableName} SET [Success] = 1 WHERE [Success] IS NULL");
            }
            return sqlList;

        }

        protected Version GetTableVersion(Func<IDbCommand> dbCommandFactory)
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
                return new Version("2.0");
            }
            else
            {
                return new Version("1.0");
            }
        }

        protected string GetTableVersionSql()
        {
            return string.Format("select COLUMN_NAME from INFORMATION_SCHEMA.COLUMNS where TABLE_NAME = '{0}'", UnquotedSchemaTableName) +
                (string.IsNullOrEmpty(SchemaTableSchema) ? "" : string.Format(" and TABLE_SCHEMA = '{0}'", SchemaTableSchema));
        }

        protected string CreateMD5(string input)
        {
            using (System.Security.Cryptography.MD5 md5 = System.Security.Cryptography.MD5.Create())
            {
                byte[] inputBytes = System.Text.Encoding.ASCII.GetBytes(input);
                byte[] hashBytes = md5.ComputeHash(inputBytes);

                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < hashBytes.Length; i++)
                {
                    sb.Append(hashBytes[i].ToString("X2"));
                }
                return sb.ToString();
            }
        }
    }
}
