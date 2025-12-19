
USE MASTER;
GO


SELECT CURRENT_DATE

-- precisions
SELECT 
		 SYSDATETIME() AS Sys_datetime
		,SYSDATETIMEOFFSET() AS sys_DatetimeOffset
		,SYSUTCDATETIME() AS SysUTC_Datetime
		,CURRENT_TIMESTAMP AS Curr_Timestamp
		,GETDATE() AS Get_date
		,GETUTCDATE() as Get_UTCDate
		,CURRENT_DATE AS current_d
		,CAST(GETDATE() AS DATE) as current_d_cast_equvival


DROP TABLE IF EXISTS dbo.TEST;
GO

CREATE TABLE dbo.test
(ID INT IDENTITY(1,1) NOT NULL
,tt CHAR(10) NULL
,dd DATE NOT NULL DEFAULT CURRENT_DATE
,ddtt SMALLDATETIME NOT NULL DEFAULT DATEADD(DAY,1,CURRENT_DATE)
)

INSERT INTO dbo.test (tt, dd)
SELECT 'aaa','2025-12-19' UNION ALL
SELECT 'bbb','2025-12-20 05:26:46.947' UNION ALL
SELECT 'ccc',GETDATE() UNION ALL
SELECT 'ddd',DATEADD(DAY, 8,CAST(GETDATE() AS DATE)) union all
select 'eee',CURRENT_TIMESTAMP 

SELECT * FROM dbo.TEST

-- testing conversion
SELECT
 GETDATE()
 ,CURRENT_DATE
 ,CAST(current_date as date)
 ,CONVERT(VARCHAR(10), current_date) 


 -- setting 

USE master;
GO
EXECUTE sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO


DBCC USEROPTIONS
/*
textsize	2147483647
language	us_english
dateformat	mdy
datefirst	7
*/


SET LANGUAGE slovenian
SELECT CURRENT_DATE
,CAST(GETDATE() AS VARCHAR(20))
go

SET LANGUAGE us_english
SELECT CURRENT_DATE
,CAST(GETDATE() AS VARCHAR(20));
go

