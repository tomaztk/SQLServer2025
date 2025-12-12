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










DECLARE @v1 AS VECTOR(2) = '[1,1]';
DECLARE @v2 AS VECTOR(2) = '[-1,-1]';

SELECT VECTOR_DISTANCE('euclidean', @v1, @v2) AS euclidean,
       VECTOR_DISTANCE('cosine', @v1, @v2) AS cosine,
       VECTOR_DISTANCE('dot', @v1, @v2) AS negative_dot_product;
