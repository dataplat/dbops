select t.name, t.create_date, s.name as [schema]
from sys.tables t
join sys.schemas s on s.schema_id = t.schema_id