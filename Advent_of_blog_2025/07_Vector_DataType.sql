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


CREATE TABLE dbo.Articles
(
    id INT PRIMARY KEY,
    title NVARCHAR(100),
    content NVARCHAR(MAX),
    embedding VECTOR(5) -- faked or mocked embeddings
);
GO


INSERT INTO Articles (id, title, content, embedding)
VALUES (1, 'Intro to AI', 'This article introduces AI concepts.', '[0.1, 0.2, 0.3, 0.4, 0.5]'),
       (2, 'Deep Learning', 'Deep learning is a subset of ML.', '[0.2, 0.1, 0.4, 0.3, 0.6]'),
       (3, 'Neural Networks', 'Neural networks are powerful models.', '[0.3, 0.3, 0.2, 0.5, 0.1]'),
       (4, 'Machine Learning Basics', 'ML basics for beginners.', '[0.4, 0.5, 0.1, 0.2, 0.3]'),
       (5, 'Advanced AI', 'Exploring advanced AI techniques.', '[0.5, 0.4, 0.6, 0.1, 0.2]');
GO

-- create a vector
CREATE VECTOR INDEX vec_idx ON Articles(embedding)
WITH (METRIC = 'cosine', TYPE = 'diskann');
GO


-- peform erform a vector similarity search
DECLARE @qv VECTOR(5) = '[0.3, 0.3, 0.3, 0.3, 0.3]';

SELECT
    t.id,
    t.title,
    t.content,
    s.distance
FROM
    VECTOR_SEARCH(
        TABLE = Articles AS t,
        COLUMN = embedding,
        SIMILAR_TO = @qv,
        METRIC = 'cosine',
        TOP_N = 4
    ) AS s
ORDER BY s.distance, t.title;
