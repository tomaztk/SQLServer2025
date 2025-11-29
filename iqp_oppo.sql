--- IQP
-- OPPO behaviour

USE Sql2025Demo;
GO


DROP TABLE IF EXISTS OrderLines;
GO

CREATE TABLE OrderLines
(
    OrderLineId  int IDENTITY(1,1) PRIMARY KEY,
    ProductId    int NOT NULL,
    Quantity     int NOT NULL,
    Price        money NOT NULL,
    CreatedDate  datetime2 NOT NULL DEFAULT sysutcdatetime()
);

-- Seed sample data
INSERT INTO OrderLines (ProductId, Quantity, Price)
SELECT TOP (50000)
       ABS(CHECKSUM(NEWID())) % 5000 + 1,
       1 + ABS(CHECKSUM(NEWID())) % 5,
       10.00 + ABS(CHECKSUM(NEWID())) % 100
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
GO

CREATE OR ALTER PROCEDURE GetOrderLines
    @ProductId int = NULL
AS
BEGIN
    SELECT *
    FROM OrderLines
    WHERE (@ProductId IS NULL OR ProductId = @ProductId);
END;
GO


--- run
-- Set database compatibility level to 170 for [Sql2025Demo]
-- Call the procedure many times with a mix of NULL and non NULL @ProductId values
-- Inspect Query Store and plans to see how OPPO behaves

EXECUTE GetOrderLines;
GO
EXECUTE GetOrderLines @ProductId=4096;
GO


-- You see how SQL Server 2025 tries to fix the “one bad plan for everyone” parameter pattern. [9]


-- You still want to refactor obviously problematic procedures. Sometimes splitting procedures or
-- using different patterns is cleaner than relying entirely on OPPO.


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
FROM sys.query_store_plan p
INNER JOIN sys.query_store_query q
    ON p.query_id = q.query_id
INNER JOIN sys.query_context_settings c
    ON c.context_settings_id = q.context_settings_id
LEFT JOIN sys.query_store_query_text t
    ON q.query_text_id = t.query_text_id




