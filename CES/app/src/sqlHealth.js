// CES health as seen from inside SQL Server: is streaming enabled, which tables are streamed,
// delivery errors and - most importantly on a self-managed VM - transaction log usage.
// (CES prevents log truncation until changes are delivered; a broken destination fills the log.)

const QUERIES = {
  database: `SELECT name, is_event_stream_enabled, recovery_model_desc, log_reuse_wait_desc,
                    DATABASEPROPERTYEX(name, 'Updateability') AS updateability
             FROM sys.databases WHERE database_id = DB_ID();`,
  version: `SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(40)) AS version,
                   CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(20)) AS updateLevel,
                   CAST(SERVERPROPERTY('Edition') AS nvarchar(100)) AS edition;`,
  tables: `SELECT s.name AS [schema], t.name AS [table], t.is_replicated AS streamed,
                  (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = t.object_id AND p.index_id IN (0,1)) AS [rows]
           FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
           WHERE t.is_ms_shipped = 0 ORDER BY s.name, t.name;`,
  log: `SELECT CAST(total_log_size_in_bytes / 1048576.0 AS decimal(12,2)) AS totalMb,
               CAST(used_log_space_in_bytes / 1048576.0 AS decimal(12,2)) AS usedMb,
               CAST(used_log_space_in_percent AS decimal(5,2)) AS usedPercent
        FROM sys.dm_db_log_space_usage;`,
  errors: 'SELECT TOP (20) * FROM sys.dm_change_feed_errors;',
  logScan: 'SELECT TOP (5) * FROM sys.dm_change_feed_log_scan_sessions;',
};

export async function readSqlHealth(getPool) {
  const pool = await getPool();
  const out = { at: new Date().toISOString(), problems: [] };
  for (const [key, q] of Object.entries(QUERIES)) {
    try {
      const r = await pool.request().query(q);
      out[key] = ['database', 'version', 'log'].includes(key) ? r.recordset[0] ?? null : r.recordset;
    } catch (e) {
      out[key] = null;
      out.problems.push(`${key}: ${e.message}`);
    }
  }
  return out;
}
