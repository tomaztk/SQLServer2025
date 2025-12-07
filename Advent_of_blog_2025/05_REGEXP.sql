
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



