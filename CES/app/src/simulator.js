// Change simulator: generates real INSERT / UPDATE / DELETE traffic against SQL Server, which
// CES then streams to Event Hubs. Each scenario runs in its own transaction so you can watch
// multi-row transactions arrive with one commit LSN and increasing sequence numbers.
import sql from 'mssql';

const FIRST = ['Eva', 'Marko', 'Lena', 'Tim', 'Nina', 'Jan', 'Sofia', 'Felix', 'Maja', 'David'];
const LAST = ['Kovac', 'Bauer', 'Zupan', 'Weber', 'Krajnc', 'Novak', 'Huber', 'Horvat'];
const CITIES = [['Maribor', 'Slovenia'], ['Linz', 'Austria'], ['Split', 'Croatia'], ['Vienna', 'Austria'], ['Ljubljana', 'Slovenia']];
const pick = a => a[Math.floor(Math.random() * a.length)];
const rnd = (min, max) => min + Math.floor(Math.random() * (max - min + 1));

export const SCENARIOS = {
  newCustomer: { label: 'New customer', weight: 15, ops: 'INS' },
  newOrder: { label: 'New order (+lines, total)', weight: 35, ops: 'INS×n + UPD' },
  advanceOrder: { label: 'Advance order status', weight: 25, ops: 'UPD' },
  priceChange: { label: 'Product price / stock change', weight: 10, ops: 'UPD' },
  upgradeCustomer: { label: 'Customer tier upgrade', weight: 5, ops: 'UPD' },
  cancelOrder: { label: 'Cancel & delete order', weight: 10, ops: 'UPD + DEL×n' },
  bigTransaction: { label: 'Big transaction (25 lines)', weight: 0, ops: 'INS×26 + UPD' },
};

export class Simulator {
  constructor({ config, logger = console }) {
    this.config = config; this.logger = logger;
    this.pool = null;
    this.running = false;
    this.rate = 2; // scenarios per second
    this.timer = null;
    this.counts = Object.fromEntries(Object.keys(SCENARIOS).map(k => [k, 0]));
    this.rowsChanged = 0;
    this.errors = 0;
    this.lastError = null;
    this.inFlight = 0;
  }

  get configured() { return !!(this.config.sql.server && this.config.sql.user && this.config.sql.password); }

  async getPool() {
    if (this.pool?.connected) return this.pool;
    const c = this.config.sql;
    this.pool = await new sql.ConnectionPool({
      server: c.server,
      port: c.port,
      database: c.database,
      user: c.user,
      password: c.password,
      pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
      options: { encrypt: true, trustServerCertificate: c.trustServerCertificate, appName: 'ces-demo-simulator' },
      connectionTimeout: 15000,
      requestTimeout: 30000,
    }).connect();
    return this.pool;
  }

  status() {
    return {
      configured: this.configured,
      running: this.running,
      rate: this.rate,
      counts: this.counts,
      rowsChanged: this.rowsChanged,
      errors: this.errors,
      lastError: this.lastError,
      scenarios: SCENARIOS,
      target: this.configured ? `${this.config.sql.server}/${this.config.sql.database}` : null,
    };
  }

  start(rate) {
    if (!this.configured) throw new Error('SQL connection is not configured (SQL_SERVER / SQL_USER / SQL_PASSWORD).');
    if (rate) this.setRate(rate);
    if (this.running) return;
    this.running = true;
    this.loop();
    this.logger.info?.(`[simulator] started at ${this.rate}/s`);
  }

  stop() {
    this.running = false;
    clearTimeout(this.timer);
    this.logger.info?.('[simulator] stopped');
  }

  setRate(rate) { this.rate = Math.max(0.2, Math.min(100, Number(rate) || 1)); }

  loop() {
    if (!this.running) return;
    const delay = 1000 / this.rate;
    this.timer = setTimeout(async () => {
      if (this.inFlight < 10) {
        this.inFlight++;
        this.runScenario(this.randomScenario()).catch(() => {}).finally(() => this.inFlight--);
      }
      this.loop();
    }, delay);
  }

  randomScenario() {
    const entries = Object.entries(SCENARIOS).filter(([, s]) => s.weight > 0);
    const total = entries.reduce((n, [, s]) => n + s.weight, 0);
    let r = Math.random() * total;
    for (const [k, s] of entries) { if ((r -= s.weight) <= 0) return k; }
    return entries[0][0];
  }

  async burst(count = 50) {
    const n = Math.max(1, Math.min(1000, Number(count) || 50));
    let ok = 0;
    for (let i = 0; i < n; i += 5) {
      const batch = [];
      for (let j = i; j < Math.min(n, i + 5); j++) batch.push(this.runScenario(this.randomScenario()).then(() => ok++).catch(() => {}));
      await Promise.all(batch);
    }
    return ok;
  }

  async runScenario(name) {
    if (!SCENARIOS[name]) throw new Error(`Unknown scenario ${name}`);
    const pool = await this.getPool();
    const tx = new sql.Transaction(pool);
    await tx.begin();
    try {
      const rows = await this[name](tx);
      await tx.commit();
      this.counts[name]++;
      this.rowsChanged += rows;
      return rows;
    } catch (e) {
      try { await tx.rollback(); } catch { /* already rolled back */ }
      this.errors++;
      this.lastError = { at: new Date().toISOString(), scenario: name, message: e.message };
      this.logger.warn?.(`[simulator] ${name} failed: ${e.message}`);
      throw e;
    }
  }

  // ---------------------------------------------------------- scenarios (return #rows changed)
  async newCustomer(tx) {
    const [city, country] = pick(CITIES);
    const f = pick(FIRST), l = pick(LAST);
    const r = await new sql.Request(tx)
      .input('f', sql.NVarChar(50), f).input('l', sql.NVarChar(50), l)
      .input('e', sql.NVarChar(200), `${f}.${l}.${rnd(1, 99999)}@example.com`.toLowerCase())
      .input('c', sql.NVarChar(100), city).input('co', sql.NVarChar(60), country)
      .query('INSERT dbo.Customers (FirstName, LastName, Email, City, Country) VALUES (@f, @l, @e, @c, @co);');
    return r.rowsAffected[0];
  }

  async createOrder(tx, lineCount) {
    const r1 = await new sql.Request(tx).query(`
      DECLARE @c int = (SELECT TOP (1) CustomerId FROM dbo.Customers ORDER BY NEWID());
      INSERT dbo.Orders (CustomerId) VALUES (@c);
      SELECT CAST(SCOPE_IDENTITY() AS bigint) AS OrderId;`);
    const orderId = r1.recordset[0].OrderId;
    const r2 = await new sql.Request(tx)
      .input('o', sql.BigInt, orderId).input('n', sql.Int, lineCount)
      .query(`
        INSERT dbo.OrderLines (OrderId, ProductId, Quantity, UnitPrice)
        SELECT TOP (@n) @o, p.ProductId, 1 + ABS(CHECKSUM(NEWID())) % 4, p.UnitPrice
        FROM dbo.Products p CROSS JOIN (VALUES (1),(2),(3)) x(n) ORDER BY NEWID();
        UPDATE dbo.Orders
           SET TotalAmount = (SELECT SUM(Quantity * UnitPrice) FROM dbo.OrderLines WHERE OrderId = @o),
               ModifiedAt = SYSUTCDATETIME()
         WHERE OrderId = @o;`);
    return 1 + r2.rowsAffected.reduce((a, b) => a + b, 0);
  }

  newOrder(tx) { return this.createOrder(tx, rnd(1, 3)); }

  bigTransaction(tx) { return this.createOrder(tx, 25); }

  async advanceOrder(tx) {
    const r = await new sql.Request(tx).query(`
      ;WITH o AS (SELECT TOP (1) * FROM dbo.Orders WHERE Status IN ('Pending','Paid','Shipped') ORDER BY NEWID())
      UPDATE o SET Status = CASE Status WHEN 'Pending' THEN 'Paid' WHEN 'Paid' THEN 'Shipped' ELSE 'Delivered' END,
                   ModifiedAt = SYSUTCDATETIME();`);
    return r.rowsAffected[0] || 0;
  }

  async priceChange(tx) {
    const r = await new sql.Request(tx).query(`
      ;WITH p AS (SELECT TOP (1) * FROM dbo.Products ORDER BY NEWID())
      UPDATE p SET UnitPrice  = CAST(UnitPrice * (0.9 + (ABS(CHECKSUM(NEWID())) % 21) / 100.0) AS decimal(10,2)),
                   StockQty   = CASE WHEN StockQty < 30 THEN StockQty + 200 ELSE StockQty - (ABS(CHECKSUM(NEWID())) % 25) END,
                   ModifiedAt = SYSUTCDATETIME();`);
    return r.rowsAffected[0] || 0;
  }

  async upgradeCustomer(tx) {
    const r = await new sql.Request(tx).query(`
      ;WITH c AS (SELECT TOP (1) * FROM dbo.Customers WHERE Tier <> 'Gold' ORDER BY NEWID())
      UPDATE c SET Tier = CASE Tier WHEN 'Bronze' THEN 'Silver' ELSE 'Gold' END, ModifiedAt = SYSUTCDATETIME();`);
    return r.rowsAffected[0] || 0;
  }

  async cancelOrder(tx) {
    const r = await new sql.Request(tx).query(`
      DECLARE @o bigint = (SELECT TOP (1) OrderId FROM dbo.Orders WHERE Status = 'Pending' ORDER BY NEWID());
      IF @o IS NOT NULL
      BEGIN
        UPDATE dbo.Orders SET Status = 'Cancelled', ModifiedAt = SYSUTCDATETIME() WHERE OrderId = @o;
        DELETE dbo.Orders WHERE OrderId = @o;  -- ON DELETE CASCADE also deletes (and streams) the lines
      END`);
    return r.rowsAffected.reduce((a, b) => a + b, 0);
  }

  async close() { this.stop(); await this.pool?.close(); }
}
