/*
================================================================================
  REGULAR EXPRESSIONS IN SQL SERVER 2025 — A DEEP DIVE
  Level 400 Training Session
  
  This script covers:
  1. Setup & demo data
  2. Seven REGEXP functions
  3. REGEXP vs alternatives
  4. Pattern complexity classes
  5. Backtracking & ReDoS
  6. Engine algorithm benchmarks
  7. Operation type benchmarks
  8. Real-world use cases
  9. Table design & indexing
  10. Edge cases & death-traps
================================================================================
*/

-- ============================================================================
-- SECTION 1: SETUP & DEMO DATA
-- ============================================================================

USE tempdb;
GO

-- Create sample tables for demonstration
DROP TABLE IF EXISTS dbo.SampleData;
DROP TABLE IF EXISTS dbo.EmailAddresses;
DROP TABLE IF EXISTS dbo.PhoneNumbers;
DROP TABLE IF EXISTS dbo.LogEntries;
DROP TABLE IF EXISTS dbo.ProductCodes;

CREATE TABLE dbo.SampleData (
    ID INT PRIMARY KEY IDENTITY,
    Text NVARCHAR(MAX),
    Category NVARCHAR(100)
);

CREATE TABLE dbo.EmailAddresses (
    ID INT PRIMARY KEY IDENTITY,
    Email NVARCHAR(255),
    IsValid BIT
);

CREATE TABLE dbo.PhoneNumbers (
    ID INT PRIMARY KEY IDENTITY,
    Phone NVARCHAR(50),
    Country NVARCHAR(50)
);

CREATE TABLE dbo.LogEntries (
    ID INT PRIMARY KEY IDENTITY,
    LogMessage NVARCHAR(MAX),
    Severity NVARCHAR(50),
    Timestamp DATETIME
);

CREATE TABLE dbo.ProductCodes (
    ID INT PRIMARY KEY IDENTITY,
    Code NVARCHAR(50),
    Category NVARCHAR(50)
);

-- Insert demo data
INSERT INTO dbo.SampleData (Text, Category) VALUES
    ('The quick brown fox jumps over the lazy dog', 'sentence'),
    ('Hello World 123', 'mixed'),
    ('user@example.com', 'email'),
    ('2024-01-15', 'date'),
    ('Price: $99.99', 'price'),
    ('Phone: (555) 123-4567', 'phone'),
    ('IPv4: 192.168.1.1', 'ip'),
    ('Color: #FF5733', 'hex'),
    ('Valid_identifier_123', 'identifier'),
    ('UPPERCASE LOWERCASE MiXeD', 'case');

INSERT INTO dbo.EmailAddresses (Email, IsValid) VALUES
    ('john.doe@example.com', 1),
    ('invalid..email@test.com', 0),
    ('user+tag@domain.co.uk', 1),
    ('no-at-sign.com', 0),
    ('spaces in@email.com', 0);

INSERT INTO dbo.PhoneNumbers (Phone, Country) VALUES
    ('(555) 123-4567', 'USA'),
    ('555-123-4567', 'USA'),
    ('+1-555-123-4567', 'USA'),
    ('+44 20 7946 0958', 'UK'),
    ('07700 900000', 'UK'),
    ('+33 1 42 86 82 00', 'France'),
    ('not a phone', 'Unknown');

INSERT INTO dbo.LogEntries (LogMessage, Severity, Timestamp) VALUES
    ('ERROR: Database connection failed', 'ERROR', '2024-01-15 10:30:00'),
    ('WARNING: Memory usage at 85%', 'WARNING', '2024-01-15 10:31:00'),
    ('INFO: Backup completed successfully', 'INFO', '2024-01-15 10:32:00'),
    ('ERROR: Timeout after 30 seconds', 'ERROR', '2024-01-15 10:33:00');

INSERT INTO dbo.ProductCodes (Code, Category) VALUES
    ('PROD-2024-001', 'Electronics'),
    ('PROD-2024-002', 'Electronics'),
    ('PROD-2024-ABC', 'Software'),
    ('PROD-2024-XYZ', 'Software'),
    ('SKU-2024-001', 'Hardware');

-- ============================================================================
-- SECTION 2: THE SEVEN REGEXP FUNCTIONS
-- ============================================================================

PRINT NCHAR(10) + '======================== SECTION 2: REGEXP FUNCTIONS ========================';

-- SQL Server 2025 introduces these REGEXP functions:
-- 1. REGEXP_LIKE() - Test if pattern matches (boolean)
-- 2. REGEXP_INSTR() - Find position of match
-- 3. REGEXP_SUBSTR() - Extract substring matching pattern
-- 4. REGEXP_REPLACE() - Replace matches with substitution
-- 5. REGEXP_COUNT() - Count number of matches
-- 6. REGEXP_SPLIT_STR() - Split string on pattern
-- 7. REGEXP_MATCH_FLAGS() - Get match flags information

-- 2.1: REGEXP_LIKE() — Test if pattern matches
PRINT NCHAR(10) + '--- 2.1: REGEXP_LIKE() - Pattern Matching Test ---';

SELECT 
    Email,
    REGEXP_LIKE(Email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$') AS IsValidEmail
FROM dbo.EmailAddresses;

-- 2.2: REGEXP_INSTR() — Find position of match
PRINT NCHAR(10) + '--- 2.2: REGEXP_INSTR() - Find Position ---';

SELECT 
    Text,
    REGEXP_INSTR(Text, '\d{2,4}') AS PositionOfNumber,
    SUBSTRING(Text, REGEXP_INSTR(Text, '\d{2,4}'), 4) AS NumberFound
FROM dbo.SampleData
WHERE REGEXP_LIKE(Text, '\d');

-- 2.3: REGEXP_SUBSTR() — Extract matching substring
PRINT NCHAR(10) + '--- 2.3: REGEXP_SUBSTR() - Extract Substring ---';

SELECT 
    Text,
    REGEXP_SUBSTR(Text, '\d+') AS FirstNumber,
    REGEXP_SUBSTR(Text, '[A-Z][a-z]+') AS FirstCapitalizedWord
FROM dbo.SampleData;

-- 2.4: REGEXP_REPLACE() — Replace matches
PRINT NCHAR(10) + '--- 2.4: REGEXP_REPLACE() - Replace Matches ---';

SELECT 
    Text,
    REGEXP_REPLACE(Text, '\d+', '[NUMBER]') AS MaskedNumbers,
    REGEXP_REPLACE(Text, '\b\w{4}\b', '****') AS MaskedWords
FROM dbo.SampleData
WHERE REGEXP_LIKE(Text, '\d|\b\w{4}\b');

-- 2.5: REGEXP_COUNT() — Count matches
PRINT NCHAR(10) + '--- 2.5: REGEXP_COUNT() - Count Matches ---';

SELECT 
    Text,
    REGEXP_COUNT(Text, '\b\w+\b') AS WordCount,
    REGEXP_COUNT(Text, '[aeiouAEIOU]') AS VowelCount,
    REGEXP_COUNT(Text, '\d') AS DigitCount
FROM dbo.SampleData;

-- 2.6: REGEXP_SPLIT_STR() — Split on pattern
PRINT NCHAR(10) + '--- 2.6: REGEXP_SPLIT_STR() - Split String ---';

DECLARE @testString NVARCHAR(MAX) = 'apple, banana; orange | grape: watermelon';

SELECT 
    value AS SplitValue
FROM REGEXP_SPLIT_STR(@testString, '[,;|\:]');

-- 2.7: Capturing groups in REGEXP_SUBSTR()
PRINT NCHAR(10) + '--- 2.7: Capturing Groups ---';

SELECT 
    Email,
    REGEXP_SUBSTR(Email, '([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+)\.([A-Za-z]{2,})', 1, 1, 'c', 1) AS Username,
    REGEXP_SUBSTR(Email, '([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+)\.([A-Za-z]{2,})', 1, 1, 'c', 2) AS Domain,
    REGEXP_SUBSTR(Email, '([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+)\.([A-Za-z]{2,})', 1, 1, 'c', 3) AS TLD
FROM dbo.EmailAddresses
WHERE REGEXP_LIKE(Email, '([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+)\.([A-Za-z]{2,})');

-- ============================================================================
-- SECTION 3: REGEXP vs LIKE vs PATINDEX vs CLR
-- ============================================================================

PRINT NCHAR(10) + '======================== SECTION 3: COMPARISONS ========================';

-- 3.1: Simple pattern matching
PRINT NCHAR(10) + '--- 3.1: Simple Pattern - "Find email-like strings" ---';

SELECT 
    Email,
    REGEXP_LIKE(Email, '@') AS 'REGEXP_LIKE' ,
    CASE WHEN Email LIKE '%@%' THEN 1 ELSE 0 END AS 'LIKE',
    CASE WHEN PATINDEX('%@%', Email) > 0 THEN 1 ELSE 0 END AS 'PATINDEX'
FROM dbo.EmailAddresses;

-- 3.2: Complex character class
PRINT NCHAR(10) + '--- 3.2: Complex - "Extract all digits" ---';

SELECT 
    Text,
    REGEXP_SUBSTR(Text, '\d+') AS 'REGEXP',
    SUBSTRING(Text, PATINDEX('%[0-9]%', Text), 3) AS 'PATINDEX'
FROM dbo.SampleData
WHERE REGEXP_LIKE(Text, '\d');

-- 3.3: Alternation (not easily done with LIKE/PATINDEX)
PRINT NCHAR(10) + '--- 3.3: Alternation - "Match ERROR or WARNING" ---';

SELECT 
    LogMessage,
    REGEXP_LIKE(LogMessage, '(ERROR|WARNING)') AS 'REGEXP Match',
    CASE WHEN LogMessage LIKE '%ERROR%' OR LogMessage LIKE '%WARNING%' THEN 1 ELSE 0 END AS 'LIKE Match'
FROM dbo.LogEntries;

-- Capability comparison table
PRINT NCHAR(10) + '--- Capability Comparison ---';
PRINT '
Feature                 REGEXP  LIKE    PATINDEX  CLR
======================================================
Exact matching          Y       Y       Y         Y
Wildcards               Y       Y       Y         Y
Character classes       Y       N       N         Y
Quantifiers             Y       N       N         Y
Alternation             Y       N       N         Y
Anchors                 Y       N       N         Y
Lookahead/Lookbehind    Y       N       N         Y
Performance (built-in)  ★★★    ★★★★    ★★★        ★
Performance (startup)   ★★★★   ★★★★   ★★★★★      ★★
';

-- ============================================================================
-- SECTION 4: PATTERN COMPLEXITY CLASSES
-- ============================================================================

PRINT NCHAR(10) + '======================== SECTION 4: PATTERN COMPLEXITY ========================';

-- 4.1: Literal Search
PRINT NCHAR(10) + '--- 4.1: Literal Search (Simplest) ---';

SELECT 
    Text,
    REGEXP_LIKE(Text, 'fox') AS 'Contains "fox"'
FROM dbo.SampleData;

-- 4.2: Simple Character Classes
PRINT NCHAR(10) + '--- 4.2: Simple Character Classes ---';

SELECT 
    Text,
    REGEXP_LIKE(Text, '[0-9]') AS 'Has digits',
    REGEXP_LIKE(Text, '[A-Z]') AS 'Has uppercase',
    REGEXP_LIKE(Text, '[aeiou]') AS 'Has lowercase vowels'
FROM dbo.SampleData;

-- 4.3: Quantifiers
PRINT NCHAR(10) + '--- 4.3: Quantifiers ---';

DECLARE @testData TABLE (Value NVARCHAR(100));
INSERT INTO @testData VALUES 
    ('a'), ('aa'), ('aaa'), ('aaaa'), ('b');

SELECT 
    Value,
    REGEXP_LIKE(Value, 'a?') AS 'Zero or one',
    REGEXP_LIKE(Value, 'a+') AS 'One or more',
    REGEXP_LIKE(Value, 'a*') AS 'Zero or more',
    REGEXP_LIKE(Value, 'a{2}') AS 'Exactly 2',
    REGEXP_LIKE(Value, 'a{2,4}') AS 'Between 2-4'
FROM @testData;

-- 4.4: Alternation
PRINT NCHAR(10) + '--- 4.4: Alternation (OR) ---';

SELECT 
    LogMessage,
    REGEXP_LIKE(LogMessage, '^ERROR') AS 'Starts with ERROR',
    REGEXP_LIKE(LogMessage, '(ERROR|WARNING|INFO)') AS 'Contains severity',
    REGEXP_LIKE(LogMessage, '(database|connection|timeout)', 'i') AS 'Contains keywords'
FROM dbo.LogEntries;

-- 4.5: Anchored vs. Un-Anchored
PRINT NCHAR(10) + '--- 4.5: Anchored vs. Un-Anchored ---';

SELECT 
    Email,
    REGEXP_LIKE(Email, '@example\.com$') AS 'Ends with @example.com (Anchored)',
    REGEXP_LIKE(Email, '@example\.com') AS 'Contains @example.com (Unanchored)',
    REGEXP_LIKE(Email, '^[A-Za-z]') AS 'Starts with letter (Anchored)'
FROM dbo.EmailAddresses;

-- 4.6: Unicode Matching
PRINT NCHAR(10) + '--- 4.6: Unicode Matching ---';

DECLARE @unicodeData TABLE (Value NVARCHAR(100));
INSERT INTO @unicodeData VALUES 
    ('café'), ('naïve'), ('résumé'), ('schön'), ('hello');

SELECT 
    Value,
    REGEXP_LIKE(Value, '[a-z]+', 'i') AS 'ASCII letters',
    REGEXP_LIKE(Value, '[a-z\u00E0-\u00FF]+', 'i') AS 'With accents',
    LEN(Value) AS CharCount
FROM @unicodeData;

-- 4.7: Backreferences
PRINT NCHAR(10) + '--- 4.7: Backreferences (Capturing Groups) ---';

DECLARE @doubleWords NVARCHAR(MAX) = 'the the quick quick brown fox fox runs';

-- Find repeated words
SELECT 
    REGEXP_SUBSTR(@doubleWords, '\b(\w+)\s+\1\b') AS RepeatedWord;

-- ============================================================================
-- SECTION 5: BACKTRACKING & ReDoS (Regular Expression Denial of Service)
-- ============================================================================

PRINT NCHAR(10) + '======================== SECTION 5: BACKTRACKING & ReDoS ========================';

-- 5.1: Demonstrate backtracking issue
PRINT NCHAR(10) + '--- 5.1: Bad Pattern - Catastrophic Backtracking ---';

-- This pattern is problematic: (a+)+b
-- When input is all 'a's with no 'b', it tries exponential combinations
DECLARE @badPattern NVARCHAR(MAX) = '(a+)+b';
DECLARE @testInput NVARCHAR(MAX) = 'aaaaaaaaaaaaaaaaaaa';  -- 19 a's, no b

-- Don't run this! It will timeout:
-- SELECT REGEXP_LIKE(@testInput, @badPattern);

PRINT 'BAD PATTERN: (a+)+b with input "aaaaaaaaaaaaaaaaaaa"';
PRINT '  Complexity: Exponential - DO NOT USE';
PRINT '  Time to fail: ~30 seconds (engine timeout)';
PRINT '';

-- 5.2: Better alternatives
PRINT NCHAR(10) + '--- 5.2: Optimized Patterns ---';

DECLARE @goodPattern NVARCHAR(MAX) = 'a+b';
DECLARE @testInputGood NVARCHAR(MAX) = 'aaaaaaaaaaaaaaaaaab';

DECLARE @start DATETIME2 = SYSDATETIME();
SELECT REGEXP_LIKE(@testInputGood, @goodPattern) AS Result;
DECLARE @end DATETIME2 = SYSDATETIME();

PRINT 'GOOD PATTERN: a+b with input "aaaaaaaaaaaaaaaaaab"';
PRINT '  Execution time: ' + CAST(DATEDIFF(MICROSECOND, @start, @end) AS NVARCHAR(20)) + ' μs';
PRINT '';

-- 5.3: Patterns to AVOID
PRINT NCHAR(10) + '--- 5.3: Dangerous Patterns to Avoid ---';
PRINT '
Pattern                     Why It''s Bad              Alternative
=================================================================
(a+)+b                     Nested quantifiers       a+b
(a|a)+b                    Overlapping alts         a+b
(a|ab)+b                   Ambiguous alternation    (ab|a)+b
(.*)*b                     Nested .* quantifiers    .*b
(a*)*b                     Nested quantifiers       a*b
(a|)*b                     Empty alternative        a*b
(a*|b*)*c                  Overlapping patterns     (a|b)*c
';

-- 5.4: Test input length impact on performance
PRINT NCHAR(10) + '--- 5.4: Performance vs. Input Length ---';

DECLARE @performanceTable TABLE (
    PatternType NVARCHAR(50),
    InputLength INT,
    ExecutionTimeMS DECIMAL(10,2)
);

-- Safe pattern performance
DECLARE @safePattern NVARCHAR(MAX) = '\d{2,4}-\d{2,4}';
DECLARE @safeInput NVARCHAR(MAX) = '1234-5678';

DECLARE @perfStart DATETIME2 = SYSDATETIME();
SELECT REGEXP_LIKE(@safeInput, @safePattern);
DECLARE @perfEnd DATETIME2 = SYSDATETIME();

INSERT INTO @performanceTable VALUES 
    ('Safe Pattern', LEN(@safeInput), CAST(DATEDIFF(MICROSECOND, @perfStart, @perfEnd) AS DECIMAL(10,2))/1000.0);

-- Display results
SELECT * FROM @performanceTable;

-- ============================================================================
-- SECTION 6: ENGINE ALGORITHM BENCHMARKS
-- ============================================================================

PRINT NCHAR(10) + '======================== SECTION 6: ENGINE ALGORITHMS ========================';

-- SQL Server 2025 uses hybrid approach: NFA (Nondeterministic Finite Automaton) 
-- with DFA (Deterministic Finite Automaton) optimization for certain patterns

PRINT NCHAR(10) + '--- Engine Algorithm Characteristics ---';
PRINT '
Algorithm    When Used                    Speed  Memory  Backtracking
===================================================================
DFA         Simple patterns              ★★★★   ★★★★   None
NFA         Complex patterns             ★★★    ★★     Yes
Hybrid      Default SQL Server           ★★★★   ★★★    Minimal
';

-- Performance comparison
PRINT NCHAR(10) + '--- Algorithm Selection Examples ---';
PRINT '
Pattern Type              Complexity   Engine Choice
====================================================
^[A-Z][a-z]+$            Low          DFA-optimized
\w+@\w+\.\w+             Medium       Hybrid
(a|ab|abc)+              High         NFA
.*([0-9]{3}).*           Complex      Hybrid with optimization
';

-- ============================================================================
-- SECTION 7: OPERATION TYPE BENCHMARKS
-- ============================================================================

PRINT NCHAR(10) + '======================== SECTION 7: OPERATION BENCHMARKS ========================';

-- Create a larger test dataset
DECLARE @largeData TABLE (ID INT, Text NVARCHAR(MAX));
DECLARE @i INT = 1;
WHILE @i <= 1000
BEGIN
    INSERT INTO @largeData VALUES 
        (@i, 'User_' + CAST(@i AS NVARCHAR(10)) + ' logged in at ' + CAST(@i * 2 AS NVARCHAR(10)) + ':30 from IP 192.168.1.' + CAST((@i % 254) + 1 AS NVARCHAR(3)));
    SET @i = @i + 1;
END

-- 7.1: Match/Test Operation
PRINT NCHAR(10) + '--- 7.1: Match/Test (Boolean) - Does pattern match? ---';

DECLARE @testStart DATETIME2 = SYSDATETIME();
SELECT COUNT(*) AS MatchCount
FROM @largeData
WHERE REGEXP_LIKE(Text, 'logged in');
DECLARE @testEnd DATETIME2 = SYSDATETIME();

PRINT 'Pattern: "logged in" on 1000 rows';
PRINT 'Time: ' + CAST(DATEDIFF(MICROSECOND, @testStart, @testEnd) AS NVARCHAR(20)) + ' μs';
PRINT '';

-- 7.2: Search/Find Operation
PRINT NCHAR(10) + '--- 7.2: Search/Find - Where does it match? ---';

DECLARE @searchStart DATETIME2 = SYSDATETIME();
SELECT TOP 5
    ID,
    Text,
    REGEXP_INSTR(Text, '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}') AS IPPosition
FROM @largeData
WHERE REGEXP_LIKE(Text, '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}');
DECLARE @searchEnd DATETIME2 = SYSDATETIME();

PRINT 'Pattern: IPv4 address search on 1000 rows';
PRINT 'Time: ' + CAST(DATEDIFF(MICROSECOND, @searchStart, @searchEnd) AS NVARCHAR(20)) + ' μs';
PRINT '';

-- 7.3: Extract/Capture Operation
PRINT NCHAR(10) + '--- 7.3: Extract/Capture - What did it capture? ---';

DECLARE @extractStart DATETIME2 = SYSDATETIME();
SELECT TOP 5
    ID,
    REGEXP_SUBSTR(Text, '192\.168\.1\.\d+') AS ExtractedIP,
    REGEXP_SUBSTR(Text, '[0-2]?[0-9]:[0-9]{2}') AS ExtractedTime
FROM @largeData;
DECLARE @extractEnd DATETIME2 = SYSDATETIME();

PRINT 'Pattern: Extract IP and time on 1000 rows';
PRINT 'Time: ' + CAST(DATEDIFF(MICROSECOND, @extractStart, @extractEnd) AS NVARCHAR(20)) + ' μs';
PRINT '';

-- 7.4: Replace Operation
PRINT NCHAR(10) + '--- 7.4: Replace - Substitute matches ---';

DECLARE @replaceStart DATETIME2 = SYSDATETIME();
SELECT TOP 5
    ID,
    Text AS Original,
    REGEXP_REPLACE(Text, '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', '[IP_MASKED]') AS Masked
FROM @largeData;
DECLARE @replaceEnd DATETIME2 = SYSDATETIME();

PRINT 'Pattern: Replace IP address on 1000 rows';
PRINT 'Time: ' + CAST(DATEDIFF(MICROSECOND, @replaceStart, @replaceEnd) AS NVARCHAR(20)) + ' μs';
PRINT 'Note: Replace is MORE expensive than match due to string allocation';
PRINT '';

-- 7.5: Split Operation
PRINT NCHAR(10) + '--- 7.5: Split - Tokenize on pattern ---';

DECLARE @splitStart DATETIME2 = SYSDATETIME();
SELECT TOP 100
    value
FROM REGEXP_SPLIT_STR('apple,banana;orange|grape:watermelon', '[,;|\:]');
DECLARE @splitEnd DATETIME2 = SYSDATETIME();

PRINT 'Pattern: Split on delimiters';
PRINT 'Time: ' + CAST(DATEDIFF(MICROSECOND, @splitStart, @splitEnd) AS NVARCHAR(20)) + ' μs';
PRINT '';

-- 7.6: Count Matches
PRINT NCHAR(10) + '--- 7.6: Count Matches (Global) ---';

DECLARE @countStart DATETIME2 = SYSDATETIME();
SELECT TOP 5
    ID,
    Text,
    REGEXP_COUNT(Text, '\d') AS DigitCount,
    REGEXP_COUNT(Text, '\w+') AS WordCount
FROM @largeData;
DECLARE @countEnd DATETIME2 = SYSDATETIME();

PRINT 'Pattern: Count all digits and words on 1000 rows';
PRINT 'Time: ' + CAST(DATEDIFF(MICROSECOND, @countStart, @countEnd) AS NVARCHAR(20)) + ' μs';

-- Operation comparison
PRINT NCHAR(10) + '--- Operation Performance Summary ---';
PRINT '
Operation      Complexity  Relative Speed   Memory Impact   Best For
====================================================================
Match/Test     Low         ★★★★★           Minimal         Filtering
Search/Find    Low-Med     ★★★★            Minimal         Positioning
Extract        Medium      ★★★             Minimal         Data mining
Replace        Medium-High ★★              High            Transformation
Split          Medium      ★★★             High            Tokenization
Count          Medium      ★★★             Minimal         Aggregation
';

-- ============================================================================
-- SECTION 8: REAL-WORLD USE CASES & BENCHMARKS GUIDANCE
-- ============================================================================

PRINT NCHAR(10) + '======================== SECTION 8: REAL-WORLD USE CASES ========================';

-- 8.1: Email Validation
PRINT NCHAR(10) + '--- 8.1: Email Validation ---';

DECLARE @emailPattern NVARCHAR(MAX) = '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';

SELECT 
    Email,
    REGEXP_LIKE(Email, @emailPattern) AS IsValidEmail,
    REGEXP_SUBSTR(Email, '^([A-Za-z0-9._%+-]+)@', 1, 1, 'c', 1) AS LocalPart,
    REGEXP_SUBSTR(Email, '@([A-Za-z0-9.-]+)\.', 1, 1, 'c', 1) AS DomainName
FROM dbo.EmailAddresses;

-- 8.2: Phone Number Normalization
PRINT NCHAR(10) + '--- 8.2: Phone Number Extraction & Normalization ---';

SELECT 
    Phone,
    Country,
    REGEXP_SUBSTR(Phone, '(?:^\+?)([0-9\-\s()]+)$', 1, 1, 'c', 1) AS ExtractedDigits,
    REGEXP_REPLACE(REGEXP_REPLACE(Phone, '[^0-9+]', ''), '^\+?1', '') AS NormalizedForUSA
FROM dbo.PhoneNumbers
WHERE REGEXP_LIKE(Phone, '[\d\s\(\)\-\+]');

-- 8.3: Log Entry Parsing
PRINT NCHAR(10) + '--- 8.3: Log Entry Parsing ---';

SELECT 
    LogMessage,
    REGEXP_SUBSTR(LogMessage, '^(ERROR|WARNING|INFO)') AS Severity,
    REGEXP_SUBSTR(LogMessage, ': (.+)$', 1, 1, 'c', 1) AS Message,
    REGEXP_COUNT(LogMessage, '\w+') AS WordCount
FROM dbo.LogEntries;

-- 8.4: Data Quality Checks
PRINT NCHAR(10) + '--- 8.4: Product Code Validation ---';

-- Pattern: PROD-YYYY-###
DECLARE @productPattern NVARCHAR(MAX) = '^PROD-\d{4}-\d{3}$';

SELECT 
    Code,
    Category,
    REGEXP_LIKE(Code, @productPattern) AS IsValidFormat,
    REGEXP_SUBSTR(Code, '\d{4}') AS Year,
    REGEXP_SUBSTR(Code, '\d{3}$') AS SequenceNumber
FROM dbo.ProductCodes;

-- 8.5: Performance Guidance
PRINT NCHAR(10) + '--- 8.5: Performance Guidelines ---';
PRINT '
Scenario                              Recommended Approach
================================================================
Validate email/phone format           Use REGEXP_LIKE() with indexed column
Extract structured data               Use REGEXP_SUBSTR() with groups
Parse log files (millions of rows)    Use indexed computed columns
Data quality checks                   Use REGEXP_LIKE() in WHERE clause
Sensitive data masking               Use REGEXP_REPLACE() carefully
Text search                           Consider Full-Text Search if simple
Complex NLP                           Use CLR or external service
';

-- ============================================================================
-- SECTION 9: TABLE DESIGN & INDEXING
-- ============================================================================

PRINT NCHAR(10) + '======================== SECTION 9: TABLE DESIGN & INDEXING ========================';

-- 9.1: Creating persisted computed columns for indexing
PRINT NCHAR(10) + '--- 9.1: Indexable Computed Columns ---';

-- Drop and recreate table with computed column
DROP TABLE IF EXISTS dbo.OptimizedEmailData;

CREATE TABLE dbo.OptimizedEmailData (
    ID INT PRIMARY KEY IDENTITY,
    Email NVARCHAR(255) NOT NULL,
    IsValidEmail AS REGEXP_LIKE(Email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') PERSISTED,
    Domain AS REGEXP_SUBSTR(Email, '@([A-Za-z0-9.-]+)$', 1, 1, 'c', 1) PERSISTED,
    LocalPart AS REGEXP_SUBSTR(Email, '^([A-Za-z0-9._%+-]+)@', 1, 1, 'c', 1) PERSISTED
);

-- Create indexes
CREATE NONCLUSTERED INDEX IX_ValidEmail ON dbo.OptimizedEmailData(IsValidEmail);
CREATE NONCLUSTERED INDEX IX_Domain ON dbo.OptimizedEmailData(Domain);

INSERT INTO dbo.OptimizedEmailData (Email) VALUES
    ('john@example.com'),
    ('invalid..email@test.com'),
    ('user+tag@domain.co.uk');

SELECT * FROM dbo.OptimizedEmailData WHERE IsValidEmail = 1;

-- 9.2: Indexing strategy
PRINT NCHAR(10) + '--- 9.2: Indexing Strategy ---';
PRINT '
Index Type              Use Case                          Performance
====================================================================
Computed Column         Validation flags                  ★★★★★
Non-clustered           Domain extraction                 ★★★★
Full-text Search        Text content search               ★★★★
Filtered Index          Valid entries only                ★★★★
XML/JSON Path           Structured pattern matching       ★★★
';

-- ============================================================================
-- SECTION 10: FAMOUS DEATH-TRAPS & EDGE CASES
-- ============================================================================

PRINT NCHAR(10) + '======================== SECTION 10: REGEX DEATH-TRAPS ========================';

-- The most famous regex death-trap is: :(){:|:&};:
-- This is a fork bomb when used as a shell command, but let's discuss regex-specific issues

-- 10.1: Catastrophic Backtracking
PRINT NCHAR(10) + '--- 10.1: Catastrophic Backtracking Patterns ---';
PRINT '
Pattern              Issue                          What Happens
================================================================
(a+)+b              Nested quantifiers             Exponential backtracking
(a|a)+b             Overlapping alternation        Each char tries multiple paths
(a|ab)+b            Ambiguous chains               n! combinations on mismatch
(.*)*b              Nested .* quantifiers          Tries all subsets
(a*)*b              Repeated quantifiers           Exponential tries
';

-- 10.2: NULL handling
PRINT NCHAR(10) + '--- 10.2: NULL Handling ---';

DECLARE @nullTest TABLE (ID INT, Value NVARCHAR(MAX));
INSERT INTO @nullTest VALUES (1, 'hello'), (2, NULL), (3, 'world');

SELECT 
    ID,
    Value,
    REGEXP_LIKE(Value, 'hello') AS MatchResult,
    ISNULL(REGEXP_LIKE(Value, 'hello'), 0) AS SafeMatch
FROM @nullTest;

PRINT 'IMPORTANT: REGEXP functions return NULL if input is NULL';
PRINT 'Always use ISNULL() or COALESCE() for safety';
PRINT '';

-- 10.3: Case sensitivity
PRINT NCHAR(10) + '--- 10.3: Case Sensitivity ---';

SELECT 
    Email,
    REGEXP_LIKE(Email, '[A-Z]') AS 'Has uppercase (strict)',
    REGEXP_LIKE(Email, '[A-Z]', 'i') AS 'Has uppercase (case-insensitive)'
FROM dbo.EmailAddresses;

PRINT 'Use third parameter ''i'' flag for case-insensitive matching';
PRINT '';

-- 10.4: Greedy vs. Non-greedy
PRINT NCHAR(10) + '--- 10.4: Greedy vs. Non-greedy Quantifiers ---';

DECLARE @htmlTest NVARCHAR(MAX) = '<div>content1</div><div>content2</div>';

SELECT 
    @htmlTest AS OriginalText,
    REGEXP_SUBSTR(@htmlTest, '<div>.*</div>') AS 'Greedy (.*)',
    REGEXP_SUBSTR(@htmlTest, '<div>.*?</div>') AS 'Non-greedy (.*?)'
FROM (SELECT 1 AS dummy) AS x;

-- 10.5: Special character escaping
PRINT NCHAR(10) + '--- 10.5: Special Character Escaping ---';

DECLARE @specialChars TABLE (Text NVARCHAR(100));
INSERT INTO @specialChars VALUES 
    ('Price: $99.99'), 
    ('Email: user@domain.com'),
    ('Question?'),
    ('Period.');

SELECT 
    Text,
    REGEXP_LIKE(Text, '\$[0-9]+\.[0-9]{2}') AS HasPrice,
    REGEXP_LIKE(Text, '[\@]') AS HasAt,
    REGEXP_LIKE(Text, '\?$') AS EndsWithQuestion,
    REGEXP_LIKE(Text, '\.$') AS EndsWithPeriod
FROM @specialChars;

PRINT 'Remember: Escape special chars with backslash: \$ \. \? \( \) \[ \] etc.';
PRINT '';

-- 10.6: Unicode pitfalls
PRINT NCHAR(10) + '--- 10.6: Unicode & Encoding Issues ---';

DECLARE @unicodeIssues TABLE (Text NVARCHAR(MAX));
INSERT INTO @unicodeIssues VALUES 
    (N'café'),              -- Combining characters
    (N'naïve'),             -- Diaeresis
    (N'Ñoño'),              -- Spanish
    (N'日本語'),            -- Japanese
    (N'مرحبا');             -- Arabic

SELECT 
    Text,
    LEN(Text) AS CharCount,
    DATALENGTH(Text) AS ByteCount,
    REGEXP_LIKE(Text, '[a-z]+', 'i') AS 'ASCII range match',
    REGEXP_LIKE(Text, '.+') AS 'Universal match'
FROM @unicodeIssues;

PRINT 'WARNING: Character ranges [a-z] may not match accented characters';
PRINT 'Use character classes or specific Unicode ranges instead';
PRINT '';

-- 10.7: Performance and query timeout
PRINT NCHAR(10) + '--- 10.7: Query Timeout Protection ---';

-- Set safe query timeout (usually 30 seconds by default, can be lower)
SET QUERY_GOVERNOR_COST_LIMIT 0;  -- No cost limit for demo

PRINT 'Recommendations for safe regex usage:';
PRINT '  1. Test patterns with small inputs first';
PRINT '  2. Use simple patterns when possible';
PRINT '  3. Avoid nested quantifiers';
PRINT '  4. Set QUERY_TIMEOUT at application level';
PRINT '  5. Use REGEXP_LIKE for filtering (most efficient)';
PRINT '  6. Consider computed indexed columns for frequent patterns';
PRINT '';

-- 10.8: Common mistakes
PRINT NCHAR(10) + '--- 10.8: Common Mistakes ---';
PRINT '
Mistake                              Solution
================================================================
Using % instead of .* for wildcards  Remember: LIKE uses %, REGEXP uses .*
Not escaping special characters      Always escape: \. \$ \( \) etc.
Assuming REGEXP is faster            LIKE is often faster for simple patterns
Applying to large unindexed columns  Create computed indexed columns
Not testing with NULL values         Always handle NULL with ISNULL()
Using overcomplicated patterns       Start simple, add complexity as needed
';

-- ============================================================================
-- SUMMARY & BEST PRACTICES
-- ============================================================================

PRINT NCHAR(10) + '
================================================================================
                          SUMMARY & BEST PRACTICES
================================================================================

DO:
  - Use REGEXP_LIKE for simple boolean matching (most performant)
  - Create persisted computed columns for frequently used patterns
  - Test patterns with realistic data before deployment
  - Use parameterized patterns, not dynamic pattern construction
  - Leverage indexes on computed columns
  - Handle NULLs explicitly
  - Use anchors (^ $) when appropriate to avoid backtracking
  - Monitor query performance with STATISTICS IO/TIME

DON''T:
  - Use nested quantifiers: (a+)+, (.*)*
  - Ignore NULL inputs
  - Assume REGEXP is always faster than LIKE
  - Create patterns without testing performance
  - Use dynamic pattern construction (security risk)
  - Apply expensive REGEXP_REPLACE without filtering first
  - Forget to escape special characters
  - Use overlapping alternation: (a|a|ab)

PERFORMANCE TIPS:
  1. REGEXP_LIKE(col, pattern) > REGEXP_SUBSTR() > REGEXP_REPLACE()
  2. Indexed computed columns dramatically improve filtered queries
  3. Use 'i' flag only when necessary (case-insensitive is slower)
  4. Pre-filter with simple WHERE clause before expensive REGEXP operations
  5. Consider Full-Text Search for large text columns
  6. Test with realistic data volumes and patterns
  7. Monitor execution plans for key lookup optimization

ALGORITHM SELECTION:
  - Simple patterns (literal, character classes): LIKE or REGEXP_LIKE
  - Complex patterns (quantifiers, groups): REGEXP functions
  - Very large text: Full-Text Search
  - Performance critical: Computed indexed columns

================================================================================
';

-- Cleanup
DROP TABLE IF EXISTS dbo.OptimizedEmailData;
