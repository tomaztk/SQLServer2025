
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