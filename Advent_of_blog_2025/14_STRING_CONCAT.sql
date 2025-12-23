USE db_02_json;
GO

 
--
-- concatenate ||
--

SELECT concat('Hello' , ', ' , 'There!') as three_strings_concat
UNION ALL
SELECT 'Hello' || ', ' || 'There!'



-- concat binary and NULL

DROP TABLE IF EXISTS test;
GO

CREATE TABLE test (
 tex1 VARCHAR(100)
,tex2 VARBINARY
,tex3 VARCHAR(10))

 
INSERT INTO test values
(NULL, NULL, NULL), ('Hello', NULL, ''), ('',0xA5, '$"#$"#$"'), (NULL, NULL, '')


SELECT
 tex1
,tex2
,tex3
,tex1 || tex2 -- will return error - can not concat varchar and varbinary
,tex1 || tex3 -- concat NULL and empty string will return NULL!
FROM test

 
--
-- compound  ||=
--

DECLARE @v1 varchar(20) = 'Hello'
SELECT @v1 as v1
SET @v1 ||= ' There!';
SELECT @v1 as v2
 

-- NULL
DECLARE @v1 varchar(20) = NULL
SET @v1 ||= ' There!';
SELECT @v1


DECLARE @v2 varchar(20) = 'Hello, There!'
SET @v2 ||= NULL;
SELECT @v2

-- different data types
DECLARE @v3 varbinary(10) = 0x1a
SET @v3 ||= 0x2b;
SELECT @v3
