using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace DBOps.Packaging
{
    // Package container object interface
    interface IPackageMember
    {
        // Retrieve a path inside a package
        string GetPackagePath();
        // Retrieve a path as stored in a SchemaVersions table
        string GetDeploymentPath();
    }
}
