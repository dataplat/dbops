using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DBOps
{
    public class ExecutedScript : Tuple<string, string>
    {
        public ExecutedScript(string script, string checksum): base(script, checksum)
        {
        }

        public string ScriptName => Item1;
        public string Checksum => Item2;
        // override object.Equals
        //public bool Equals(ExecutedScript obj)
        //{
        //    //       
        //    // See the full list of guidelines at
        //    //   http://go.microsoft.com/fwlink/?LinkID=85237  
        //    // and also the guidance for operator== at
        //    //   http://go.microsoft.com/fwlink/?LinkId=85238
        //    //

        //    if (obj == null || GetType() != obj.GetType())
        //    {
        //        return false;
        //    }

        //    // TODO: write your implementation of Equals() here
        //    return obj.ScriptName.Equals(ScriptName) && obj.Checksum.Equals(Checksum);
        //}

        //// override object.GetHashCode
        //public override int GetHashCode()
        //{
        //    return ScriptName.GetHashCode();
        //}
    }
}
