/* =====================================================================
   99_disable_ces.sql
   Removes all tables from the stream group, drops the group, disables CES.
   Optionally drops the demo database and login.
   ===================================================================== */
:setvar DatabaseName    "CesDemo"
:setvar StreamGroupName "CesDemoGroup"
:setvar SimulatorLogin  "ces_simulator"
:setvar DropDatabase    "0"

SET NOCOUNT ON;
USE [$(DatabaseName)];
GO

DECLARE @t nvarchar(512);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT SCHEMA_NAME(schema_id) + N'.' + name FROM sys.tables WHERE is_replicated = 1;
OPEN c; FETCH NEXT FROM c INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sys.sp_remove_object_from_event_stream_group N'$(StreamGroupName)', @t;
    PRINT 'Removed ' + @t;
    FETCH NEXT FROM c INTO @t;
END
CLOSE c; DEALLOCATE c;
GO

BEGIN TRY EXEC sys.sp_drop_event_stream_group N'$(StreamGroupName)'; END TRY
BEGIN CATCH PRINT ERROR_MESSAGE(); END CATCH;
GO

IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id = DB_ID() AND is_event_stream_enabled = 1)
    EXEC sys.sp_disable_event_stream;
GO

USE master;
GO
IF N'$(DropDatabase)' = N'1'
BEGIN
    ALTER DATABASE [$(DatabaseName)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$(DatabaseName)];
    IF SUSER_ID(N'$(SimulatorLogin)') IS NOT NULL DROP LOGIN [$(SimulatorLogin)];
    PRINT 'Dropped database and login';
END
GO
