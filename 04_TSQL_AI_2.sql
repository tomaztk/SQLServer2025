/*

SP invoke External rest endpoint  in SQL Server 2025
This demo is to show the support in the T-SQL language in SQL Server 2025.


SP extented procedure:
sp_invoke_external_rest_endpoint

*/

USE MASTER;
GO

DROP DATABASE IF EXISTS sql_ai;
GO
CREATE DATABASE sql_ai;
GO

USE sql_ai;
GO

-- GRANT EXECUTE ANY EXTERNAL ENDPOINT TO ...
-- GO


-- 1) Create a DMK if it doesn't exist (pick a strong password you can keep safe)
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
  CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Very_Strong_P@ssw0rd!_Keep_Safe';
END
GO

-- 2) (Recommended) Also encrypt the DMK by the Service Master Key so SQL Server can auto-open it
--    This avoids having to OPEN MASTER KEY in every session.
IF NOT EXISTS (
    SELECT 1
    FROM sys.key_encryptions
    WHERE key_id = (SELECT key_id FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
      AND thumbprint IS NULL -- SMK encryption entry
)
BEGIN
  ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;
END
GO

-- 3) If you already had a DMK and still get 15581, OPEN it for this session once:
-- OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Very_Strong_P@ssw0rd!_Keep_Safe';



IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = 'AZURE_OPENAI_HEADER_AUTH_v2')
BEGIN
  CREATE DATABASE SCOPED CREDENTIAL AZURE_OPENAI_HEADER_AUTH_v2
  WITH IDENTITY = 'HTTPEndpointHeaders',
   SECRET   = '{"api-key":"GFMGz1TRcIBBHcJVgbyJ6QxxxxxxxxxxxxxxxxxxxxxxxxAACOGgPJq"}';
END
GO



CREATE OR ALTER PROCEDURE dbo.stpExecuta_SQL_AI (
    @Prompt VARCHAR(MAX),
    @Fl_Debug BIT = 0
)
AS 
BEGIN

    -- Executa a API
    DECLARE
        @ret INT,
        @response NVARCHAR(MAX),
        @payload VARCHAR(MAX) = '{
      "messages": [
        {
          "role": "system",
          "content": [
            {
              "type": "text",
              "text": "Sem klasičen DBA, ki želi postati Dejan Sarka. ' + @Prompt + '"
            }
          ]
        }
      ],
      "temperature": 0.7,
      "top_p": 0.95,
      "max_tokens": 8000
    }'

    EXEC @ret = sys.sp_invoke_external_rest_endpoint 
	     @method = 'POST',
          @headers = '{"Content-Type":"application/json"}',
	     @url = N'https://tomaz-m821w85v-eastus2.cognitiveservices.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2025-01-01-preview',
         @payload = @payload,
         --@credential = [<OPENAI_URL>],
         @credential = [https://tomaz-m821w85v-eastus2.cognitiveservices.azure.com],
	     @response = @response OUTPUT

    -- PRINT @response


    DECLARE @API_RETURN VARCHAR(MAX)
    SET @API_RETURN = JSON_VALUE(@response, '$.result.choices[0].message.content')
    SET @API_RETURN = REPLACE(REPLACE(@API_RETURN, '```sql', ''), '```', '')

    PRINT @API_RETURN

    IF (LEN(TRIM(@API_RETURN)) > 0 AND @Fl_Debug = 0)
        EXEC(@API_RETURN)

END


-- check scoped_credentials

SELECT name FROM sys.database_scoped_credentials;

-- EXECUTE API

EXEC dbo.stpExecuta_SQL_AI 'Kako določim primani ključ?.'


