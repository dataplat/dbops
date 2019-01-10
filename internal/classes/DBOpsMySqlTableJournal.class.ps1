class DBOpsMySqlTableJournal : DbUp.MySql.MySqlTableJournal {
    # Constructors
    DBOpsMySqlTableJournal([Func[DbUp.Engine.Transactions.IConnectionManager]] $connectionManager, [Func[DbUp.Engine.Output.IUpgradeLog]] $logger, [string] $schema, [string] $table) :base($connectionManager, $logger, $schema, $table) {}
    # Overriding DoesTalbeExist method to get the proper schema table when schemaversiontable name is not specified
    [string] DoesTableExistSql() {
        if ($this.SchemaTableSchema) {
            return "select 1 from INFORMATION_SCHEMA.TABLES where TABLE_NAME = '{0}' and TABLE_SCHEMA = '{1}'" -f $this.UnquotedSchemaTableName, $this.SchemaTableSchema
        }
        else {
            return "select 1 from INFORMATION_SCHEMA.TABLES where TABLE_NAME = '{0}' and TABLE_SCHEMA = DATABASE()" -f $this.UnquotedSchemaTableName
        }
    }
}