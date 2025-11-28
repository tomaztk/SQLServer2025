USe AdventureWorks;
GO


CREATE EXTERNAL MODEL embedding_model
FROM OPENAI
WITH (ENDPOINT = 'https://api.openai.com/v1/embeddings',
      API_KEY = SECRET('openai_key'),
      MODEL_NAME = 'text-embedding-3-small');



CREATE TABLE ProductEmbeddings
(
    ProductID INT PRIMARY KEY,
    Description NVARCHAR(MAX),
    Embedding VECTOR(1536)
);

INSERT INTO ProductEmbeddings (ProductID, Description, Embedding)
SELECT ProductID,
       Description,
       AI_GENERATE_EMBEDDINGS('embedding_model', Description)
FROM Products;


CREATE VECTOR INDEX idx_ProductEmbedding
ON ProductEmbeddings (Embedding)
WITH (DISTANCE_METRIC = 'cosine');



DECLARE @query NVARCHAR(MAX) = 'waterproof hiking backpack';
DECLARE @vector VECTOR(1536) = AI_GENERATE_EMBEDDINGS('embedding_model', @query);

SELECT TOP 5 ProductID, Description,
       VECTOR_DISTANCE(Embedding, @vector, 'cosine') AS SimilarityScore
FROM ProductEmbeddings
ORDER BY SimilarityScore ASC;
