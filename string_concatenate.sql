

-- declare @v varchar(200)

with aa as (
select 
  1 as idx
 ,cast('aa' as varchar(200)) as tekst

 union all
select
 idx + 1
 ,tekst ||= 'b'
from aa
where 
  idx < 10
)

select * from aa






DECLARE @i INT = 1;
DECLARE @j VARCHAR(200) = 'a' 

WHILE @i <= 5
BEGIN
    SELECT @j ||= @i;
    SET @i += 1;
END

SELECT 
 @j AS results
 ,SQL_VARIANT_PROPERTY(@j, 'BaseType') AS DataType
 ,SQL_VARIANT_PROPERTY(@j, 'MaxLength') AS MaxLengthBytes;
 GO
 

 --- an ansi standard would be

DECLARE @i int = 1
DECLARE @j VARCHAR(200) = 'a'

WHILE @i <= 5
BEGIN
    SET @j = @j || CAST(@i AS VARCHAR(10))
    SET @i = @i + 1
END

SELECT 
  @j
 ,SQL_VARIANT_PROPERTY(@j, 'BaseType') AS DataType
 ,SQL_VARIANT_PROPERTY(@j, 'MaxLength') AS MaxLengthBytes;
 GO


 --- Or with CONCAT

DECLARE @i INT = 1;
DECLARE @j VARCHAR(200) = 'a';

WHILE @i <= 5
BEGIN
    SET @j = CONCAT(@j, @i);
    SET @i += 1;
END

SELECT @j AS Result;



--- creating a list and adding logic
-- and using ||= with || together

DECLARE @i INT = 1;
DECLARE @list VARCHAR(200) = '';

WHILE @i <= 5
BEGIN
    --SET @list = CONCAT(@list, IIF(@i = 1, '', ','), @i);
    SET @list ||=  IIF(@i = 1, '', ',' ) || @i
    SET @i += 1;
END

SELECT @list AS NumberList;



--- STRING_AGG vs ||

--a) string_agg
DECLARE @j1 VARCHAR(200) = 'a';

SELECT @j1 = CONCAT(
    @j1,
    STRING_AGG(CAST(n AS VARCHAR(10)), '')
)
FROM (
    SELECT TOP (5) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.objects
) AS numbers;

SELECT @j1 AS Result;


---  ||

DECLARE @j2 VARCHAR(200) = 'a';

-- SELECT @j2 = CONCAT( @j2, STRING_AGG(CAST(n AS VARCHAR(10)), '')  )
SELECT @j2 ||= n 

FROM (
    --SELECT TOP (5) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.objects
--  I cant believe spt_values is still here in SQL Server 2025 (!) despite being depricated :)
SELECT number as n FROM spt_values where type = 'P' and number > 0 and number < 6
) AS numbers;

SELECT @j2 AS Result;


SELECT number
FROM spt_values
WHERE type = 'P' 


SELECT 
ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
FROM sys.objects;




-------
-- dirty  - exec plan comparison

PRINT ' --  part 1.'

SET STATISTICS TIME ON

DECLARE @j1 VARCHAR(8000) = 'a';
-- SELECT @j1 = CONCAT(@j1,STRING_AGG(CAST(n AS VARCHAR(10)), ''))
SELECT @j1 = CONCAT(@j1,STRING_AGG(cast(n as varchar(10)), ''))
FROM (
    SELECT number as n FROM spt_values where type = 'P' 
) AS numbers
--SELECT @j1 AS Result;
OPTION (MAXDOP 1);

SET STATISTICS TIME Off;

PRINT ' --  part 2.'

SET STATISTICS TIME ON


DECLARE @j2 VARCHAR(8000) = 'a';
SELECT @j2 ||= n 
FROM (
  SELECT number as n FROM spt_values where type = 'P' 
) AS numbers
--SELECT @j2 AS Result;
OPTION (MAXDOP 1);

SET STATISTICS TIME Off;



SELECT 
  @j1
 ,@j2
 ,case when @j1 = @j2 THEN 'same' else 'nevem' end as sameneessness
 ,SQL_VARIANT_PROPERTY(@j1, 'BaseType') AS DataType1
 ,SQL_VARIANT_PROPERTY(@j1, 'MaxLength') AS MaxLengthBytes1
 ,SQL_VARIANT_PROPERTY(@j2, 'BaseType') AS DataType2
 ,SQL_VARIANT_PROPERTY(@j2, 'MaxLength') AS MaxLengthBytes2
 GO


--  Ansi standards
