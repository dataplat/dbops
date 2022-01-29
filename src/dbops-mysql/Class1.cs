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
    class MySqlChecksumTableJournal : MySqlTableJournal
    {
        private bool journalExists = false;
        public MySqlChecksumTableJournal(Func<IConnectionManager> connectionManager, Func<IUpgradeLog> logger, string schema, string table)
        : base(connectionManager, logger, schema, table)
        {
        }
        protected new string GetJournalEntriesSql()
        {
            return $"select CONCAT(scriptname,':',checksum,'dbops+checksum') from {FqSchemaTableName} order by scriptname";
        }

        public new string[] GetExecutedScripts()
        {
            return ConnectionManager().ExecuteCommandsWithManagedConnection(dbCommandFactory =>
            {
                if (journalExists || DoesTableExist(dbCommandFactory))
                {
                    Log().WriteInformation("Fetching list of already executed scripts.");

                    var executedScripts = new List<string>();

                    using (var command = GetJournalEntriesCommand(dbCommandFactory))
                    {
                        using (var reader = command.ExecuteReader())
                        {
                            while (reader.Read())
                                executedScripts.Add((string)reader[0]);
                        }
                    }

                    return executedScripts.ToArray();
                }
                else
                {
                    Log().WriteInformation("Journal table does not exist");
                    return new string[0];
                }
            });
        }
    }
}
