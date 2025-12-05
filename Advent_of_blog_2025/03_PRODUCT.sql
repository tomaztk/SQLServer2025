--- PRODUCT


-- NULL
SELECT 
 PRODUCT(vals)  
FROM (VALUES (4), (4),(3),(2),(NULL) ) AS MyTable(vals);
-- result: 4*4*3*2 = 96; NULL IS IGNORED


-- DISTINCT
SELECT 
 PRODUCT(DISTINCT vals)
FROM (VALUES (4), (4),(3),(2),(NULL) ) AS MyTable(vals);
-- result: 4*3*2 = 24; NULL IS IGNORED


-- OVER CALUSE with return rate example
SELECT DISTINCT ProductGroup
   ,PRODUCT(1 + RR_Value) OVER (PARTITION BY ProductGroup ORDER BY ProductGroup) AS CalculatedReturn
FROM (VALUES (0.1626, 'Group1'),
             (0.0483, 'Group2'),
             (0.2689, 'Group3'),
             (0.1944, 'Group1'),
             (0.2423, 'Group1'),
             (0.3423, 'Group3')
) AS MyTable2(RR_Value, ProductGroup);