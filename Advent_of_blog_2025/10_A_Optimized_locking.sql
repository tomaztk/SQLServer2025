-- enable Optimized locking

USE MASTER;
GO

DROP DATABASE IF EXISTS db_18_OptimizedLocking;
GO

CREATE DATABASE db_18_OptimizedLocking;
GO

USE db_18_OptimizedLocking;
GO

SELECT database_id,
       name,
       is_accelerated_database_recovery_on,
       is_read_committed_snapshot_on,
       is_optimized_locking_on
FROM sys.databases
WHERE name = DB_NAME();



--- Sample data
DROP TABLE IF EXISTS dbo.TestTable
GO
CREATE TABLE dbo.TestTable
(
ID INT NOT NULL,
Val INT
);

INSERT INTO dbo.TestTable (ID, Val) 
VALUES (1,10),(2,20),(3,30);
GO

SELECT * FROM dbo.TestTable
GO

SELECT 

 DB_NAME(database_id) AS DatabaseName
,OBJECT_NAME(object_id) AS TableName
,index_type_desc
FROM sys.dm_db_index_physical_stats(DB_ID('db_18_OptimizedLocking'), OBJECT_ID('dbo.T1'), NULL, NULL, 'DETAILED')
GO


SELECT DATABASEPROPERTYEX(DB_NAME(), 'IsOptimizedLockingOn') AS IsOptimizedLockingOn
GO

-- update query

-- file 1 (Session 1)
USE db_18_OptimizedLocking;
go

BEGIN transaction
UPDATE TestTable
SET val = val + 10
where id = 1

-- COMMIT TRANSACTION
ROLLBACK;
GO


-- file 2 (Session 2)
USE db_18_OptimizedLocking;
go

begin transaction
update TestTable
SET  val = val + 30
WHERE id = 2



-- COMMIT TRANSACTION
ROLLBACK
GO


-- file 3 (Session 3)
select 
    resource_type,
    resource_database_id,
    resource_associated_entity_id,
   -- resource_description,
    request_mode,
    request_session_id,
    request_status

 from sys.dm_tran_locks
where resource_type not in ('DATABASE')




USE [master]
GO
ALTER DATABASE [db_18_OptimizedLocking] SET ACCELERATED_DATABASE_RECOVERY = ON;
GO
ALTER DATABASE [db_18_OptimizedLocking] SET OPTIMIZED_LOCKING = ON;
GO


USE db_18_OptimizedLocking;
GO


SELECT database_id,
       name,
       is_accelerated_database_recovery_on,
       is_read_committed_snapshot_on,
       is_optimized_locking_on
FROM sys.databases
WHERE name = DB_NAME();

-- Turn on also RCSI
USE [master]
GO

ALTER DATABASE [db_18_OptimizedLocking] 
SET READ_COMMITTED_SNAPSHOT ON


USE db_18_OptimizedLocking;
GO


SELECT database_id,
       name,
       is_accelerated_database_recovery_on,
       is_read_committed_snapshot_on,
       is_optimized_locking_on
FROM sys.databases
WHERE name = DB_NAME();
