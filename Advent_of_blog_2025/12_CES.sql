
/*

Change Event Streaming (CES)

*/


USE master
GO
 
CREATE DATABASE db_22_CES;
GO
 
USE db_22_CES
GO
 

-- Create some demo tables
CREATE TABLE dbo.Customer (
  CustomerId    int IDENTITY PRIMARY KEY,
  CustomerName  varchar(50),
  CustomerCity   varchar(20)
);
GO
 

INSERT INTO dbo.Customer (CustomerName,   CustomerCity) VALUES
  ('Awesome bikes','Manila'),
  ('Fixed Gear bikes Co.','Capetown'),
  ('Red gears', 'London');
  GO

 
CREATE TABLE dbo.Products (
  ProductId     int IDENTITY PRIMARY KEY,
  ProductName          varchar(80),
  UnitPrice     decimal(8, 2)
);
GO
 
 
INSERT INTO dbo.Products
  (ProductName,  UnitPrice) VALUES
  ('Cinelli Verduro 1024', 3899.99),
  ('Leader A 524', 1996.95);
  GO
 
 
-- procedure to add new rows to table
CREATE PROCEDURE dbo.AddProduct
  @ProductName varchar(80)
  ,@UnitPrice decimal(8,2)
AS
BEGIN
  INSERT INTO dbo.Products(ProductName,  UnitPrice)
  VALUES (@ProductName, @UnitPrice)

END
GO
 



-- Configuration
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'H@rd2Gue$$P@$$w0rd'

CREATE DATABASE SCOPED CREDENTIAL SqlCesCredential2
WITH
  IDENTITY = 'SHARED ACCESS SIGNATURE',
  SECRET = '*******token_from_powershell_Script*********'


 -- make sure to have preview feature enabled (for your database "db_22_CES")
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;

EXEC sys.sp_enable_event_stream
-- OK

SELECT is_event_stream_enabled, * FROM sys.databases  WHERE is_event_stream_enabled = 1
-- OK

-- Create event stream group
EXEC sys.sp_create_event_stream_group
@stream_group_name      = 'SqlCesGroup',
@destination_location   = 'ces-demo-sqlserver2025-namespace.servicebus.windows.net/ces-hub',
@destination_credential = SqlCesCredential2,
@destination_type       = 'AzureEventHubsAmqp'


  -- add tables
EXEC sys.sp_add_object_to_event_stream_group
  @stream_group_name = 'SqlCesGroup',
  @object_name = 'dbo.Customer',
  @include_old_values = 1,     
  @include_all_columns = 1     
 

EXEC sys.sp_add_object_to_event_stream_group
  @stream_group_name = 'SqlCesGroup',
  @object_name = 'dbo.Products',
  @include_old_values = 1,     
  @include_all_columns = 0

-- verify CES on tables:
EXEC sp_help_change_feed_table @source_schema = 'dbo', @source_name = 'Customer'
EXEC sp_help_change_feed_table @source_schema = 'dbo', @source_name = 'Products'



-- update Customer 
INSERT INTO dbo.Customer (CustomerName,   CustomerCity) VALUES ('Bikes by Tomaz2','Ljubljana')