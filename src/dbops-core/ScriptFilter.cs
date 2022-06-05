using System.Collections.Generic;
using System.Linq;
using DbUp.Support;
using DbUp.Engine;

namespace DBOps
{
    public class ScriptFilter : IScriptFilter
    {
        public IEnumerable<DbUp.Engine.SqlScript> Filter(IEnumerable<DbUp.Engine.SqlScript> sorted, HashSet<string> executedScriptNames, ScriptNameComparer comparer)
        {
            return sorted.Where(s =>
            {
                var hashedName = $"{s.Name})|{s.GetHashCode()}";
                return s.SqlScriptOptions.ScriptType == ScriptType.RunAlways || !executedScriptNames.Contains(hashedName, comparer) || !executedScriptNames.Contains(s.Name, comparer);
            });
        }
    }
}
