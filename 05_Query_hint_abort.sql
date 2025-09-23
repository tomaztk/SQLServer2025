

/*
SQL Server 2025 - ABORT QUERY EXECUTION
New query hint, ABORT_QUERY_EXECUTION. The hint is intended to be used as a Query Store hint to let
 administrators block future execution of known problematic queries,
 for example non-essential queries causing high resource consumption and affecting application workloads.


*/

USE MASTER;
GO

RESTORE DATABASE AdventureWorks FROM DISK = 'C:\sql_sample_databases\AdventureWorks2022.bak'
WITH MOVE 'AdventureWorks2022' TO 'c:\data\AdventureWorks.mdf',
MOVE 'AdventureWorks2022_Log' TO 'c:\data\AdventureWorks_log.ldf'
GO

-- 0. Enable query store

USE master;
GO
ALTER DATABASE [AdventureWorks]
SET QUERY_STORE = ON;
GO
-- Clear the query store
ALTER DATABASE [AdventureWorks] 
SET QUERY_STORE CLEAR;
GO

-- 0. Run the "poor" query

USE [AdventureWorks];
GO
WITH LargeDataSet AS (
    SELECT 
        p.ProductID, p.Name, p.ProductNumber, p.Color, 
        s.SalesOrderID, s.OrderQty, s.UnitPrice, s.LineTotal, 
        c.CustomerID, c.AccountNumber,
        (SELECT AVG(UnitPrice) FROM Sales.SalesOrderDetail WHERE ProductID = p.ProductID) AS AvgUnitPrice,
        (SELECT COUNT(*) FROM Sales.SalesOrderDetail WHERE ProductID = p.ProductID) AS OrderCount,
        (SELECT SUM(LineTotal) FROM Sales.SalesOrderDetail WHERE ProductID = p.ProductID) AS TotalSales,
        (SELECT MAX(OrderDate) FROM Sales.SalesOrderHeader WHERE CustomerID = c.CustomerID) AS LastOrderDate,
        r.ReviewCount
    FROM 
        Production.Product p
    JOIN 
        Sales.SalesOrderDetail s ON p.ProductID = s.ProductID
    JOIN 
        Sales.SalesOrderHeader h ON s.SalesOrderID = h.SalesOrderID
    JOIN 
        Sales.Customer c ON h.CustomerID = c.CustomerID
    JOIN 
        (SELECT 
             ProductID, COUNT(*) AS ReviewCount 
         FROM 
             Production.ProductReview 
         GROUP BY 
             ProductID) r ON p.ProductID = r.ProductID
     CROSS JOIN 
       (SELECT TOP 1000 * FROM Sales.SalesOrderDetail) s2
)
SELECT 
    ld.ProductID, ld.Name, ld.ProductNumber, ld.Color, 
    ld.SalesOrderID, ld.OrderQty, ld.UnitPrice, ld.LineTotal, 
    ld.CustomerID, ld.AccountNumber, ld.AvgUnitPrice, ld.OrderCount, ld.TotalSales, ld.LastOrderDate, ld.ReviewCount
FROM 
    LargeDataSet ld
ORDER BY 
    ld.OrderQty DESC, ld.ReviewCount ASC;
GO



-- 1. Find top duration queries

USE AdventureWorks;
GO
SELECT 
    qsqt.query_sql_text,
    qsp.plan_id,
    qsp.query_id,
    rs.avg_duration,
    rs.count_executions
FROM 
    sys.query_store_query_text AS qsqt
JOIN 
    sys.query_store_query AS qsq
    ON qsqt.query_text_id = qsq.query_text_id
JOIN 
    sys.query_store_plan AS qsp
    ON qsq.query_id = qsp.query_id
JOIN 
    sys.query_store_runtime_stats AS rs
    ON qsp.plan_id = rs.plan_id
GROUP BY qsqt.query_sql_text, qsp.plan_id, qsp.query_id, rs.avg_duration, rs.count_executions
ORDER BY 
    rs.avg_duration DESC;
GO

-- use query hint
USE AdventureWorks;
GO
EXEC sys.sp_query_store_set_hints
 @query_id = 9,
 @query_hints = N'OPTION (USE HINT (''ABORT_QUERY_EXECUTION''))';
GO


-- Run same poor query again


USE [AdventureWorks];
GO
WITH LargeDataSet AS (
    SELECT 
        p.ProductID, p.Name, p.ProductNumber, p.Color, 
        s.SalesOrderID, s.OrderQty, s.UnitPrice, s.LineTotal, 
        c.CustomerID, c.AccountNumber,
        (SELECT AVG(UnitPrice) FROM Sales.SalesOrderDetail WHERE ProductID = p.ProductID) AS AvgUnitPrice,
        (SELECT COUNT(*) FROM Sales.SalesOrderDetail WHERE ProductID = p.ProductID) AS OrderCount,
        (SELECT SUM(LineTotal) FROM Sales.SalesOrderDetail WHERE ProductID = p.ProductID) AS TotalSales,
        (SELECT MAX(OrderDate) FROM Sales.SalesOrderHeader WHERE CustomerID = c.CustomerID) AS LastOrderDate,
        r.ReviewCount
    FROM 
        Production.Product p
    JOIN 
        Sales.SalesOrderDetail s ON p.ProductID = s.ProductID
    JOIN 
        Sales.SalesOrderHeader h ON s.SalesOrderID = h.SalesOrderID
    JOIN 
        Sales.Customer c ON h.CustomerID = c.CustomerID
    JOIN 
        (SELECT 
             ProductID, COUNT(*) AS ReviewCount 
         FROM 
             Production.ProductReview 
         GROUP BY 
             ProductID) r ON p.ProductID = r.ProductID
     CROSS JOIN 
       (SELECT TOP 1000 * FROM Sales.SalesOrderDetail) s2
)
SELECT 
    ld.ProductID, ld.Name, ld.ProductNumber, ld.Color, 
    ld.SalesOrderID, ld.OrderQty, ld.UnitPrice, ld.LineTotal, 
    ld.CustomerID, ld.AccountNumber, ld.AvgUnitPrice, ld.OrderCount, ld.TotalSales, ld.LastOrderDate, ld.ReviewCount
FROM 
    LargeDataSet ld
ORDER BY 
    ld.OrderQty DESC, ld.ReviewCount ASC;
GO





-- 1. and check again

USE AdventureWorks;
GO
SELECT 
    qsqt.query_sql_text,
    qsp.plan_id,
    qsp.query_id,
    rs.avg_duration,
    rs.count_executions
FROM 
    sys.query_store_query_text AS qsqt
JOIN 
    sys.query_store_query AS qsq
    ON qsqt.query_text_id = qsq.query_text_id
JOIN 
    sys.query_store_plan AS qsp
    ON qsq.query_id = qsp.query_id
JOIN 
    sys.query_store_runtime_stats AS rs
    ON qsp.plan_id = rs.plan_id
GROUP BY qsqt.query_sql_text, qsp.plan_id, qsp.query_id, rs.avg_duration, rs.count_executions
ORDER BY 
    rs.avg_duration DESC;
GO


/*


results:

query_sql_text	     plan_id	query_id	avg_duration	count_executions
WITH LargeDataSet AS 	1	    9	        21993940	     1
WITH LargeDataSet AS	1	    9	         1170	        1


*/



-- 0. Clear query hints

USE AdventureWorks;
GO
EXEC sys.sp_query_store_clear_hints @query_id = 9;
GO


-- Check blocked queries

SELECT qsh.query_id,
       q.query_hash,
       qt.query_sql_text
FROM sys.query_store_query_hints AS qsh
INNER JOIN sys.query_store_query AS q
ON qsh.query_id = q.query_id
INNER JOIN sys.query_store_query_text AS qt
ON q.query_text_id = qt.query_text_id
WHERE UPPER(qsh.query_hint_text) LIKE '%ABORT[_]QUERY[_]EXECUTION%'