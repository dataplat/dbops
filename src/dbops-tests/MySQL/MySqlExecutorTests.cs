using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Common;
using DBOps.MySql;
using DbUp.Engine.Output;
using DbUp.Engine.Transactions;
using DBOps.Tests.TestInfrastructure;
using NSubstitute;
using Shouldly;
using Xunit;

namespace DBOps.Tests.MySql
{
    public class MySqlScriptExecutorTests
    {
        [Fact]
        public void records_execution_time()
        {
            var dbConnection = Substitute.For<IDbConnection>();
            var command = Substitute.For<IDbCommand>();
            dbConnection.CreateCommand().Returns(command);
            var executor = new MySqlScriptExecutor(() => new TestConnectionManager(dbConnection, true)
            {
                IsScriptOutputLogged = true
            }, () => new ConsoleUpgradeLog(), "foo", () => true, null, () => Substitute.For<DbUp.Engine.IJournal>());

            var script = new SqlScript("Test", "SELECT 1");
            executor.Execute(script);

            script.ExecutionTime.ShouldBeGreaterThan(-1);
        }
    }
}