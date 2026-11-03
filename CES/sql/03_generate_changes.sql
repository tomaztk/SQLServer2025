/* =====================================================================
   03_generate_changes.sql
   Generates a realistic mix of INSERT / UPDATE / DELETE activity from
   T-SQL, without the web app. Each loop iteration is one transaction, so
   you can see multi-row transactions (same commitlsn, increasing
   sequencenumber) in the dashboard / Event Hubs Data Explorer.
   ===================================================================== */
:setvar DatabaseName "CesDemo"
:setvar Iterations   "50"
:setvar DelayMs      "500"

SET NOCOUNT ON;
USE [$(DatabaseName)];
GO

DECLARE @i int = 0, @n int = $(Iterations);
DECLARE @delay varchar(12) = CAST(DATEADD(millisecond, $(DelayMs), CAST('00:00:00' AS time(3))) AS varchar(12)); -- 'hh:mm:ss.mmm'
DECLARE @roll int, @cust int, @order bigint, @prod int;

WHILE @i < @n
BEGIN
    SET @roll = ABS(CHECKSUM(NEWID())) % 100;

    BEGIN TRAN;

    IF @roll < 15
    BEGIN   -- new customer (INS)
        INSERT dbo.Customers (FirstName, LastName, Email, City, Country)
        SELECT TOP (1) f.v, l.v,
               LOWER(f.v + N'.' + l.v + N'.' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS nvarchar(10)) + N'@example.com'),
               c.city, c.country
        FROM (VALUES (N'Eva'),(N'Marko'),(N'Lena'),(N'Tim'),(N'Nina'),(N'Jan')) f(v)
        CROSS JOIN (VALUES (N'Kovac'),(N'Bauer'),(N'Zupan'),(N'Weber'),(N'Krajnc')) l(v)
        CROSS JOIN (VALUES (N'Maribor',N'Slovenia'),(N'Linz',N'Austria'),(N'Split',N'Croatia')) c(city,country)
        ORDER BY NEWID();
    END
    ELSE IF @roll < 50
    BEGIN   -- new order with 1-3 lines (INS x N, then UPD of the total) in ONE transaction
        SELECT TOP (1) @cust = CustomerId FROM dbo.Customers ORDER BY NEWID();
        INSERT dbo.Orders (CustomerId) VALUES (@cust);
        SET @order = SCOPE_IDENTITY();

        INSERT dbo.OrderLines (OrderId, ProductId, Quantity, UnitPrice)
        SELECT TOP (1 + ABS(CHECKSUM(NEWID())) % 3) @order, ProductId, 1 + ABS(CHECKSUM(NEWID())) % 4, UnitPrice
        FROM dbo.Products ORDER BY NEWID();

        UPDATE dbo.Orders
           SET TotalAmount = (SELECT SUM(Quantity * UnitPrice) FROM dbo.OrderLines WHERE OrderId = @order),
               ModifiedAt  = SYSUTCDATETIME()
         WHERE OrderId = @order;
    END
    ELSE IF @roll < 80
    BEGIN   -- advance an order through its lifecycle (UPD)
        UPDATE TOP (1) o
           SET Status = CASE o.Status WHEN 'Pending' THEN 'Paid' WHEN 'Paid' THEN 'Shipped' ELSE 'Delivered' END,
               ModifiedAt = SYSUTCDATETIME()
          FROM dbo.Orders o
         WHERE o.Status IN ('Pending','Paid','Shipped');
    END
    ELSE IF @roll < 90
    BEGIN   -- price / stock change (UPD)
        SELECT TOP (1) @prod = ProductId FROM dbo.Products ORDER BY NEWID();
        UPDATE dbo.Products
           SET UnitPrice  = CAST(UnitPrice * (0.9 + (ABS(CHECKSUM(NEWID())) % 21) / 100.0) AS decimal(10,2)),
               StockQty   = StockQty + (ABS(CHECKSUM(NEWID())) % 50) - 25,
               ModifiedAt = SYSUTCDATETIME()
         WHERE ProductId = @prod;
    END
    ELSE
    BEGIN   -- cancel and delete a pending order (UPD, then DEL of order + cascaded lines)
        SELECT TOP (1) @order = OrderId FROM dbo.Orders WHERE Status = 'Pending' ORDER BY NEWID();
        IF @order IS NOT NULL
        BEGIN
            UPDATE dbo.Orders SET Status = 'Cancelled', ModifiedAt = SYSUTCDATETIME() WHERE OrderId = @order;
            DELETE dbo.Orders WHERE OrderId = @order;   -- ON DELETE CASCADE removes the lines too
        END
    END

    COMMIT;
    SET @i += 1; SET @order = NULL;
    WAITFOR DELAY @delay;
END

SELECT 'Customers' AS tbl, COUNT(*) AS rows FROM dbo.Customers
UNION ALL SELECT 'Orders', COUNT(*) FROM dbo.Orders
UNION ALL SELECT 'OrderLines', COUNT(*) FROM dbo.OrderLines;
GO
