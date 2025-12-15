/*

Vector Data Type

*/

DROP TABLE IF EXISTS #VectorDataTypeExample;

CREATE TABLE #VectorDataTypeExample(
	Id INT NOT NULL IDENTITY(1,1),
	MyVector VECTOR(5) NOT NULL
);

INSERT INTO #VectorDataTypeExample(MyVector)
VALUES ('[10, 20, 30, 40, 500000]');

INSERT INTO #VectorDataTypeExample(MyVector)
VALUES (JSON_ARRAY(6.34, 227, 82342, 934, 10.342342));

SELECT * FROM #VectorDataTypeExample;
GO


/*
Functions
*/



-- VECTOR_DISTANCE

DECLARE @v1 AS VECTOR(2) = '[1,1]';
DECLARE @v2 AS VECTOR(2) = '[-1,-1]';
DECLARE @v3 AS VECTOR(2) = '[1,1]';

SELECT 
 VECTOR_DISTANCE('euclidean', @v1, @v2) AS euclidean_v1_v2
,VECTOR_DISTANCE('cosine', @v1, @v2) AS cosine_v1_v2
,VECTOR_DISTANCE('dot', @v1, @v2) AS negative_dot_product_v1_v2
,VECTOR_DISTANCE('euclidean', @v1, @v3) AS euclidean_v1_v3
,VECTOR_DISTANCE('cosine', @v1, @v3) AS cosine_v1_v3
,VECTOR_DISTANCE('dot', @v1, @v3) AS negative_dot_product_v1_v3


-- VECTOR_NORM

DECLARE @v4 AS VECTOR(6) = '[1, 2, 3, 4, 6, 5]';

SELECT 
  VECTOR_NORM(@v4, 'norm1') AS norm1
 ,VECTOR_NORM(@v4, 'norm2') AS norm2
 ,VECTOR_NORM(@v4, 'norminf') AS norminf


 -- VECTOR NORMALIZE

DECLARE @v7 AS VECTOR(3) = '[1, 2, 3]';


SELECT 
       VECTOR_NORMALIZE(@v7, 'norm1') as V7_norm1
       ,VECTOR_NORMALIZE(@v7, 'norminf') as V7_NormInf



 -- VECTOR_SEARCH
 USE MASTER;
 GO

 CREATE DATABASE db_11_vector;
 GO

 USE db_11_vector;
 GO
 

 -- option
ALTER DATABASE SCOPED CONFIGURATION
SET PREVIEW_FEATURES = ON;
GO

DROP TABLE IF EXISTS dbo.Aoc_days;
GO

CREATE TABLE dbo.Aoc_days
(
    id INT PRIMARY KEY,
    title NVARCHAR(100),
    content NVARCHAR(MAX),
    embedding VECTOR(6) -- faked or mocked embeddings
);
GO



INSERT INTO dbo.Aoc_days(id, title, content, embedding)
VALUES
  (1,  'Day 1: Secret Entrance',
       'Simulate a rotating dial from a sequence of turn commands; count how often you land on zero (and, in the second part, how often you cross zero while turning).',
       '[0.558, 0.646, 0.478, 0.173, 0.000, 0.999]'),

  (2,  'Day 2: Gift Shop',
       'Validate product IDs by detecting repeated patterns; part two broadens the repetition rule to catch more invalid IDs.',
       '[0.464, 0.950, 0.023, 0.693, 0.844, 0.536]'),

  (3,  'Day 3: Lobby',
       'Choose digits from multiple battery banks to maximize a joltage value under ordering constraints; part two scales up the selection size and tightens constraints.',
       '[0.072, 0.189, 0.662, 0.050, 0.243, 0.234]'),

  (4,  'Day 4: Printing Department',
       'Work on a grid of paper rolls: count which rolls are reachable under adjacency rules, then simulate a removal process to compute the total removed.',
       '[0.439, 0.617, 0.943, 0.945, 0.409, 0.025]'),

  (5,  'Day 5: Cafeteria',
       'Compare available ingredient IDs to freshness ranges: count IDs inside ranges, then merge overlapping ranges and compute the total unique fresh IDs.',
       '[0.318, 0.566, 0.744, 0.527, 0.210, 0.730]'),

  (6,  'Day 6: Trash Compactor',
       'Parse vertically-stacked arithmetic problems and evaluate them; part two changes how you read the columns (right-to-left / column-wise) before solving.',
       '[0.905, 0.912, 0.508, 0.705, 0.253, 0.935]'),

  (7,  'Day 7: Laboratories',
       'Trace beam paths through splitters and obstacles; part two counts the number of resulting timelines/paths efficiently using dynamic programming.',
       '[0.446, 0.127, 0.219, 0.736, 0.236, 0.395]'),

  (8,  'Day 8: Playground',
       'Connect floating junction boxes using the shortest total cable length (graph MST style); part two adds additional constraints requiring careful component tracking.',
       '[0.047, 0.232, 0.145, 0.114, 0.944, 0.325]'),

  (9,  'Day 9: Movie Theater',
       'Analyze a tile grid to find maximum-area rectangles under corner/marker constraints; part two extends the geometry logic with more complex inclusion rules.',
       '[0.059, 0.341, 0.897, 0.057, 0.815, 0.342]'),

  (10, 'Day 10: Factory',
       'Configure machines by pressing button pairs that toggle multiple indicators; find the minimum presses to reach target states, then aggregate results across many machines.',
       '[0.327, 0.857, 0.555, 0.290, 0.000, 0.000]'),

  (11, 'Day 11: Reactor',
       'Interpret device outputs as a network; compute connectivity and path counts between key components to restore communication between the server rack and reactor.',
       '[0.812, 0.116, 0.571, 0.115, 0.944, 0.623]'),

  (12, 'Day 12: Christmas Tree Farm',
       'Optimize a constrained arrangement/packing problem among many trees; brute force fails, so you derive a more efficient strategy to compute the final score.',
       '[0.585, 0.940, 0.231, 0.116, 0.977, 0.322]');
GO


-- create a vector
CREATE VECTOR INDEX vec_idx ON dbo.Aoc_days(embedding)
WITH (METRIC = 'cosine', TYPE = 'diskann');
GO


-- peform erform a vector similarity search
DECLARE @aoc VECTOR(6) = '[0.812, 0.235, 0.625, 0.011, 0.952, 0.043]';

SELECT
     a.id,
    ,a.title
    ,a.content
    ,s.distance
FROM
    VECTOR_SEARCH(
        TABLE = dbo.Aoc_days AS a,
        COLUMN = embedding,
        SIMILAR_TO = @aoc,
        METRIC = 'cosine',
        TOP_N = 4
    ) AS s
ORDER BY s.distance, a.title;


/*
VECTORPROPERTY

*/


DECLARE @v6 AS VECTOR(4) = '[1.043,2043.1234,-205.043, 0.000034234]';
SELECT 
   VECTORPROPERTY(@v6, 'Dimensions') AS VectorDimension
  ,VECTORPROPERTY(@v6 ,'BaseType') AS VectorType



  /*

  AI_GENERATE_EMBEDDINGS

  */

use [db_11_vector];
GO

GRANT EXECUTE ANY EXTERNAL ENDPOINT TO dbo;
GO


-- 1) Create a DMK if it doesn't exist (pick a strong password you can keep safe)
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
  CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Very_Strong_P@ssw0rd!_Keep_Safe';
END
GO



IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = 'https://my_location.cognitiveservices.azure.com]')
BEGIN
  CREATE DATABASE SCOPED CREDENTIAL [https://my_location.cognitiveservices.azure.com]
  WITH IDENTITY = 'HTTPEndpointHeaders',
   SECRET   = '{"api-key":"My_Foundry_API_Key_Secrets"}';
END
GO

CREATE EXTERNAL MODEL MyFoundryEmbeddingModel
WITH (
      LOCATION = 'https://my_location/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15',
      API_FORMAT = 'Azure OpenAI',
      MODEL_TYPE = EMBEDDINGS,
      MODEL = 'text-embedding-ada-002',
      CREDENTIAL = [https://my_location.cognitiveservices.azure.com]
);


SELECT id
     ,content
     ,AI_GENERATE_EMBEDDINGS(content USE MODEL MyFoundryEmbeddingModel) AS AoC_Embeddings
from [db_11_vector].dbo.Aoc_days;


/*

Chunks

*/

CREATE TABLE sample_AoC_chunks (text_id INT IDENTITY(1,1) PRIMARY KEY, text_to_chunk nvarchar(max));
GO

INSERT INTO sample_AoC_chunks (text_to_chunk)
VALUES
  ('Simulate a rotating dial from a sequence of turn commands; count how often you land on zero (and, in the second part, how often you cross zero while turning).'),
  ('Validate product IDs by detecting repeated patterns; part two broadens the repetition rule to catch more invalid IDs.'),
  ('Choose digits from multiple battery banks to maximize a joltage value under ordering constraints; part two scales up the selection size and tightens constraints.')
 

SELECT c.*
FROM sample_AoC_chunks as  AoC
CROSS APPLY
   AI_GENERATE_CHUNKS(source = text_to_chunk, chunk_type = FIXED, chunk_size = 30, enable_chunk_set_id = 1) c




/*
Chunks with embeddings
*/

DROP TABLE IF EXISTS dbo.AoC_embeddings;
GO

CREATE TABLE dbo.AoC_embeddings
(
    embeddings_id INT IDENTITY (1, 1) PRIMARY KEY,
    chunked_text NVARCHAR (MAX),
    vector_embeddings VECTOR(1536)
);


INSERT INTO AoC_embeddings (chunked_text, vector_embeddings)

SELECT  c.chunk AS chunked_text
       ,AI_GENERATE_EMBEDDINGS(c.chunk USE MODEL MyFoundryEmbeddingModel) AS vector_embeddings
FROM sample_AoC_chunks AS t
CROSS APPLY
    AI_GENERATE_CHUNKS (SOURCE = t.text_to_chunk, CHUNK_TYPE = FIXED, CHUNK_SIZE = 30) AS c;


SELECT * FROM AoC_embeddings;