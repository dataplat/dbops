using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DBOps
{
    public class UpgradeConfiguration : DbUp.Builder.UpgradeConfiguration
    {
        public UpgradeConfiguration() : base() { }
        /// <summary>
        /// Gets or sets the journal, which tracks the scripts that have already been run.
        /// </summary>
        public new IJournal Journal { get; set; }
        /// <summary>
        /// Gets or sets the script filter, which filters the scripts before execution
        /// </summary>
        public new IScriptFilter ScriptFilter { get; set; } = new DefaultScriptFilter();
        /// <summary>
        /// Gets or sets the comparer used to sort scripts and match script names against the log of already run scripts.
        /// The default comparer is <see cref="StringComparer.Ordinal"/> and doesn't compare checksum.
        /// </summary>
        public ExecutedScriptComparer ExecutedScriptComparer { get; set; } = new ExecutedScriptComparer(StringComparer.Ordinal, false);

    }
}
