using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DBOps
{
    class ScriptComparer : IEqualityComparer<string>, IComparer<string>
    {
        class ScriptWithChecksum
        {
            public string Name;
            public string Checksum = "";

            public ScriptWithChecksum(string script)
            {
                var items = script.Split(':');
                if (items.Last() == "dbops+checksum")
                {
                    Name = string.Join(":", items.Take(items.Length - 2));
                    Checksum = items[items.Length - 2];
                }
                else
                {
                    Name = script;
                }
            }

            public bool Equals(ScriptWithChecksum x)
            {
                return x.Name.Equals(Name) && x.Checksum.Equals(Checksum);
            }
            public new int GetHashCode()
            {
                return Name.GetHashCode();
            }
        }
        List<SqlScript> Scripts;
        ScriptComparer(List<SqlScript> scriptList)
        {
            Scripts = scriptList;
        }
        public bool Equals(string x, string y) {
            return (new ScriptWithChecksum(x)).Equals(new ScriptWithChecksum(y));
        }
        int IEqualityComparer<string>.GetHashCode(string x)
        {
            return (new ScriptWithChecksum(x)).GetHashCode();
        }

        int IComparer<string>.Compare(string x, string y)
        {
            var list = (List<String>)(Scripts.Select(s => s.Name));
            return list.IndexOf(x).CompareTo(list.IndexOf(y));
        }
    }
}
