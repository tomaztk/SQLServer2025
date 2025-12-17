

/*
 ABORT QUERY EXECUTION
*/

USE [db_16_IQP];
GO

-- 0. Enable query store

USE master;
GO
ALTER DATABASE [db_16_IQP]
SET QUERY_STORE = ON;
GO
 
ALTER DATABASE [db_16_IQP] 
SET QUERY_STORE CLEAR;
GO


-- 0. Run the long running query

USE [db_16_IQP];
GO

WITH LargeDataSet AS (
    SELECT 
    O1.productID as P1
    ,O1.Quantity as Q1
    ,O2.ProductID as P2
    ,O2.Quantity as Q2
    ,O2.CreatedDate AS CDate
      FROM  [dbo].[OrderLines] as O1
      CROSS JOIN  [dbo].[OrderLines] as O2
    
)
SELECT 
* FrOM
    LargeDataSet  AS LDS
WHERE LDS.Q1 < 2 
  AND LDS.P2 > 4997 
  AND LDS.Q2 = 1 
  AND LDS.P1 < 6;
GO



-- 1. Find top duration queries

USE [db_16_IQP];
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
query_id plan_id avg_duration count_exections
1	1	17459691	1
*/

-- use query hint
USE [db_16_IQP];
GO
EXEC sys.sp_query_store_set_hints
 @query_id = 1,
 @query_hints = N'OPTION (USE HINT (''ABORT_QUERY_EXECUTION''))';
GO


-- Run same poor query again

USE [db_16_IQP];
GO

WITH LargeDataSet AS (
    SELECT 
    O1.productID as P1
    ,O1.Quantity as Q1
    ,O2.ProductID as P2
    ,O2.Quantity as Q2
    ,O2.CreatedDate AS CDate
      FROM  [dbo].[OrderLines] as O1
      CROSS JOIN  [dbo].[OrderLines] as O2
    
)
SELECT 
* FrOM
    LargeDataSet  AS LDS
WHERE LDS.Q1 < 2 
  AND LDS.P2 > 4997 
  AND LDS.Q2 = 1 
  AND LDS.P1 < 6;
GO




-- 1. and check again

USE [db_16_IQP];
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
    plan_id asc
GO



-- Check blocked queries

SELECT  qsh.query_id
       ,q.query_hash
       ,qt.query_sql_text
       ,qsh.query_hint_text
FROM sys.query_store_query_hints AS qsh
INNER JOIN sys.query_store_query AS q
ON qsh.query_id = q.query_id
INNER JOIN sys.query_store_query_text AS qt
ON q.query_text_id = qt.query_text_id
WHERE UPPER(qsh.query_hint_text) LIKE '%ABORT[_]QUERY[_]EXECUTION%'



