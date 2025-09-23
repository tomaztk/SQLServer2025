
USE [sql_ai]
GO

--IF NOT EXISTS(SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##') 
--BEGIN
--    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'LONg_Pa$$_w0rd!'
--END
-- GO

-- API: 'https://tomaz-m821w85v-eastus2.cognitiveservices.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2025-01-01-preview',


IF EXISTS(SELECT * FROM sys.database_scoped_credentials WHERE [name] = 'https://tomaz-m821w85v-eastus2.cognitiveservices.azure.com')
BEGIN
    DROP DATABASE SCOPED CREDENTIAL [https://tomaz-m821w85v-eastus2.cognitiveservices.azure.com]
END;


DECLARE 
    @Query VARCHAR(MAX)


SET @Query = 'CREATE DATABASE SCOPED CREDENTIAL [https://tomaz-m821w85v-eastus2.cognitiveservices.azure.com] WITH IDENTITY = ''HTTPEndpointHeaders'', SECRET = ''{"Authorization": "Bearer ' + CONVERT(VARCHAR(MAX), 'GFMGz1TRcIBxxxxxxJ6QxTcgeTxRbx4xxxxxxxxxxxxxxHv6xxxxxAAACOGgPJq')  + '"}'''
EXEC(@Query)


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
          "text": "Sem novodobni France Prešern in bom napisal haiku"
        }
      ]
    }
  ],
  "temperature": 0.7,
  "top_p": 0.95,
  "max_tokens": 800,
  "stream": false
}'

EXEC @ret = sys.sp_invoke_external_rest_endpoint 
	@method = 'POST',
	@url = N'https://tomaz-m821w85v-eastus2.cognitiveservices.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2025-01-01-preview',
	@payload = @payload,
    @credential = [https://tomaz-m821w85v-eastus2.cognitiveservices.azure.com],
	@response = @response OUTPUT;


SELECT @response


SELECT
  -- response.status.http
  JSON_VALUE(@response, '$.response.status.http.code') AS http_code,
  JSON_VALUE(@response, '$.response.status.http.description') AS http_description,

  -- response.headers
  JSON_VALUE(@response, '$.response.headers.Date') AS header_date,
  JSON_VALUE(@response, '$.response.headers."Content-Length"') AS header_content_length,
  JSON_VALUE(@response, '$.response.headers."Content-Type"') AS header_content_type,
  JSON_VALUE(@response, '$.response.headers."apim-request-id"') AS header_apim_request_id,
  JSON_VALUE(@response, '$.response.headers."strict-transport-security"') AS header_strict_transport_security,
  JSON_VALUE(@response, '$.response.headers."x-content-type-options"') AS header_x_content_type_options,
  JSON_VALUE(@response, '$.response.headers."x-ms-region"') AS header_x_ms_region,
  JSON_VALUE(@response, '$.response.headers."x-ratelimit-remaining-requests"') AS header_x_ratelimit_remaining_requests,
  JSON_VALUE(@response, '$.response.headers."x-ratelimit-limit-requests"') AS header_x_ratelimit_limit_requests,
  JSON_VALUE(@response, '$.response.headers."x-ratelimit-remaining-tokens"') AS header_x_ratelimit_remaining_tokens,
  JSON_VALUE(@response, '$.response.headers."x-ratelimit-limit-tokens"') AS header_x_ratelimit_limit_tokens,
  JSON_VALUE(@response, '$.response.headers."azureml-model-session"') AS header_azureml_model_session,
  JSON_VALUE(@response, '$.response.headers."cmp-upstream-response-duration"') AS header_cmp_upstream_response_duration,
  JSON_VALUE(@response, '$.response.headers."x-accel-buffering"') AS header_x_accel_buffering,
  JSON_VALUE(@response, '$.response.headers."x-ms-rai-invoked"') AS header_x_ms_rai_invoked,
  JSON_VALUE(@response, '$.response.headers."x-request-id"') AS header_x_request_id,
  JSON_VALUE(@response, '$.response.headers."x-ms-client-request-id"') AS header_x_ms_client_request_id,
  JSON_VALUE(@response, '$.response.headers."x-ms-deployment-name"') AS header_x_ms_deployment_name,

  -- results metadata
  JSON_VALUE(@response, '$.result.id') AS result_id,
  JSON_VALUE(@response, '$.result.model') AS result_model,
  JSON_VALUE(@response, '$.result.object') AS result_object,
  JSON_VALUE(@response, '$.result.created') AS result_created,
  JSON_VALUE(@response, '$.result.system_fingerprint') AS result_system_fingerprint,

  -- Information on tokens
  JSON_VALUE(@response, '$.result.usage.completion_tokens') AS completion_tokens,
  JSON_VALUE(@response, '$.result.usage.prompt_tokens') AS prompt_tokens,
  JSON_VALUE(@response, '$.result.usage.total_tokens') AS total_tokens,

  JSON_VALUE(@response, '$.result.usage.completion_tokens_details.accepted_prediction_tokens') AS accepted_prediction_tokens,
  JSON_VALUE(@response, '$.result.usage.completion_tokens_details.rejected_prediction_tokens') AS rejected_prediction_tokens,
  JSON_VALUE(@response, '$.result.usage.completion_tokens_details.audio_tokens') AS usage_audio_tokens,
  JSON_VALUE(@response, '$.result.usage.completion_tokens_details.reasoning_tokens') AS reasoning_tokens,

  JSON_VALUE(@response, '$.result.usage.prompt_tokens_details.cached_tokens') AS cached_tokens,
  JSON_VALUE(@response, '$.result.usage.prompt_tokens_details.audio_tokens') AS prompt_audio_tokens,

  -- choices (0)
  choices.[index],
  choices.finish_reason,
  message.role,
  message.content,

  -- filters hatery 
  hate.filtered AS hate_filtered,
  hate.severity AS hate_severity,
  violence.filtered AS violence_filtered,
  violence.severity AS violence_severity,
  self_harm.filtered AS selfharm_filtered,
  self_harm.severity AS selfharm_severity,
  sexual.filtered AS sexual_filtered,
  sexual.severity AS sexual_severity,
  pm_text.filtered AS pm_text_filtered,
  pm_text.detected AS pm_text_detected,
  pm_code.filtered AS pm_code_filtered,
  pm_code.detected AS pm_code_detected

FROM OPENJSON(@response, '$.result.choices')
WITH (
  [index] INT,
  finish_reason NVARCHAR(100),
  message NVARCHAR(MAX) AS JSON,
  content_filter_results NVARCHAR(MAX) AS JSON
) AS choices

CROSS APPLY OPENJSON(choices.message)
WITH (
  role NVARCHAR(50),
  content NVARCHAR(MAX)
) AS message

CROSS APPLY OPENJSON(choices.content_filter_results)
WITH (
  hate NVARCHAR(MAX) AS JSON,
  violence NVARCHAR(MAX) AS JSON,
  self_harm NVARCHAR(MAX) AS JSON,
  sexual NVARCHAR(MAX) AS JSON,
  protected_material_text NVARCHAR(MAX) AS JSON,
  protected_material_code NVARCHAR(MAX) AS JSON
) AS filters

CROSS APPLY OPENJSON(filters.hate)
WITH (
  filtered BIT,
  severity NVARCHAR(20)
) AS hate

CROSS APPLY OPENJSON(filters.violence)
WITH (
  filtered BIT,
  severity NVARCHAR(20)
) AS violence

CROSS APPLY OPENJSON(filters.self_harm)
WITH (
  filtered BIT,
  severity NVARCHAR(20)
) AS self_harm

CROSS APPLY OPENJSON(filters.sexual)
WITH (
  filtered BIT,
  severity NVARCHAR(20)
) AS sexual

CROSS APPLY OPENJSON(filters.protected_material_text)
WITH (
  filtered BIT,
  detected BIT
) AS pm_text

CROSS APPLY OPENJSON(filters.protected_material_code)
WITH (
  filtered BIT,
  detected BIT
) AS pm_code;