using System;
using System.Collections.Generic;
using System.Data;
using DbUp.Builder;
using DbUp.Engine;
using DbUp.Engine.Output;
using DbUp.Engine.Transactions;
using DBOps.Postgresql;
using DBOps.Tests.TestInfrastructure;
using NSubstitute;
using Shouldly;

namespace DBOps.Tests.Postgresql
{
    public class PostgresqlTableJournalTests
    {

        public class upgrade_table_when_version_mismatch : SpecificationFor<PostgresqlTableJournal>
        {
            IDbConnection dbConnection;
            IDbCommand dbCommand;
            CaptureLogsLogger log;

            public override PostgresqlTableJournal Given()
            {

                dbConnection = Substitute.For<IDbConnection>();
                dbCommand = Substitute.For<IDbCommand>();
                dbCommand.ExecuteScalar().Returns(1);
                log = new CaptureLogsLogger();

                var table = new DataTable();
                table.Columns.Add("column", Type.GetType("System.String"));
                var row = table.NewRow();
                row["column"] = "id";
                table.Rows.Add(row);
                var fakeReader = new FakeReader(table);
                dbCommand.ExecuteReader().Returns(fakeReader);
                dbConnection.CreateCommand().Returns(dbCommand);

                var connectionManager = new TestConnectionManager(dbConnection);
                var versionTracker = new PostgresqlTableJournal(() => connectionManager, () => log, null, "history");
                return versionTracker;
            }

            protected override void When()
            {
                Subject.UpgradeJournalTable(() => dbCommand);
            }

            [Then]
            public void nonreader_is_called()
            {
                dbCommand.Received().ExecuteNonQuery();
            }
            [Then]
            public void log_should_contain_upgrade_line()
            {
                log.Log.ShouldContain("Upgrading schema version table...");
            }
        }
    }
}
