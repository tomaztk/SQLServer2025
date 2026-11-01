/* =====================================================================
   01_create_demo_database.sql
   Creates the demo database, the tables that will be streamed, seed data,
   and a low-privilege SQL login that the web app uses for the simulator.

   Run in SSMS / Azure Data Studio in SQLCMD mode, or let the Bicep
   run-command (infra/scripts/Configure-SqlCes.ps1) run it for you.
   The script is idempotent: re-running it is safe.
   ===================================================================== */
:setvar DatabaseName      "CesDemo"
:setvar SimulatorLogin    "ces_simulator"
:setvar SimulatorPassword "ChangeMe_Str0ng!Passw0rd"

SET NOCOUNT ON;
USE master;
GO

IF DB_ID(N'$(DatabaseName)') IS NULL
BEGIN
    PRINT 'Creating database [$(DatabaseName)]';
    CREATE DATABASE [$(DatabaseName)];
END
GO

-- CES only supports the FULL recovery model.
ALTER DATABASE [$(DatabaseName)] SET RECOVERY FULL;
GO

-- Allow larger LOB values to be written while CES is enabled (doc recommendation).
EXEC sys.sp_configure N'show advanced options', 1;  RECONFIGURE;
EXEC sys.sp_configure N'max text repl size (B)', -1; RECONFIGURE;
GO

USE [$(DatabaseName)];
GO

-- CES is a preview feature in SQL Server 2025.
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

/* ---------------------------------------------------------------------
   Tables. Avoid types CES skips (json, xml, geography, rowversion, ...)
   and features CES rejects (columnstore, temporal, memory-optimized ...).
   Every table has a primary key so events carry "pkkey".
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Customers', N'U') IS NULL
CREATE TABLE dbo.Customers
(
    CustomerId  int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Customers PRIMARY KEY,
    FirstName   nvarchar(50)  NOT NULL,
    LastName    nvarchar(50)  NOT NULL,
    Email       nvarchar(200) NOT NULL,
    City        nvarchar(100) NULL,
    Country     nvarchar(60)  NULL,
    Tier        varchar(10)   NOT NULL CONSTRAINT DF_Customers_Tier DEFAULT ('Bronze'),
    CreatedAt   datetime2(3)  NOT NULL CONSTRAINT DF_Customers_CreatedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedAt  datetime2(3)  NULL
);
GO

IF OBJECT_ID(N'dbo.Products', N'U') IS NULL
CREATE TABLE dbo.Products
(
    ProductId   int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Products PRIMARY KEY,
    Sku         varchar(20)   NOT NULL CONSTRAINT UQ_Products_Sku UNIQUE,
    Name        nvarchar(100) NOT NULL,
    Category    nvarchar(50)  NOT NULL,
    UnitPrice   decimal(10,2) NOT NULL,
    StockQty    int           NOT NULL,
    ModifiedAt  datetime2(3)  NULL
);
GO

IF OBJECT_ID(N'dbo.Orders', N'U') IS NULL
CREATE TABLE dbo.Orders
(
    OrderId     bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_Orders PRIMARY KEY,
    CustomerId  int           NOT NULL CONSTRAINT FK_Orders_Customers REFERENCES dbo.Customers(CustomerId),
    OrderDate   datetime2(3)  NOT NULL CONSTRAINT DF_Orders_OrderDate DEFAULT (SYSUTCDATETIME()),
    Status      varchar(20)   NOT NULL CONSTRAINT DF_Orders_Status DEFAULT ('Pending')
                CONSTRAINT CK_Orders_Status CHECK (Status IN ('Pending','Paid','Shipped','Delivered','Cancelled')),
    TotalAmount decimal(12,2) NOT NULL CONSTRAINT DF_Orders_Total DEFAULT (0),
    ModifiedAt  datetime2(3)  NULL
);
GO

IF OBJECT_ID(N'dbo.OrderLines', N'U') IS NULL
CREATE TABLE dbo.OrderLines
(
    OrderLineId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderLines PRIMARY KEY,
    OrderId     bigint        NOT NULL CONSTRAINT FK_OrderLines_Orders REFERENCES dbo.Orders(OrderId) ON DELETE CASCADE,
    ProductId   int           NOT NULL CONSTRAINT FK_OrderLines_Products REFERENCES dbo.Products(ProductId),
    Quantity    int           NOT NULL,
    UnitPrice   decimal(10,2) NOT NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_OrderLines_OrderId')
    CREATE INDEX IX_OrderLines_OrderId ON dbo.OrderLines(OrderId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Orders_Status')
    CREATE INDEX IX_Orders_Status ON dbo.Orders(Status) INCLUDE (CustomerId);
GO

/* ---------------------------------------------------------------------
   Seed data. NOTE: CES does not snapshot existing rows, so these rows
   never appear in Event Hubs - only changes made after CES is enabled do.
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.Products)
INSERT dbo.Products (Sku, Name, Category, UnitPrice, StockQty) VALUES
 ('SKU-1001', N'Espresso beans 1kg',        N'Coffee',    24.90, 500),
 ('SKU-1002', N'Filter coffee 500g',        N'Coffee',    11.50, 800),
 ('SKU-1003', N'Ceramic pour-over dripper', N'Equipment', 29.00, 150),
 ('SKU-1004', N'Burr grinder',              N'Equipment', 139.00, 60),
 ('SKU-1005', N'Gooseneck kettle',          N'Equipment', 69.00, 90),
 ('SKU-1006', N'Oat milk 1l',               N'Dairy-free', 2.40, 1200),
 ('SKU-1007', N'Paper filters (100)',       N'Supplies',   4.90, 2000),
 ('SKU-1008', N'Travel mug',                N'Merch',     19.90, 300),
 ('SKU-1009', N'Matcha 100g',               N'Tea',       18.00, 220),
 ('SKU-1010', N'Earl Grey loose 250g',      N'Tea',        9.80, 400);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Customers)
INSERT dbo.Customers (FirstName, LastName, Email, City, Country, Tier) VALUES
 (N'Ana',    N'Novak',    N'ana.novak@example.com',    N'Ljubljana', N'Slovenia', 'Gold'),
 (N'Luka',   N'Horvat',   N'luka.horvat@example.com',  N'Zagreb',    N'Croatia',  'Silver'),
 (N'Mia',    N'Gruber',   N'mia.gruber@example.com',   N'Vienna',    N'Austria',  'Bronze'),
 (N'Jonas',  N'Huber',    N'jonas.huber@example.com',  N'Graz',      N'Austria',  'Bronze'),
 (N'Sara',   N'Rossi',    N'sara.rossi@example.com',   N'Trieste',   N'Italy',    'Silver');
GO

/* ---------------------------------------------------------------------
   Low-privilege login for the web app (simulator + health panel).
   --------------------------------------------------------------------- */
USE master;
GO
IF SUSER_ID(N'$(SimulatorLogin)') IS NULL
    CREATE LOGIN [$(SimulatorLogin)] WITH PASSWORD = N'$(SimulatorPassword)', CHECK_POLICY = ON, DEFAULT_DATABASE = [$(DatabaseName)];
ELSE
    ALTER LOGIN [$(SimulatorLogin)] WITH PASSWORD = N'$(SimulatorPassword)';
-- Needed to read sys.dm_change_feed_errors / sys.dm_change_feed_log_scan_sessions
GRANT VIEW SERVER STATE TO [$(SimulatorLogin)];
GO

USE [$(DatabaseName)];
GO
IF USER_ID(N'$(SimulatorLogin)') IS NULL
    CREATE USER [$(SimulatorLogin)] FOR LOGIN [$(SimulatorLogin)];
ALTER ROLE db_datareader ADD MEMBER [$(SimulatorLogin)];
ALTER ROLE db_datawriter ADD MEMBER [$(SimulatorLogin)];
GRANT VIEW DATABASE STATE TO [$(SimulatorLogin)];
GRANT VIEW DEFINITION     TO [$(SimulatorLogin)];
GO

/* A full backup starts the log chain so FULL recovery is really in effect.
   Without it the database behaves as SIMPLE ("pseudo-simple") until the first full backup. */
DECLARE @file nvarchar(4000) = N'$(DatabaseName)_ces_init.bak';
BACKUP DATABASE [$(DatabaseName)] TO DISK = @file WITH INIT, STATS = 50;
GO

PRINT '01_create_demo_database.sql completed';
GO
