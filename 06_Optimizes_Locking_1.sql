/*
Optimized Locking - SQL Server 2025

*/


-- 1. Run this with open Transanctions

USE AdventureWorks;
GO
-- Run this batch first to update 10000 rows
DECLARE @minsalesorderid INT;
SELECT @minsalesorderid = MIN(SalesOrderID) FROM Sales.SalesOrderHeader;
BEGIN TRAN
UPDATE Sales.SalesOrderHeader
SET Freight = Freight * .10
WHERE SalesOrderID <= @minsalesorderid + 10000;
GO
-- (10001 rows affected) 


-- Rollback the transaction when needed
ROLLBACK TRAN;
GO


-- Step 2:
-- Check locks in file 07_optimized_locking.sql


-- Step 3:
-- Rollback tran

-- Step 4:
--check locks

-- Repeat step 2-3-4

-- Step 5:
-- Run max updates with open tran
-- go to 08_optimized_locking.sql


-- step 6:
-- check locks