SELECT tablename as "name", schemaname AS "schema" FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema');