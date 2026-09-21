/* ============================================================
   SQL SERVER 2025 — REGEX BENCHMARK: PATTERN COMPLEXITY CLASSES
   Requires: SQL Server 2025, compatibility level 170
   Demo data: 100,000 rows generated inline
   Measurement: SET STATISTICS TIME ON  (CPU ms + elapsed ms)
                sys.dm_exec_query_stats for repeatable reads
   ============================================================ */

--  NTK 2026  - 2026-09-21

USE master;
GO

-- DROP DATABASE RegexBench;
-- GO
CREATE DATABASE RegexBench;
GO
USE RegexBench;
GO
ALTER DATABASE RegexBench SET COMPATIBILITY_LEVEL = 170;
GO

-- --------------------------------------------------------
-- Demo table: 100,000 rows, mixed ASCII + Unicode content
-- --------------------------------------------------------
DROP TABLE IF EXISTS dbo.BenchRows;
CREATE TABLE dbo.BenchRows (
    RowID       INT            NOT NULL PRIMARY KEY,
    AsciiText   VARCHAR(200)   NOT NULL,   -- plain ASCII log lines
    UnicodeText NVARCHAR(200)  NOT NULL,   -- mixed-script content
    EmailCol    VARCHAR(200)   NOT NULL,   -- email addresses (some invalid)
    IPCol       VARCHAR(20)    NOT NULL,   -- IPv4 strings
    TagCol      VARCHAR(200)   NOT NULL    -- comma-separated words
);

-- Generate data with a tally CTE
WITH tally AS (
    SELECT TOP (100000)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_columns a CROSS JOIN sys.all_columns b
)
INSERT INTO dbo.BenchRows
    (RowID, AsciiText, UnicodeText, EmailCol, IPCol, TagCol)
SELECT
    n,
    -- AsciiText: log lines with varying content
    CASE n % 6
        WHEN 0 THEN 'ERROR: Connection timeout after 30s on host 192.168.' + CAST(n % 255 AS VARCHAR) + '.1'
        WHEN 1 THEN 'INFO: User john.doe@example.com logged in at 2025-03-14T08:23:11Z'
        WHEN 2 THEN 'WARN: Slow query Duration=4523ms QueryID=QRY-2025-' + RIGHT('000000'+CAST(n AS VARCHAR),6)
        WHEN 3 THEN 'DEBUG: cat jumped over dog and bird flew away'
        WHEN 4 THEN 'INFO: Order ORD-2025-' + RIGHT('000000'+CAST(n AS VARCHAR),6) + ' processed OK'
        ELSE        'ERROR: Auth failed for admin from 10.' + CAST(n%256 AS VARCHAR) + '.0.1'
    END,
    -- UnicodeText: mix of Latin, Cyrillic, CJK, Arabic
    CASE n % 5
        WHEN 0 THEN N'Hello world from New York'
        WHEN 1 THEN N'Привет мир из Москвы'           -- Russian
        WHEN 2 THEN N'你好，来自北京的世界'              -- Chinese
        WHEN 3 THEN N'مرحبا بالعالم من القاهرة'        -- Arabic
        ELSE        N'Héllo wörld from München'        -- Latin + diacritics
    END,
    -- EmailCol: 80% valid, 20% intentionally broken
    CASE n % 5
        WHEN 0 THEN 'user' + CAST(n AS VARCHAR) + '@example.com'
        WHEN 1 THEN 'first.last' + CAST(n AS VARCHAR) + '@corp.co.uk'
        WHEN 2 THEN 'no-at-sign-here-' + CAST(n AS VARCHAR)      -- invalid
        WHEN 3 THEN 'missing@'                                    -- invalid
        ELSE        'valid+tag' + CAST(n AS VARCHAR) + '@domain.org'
    END,
    -- IPCol: mix of valid and invalid IPv4 strings
    CASE n % 4
        WHEN 0 THEN CAST(n%256 AS VARCHAR)+'.'+CAST((n+1)%256 AS VARCHAR)+'.'+CAST((n+2)%256 AS VARCHAR)+'.'+CAST((n+3)%256 AS VARCHAR)
        WHEN 1 THEN '192.168.' + CAST(n%256 AS VARCHAR) + '.1'
        WHEN 2 THEN '999.999.999.999'                             -- invalid
        ELSE        '10.0.' + CAST(n%256 AS VARCHAR) + '.' + CAST(n%100 AS VARCHAR)
    END,
    -- TagCol: comma-separated words from a small vocabulary
    CASE n % 8
        WHEN 0 THEN 'cat,dog,bird'
        WHEN 1 THEN 'error,timeout,retry'
        WHEN 2 THEN 'cat,widget,sale'
        WHEN 3 THEN 'dog,legacy,clearance'
        WHEN 4 THEN 'bird,new,featured'
        WHEN 5 THEN 'hardware,cat,subscription'
        WHEN 6 THEN 'software,dog,new'
        ELSE        'accessories,bird,refurbished'
    END
FROM tally;

-- Confirm row count
SELECT COUNT(*) AS TotalRows FROM dbo.BenchRows;  -- expect 100,000
GO


/* ============================================================
   Then check Messages tab for CPU time and elapsed time.
   Clear plan cache between runs on a dev/test instance only:
       DBCC FREEPROCCACHE;
       DBCC DROPCLEANBUFFERS;
   ============================================================ */

SET STATISTICS TIME ON;
GO


/* ============================================================
   BENCHMARK 1 — LITERAL SEARCH
   Question: does the engine use fast substring scan (like
   Boyer-Moore / SIMD) for plain-text literals, or treat every
   character as a regex state?
   ============================================================ */
PRINT '======== BENCHMARK 1: LITERAL SEARCH ========';
GO

-- 1a. LIKE  (baseline — uses native substring scan)
SELECT COUNT(*) AS [1a_LIKE_literal]
FROM dbo.BenchRows
WHERE AsciiText LIKE '%timeout%';
GO

-- 1b. CHARINDEX  (alternative baseline)
SELECT COUNT(*) AS [1b_CHARINDEX_literal]
FROM dbo.BenchRows
WHERE CHARINDEX('timeout', AsciiText) > 0;
GO

-- 1c. REGEXP_LIKE — single literal word (no metacharacters)
SELECT COUNT(*) AS [1c_REGEXP_literal_word]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, 'timeout');
GO

-- 1d. REGEXP_LIKE — two-word phrase (space is literal in regex)
SELECT COUNT(*) AS [1d_REGEXP_literal_phrase]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, 'Connection timeout');
GO

-- 1e. REGEXP_LIKE — case-insensitive literal ('i' flag)
SELECT COUNT(*) AS [1e_REGEXP_literal_caseinsensitive]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, 'error', 'i');
GO

/*
   WHAT TO LOOK FOR:
   - 1a and 1b should be significantly faster than 1c-1e.
   - The gap tells you the regex engine overhead even on trivial patterns.
   - If 1c is close to 1a, the engine has good literal optimization.
   - The 'i' flag in 1e adds a Unicode case-folding cost — watch CPU.
*/


/* ============================================================
   BENCHMARK 2 — SIMPLE CHARACTER CLASSES
   Question: how fast are basic metacharacters (\d, [a-z], \w)
   vs. equivalent LIKE patterns?
   ============================================================ */
PRINT '======== BENCHMARK 2: SIMPLE CHARACTER CLASSES ========';
GO

-- 2a. LIKE with character range (SQL Server LIKE supports [a-z])
SELECT COUNT(*) AS [2a_LIKE_charclass]
FROM dbo.BenchRows
WHERE AsciiText LIKE '%[0-9][0-9][0-9][0-9]%';  -- 4 consecutive digits
GO

-- 2b. PATINDEX with character class
SELECT COUNT(*) AS [2b_PATINDEX_charclass]
FROM dbo.BenchRows
WHERE PATINDEX('%[0-9][0-9][0-9][0-9]%', AsciiText) > 0;
GO

-- 2c. REGEXP_LIKE — \d{4} (exactly 4 digits)
SELECT COUNT(*) AS [2c_REGEXP_digit4]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, '\d{4}');
GO

-- 2d. REGEXP_LIKE — \d+ (one or more digits — greedy)
SELECT COUNT(*) AS [2d_REGEXP_digits_greedy]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, '\d+');
GO

-- 2e. REGEXP_LIKE — word characters [a-zA-Z0-9_]+
SELECT COUNT(*) AS [2e_REGEXP_word_class]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, '[a-zA-Z0-9_]{6,}');
GO

-- 2f. REGEXP_LIKE — explicit character class vs shorthand
--     [0-9] vs \d — are they the same cost in RE2?
SELECT COUNT(*) AS [2f_REGEXP_explicit_vs_shorthand]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, '[0-9]{4}');
GO

-- 2g. REGEXP_COUNT on a character class (costs more — returns a value)
SELECT SUM(REGEXP_COUNT(AsciiText, '\d')) AS [2g_REGEXP_COUNT_digits]
FROM dbo.BenchRows;
GO

/*
   WHAT TO LOOK FOR:
   - 2a vs 2b: LIKE and PATINDEX should be similar for simple ranges.
   - 2c vs 2a: REGEXP adds overhead but expresses {4} cleanly.
   - 2f vs 2c: [0-9] and \d should cost nearly the same in RE2.
   - 2g will be the most expensive — it evaluates every row fully.
*/


/* ============================================================
   BENCHMARK 3 — ALTERNATION
   Question: can the engine optimize multi-branch alternation
   (like Aho-Corasick), or does it test each branch sequentially?
   ============================================================ */
PRINT '======== BENCHMARK 3: ALTERNATION ========';
GO

-- 3a. LIKE with OR  (most common T-SQL approach)
SELECT COUNT(*) AS [3a_LIKE_OR_3terms]
FROM dbo.BenchRows
WHERE AsciiText LIKE '%cat%'
   OR AsciiText LIKE '%dog%'
   OR AsciiText LIKE '%bird%';
GO

-- 3b. REGEXP_LIKE — 3-way alternation (same logical query)
SELECT COUNT(*) AS [3b_REGEXP_alternation_3]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(TagCol, 'cat|dog|bird');
GO

-- 3c. REGEXP_LIKE — 5-way alternation (stress test)
SELECT COUNT(*) AS [3c_REGEXP_alternation_5]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, 'error|timeout|duration|auth|order');
GO

-- 3d. LIKE with OR — 5 terms (equivalent to 3c)
SELECT COUNT(*) AS [3d_LIKE_OR_5terms]
FROM dbo.BenchRows
WHERE AsciiText LIKE '%error%'
   OR AsciiText LIKE '%timeout%'
   OR AsciiText LIKE '%duration%'
   OR AsciiText LIKE '%auth%'
   OR AsciiText LIKE '%order%';
GO

-- 3e. Anchored alternation — word must appear at start
SELECT COUNT(*) AS [3e_REGEXP_anchored_alternation]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, '^(ERROR|INFO|WARN|DEBUG):');
GO

-- 3f. LIKE equivalent of 3e
SELECT COUNT(*) AS [3f_LIKE_prefix_OR]
FROM dbo.BenchRows
WHERE AsciiText LIKE 'ERROR:%'
   OR AsciiText LIKE 'INFO:%'
   OR AsciiText LIKE 'WARN:%'
   OR AsciiText LIKE 'DEBUG:%';
GO

/*
   WHAT TO LOOK FOR:
   - 3b vs 3a: single REGEXP_LIKE vs. multiple LIKE+OR.
     RE2 builds a DFA for alternation — at large n, it should
     match all branches in a single pass. LIKE needs multiple passes.
   - 3e vs 3f: anchored patterns should be faster; LIKE 'X%' can
     seek in indexes while REGEXP cannot, but on heap scans watch
     whether anchoring helps the regex engine short-circuit.
   - As you scale to 10, 20 terms, regex alternation should
     widen its lead over repeated LIKE+OR.
*/


/* ============================================================
   BENCHMARK 4 — ANCHORED vs. UNANCHORED
   Question: do anchors (^ and $) meaningfully reduce work,
   the same way LIKE 'foo%' is faster than LIKE '%foo%'?
   ============================================================ */
PRINT '======== BENCHMARK 4: ANCHORED vs. UNANCHORED ========';
GO

-- 4a. LIKE unanchored (leading wildcard — always full scan)
SELECT COUNT(*) AS [4a_LIKE_unanchored]
FROM dbo.BenchRows
WHERE AsciiText LIKE '%ERROR%';
GO

-- 4b. LIKE anchored at start (no leading wildcard — can use index)
SELECT COUNT(*) AS [4b_LIKE_anchored_prefix]
FROM dbo.BenchRows
WHERE AsciiText LIKE 'ERROR%';
GO

-- 4c. REGEXP_LIKE — unanchored
SELECT COUNT(*) AS [4c_REGEXP_unanchored]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, 'ERROR');
GO

-- 4d. REGEXP_LIKE — anchored at start with ^
SELECT COUNT(*) AS [4d_REGEXP_anchored_start]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, '^ERROR');
GO

-- 4e. REGEXP_LIKE — anchored at end with $
SELECT COUNT(*) AS [4e_REGEXP_anchored_end]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, 'OK$');
GO

-- 4f. REGEXP_LIKE — fully anchored (must match entire string)
SELECT COUNT(*) AS [4f_REGEXP_fully_anchored]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(EmailCol, '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');
GO

-- 4g. REGEXP_LIKE — unanchored equivalent of 4f (no ^ and $)
SELECT COUNT(*) AS [4g_REGEXP_unanchored_email]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(EmailCol, '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
GO

/*
   WHAT TO LOOK FOR:
   - 4b will typically be dramatically faster than 4a IF there is an
     index on AsciiText (add one to test). On a heap, both scan.
   - 4d vs 4c: RE2 can short-circuit after matching the first char
     when anchored at ^ — expect modest but real improvement.
   - 4f vs 4g: full anchoring forces the engine to match the whole
     string, which for email validation is actually more correct AND
     should be slightly faster (no need to find the pattern anywhere).
   - On a 100k heap: anchoring helps regex less than it helps LIKE.
     On indexed columns, LIKE 'foo%' has a decisive advantage.
*/

-- Optional: add an index to see the LIKE anchoring effect
CREATE INDEX IX_BenchRows_AsciiText ON dbo.BenchRows (AsciiText);
GO

-- Re-run 4a and 4b after the index and compare plans
SELECT COUNT(*) AS [4a_LIKE_unanchored_indexed]
FROM dbo.BenchRows
WHERE AsciiText LIKE '%ERROR%';
GO

SELECT COUNT(*) AS [4b_LIKE_anchored_indexed]
FROM dbo.BenchRows
WHERE AsciiText LIKE 'ERROR%';
GO
-- REGEXP_LIKE will still scan even with the index. See the lesson.


/* ============================================================
   BENCHMARK 5 — UNICODE-AWARE MATCHING
   Question: what is the cost of matching Unicode content
   vs. ASCII? Does \w behave differently on NVARCHAR vs VARCHAR?
   ============================================================ */
PRINT '======== BENCHMARK 5: UNICODE MATCHING ========';
GO

-- 5a. ASCII column — simple word match
SELECT COUNT(*) AS [5a_ASCII_word_match]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, '\b\w+\b');
GO

-- 5b. NVARCHAR column — same pattern, Unicode content
SELECT COUNT(*) AS [5b_UNICODE_word_match]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(UnicodeText, '\b\w+\b');
GO

-- 5c. ASCII column — count words per row (REGEXP_COUNT)
SELECT SUM(REGEXP_COUNT(AsciiText, '\b\w+\b')) AS [5c_ASCII_word_count]
FROM dbo.BenchRows;
GO

-- 5d. NVARCHAR column — count words per row
SELECT SUM(REGEXP_COUNT(UnicodeText, '\b\w+\b')) AS [5d_UNICODE_word_count]
FROM dbo.BenchRows;
GO

-- 5e. Explicit ASCII class vs \w on Unicode column
--     [A-Za-z0-9_]+ matches only ASCII word chars
SELECT COUNT(*) AS [5e_UNICODE_col_ASCII_class]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(UnicodeText, '[A-Za-z0-9_]+');
GO

-- 5f. \w on the Unicode column — may or may not match CJK/Cyrillic
--     depending on RE2's Unicode property support in SQL Server 2025
SELECT COUNT(*) AS [5f_UNICODE_col_w_shorthand]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(UnicodeText, '\w+');
GO

-- 5g. Unicode letter class \p{L} — matches any Unicode letter
--     (if supported by SQL Server 2025's RE2 build)
SELECT COUNT(*) AS [5g_UNICODE_letter_property]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(UnicodeText, '\p{L}+');
GO

-- 5h. Detect non-ASCII characters (useful for data quality checks)
SELECT COUNT(*) AS [5h_detect_nonASCII]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(UnicodeText, '[^\x00-\x7F]');
GO

-- 5i. Compare: LIKE on NVARCHAR with collation vs. REGEXP
--     LIKE respects the column collation; REGEXP_LIKE may not
SELECT COUNT(*) AS [5i_LIKE_unicode_caseinsensitive]
FROM dbo.BenchRows
WHERE UnicodeText LIKE N'%hello%';   -- depends on collation
GO

SELECT COUNT(*) AS [5i_REGEXP_unicode_caseinsensitive]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(UnicodeText, 'hello', 'i');
GO

/*
   WHAT TO LOOK FOR:
   - 5a vs 5b: VARCHAR is typically faster because bytes are fixed-width.
     NVARCHAR uses UTF-16; RE2 may process it differently.
   - 5e vs 5f: the gap reveals whether \w is Unicode-aware in this build.
     If 5f matches Cyrillic/CJK rows and 5e does not, \w is Unicode-aware.
   - 5g: if \p{L} is not supported by SQL Server 2025's RE2 build,
     you'll get an error — important to test and document.
   - 5i: LIKE honors SQL collation (case-insensitive by default on most
     databases). REGEXP_LIKE is case-sensitive unless you pass 'i'.
     This difference can cause confusing result mismatches.
*/


/* ============================================================
   BENCHMARK 6 — BACKREFERENCES
   RE2 (SQL Server 2025's engine) does NOT support backreferences.
   This section documents that boundary and shows workarounds.
   ============================================================ */
PRINT '======== BENCHMARK 6: BACKREFERENCES ========';
GO

-- 6a. Backreference attempt — will ERROR in SQL Server 2025 (RE2)
--     Pattern: find repeated consecutive words like "the the"
--     In PCRE: (\b\w+\b)\s+\1  — \1 backreferences group 1
--     In RE2/SQL Server 2025: NOT SUPPORTED — here for documentation
/*
SELECT COUNT(*) AS [6a_REGEXP_backreference_UNSUPPORTED]
FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, '(\b\w+\b)\s+\1');   -- will fail
-- Error: backreferences are not supported by the RE2 engine
*/

-- 6b. WORKAROUND: find repeated words with a self-join approach
--     Create a small test table for this demo
DROP TABLE IF EXISTS #RepeatWords;
CREATE TABLE #RepeatWords (Phrase NVARCHAR(200));
INSERT INTO #RepeatWords VALUES
    (N'the the quick brown fox'),
    (N'cat cat sat on the mat'),
    (N'no repeats here'),
    (N'dog dog dog jumped');

-- No REGEXP backreference available; use a scalar approach:
-- extract word tokens via REGEXP_SPLIT_TO_TABLE, then find duplicates
SELECT
    r.Phrase,
    s.value AS Word,
    COUNT(*) AS Occurrences
FROM #RepeatWords r
CROSS APPLY REGEXP_SPLIT_TO_TABLE(r.Phrase, '\s+') s
GROUP BY r.Phrase, s.value
HAVING COUNT(*) > 1;
GO

-- 6c. WORKAROUND 2: REGEXP_MATCHES to get all words, then self-join
SELECT DISTINCT a.Phrase
FROM (
    SELECT r.Phrase, m.substring_match AS Word
    FROM #RepeatWords r
    CROSS APPLY REGEXP_MATCHES(r.Phrase, '\b\w+\b') m
) a
JOIN (
    SELECT r.Phrase, m.substring_match AS Word
    FROM #RepeatWords r
    CROSS APPLY REGEXP_MATCHES(r.Phrase, '\b\w+\b') m
) b ON a.Phrase = b.Phrase AND a.Word = b.Word
-- just to illustrate the pattern; this doesn't fully replicate \1
;
GO

-- 6d. WORKAROUND 3: CLR regex (pre-2025 approach using .NET engine)
--     .NET supports backreferences; if CLR is enabled, it can do what
--     RE2 cannot. Shown as pseudocode since CLR setup is environment-specific:
/*
-- Register CLR assembly with PCRE/BCL regex:
CREATE ASSEMBLY RegexHelper FROM 'C:\path\RegexHelper.dll'
    WITH PERMISSION_SET = SAFE;
CREATE FUNCTION dbo.RegexIsMatch(@input NVARCHAR(MAX), @pattern NVARCHAR(MAX))
RETURNS BIT AS EXTERNAL NAME RegexHelper.[RegexHelper.Functions].IsMatch;
GO

-- Now backreferences work:
SELECT COUNT(*) FROM dbo.BenchRows
WHERE dbo.RegexIsMatch(AsciiText, N'(\b\w+\b)\s+\1') = 1;
*/

-- 6e. BENCHMARK: What's the cost of the PCRE2-via-CLR approach?
--     Compare CLR regex vs REGEXP_LIKE for equivalent non-backreference pattern
--     Shown structurally — fill in CLR function name if available:
/*
-- CLR approach (PCRE, supports everything, slower startup):
SELECT COUNT(*) FROM dbo.BenchRows
WHERE dbo.ClrRegexIsMatch(AsciiText, N'\d{4}') = 1;  -- CLR PCRE

-- vs native REGEXP_LIKE (RE2, no startup cost):
SELECT COUNT(*) FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText, '\d{4}') = 1;            -- RE2
*/





/* ============================================================
   BENCHMARK 7 — CONSOLIDATED COMPARISON SUMMARY
   Run this after all benchmarks to get a single result set
   you can paste into Excel / a slide.
   ============================================================ */
PRINT '======== BENCHMARK 7: SUMMARY PASS ========';
GO

DECLARE @t0 DATETIME2, @t1 DATETIME2, @cpu0 INT, @cnt INT;
DECLARE @Results TABLE (
    TestID      INT,
    Category    VARCHAR(50),
    Method      VARCHAR(60),
    Pattern     VARCHAR(100),
    MatchCount  INT,
    ElapsedMs   INT
);

-- Helper macro pattern: capture time, run query, capture time again
-- (In a real benchmark harness you would use sys.dm_exec_query_stats;
--  here we use SYSDATETIME() for simplicity in a demo context.)

-- T1: LIKE literal
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE AsciiText LIKE '%timeout%';
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (1,'Literal','LIKE','%timeout%',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T2: CHARINDEX literal
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE CHARINDEX('timeout',AsciiText)>0;
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (2,'Literal','CHARINDEX','timeout',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T3: REGEXP literal
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE REGEXP_LIKE(AsciiText,'timeout');
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (3,'Literal','REGEXP_LIKE','timeout',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T4: LIKE char class (4 digits)
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE AsciiText LIKE '%[0-9][0-9][0-9][0-9]%';
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (4,'Char Class','LIKE','%[0-9]{4}%',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T5: REGEXP char class
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE REGEXP_LIKE(AsciiText,'\d{4}');
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (5,'Char Class','REGEXP_LIKE','\d{4}',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T6: LIKE OR 3 terms
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows
WHERE AsciiText LIKE '%cat%' OR AsciiText LIKE '%dog%' OR AsciiText LIKE '%bird%';
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (6,'Alternation','LIKE OR (3)','cat|dog|bird',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T7: REGEXP alternation 3 terms
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE REGEXP_LIKE(TagCol,'cat|dog|bird');
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (7,'Alternation','REGEXP_LIKE (3)','cat|dog|bird',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T8: LIKE OR 5 terms
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows
WHERE AsciiText LIKE '%error%' OR AsciiText LIKE '%timeout%'
   OR AsciiText LIKE '%duration%' OR AsciiText LIKE '%auth%'
   OR AsciiText LIKE '%order%';
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (8,'Alternation','LIKE OR (5)','5 terms',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T9: REGEXP alternation 5 terms
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows
WHERE REGEXP_LIKE(AsciiText,'error|timeout|duration|auth|order');
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (9,'Alternation','REGEXP_LIKE (5)','5 terms',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T10: LIKE unanchored
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE AsciiText LIKE '%ERROR%';
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (10,'Anchoring','LIKE unanchored','%ERROR%',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T11: LIKE anchored
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE AsciiText LIKE 'ERROR%';
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (11,'Anchoring','LIKE anchored ^','ERROR%',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T12: REGEXP unanchored
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE REGEXP_LIKE(AsciiText,'ERROR');
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (12,'Anchoring','REGEXP unanchored','ERROR',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T13: REGEXP anchored
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE REGEXP_LIKE(AsciiText,'^ERROR');
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (13,'Anchoring','REGEXP anchored ^','^ERROR',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T14: Unicode ASCII col
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE REGEXP_LIKE(AsciiText,'\w+');
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (14,'Unicode','REGEXP VARCHAR','\w+ on VARCHAR',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- T15: Unicode NVARCHAR col
SET @t0 = SYSDATETIME();
SELECT @cnt = COUNT(*) FROM dbo.BenchRows WHERE REGEXP_LIKE(UnicodeText,'\w+');
SET @t1 = SYSDATETIME();
INSERT INTO @Results VALUES (15,'Unicode','REGEXP NVARCHAR','\w+ on NVARCHAR',@cnt,DATEDIFF(MILLISECOND,@t0,@t1));

-- Display results
SELECT
    TestID,
    Category,
    Method,
    Pattern,
    MatchCount,
    ElapsedMs,
    CASE
        WHEN ElapsedMs = 0 THEN '< 1ms'
        ELSE CAST(ElapsedMs AS VARCHAR) + ' ms'
    END AS Duration,
    -- Ratio vs the fastest test in the same category
    CAST(
        1.0 * ElapsedMs /
        NULLIF(MIN(ElapsedMs) OVER (PARTITION BY Category), 0)
    AS DECIMAL(6,2)) AS [SlowerThanFastestInCategory_x]
FROM @Results
ORDER BY Category, TestID;
GO

SET STATISTICS TIME OFF;
GO

