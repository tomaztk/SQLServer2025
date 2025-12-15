# SQL Server 2025
Microsoft SQL Server 2025


## Advent of Blog 2025

This is an advent blog series on new functionalities in SQL Server 2025 as fun and educational way of christmas gifts and advent calendar :-)

* Dec 01: [Microsoft SQL Server 2025 – Introduction and installation](https://tomaztsql.wordpress.com/2025/12/01/advent-of-2025-day-1-sql-server-2025-introduction-and-installation/)
* Dec 02: [Microsoft SQL Server 2025 New T-SQL functions -  native JSON data type and some functions](https://tomaztsql.wordpress.com/2025/12/02/advent-of-2025-day-2-sql-server-2025-new-t-sql-functions-native-json-data-type-and-some-functions/)
* Dec 03: [Microsoft SQL Server 2025 – New T-SQL functions – JSON Index](https://tomaztsql.wordpress.com/2025/12/03/advent-of-2025-day-3-sql-server-2025-new-t-sql-functions-json-index/)
* Dec 04: [Microsoft SQL Server 2025 – New T-SQL functions – Product()](https://tomaztsql.wordpress.com/2025/12/04/advent-of-2025-day-3-sql-server-2025-new-t-sql-functions-product/)
* Dec 05: [Microsoft SQL Server 2025 - New T-SQL functions - BASE64_ENCODE() and BASE64_DECODE()](https://tomaztsql.wordpress.com/2025/12/05/advent-of-2025-day-5-sql-server-2025-new-t-sql-functions-base64_encode-and-base64_decode/)
* Dec 06: [Micosoft SQL Server 2025 – New T-SQL functions – REGEXP_LIKE()](https://tomaztsql.wordpress.com/2025/12/06/advent-of-2025-day-5-sql-server-2025-new-t-sql-functions-regexp_like/)
* Dec 07: [Micosoft SQL Server 2025 – New T-SQL functions – REGEXP_SUBSTR() and REGEXP_REPLACE()](https://tomaztsql.wordpress.com/2025/12/07/advent-of-2025-day-7-sql-server-2025-new-t-sql-functions-regexp_substr-and-regexp_replace/)
* Dec 08: [Micosoft SQL Server 2025 – New T-SQL functions – REGEXP_INSTR() and REGEXP_COUNT()](https://tomaztsql.wordpress.com/2025/12/08/advent-of-2025-day-8-sql-server-2025-new-t-sql-functions-regexp_instr-and-regexp_count/)
* Dec 09: [Microsoft SQL Server 2025 – New T-SQL functions – REGEXP_MATCHES() and REGEXP_SPLIT_TO_TABLE()](https://tomaztsql.wordpress.com/2025/12/09/advent-of-2025-day-9-sql-server-2025-new-t-sql-functions-regexp_matches-and-regexp_split_to_table/)
* Dec 10: [Microsoft SQL Server 2025 – External REST endpoint invocation](https://tomaztsql.wordpress.com/2025/12/10/advent-of-2025-day-9-sql-server-2025-external-rest-endpoint-invocation/)
* Dec 11: [Microsoft SQL Server 2025 – External REST endpoint invocation using LLM](https://tomaztsql.wordpress.com/2025/12/11/advent-of-2025-day-11-sql-server-2025-external-rest-endpoint-invocation-using-llm/)
* Dec 12: [Microsoft SQL Server 2025 – New vector data type and Vector functions](https://tomaztsql.wordpress.com/2025/12/12/advent-of-2025-day-12-sql-server-2025-new-vector-data-type-and-vector-functions/)
* Dec 13: [Microsoft SQL Server 2025 – Vector functions](https://tomaztsql.wordpress.com/2025/12/13/advent-of-2025-day-13-sql-server-2025-vector-function/)
* Dec 14: [Microsoft SQL Server 2025 – Vector arrays or embeddings with function AI_GENERATE_EMBEDDINGS](https://tomaztsql.wordpress.com/2025/12/14/advent-of-2025-day-14-sql-server-2025-vector-arrays-or-embeddings-with-function-ai_generate_embeddings/)
* Dec 15: [Microsoft SQL Server 2025 – T-SQL functions for AI External_Models, Chunks and Embeddings](https://tomaztsql.wordpress.com/2025/12/15/advent-of-2025-day-15-sql-server-2025-t-sql-functions-for-ai-external_models-chunks-and-embeddings/)


## Topics

- T-SQL
  * RegEx
  * PRODUCT()
  * Current_date
  * fuzzy string matching
  * unistr()
  * string concat operator ||
  * base64 functions
  * substring() (optinal length)
  * dateadd suppots bigint
- API (sp_invoke_external_rest_api)
- CES (Change event streaming)   (Compare CT, CDC and CES)
- Fabric Mirroring
  
- Core engine
  * Security
     *  Security cache improvements
     *   AEP support for encryption
     * PBKDF password hashing
     *   Authentication using system-assigned managed identity
     *  Backup to URL with managed identity
     *   Managed identity support for EKM
     *   Managed identity for AI models
     *   Entra logins with nonunique display names
     *   Custom password policy on Linux
     *   TDS 8.0/TLS 1.3 support for tools

  * Performance
    * Optimized Locking
    * Tempdb space resource governance
    * ADR in tempdb
    * Persisted stats for readable secondaries
    * Change tracking cleanup
    * Columnstore index maintenance
    * CE feedback for expressions
    * Optional parameter plans optimization
    * DOP feedback on by default
    * Optimized Halloween protection
    * Query store for readable secondaries
    * ABORT_QUERY_EXECUTION query hint
    * Optimized sp_executesql
    * Batch mode optimizations
    * Remove In-Memory OLTP from a database
    * tmpfs support for tempdb in Linux

  * HADR
    * Fast failover for persistent AG Health
    * Async page request dispatching
    * Improved health diagnostics
    * Communication control flow tuning
    * Switching to resolving state
    * Remove listener IP address
    * NONE for routing
    * AG group commit waiting tuning
    * Contained AG support for DAG
    * DAG sync improvements
    * Backups on secondary replicas
    * ZSTD Backup compression
    * Backup to Azure immutable storage


