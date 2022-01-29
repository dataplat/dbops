using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DBOps
{
    public class DefaultScriptFilter : IScriptFilter
    {
        public IEnumerable<SqlScript> Filter(IEnumerable<SqlScript> sorted, HashSet<ExecutedScript> executedScripts, ExecutedScriptComparer comparer)
             => sorted.Where(s => s.SqlScriptOptions.ScriptType == DbUp.Support.ScriptType.RunAlways || !executedScripts.Contains(new ExecutedScript(s.Name, s.GetMD5()), comparer));
    }
}
