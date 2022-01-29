using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using DbUp.Engine;
using DbUp.Engine.Output;
using DbUp.Engine.Transactions;

namespace DBOps
{
    public abstract class TableJournal : DbUp.Support.TableJournal, IJournal
    {
        bool journalExists;
        protected TableJournal(
            Func<IConnectionManager> connectionManager,
            Func<IUpgradeLog> logger,
            ISqlObjectParser sqlObjectParser,
            string schema, string table) : base(connectionManager, logger, sqlObjectParser, schema, table) { }
        public new ExecutedScript[] GetExecutedScripts()
        {
            return ConnectionManager().ExecuteCommandsWithManagedConnection(dbCommandFactory =>
            {
                if (journalExists || DoesTableExist(dbCommandFactory))
                {
                    Log().WriteInformation("Fetching list of already executed scripts.");

                    var scripts = new List<ExecutedScript>();

                    using (var command = GetJournalEntriesCommand(dbCommandFactory))
                    {
                        using (var reader = command.ExecuteReader())
                        {
                            while (reader.Read())
                                scripts.Add(new ExecutedScript((string)reader[0], (string)reader[1]));
                        }
                    }

                    return scripts.ToArray();
                }
                else
                {
                    Log().WriteInformation("Journal table does not exist");
                    return new List<ExecutedScript>().ToArray();
                }
            });
        }
    }
}
