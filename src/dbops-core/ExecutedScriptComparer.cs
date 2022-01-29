using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DBOps
{
    public class ExecutedScriptComparer : IComparer<ExecutedScript>, IEqualityComparer<ExecutedScript>
    {
        readonly IComparer<string> comparer;
        readonly bool CompareChecksum;

        public ExecutedScriptComparer(IComparer<string> comparer, bool compareChecksum)
        {
            this.comparer = comparer ?? throw new ArgumentNullException(nameof(comparer));
            CompareChecksum = compareChecksum;
        }

        public int Compare(ExecutedScript x, ExecutedScript y) {
            var comparedName = comparer.Compare(x.ScriptName, y.ScriptName);
            var comparedChecksum = comparer.Compare(x.Checksum, y.Checksum);
            if (comparedName != 0 || !CompareChecksum) {
                return comparedName;
            }
            else
            {
                return comparedChecksum;
            }
        }

        public bool Equals(ExecutedScript x, ExecutedScript y) => Compare(x, y) == 0;

        public int GetHashCode(ExecutedScript obj) => obj.GetHashCode();
    }
}
