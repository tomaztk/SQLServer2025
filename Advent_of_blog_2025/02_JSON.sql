-- New JSON Functionalities in SQL Server 2025


USE master;
GO
DROP DATABASE IF EXISTS db_02_json;
GO
CREATE DATABASE db_02_json;
GO
USE db_02_json;
GO



--  native JSON type and JSON index

-- JSON_OBJECTAGG 	Construct a JSON object from an aggregation.
-- JSON_ARRAYAGG 	Construct a JSON array from an aggregation.

-- Create a new database with a JSON type to hold the document
DROP TABLE IF EXISTS contacts;
GO

-- Create a table with native JSON data type
CREATE TABLE contacts (
        id INT IDENTITY PRIMARY KEY
       ,jdoc JSON);
GO


INSERT INTO contacts (jdoc) VALUES
(
'{
    "id": 1,
    "firstName": "Lena",
    "lastName": "Hughes",
    "email": "lena.hughes@example.com",
    "phone": "+1-202-555-0147",
    "company": "Northwind Studio",
    "jobTitle": "Product Designer",
    "tags": ["design", "freelance"],
    "address": {
      "street": "1840 Oakwood Ave",
      "city": "Portland",
      "state": "OR",
      "postalCode": "97205",
      "country": "USA"
    }
  }'
),
(
'
 {
    "id": 2,
    "firstName": "Mateo",
    "lastName": "Keller",
    "email": "mateo.keller@example.org",
    "phone": "+49-30-555-9821",
    "company": "Keller & Co. Consulting",
    "jobTitle": "Management Consultant",
    "tags": ["consulting", "b2b", "vip"],
    "preferredContactMethod": "email",
    "address": {
      "street": "Prenzlauer Allee 77",
      "city": "Berlin",
      "state": "BE",
      "postalCode": "10405",
      "country": "Germany"
    }
  }
'
),
(
'{
    "id": 3,
    "firstName": "Aisha",
    "lastName": "Rahman",
    "email": "aisha.rahman@example.net",
    "phone": "+44-20-7946-0034",
    "company": "BrightPath Education",
    "jobTitle": "Curriculum Developer",
    "notes": "Interested in collaboration on STEM projects.",
    "newsletterSubscribed": true
  }'
),
(
'{
    "id": 4,
    "firstName": "Jonas",
    "lastName": "Petrovic",
    "email": "jonas.p@example.com",
    "phone": "+386-40-555-229",
    "company": null,
    "jobTitle": null,
    "tags": ["personal"],
    "social": {
      "instagram": "@jonas.moves",
      "linkedin": null
    },
    "birthday": "1992-08-17"
  }'
),
(
' {
    "id": 5,
    "firstName": "Priya",
    "lastName": "Menon",
    "email": "priya.menon@example.com",
    "phone": "+1-415-555-3320",
    "company": "Skyline Analytics",
    "jobTitle": "Data Engineer",
    "preferredContactMethod": "phone",
    "timezone": "America/Los_Angeles",
    "address": {
      "street": "501 Mission St",
      "city": "San Francisco",
      "state": "CA",
      "postalCode": "94105",
      "country": "USA"
    }
  }
'
);
GO

-- Check table
SELECT * FROM [dbo].[contacts]


-- Show names and social using JSON_VALUE and JSON_QUERY
SELECT 
 JSON_VALUE(jdoc, '$.firstName') AS names
,JSON_QUERY(jdoc, '$.address.postalCode' WITH ARRAY WRAPPER) AS socials
FROM contacts;
GO



-- Show names and tags for certain tag values using a JSON index and JSON_CONTAINS
-- Check Execution plan
SELECT JSON_VALUE(jdoc, '$.firstName') AS names
     , JSON_QUERY(jdoc, '$.social') AS socials
FROM contacts
WHERE JSON_CONTAINS(jdoc, 'personal', '$.tags[*]') = 1;
GO




-- Create a JSON index
DROP INDEX IF EXISTS [j_index_contacts] ON contacts;
GO
CREATE JSON INDEX [j_index_contacts] ON contacts(jdoc) FOR ('$');
GO



-- Show names and tags for certain tag values using a JSON index and JSON_CONTAINS
-- Check Execution plan -- same
SELECT JSON_VALUE(jdoc, '$.firstName') AS names
  , JSON_QUERY(jdoc, '$.social') AS socials
FROM contacts
WHERE JSON_CONTAINS(jdoc, 'personal', '$.tags[*]') = 1;
GO


-- Increase rowcount to enable use of JSON index
UPDATE STATISTICS contacts WITH ROWCOUNT = 10000;
GO

-- Show names and tags for certain tag values using a JSON index and JSON_CONTAINS
-- Check Execution plan -- same
SELECT JSON_VALUE(jdoc, '$.firstName') AS names
  , JSON_QUERY(jdoc, '$.social') AS socials
FROM contacts
WHERE JSON_CONTAINS(jdoc, 'personal', '$.tags[*]') = 1;
GO


-- ## JSON_ARRAYAGG
-- Constructs a JSON array from an aggregation of SQL data or columns.
-- JSON_ARRAYAGG can also be used in a SELECT statement with GROUP BY GROUPING SETS clause.

SELECT JSON_ARRAYAGG(JSON_VALUE(jdoc, '$.firstName'))
FROM contacts;


-- ## JSON_OBJECTAGG
--The JSON_OBJECTAGG syntax constructs a JSON object from an aggregation of 
--SQL data or columns. JSON_OBJECTAGG can also be used in a 
--SELECT statement with GROUP BY GROUPING SETS clause.


SELECT JSON_OBJECTAGG(JSON_VALUE(jdoc, '$.firstName'):JSON_VALUE(jdoc, '$.social')) 
FROM contacts; 

 

--- In addition, we can create an index:

-- observe the execution plan
SELECT 
  JSON_VALUE(jdoc, '$.firstName') AS FirstName
 ,JSON_VALUE(jdoc, '$.lastName') AS LastName
FROM contacts
WHERE  JSON_VALUE(jdoc, '$.firstName')  = 'Priya'
GO

-- A JSON index 'j_index_contacts' already exists on column 'jdoc' on table 'contacts', and multiple JSON 
-- indexes per column are not allowed.

DROP INDEX IF EXISTS [j_index_contacts] ON contacts;
GO

DROP INDEX IF EXISTS IX_Contact_Name ON dbo.contacts;
GO

CREATE JSON INDEX IX_Contact_Name
ON dbo.contacts(jdoc)
FOR ('$.firstName', '$.lastName');


-- observe the execution plan
SELECT 
  JSON_VALUE(jdoc, '$.firstName') AS names
 ,JSON_VALUE(jdoc, '$.lastName') AS names
FROM contacts
WHERE  JSON_VALUE(jdoc, '$.firstName')  = 'Priya'
GO