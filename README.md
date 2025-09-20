# SQL Server 2025
Microsoft SQL Server 2025

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


