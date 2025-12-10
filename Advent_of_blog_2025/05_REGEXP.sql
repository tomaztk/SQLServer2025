
USE master;
GO

DROP DATABASE IF EXISTS db_05_regex;
GO

CREATE DATABASE db_05_regex;
GO

-- Just in case
ALTER DATABASE db_05_regex SET COMPATIBILITY_LEVEL = 170;

USE db_05_regex;
GO


/*

REGEXP_LIKE 

*/

DROP TABLE IF EXISTS EMPLOYEES;
GO
CREATE TABLE EMPLOYEES (  
    ID INT IDENTITY(101,1),  
    [Name] VARCHAR(150),  
    Email VARCHAR(320)  
    CHECK (REGEXP_LIKE(Email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')),  
    Phone_Number NVARCHAR(20)  
    CHECK (REGEXP_LIKE(Phone_Number, '^\(\d{3}\) \d{3}-\d{4}$'))  
);
GO

-- Valid INSERT
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Tomaz Kastrun', 'tomaz.kastrun@example.com', '(123) 456-7890');
GO

-- Invalid INSERT
INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Tom Jones', 'tom.jones@example.com', '123-456-7890');
GO

-- SELECT
SELECT * FROM EMPLOYEES
WHERE REGEXP_LIKE(Email, '^[^@]+\.[^.]*exa.*\.com$');
GO



/*

REGEXP_SUBSTR
-- Returns one occurrence of a substring of a string that matches the regular expression pattern.
If no match is found, it returns NULL.
*/

USE db_05_regex;
GO

INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Orange Blue', 'Orage.blue@fruits.co.uk', '(040) 456-7890');
GO

INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Tomato Green', 'tomato@gov.uk.com', '(080) 431-9760');
GO

SELECT REGEXP_SUBSTR(EMAIL, '@(.+)$', 1, 1, 'i', 1) AS DOMAIN
FROM EMPLOYEES


INSERT INTO EMPLOYEES ([Name], Email, Phone_Number)
VALUES ('Tomato Slovenian', 'tomato@gov.si', '(080) 431-9760');
GO

SELECT REGEXP_SUBSTR(EMAIL, '@(.+)$', 1, 1, 'i', 1) AS DOMAIN
FROM EMPLOYEES

-- No Match
-- later we get match
SELECT 
   REGEXP_SUBSTR(EMAIL, '@(.+)si',1,1, 'i', 0) AS email_domain
FROM EMPLOYEES



/*

REGEXP_REPLACE()
-- Returns a modified source string replaced by a replacement string, where the occurrence of the regular expression pattern found.
If no matches are found, the function returns the original string.
*/

-- obfuscate the last four digits
SELECT REGEXP_REPLACE(PHONE_NUMBER, '\d{4}$', '****') AS PHONE_OBFUSCATE
FROM EMPLOYEES;



/*

REGEXP_INSTR()
-- Returns the starting or ending position of the matched substring, depending on the value of the return_option argument.
*/

--  

SELECT REGEXP_INSTR(EMAIL, 'tom*', 1, 1, 0) as INSTR_POS
, EMAIL
FROM EMPLOYEES;


SELECT REGEXP_INSTR(EMAIL, 'tom*', 1, 2, 1) as INSTR_POS
, EMAIL
FROM EMPLOYEES;



/*

REGEXP_COUNT()
 
*/
-- count of "o" in email
SELECT Email,
       REGEXP_COUNT(email, 'o') AS A_COUNT
FROM EMPLOYEES


SELECT COUNT(*)
FROM EMPLOYEES
WHERE REGEXP_COUNT(Email, '[^aeiou]{3}', 1, 'i') > 0;



/*
REGEXP_MATCHES
*/


SELECT 
 ID
,Name
,Email
FROM [dbo].[EMPLOYEES]
CROSS APPLY REGEXP_MATCHES(email, '^[a-zA-Z0-9. _%+-]+@[a-zA-Z0-9.]') AS RegexMatchEmail 


-- in general searches
SELECT *
FROM REGEXP_MATCHES ('This is a blog post on topics of #SQLServer2025 #AzureSQL', '#([A-Za-z0-9_]+)');



/*
REGEXP_SPLIT_TO_TABLE
*/

SELECT *
FROM REGEXP_SPLIT_TO_TABLE ('A journey of a thousand miles begins with a single step. Step step.', '\s+');



SELECT 
 Value
,ordinal
,email
 
FROM [dbo].[EMPLOYEES] 
cross apply REGEXP_SPLIT_TO_TABLE(Email, '[\\.,@]+') as SplitEmail
