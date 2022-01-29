using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using DbUp.Builder;
using DbUp.Engine;

namespace DBOps
{
    public class UpgradeEngine : DbUp.Engine.UpgradeEngine
    {
        readonly UpgradeConfiguration configuration;
        /// <summary>
        /// Initializes a new instance of the <see cref="UpgradeEngine"/> class.
        /// </summary>
        /// <param name="configuration">The configuration.</param>
        public UpgradeEngine(UpgradeConfiguration configuration) : base(configuration)
        {
        }

        List<SqlScript> GetScriptsToExecuteInsideOperation()
        {
            var allScripts = GetDiscoveredScriptsAsEnumerable();
            var executedScripts = new HashSet<ExecutedScript>(configuration.Journal.GetExecutedScripts());

            var sorted = allScripts.OrderBy(s => s.SqlScriptOptions.RunGroupOrder).ThenBy(s => s.Name, configuration.ScriptNameComparer);
            var filtered = configuration.ScriptFilter.Filter(sorted, executedScripts, configuration.ExecutedScriptComparer);
            //var filteredConverted = new List<SqlScript>();
            //foreach (var subsetItem in filtered)
            //{
            //    filteredConverted.Add((SqlScript)subsetItem);
            //}
            return filtered.ToList();
        }

        IEnumerable<SqlScript> GetDiscoveredScriptsAsEnumerable()
        {
            return (IEnumerable<SqlScript>)configuration.ScriptProviders.SelectMany(scriptProvider => scriptProvider.GetScripts(configuration.ConnectionManager));
        }

        /// <summary>
        /// Performs the database upgrade.
        /// </summary>
        public new DatabaseUpgradeResult PerformUpgrade()
        {
            var executed = new List<DbUp.Engine.SqlScript>();

            SqlScript executedScript = null;
            try
            {
                using (configuration.ConnectionManager.OperationStarting(configuration.Log, executed))
                {

                    configuration.Log.WriteInformation("Beginning database upgrade");

                    var scriptsToExecute = GetScriptsToExecuteInsideOperation();

                    if (scriptsToExecute.Count == 0)
                    {
                        configuration.Log.WriteInformation("No new scripts need to be executed - completing.");
                        return new DatabaseUpgradeResult(executed, true, null, null);
                    }

                    configuration.ScriptExecutor.VerifySchema();

                    foreach (var script in scriptsToExecute)
                    {
                        executedScript = script;

                        configuration.ScriptExecutor.Execute(script, configuration.Variables);

                        OnScriptExecuted(new ScriptExecutedEventArgs(script, configuration.ConnectionManager));

                        executed.Add(script);
                    }

                    configuration.Log.WriteInformation("Upgrade successful");
                    return new DatabaseUpgradeResult(executed, true, null, null);
                }
            }
            catch (Exception ex)
            {
                if (executedScript != null)
                {
                    ex.Data["Error occurred in script: "] = executedScript.Name;
                }
                configuration.Log.WriteError("Upgrade failed due to an unexpected exception:\r\n{0}", ex.ToString());
                return new DatabaseUpgradeResult(executed, false, ex, executedScript);
            }
        }

        /// <summary>
        /// Returns a list of scripts that will be executed when the upgrade is performed
        /// </summary>
        /// <returns>The scripts to be executed</returns>
        public new List<SqlScript> GetScriptsToExecute()
        {
            using (configuration.ConnectionManager.OperationStarting(configuration.Log, new List<DbUp.Engine.SqlScript>()))
            {
                return GetScriptsToExecuteInsideOperation();
            }
        }
        ///<summary>
        /// Creates version record for any new migration scripts without executing them.
        /// Useful for bringing development environments into sync with automated environments
        ///</summary>
        ///<returns></returns>
        public new DatabaseUpgradeResult MarkAsExecuted()
        {
            var marked = new List<DbUp.Engine.SqlScript>();
            SqlScript executedScript = null;
            using (configuration.ConnectionManager.OperationStarting(configuration.Log, marked))
            {
                try
                {
                    var scriptsToExecute = GetScriptsToExecuteInsideOperation();

                    foreach (var script in scriptsToExecute)
                    {
                        executedScript = script;
                        configuration.ConnectionManager.ExecuteCommandsWithManagedConnection(
                            connectionFactory => configuration.Journal.StoreExecutedScript(script, connectionFactory));
                        configuration.Log.WriteInformation("Marking script {0} as executed", script.Name);
                        marked.Add(script);
                    }

                    configuration.Log.WriteInformation("Script marking successful");
                    return new DatabaseUpgradeResult(marked, true, null, null);
                }
                catch (Exception ex)
                {
                    configuration.Log.WriteError("Upgrade failed due to an unexpected exception:\r\n{0}", ex.ToString());
                    return new DatabaseUpgradeResult(marked, false, ex, executedScript);
                }
            }
        }
    }
}
