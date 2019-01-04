$enums = @'
namespace DBOps {
    public enum ConnectionType {
        SQLServer,
        Oracle,
        MySql
    }
    public enum ConfigProperty {
        ApplicationName,
        SqlInstance,
        Database,
        DeploymentMethod,
        ConnectionTimeout,
        ExecutionTimeout,
        Encrypt,
        Credential,
        Username,
        Password,
        SchemaVersionTable,
        Silent,
        Variables,
        Schema,
        ConnectionString,
        CreateDatabase,
    }
}
'@
Add-Type -TypeDefinition $enums -ErrorAction Stop