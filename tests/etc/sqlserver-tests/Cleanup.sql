if OBJECT_ID('dbo.a') IS NOT NULL
    drop table dbo.a
if OBJECT_ID('dbo.b') IS NOT NULL
    drop table dbo.b
if OBJECT_ID('dbo.c') IS NOT NULL
    drop table dbo.c
if OBJECT_ID('dbo.d') IS NOT NULL
    drop table dbo.d
if OBJECT_ID('dbo.e') IS NOT NULL
    drop table dbo.e
if OBJECT_ID('dbo.f') IS NOT NULL
    drop table dbo.f
if OBJECT_ID('testschema.a') IS NOT NULL
    drop table testschema.a
if OBJECT_ID('testschema.b') IS NOT NULL
    drop table testschema.b
if OBJECT_ID('testschema.c') IS NOT NULL
    drop table testschema.c
if OBJECT_ID('testschema.d') IS NOT NULL
    drop table testschema.d
if OBJECT_ID('dbo.testdeploymenthistory') IS NOT NULL
    drop table dbo.testdeploymenthistory
if OBJECT_ID('testschema.testdeploymenthistory') IS NOT NULL
    drop table testschema.testdeploymenthistory
if OBJECT_ID('testschema.SchemaVersions') IS NOT NULL
    drop table testschema.SchemaVersions
if OBJECT_ID('dbo.SchemaVersions') IS NOT NULL
    drop table dbo.SchemaVersions
if exists (select * from sys.schemas where name = 'testschema')
    drop schema testschema