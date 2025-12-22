USE [db_02_json]
GO

/*

UNISTR

*/


SELECT N'Hello! ' UNION ALL
SELECT N'Hello! ' + NCHAR(0xd83d)  UNION ALL
SELECT N'Hello! ' + NCHAR(0xde00) UNION ALL
SELECT N'Hello! ' + NCHAR(0xd83d) + NCHAR(0xde00);
 

SELECT UNISTR(N'Hello! \D83D\DE00') union all
SELECT UNISTR(N'Hello! \+01F603');


SELECT UNISTR(N'ABC#00C0#0181#0187', '#');
SELECT UNISTR('\306F\3044' COLLATE Latin1_General_100_BIN2_UTF8) AS Yes_in_Japanese_Hiragana;


SELECT UNISTR('U+06Fx') 
SELECT UNISTR('FE90') 

🤦‍♂️


SELECT UNISTR(N'Sleepy face: \+01F634') as sleepy_face

SELECT N'ありがとう ございます' as TY_alone
SELECT 'Thank you' AS T_Y
SELECT 'Thank you ' + N'ありがとう ございます' as TY_mixed
SELECT UNISTR(N'Thank you \3042\308a\304c\3068\3046\0020\3054\3056\3044\307e\3059', '\') as Thank_you