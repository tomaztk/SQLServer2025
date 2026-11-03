/* =====================================================================
   04_monitor_ces.sql
   Health checks for change event streaming. Run as db_owner / sysadmin.
   ===================================================================== */
:setvar DatabaseName "CesDemo"

USE [$(DatabaseName)];
GO

-- Is CES enabled, and what is holding the log?
SELECT name, is_event_stream_enabled, recovery_model_desc, log_reuse_wait_desc
FROM sys.databases WHERE database_id = DB_ID();

-- Which tables are streamed
SELECT SCHEMA_NAME(schema_id) AS [schema], name AS [table], is_replicated
FROM sys.tables ORDER BY 1, 2;

-- Stream group / destination configuration
EXEC sys.sp_help_change_feed_settings;
EXEC sys.sp_help_change_feed;
EXEC sys.sp_help_change_feed_table_groups;
EXEC sys.sp_help_change_feed_table @source_schema = N'dbo', @source_name = N'Orders';

-- Delivery errors (credential, network, message size, throttling ...)
SELECT TOP (50) * FROM sys.dm_change_feed_errors ORDER BY 1 DESC;

-- Log scan activity (latency / throughput of the CES log reader)
SELECT TOP (20) * FROM sys.dm_change_feed_log_scan_sessions ORDER BY 1 DESC;

-- Transaction log usage. CES holds log truncation until changes are delivered,
-- so watch this on SQL Server on Azure VMs - you own this, Azure does not.
SELECT total_log_size_in_bytes / 1048576.0  AS total_log_mb,
       used_log_space_in_bytes / 1048576.0  AS used_log_mb,
       used_log_space_in_percent
FROM sys.dm_db_log_space_usage;
GO

/* Extended Events: message-size failures are only visible through XE in
   SQL Server 2025. A quick session that captures the CES events:        */
/*
CREATE EVENT SESSION [ces_trace] ON SERVER
ADD EVENT sqlserver.error_reported (WHERE ([severity] >= 11))
ADD TARGET package0.ring_buffer
WITH (MAX_DURATION = 30 MINUTES);   -- time-bound session (new in SQL Server 2025)
ALTER EVENT SESSION [ces_trace] ON SERVER STATE = START;
-- Browse sys.dm_xe_objects WHERE name LIKE '%change_feed%' OR name LIKE '%event_stream%'
-- to add the CES specific events available in your build.
*/
