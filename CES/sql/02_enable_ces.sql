/* =====================================================================
   02_enable_ces.sql
   Enables Change Event Streaming (CES) on the demo database and streams
   the demo tables to Azure Event Hubs over the Kafka protocol
   (destination type AzureEventHubsApacheKafka, port 9093).

   CesAuthMode:
     SAS             - Shared access policy with Send rights (works on every CU).
     ManagedIdentity - Microsoft Entra / managed identity. SQL Server 2025 CU3+
                       on an Azure VM (or Arc) with Entra auth configured for the
                       instance, and "Azure Event Hubs Data Sender" granted on the hub.

   RecreateStreamGroup = 1 drops and re-creates the stream group so that a
   changed destination / key / partitioning is applied. Idempotent either way.
   ===================================================================== */
:setvar DatabaseName         "CesDemo"
:setvar EventHubNamespace    "<your-namespace>"
:setvar EventHubName         "sql-changes"
:setvar CesAuthMode          "SAS"
:setvar SasPolicyName        "ces-sender"
:setvar SasKey               "<primary-key-of-ces-sender-policy>"
:setvar MasterKeyPassword    "ChangeMe_MasterKey!2026"
:setvar CredentialName       "CesEventHubCredential"
:setvar StreamGroupName      "CesDemoGroup"
:setvar PartitionKeyScheme   "Table"
:setvar MaxMessageSizeKb     "256"
:setvar Tables               "dbo.Customers,dbo.Products,dbo.Orders,dbo.OrderLines"
:setvar RecreateStreamGroup  "0"

SET NOCOUNT ON;
SET XACT_ABORT ON;
USE [$(DatabaseName)];
GO

-- Prerequisites ---------------------------------------------------------
IF (SELECT recovery_model_desc FROM sys.databases WHERE database_id = DB_ID()) <> 'FULL'
    THROW 50001, 'CES requires the FULL recovery model. Run 01_create_demo_database.sql first.', 1;

ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

-- 1. Database master key ------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
BEGIN
    PRINT 'Creating database master key';
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$(MasterKeyPassword)';
END
GO

-- 2. Database scoped credential (create or rotate) -----------------------
DECLARE @mode sysname = N'$(CesAuthMode)';
DECLARE @verb nvarchar(10) =
    CASE WHEN EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = N'$(CredentialName)')
         THEN N'ALTER' ELSE N'CREATE' END;
DECLARE @sql nvarchar(max);

IF @mode = N'ManagedIdentity'
    SET @sql = @verb + N' DATABASE SCOPED CREDENTIAL [$(CredentialName)] WITH IDENTITY = ''Managed Identity'';';
ELSE IF @mode = N'SAS'
    SET @sql = @verb + N' DATABASE SCOPED CREDENTIAL [$(CredentialName)] WITH IDENTITY = N''' + REPLACE(N'$(SasPolicyName)', N'''', N'''''')
             + N''', SECRET = N''' + REPLACE(N'$(SasKey)', N'''', N'''''') + N''';';
ELSE
    THROW 50002, 'CesAuthMode must be SAS or ManagedIdentity.', 1;

PRINT @verb + ' credential [$(CredentialName)] using ' + @mode;
EXEC sys.sp_executesql @sql;
GO

-- 3. Enable CES on the database -----------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE database_id = DB_ID() AND is_event_stream_enabled = 1)
BEGIN
    PRINT 'Enabling change event streaming';
    EXEC sys.sp_enable_event_stream;
END
ELSE
    PRINT 'Change event streaming already enabled';
GO

-- 4. (optional) Tear down an existing stream group so new settings apply --
IF N'$(RecreateStreamGroup)' = N'1'
BEGIN
    DECLARE @plain nvarchar(512);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT SCHEMA_NAME(schema_id) + N'.' + name   -- two-part name, no brackets
        FROM sys.tables WHERE is_replicated = 1;
    OPEN c;
    FETCH NEXT FROM c INTO @plain;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC sys.sp_remove_object_from_event_stream_group N'$(StreamGroupName)', @plain;
            PRINT 'Removed ' + @plain + ' from stream group';
        END TRY
        BEGIN CATCH
            PRINT 'Could not remove ' + @plain + ': ' + ERROR_MESSAGE();
        END CATCH
        FETCH NEXT FROM c INTO @plain;
    END
    CLOSE c; DEALLOCATE c;

    BEGIN TRY
        EXEC sys.sp_drop_event_stream_group N'$(StreamGroupName)';
        PRINT 'Dropped stream group $(StreamGroupName)';
    END TRY
    BEGIN CATCH
        PRINT 'Stream group not dropped (probably did not exist): ' + ERROR_MESSAGE();
    END CATCH
END
GO

-- 5. Create the stream group --------------------------------------------
DECLARE @rc int;
DECLARE @destination nvarchar(4000) = N'$(EventHubNamespace).servicebus.windows.net:9093/$(EventHubName)';
BEGIN TRY
    EXEC @rc = sys.sp_create_event_stream_group
        @stream_group_name      = N'$(StreamGroupName)',
        @destination_type       = N'AzureEventHubsApacheKafka',   -- AMQP is deprecated
        @destination_location   = @destination,
        @destination_credential = N'$(CredentialName)',
        @max_message_size_kb    = $(MaxMessageSizeKb),
        @partition_key_scheme   = N'$(PartitionKeyScheme)',
        @encoding               = N'JSON';
    IF @rc <> 0 THROW 50003, 'sp_create_event_stream_group returned a failure code.', 1;
    PRINT 'Created stream group $(StreamGroupName) -> ' + @destination;
END TRY
BEGIN CATCH
    IF N'$(RecreateStreamGroup)' = N'1' THROW;  -- after a teardown, a failure is real
    PRINT 'Stream group not created (it probably exists already): ' + ERROR_MESSAGE();
END CATCH
GO

-- 6. Add tables to the stream group -------------------------------------
DECLARE @tables TABLE (name nvarchar(512));
INSERT @tables (name)
SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(N'$(Tables)', N',') WHERE LTRIM(RTRIM(value)) <> N'';

DECLARE @t nvarchar(512), @rc int;
DECLARE tc CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM @tables;
OPEN tc;
FETCH NEXT FROM tc INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID(@t, N'U') IS NULL
        PRINT 'Skipping ' + @t + ' (table not found)';
    ELSE IF EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID(@t) AND is_replicated = 1)
        PRINT @t + ' is already streamed';
    ELSE
    BEGIN
        EXEC @rc = sys.sp_add_object_to_event_stream_group
            @stream_group_name   = N'$(StreamGroupName)',
            @object_name         = @t,
            @include_all_columns = 1,   -- full row image in "current"
            @include_old_values  = 1;   -- previous row image in "old" for UPD/DEL
        IF @rc <> 0 THROW 50004, 'sp_add_object_to_event_stream_group failed.', 1;
        PRINT 'Added ' + @t + ' to stream group $(StreamGroupName)';
    END
    FETCH NEXT FROM tc INTO @t;
END
CLOSE tc; DEALLOCATE tc;
GO

-- 7. Show the result ----------------------------------------------------
SELECT name, is_event_stream_enabled FROM sys.databases WHERE database_id = DB_ID();
SELECT SCHEMA_NAME(schema_id) AS [schema], name AS [table], is_replicated FROM sys.tables ORDER BY 1, 2;
EXEC sys.sp_help_change_feed_settings;
GO

PRINT '02_enable_ces.sql completed';
GO
