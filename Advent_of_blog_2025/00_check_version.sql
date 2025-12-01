USE MASTER;
GO

SELECT 
 @@VERSION
,@@MICROSOFTVERSION


SELECT compatibility_level, database_id, name
FROM sys.databases
GO

