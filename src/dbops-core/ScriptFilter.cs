using System.Collections.Generic;
using System.Linq;
using DbUp.Support;
using DbUp.Engine;

namespace DBOps
{
    public class ChecksumValidatingScriptFilter : IScriptFilter
    {
        public IEnumerable<DbUp.Engine.SqlScript> Filter(IEnumerable<DbUp.Engine.SqlScript> sorted, HashSet<string> executedScriptNames, ScriptNameComparer comparer)
        {
            return sorted.Where(s =>
            {
                SqlScript script = (SqlScript)s;
                var hashedName = $"{script.Name})|{script.GetHashCode()}";
                return script.SqlScriptOptions.ScriptType == ScriptType.RunAlways || !executedScriptNames.Contains(hashedName, comparer) || !executedScriptNames.Contains(script.Name, comparer);
            });
        }
    }
}
