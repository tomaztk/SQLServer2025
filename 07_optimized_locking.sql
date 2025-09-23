USE AdventureWorks;
GO
SELECT 
    resource_type,
    resource_database_id,
    resource_associated_entity_id,
   -- resource_description,
    request_mode,
    request_session_id,
    request_status,
    COUNT(*) AS lock_count
FROM 
    sys.dm_tran_locks
WHERE resource_type != 'DATABASE'
GROUP BY 
    resource_type,
    resource_database_id,
    resource_associated_entity_id,
    request_mode,
    request_session_id,
    request_status
ORDER BY 
    resource_type,
    resource_database_id,
    resource_associated_entity_id,
    request_mode,
    request_session_id,
    request_status;
GO



-- Step 2:

/*
resource_type	resource_database_id	resource_associated_entity_id	request_mode	request_session_id	request_status	lock_count
METADATA	           12	            0	                            Sch-S	        151	                GRANT	1
OBJECT	            12	                1602104748                  	X	            151	                GRANT	1

*/


-- Step 6:
-- Run locks

/*

resource_type	resource_database_id	resource_associated_entity_id	request_mode	request_session_id	request_status	lock_count
OBJECT	12	1602104748	IX	154	WAIT	1
OBJECT	12	1602104748	X	151	GRANT	1
*/


-- Run DM_EXEC Requests
SELECT 
    blocking_session_id AS BlockingSessionID,
    session_id AS BlockedSessionID,
    wait_type,
    wait_time,
    wait_resource,
    DB_NAME(database_id) AS DatabaseName,
    TEXT AS BlockingQuery
FROM 
    sys.dm_exec_requests
CROSS APPLY 
    sys.dm_exec_sql_text(sql_handle)
WHERE 
    blocking_session_id <> 0
ORDER BY 
    BlockingSessionID, BlockedSessionID;
GO


/*
BlockingSessionID	BlockedSessionID	wait_type	wait_time	wait_resource	DatabaseName	BlockingQuery
151	154	LCK_M_IX	29655	OBJECT: 12:1602104748:0 	AdventureWorks	-- Update the highest salesorderid  DECLARE @maxsalesorderid I

*/



-- step 9:
-- enable: optimized locking
-- make sure to have ADR enabled!

USE [master];
GO
ALTER DATABASE [AdventureWorks]
SET ACCELERATED_DATABASE_RECOVERY = ON
WITH ROLLBACK IMMEDIATE;
GO

USE MASTER;
GO
ALTER DATABASE [AdventureWorks]
SET OPTIMIZED_LOCKING = ON
WITH ROLLBACK IMMEDIATE;
GO


/*
-- not blocking and the have 
-- XACT type on the table menaing that another transaction can do updated and are not blocked

-- Each query have transaction locks and they are not blocking each other
resource_type	resource_database_id	resource_associated_entity_id	request_mode	request_session_id	request_status	lock_count
METADATA	12	0	Sch-S	53	GRANT	1
METADATA	12	0	Sch-S	59	GRANT	1
OBJECT	12	1602104748	IX	53	GRANT	1
OBJECT	12	1602104748	IX	59	GRANT	1
XACT	12	0	X	53	GRANT	1
XACT	12	0	X	59	GRANT	1

*/


-- same logic happens with 

USE [master];
GO
ALTER DATABASE [AdventureWorks]
SET READ_COMMITTED_SNAPSHOT ON
WITH ROLLBACK IMMEDIATE;
GO

-- with two separate updates

-- query 1
USE AdventureWorks;
GO
-- Update a specific purchase order number
DECLARE @minsalesorderid INT;
SELECT @minsalesorderid = MIN(SalesOrderID) FROM Sales.SalesOrderHeader;
BEGIN TRAN;
UPDATE Sales.SalesOrderHeader
SET Freight = Freight * .10
WHERE PurchaseOrderNumber = 'PO522145787';
GO

-- Rollback transaction if needed
ROLLBACK TRAN;
GO


-- query 2
USE AdventureWorks;
GO
-- Update a specific purchase order number
DECLARE @minsalesorderid INT;
SELECT @minsalesorderid = MIN(SalesOrderID) FROM Sales.SalesOrderHeader;
BEGIN TRAN;
UPDATE Sales.SalesOrderHeader
SET Freight = Freight * .10
WHERE PurchaseOrderNumber = 'PO522145787';
GO

-- Rollback transaction if needed
ROLLBACK TRAN;
GO