/*

IQP - OPPO behaviour

*/


USE MASTER;
GO

CREATE DATABASE db_16_IQP;
GO

USE db_16_IQP;
GO


Use db_16_IQP
GO

-- IS enabled by default; for test, we will turn it off and then on
ALTER DATABASE SCOPED CONFIGURATION SET OPTIONAL_PARAMETER_OPTIMIZATION = OFF; --ON;
GO

DROP TABLE IF EXISTS OrderLines;
GO

CREATE TABLE OrderLines
(
     OrderLineId  int IDENTITY(1,1) PRIMARY KEY
    ,ProductId    int NOT NULL
    ,Quantity     int NOT NULL
    ,Price        money NOT NULL
    ,CreatedDate  datetime2 NOT NULL DEFAULT sysutcdatetime()
);

-- Get some sample data
INSERT INTO OrderLines (ProductId, Quantity, Price)
SELECT TOP (5000000)
       ABS(CHECKSUM(NEWID())) % 5000 + 1,
       1 + ABS(CHECKSUM(NEWID())) % 5,
       10.00 + ABS(CHECKSUM(NEWID())) % 100
FROM sys.all_objects AS a 
 CROSS JOIN sys.all_objects AS b;
GO
-- (5000000 rows affected)
-- Duration 23s



CREATE INDEX IX_Product On dbo.OrderLines(ProductId)
WITH (Data_Compression = Page)
GO


-- the magic procedure
CREATE OR ALTER PROCEDURE dbo.GetOrderLines
    @ProductId int = NULL
AS
BEGIN
    SELECT *
    FROM OrderLines
    WHERE (@ProductId IS NULL OR ProductId = @ProductId);
END;
GO

-- TEST!

DBCC FREEPROCCACHE;
GO

-- with product id + check exec plan
EXECUTE GetOrderLines @ProductId=4096;
GO


-- with no product ID + exec
EXECUTE GetOrderLines;
GO


-- with  product ID + check exec plan again
EXECUTE GetOrderLines @ProductId=19;
GO

EXECUTE GetOrderLines @ProductId=574;
GO


-- You still want to refactor obviously problematic procedures. Sometimes splitting procedures or
-- using different patterns is cleaner than relying entirely on OPPO.

ALTER DATABASE db_16_IQP SET QUERY_STORE CLEAR;
GO

SELECT
    p.query_id,
    p.plan_id,
    p.last_force_failure_reason_desc,
    p.force_failure_count,
    p.last_compile_start_time,
    p.last_execution_time,
    p.*,
    q.last_bind_duration,
    q.query_parameterization_type_desc,
    q.context_settings_id,
    c.set_options,
    c.STATUS
    ,t.*
FROM sys.query_store_plan p
INNER JOIN sys.query_store_query q
    ON p.query_id = q.query_id
INNER JOIN sys.query_context_settings c
    ON c.context_settings_id = q.context_settings_id
LEFT JOIN sys.query_store_query_text t
    ON q.query_text_id = t.query_text_id



-- IS enabled by default; for test, we will turn it off and then on
ALTER DATABASE SCOPED CONFIGURATION SET OPTIONAL_PARAMETER_OPTIMIZATION = ON;
GO



DBCC FREEPROCCACHE;
GO

-- with product id + check exec plan
EXECUTE GetOrderLines @ProductId=4096;
GO


-- with no product ID + exec
EXECUTE GetOrderLines;
GO


-- with  product ID + check exec plan again
EXECUTE GetOrderLines @ProductId=19;
GO

EXECUTE GetOrderLines @ProductId=574;
GO




-- the magic procedure #2 where OPPO will not perform as good!
CREATE OR ALTER PROCEDURE dbo.GetOrderLines2
     @ProductId int = NULL
    ,@QuantityP int = NULL
AS
BEGIN
    SELECT *
    FROM OrderLines
    WHERE 
       (@ProductId IS NULL OR ProductId = @ProductId) 
    AND
       (@QuantityP IS NULL or Price = @QuantityP )

END;
GO