/*


*/
USE MASTER;
GO

--Permission:
GRANT EXECUTE ANY EXTERNAL ENDPOINT TO [dbo];

--Enable:
EXECUTE sp_configure 'external rest endpoint enabled', 1;
RECONFIGURE WITH OVERRIDE;



CREATE DATABASE db_06_api;
GO

USE db_06_api;
GO


    -- Call REST endpoint - No login or payload passed in
    -- @headers and @payload parameters take JSON inputs


    DECLARE @ReturnCode AS INT;
    DECLARE @Response AS NVARCHAR (MAX);

    EXECUTE
        @ReturnCode = sp_invoke_external_rest_endpoint
        @url = N'https://catfact.ninja/fact',
        @method = 'GET',
        @response = @response OUTPUT;
   
 
    -- SELECT @response

    SELECT
    value as Cat_Fact
    FROM OPENJSON(@response, '$.result')
    where type = 1




    --- LLM

USE db_06_api;
GO

GRANT EXECUTE ANY EXTERNAL ENDPOINT TO dbo;
GO


-- 1) Create a DMK if it doesn't exist (pick a strong password you can keep safe)
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
  CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Very_Strong_P@ssw0rd!_Keep_Safe';
END
GO




IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = 'https://tomaz-m821w85v-eastus2.cognitiveservices.azure.com]')
BEGIN
  CREATE DATABASE SCOPED CREDENTIAL [https://tomaz-m821w85v-eastus2.cognitiveservices.azure.com]
  WITH IDENTITY = 'HTTPEndpointHeaders',
   SECRET   = '{"api-key":"your_api_key_from_azure_Foundry"}';
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
              "text": "I am reading blog post on SQL Server 2025 by tomaztsql. ' + @Prompt + '"
            }
          ]
        }
      ],
      "temperature": 0.2,
      "top_p": 0.1,
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



-- EXECUTE API

EXEC dbo.stpExecuta_SQL_AI 'Where can I buy book on SQL Server 2025?'
