// Builds CES-shaped CloudEvents without SQL Server. Used for
//   * MOCK mode (no Azure at all - the UI is fed in-process), and
//   * "Inject synthetic events" - publishes to the real Event Hub to test the consumer path
//     independently of SQL Server. Synthetic events carry source "/synthetic" so they are
//     clearly distinguishable from what SQL Server sends (source "/").
import { randomUUID } from 'node:crypto';

const TABLES = {
  Customers: [
    ['CustomerId', 'int'], ['FirstName', 'nvarchar(50)'], ['LastName', 'nvarchar(50)'], ['Email', 'nvarchar(200)'],
    ['City', 'nvarchar(100)'], ['Country', 'nvarchar(60)'], ['Tier', 'varchar(10)'], ['CreatedAt', 'datetime2(3)'], ['ModifiedAt', 'datetime2(3)'],
  ],
  Orders: [
    ['OrderId', 'bigint'], ['CustomerId', 'int'], ['OrderDate', 'datetime2(3)'], ['Status', 'varchar(20)'],
    ['TotalAmount', 'decimal(12,2)'], ['ModifiedAt', 'datetime2(3)'],
  ],
  Products: [
    ['ProductId', 'int'], ['Sku', 'varchar(20)'], ['Name', 'nvarchar(100)'], ['Category', 'nvarchar(50)'],
    ['UnitPrice', 'decimal(10,2)'], ['StockQty', 'int'], ['ModifiedAt', 'datetime2(3)'],
  ],
  OrderLines: [
    ['OrderLineId', 'bigint'], ['OrderId', 'bigint'], ['ProductId', 'int'], ['Quantity', 'int'], ['UnitPrice', 'decimal(10,2)'],
  ],
};

let lsnCounter = 0xB1000;
const nextLsn = () => {
  lsnCounter += 1 + Math.floor(Math.random() * 8);
  const a = (lsnCounter >>> 12).toString(16).toUpperCase().padStart(8, '0');
  const b = (lsnCounter & 0xfff).toString(16).toUpperCase().padStart(8, '0');
  return `${a}:${b}:${String(Math.floor(Math.random() * 9) + 1).padStart(4, '0')}`;
};
const sqlTime = d => d.toISOString().replace('T', ' ').replace('Z', '');
const pick = a => a[Math.floor(Math.random() * a.length)];
let ids = { Customers: 100, Orders: 1000, Products: 10, OrderLines: 5000 };

function rowFor(table, id) {
  const now = sqlTime(new Date());
  switch (table) {
    case 'Customers': return {
      CustomerId: String(id), FirstName: pick(['Eva', 'Marko', 'Lena', 'Tim', 'Nina']), LastName: pick(['Kovac', 'Bauer', 'Zupan', 'Weber']),
      Email: `user${id}@example.com`, City: pick(['Vienna', 'Ljubljana', 'Graz', 'Zagreb']), Country: pick(['Austria', 'Slovenia', 'Croatia']),
      Tier: pick(['Bronze', 'Silver', 'Gold']), CreatedAt: now, ModifiedAt: null,
    };
    case 'Orders': return {
      OrderId: String(id), CustomerId: String(100 + Math.ceil(Math.random() * 20)), OrderDate: now, Status: 'Pending',
      TotalAmount: (Math.random() * 300).toFixed(2), ModifiedAt: null,
    };
    case 'Products': return {
      ProductId: String(id), Sku: `SKU-${1000 + Number(id)}`, Name: 'Espresso beans 1kg', Category: 'Coffee',
      UnitPrice: (10 + Math.random() * 40).toFixed(2), StockQty: String(Math.floor(Math.random() * 500)), ModifiedAt: now,
    };
    default: return {
      OrderLineId: String(id), OrderId: String(ids.Orders), ProductId: String(1 + Math.floor(Math.random() * 10)),
      Quantity: String(1 + Math.floor(Math.random() * 4)), UnitPrice: (5 + Math.random() * 50).toFixed(2),
    };
  }
}

/** One CES CloudEvent, byte-for-byte shaped like the JSON format in the docs. */
export function buildCesEvent({ db = 'CesDemo', table = 'Orders', operation = 'INS', oldRow = {}, current = {}, pkCol, commitLsn, beginLsn, seq = 1, source = '/synthetic' } = {}) {
  const cols = TABLES[table] || TABLES.Orders;
  const pk = pkCol || cols[0][0];
  const commitTime = new Date().toISOString();
  const cLsn = commitLsn || nextLsn();
  const data = {
    eventsource: {
      db, schema: 'dbo', tbl: table,
      cols: cols.map(([name, type], index) => ({ name, type, index })),
      pkkey: [{ columnname: pk, value: String((operation === 'DEL' ? oldRow : current)[pk] ?? '') }],
      transaction: { commitlsn: cLsn, beginlsn: beginLsn || cLsn, sequencenumber: seq, finalevent: false, committime: commitTime },
    },
    eventrow: { old: JSON.stringify(oldRow), current: JSON.stringify(current) },
  };
  return {
    specversion: '1.0',
    type: 'com.microsoft.SQL.CES.DML.V1',
    source,
    id: randomUUID(),
    logicalid: `${randomUUID()}:${cLsn.replace(/:/g, '')}:${String(seq).padStart(20, '0')}`,
    time: commitTime,
    datacontenttype: 'application/json',
    operation,
    segmentindex: 0,
    finalsegment: true,
    data: JSON.stringify(data),
  };
}

/** A small "transaction": returns 1..n CloudEvents sharing one commit LSN. */
export function randomTransaction() {
  const roll = Math.random();
  const lsn = nextLsn();
  if (roll < 0.25) {
    const id = ++ids.Customers;
    return [buildCesEvent({ table: 'Customers', operation: 'INS', current: rowFor('Customers', id), commitLsn: lsn })];
  }
  if (roll < 0.55) {
    const orderId = ++ids.Orders;
    const order = rowFor('Orders', orderId);
    const events = [buildCesEvent({ table: 'Orders', operation: 'INS', current: order, commitLsn: lsn, seq: 1 })];
    const lines = 1 + Math.floor(Math.random() * 3);
    for (let i = 0; i < lines; i++) {
      events.push(buildCesEvent({ table: 'OrderLines', operation: 'INS', current: rowFor('OrderLines', ++ids.OrderLines), commitLsn: lsn, seq: i + 2 }));
    }
    const updated = { ...order, TotalAmount: (Math.random() * 300).toFixed(2), ModifiedAt: sqlTime(new Date()) };
    events.push(buildCesEvent({ table: 'Orders', operation: 'UPD', oldRow: order, current: updated, commitLsn: lsn, seq: lines + 2 }));
    return events;
  }
  if (roll < 0.85) {
    const old = { ...rowFor('Orders', ids.Orders - Math.floor(Math.random() * 5)), Status: pick(['Pending', 'Paid', 'Shipped']) };
    const next = { Pending: 'Paid', Paid: 'Shipped', Shipped: 'Delivered' }[old.Status];
    return [buildCesEvent({ table: 'Orders', operation: 'UPD', oldRow: old, current: { ...old, Status: next, ModifiedAt: sqlTime(new Date()) }, commitLsn: lsn })];
  }
  if (roll < 0.93) {
    const old = rowFor('Products', 1 + Math.floor(Math.random() * 10));
    return [buildCesEvent({ table: 'Products', operation: 'UPD', oldRow: old, current: { ...old, UnitPrice: (Number(old.UnitPrice) * 1.05).toFixed(2) }, commitLsn: lsn })];
  }
  const old = { ...rowFor('Orders', ids.Orders - 3), Status: 'Cancelled' };
  return [
    buildCesEvent({ table: 'OrderLines', operation: 'DEL', oldRow: rowFor('OrderLines', ids.OrderLines - 1), commitLsn: lsn, seq: 1 }),
    buildCesEvent({ table: 'Orders', operation: 'DEL', oldRow: old, commitLsn: lsn, seq: 2 }),
  ];
}

/** Publishes synthetic CES events to the real Event Hub (needs Azure Event Hubs Data Sender). */
export class SyntheticPublisher {
  constructor({ fqdn, eventHubName, credential, logger = console }) {
    this.fqdn = fqdn; this.eventHubName = eventHubName; this.credential = credential; this.logger = logger;
    this.producer = null; this.sent = 0;
  }

  async send(count = 10) {
    if (!this.producer) {
      const { EventHubProducerClient } = await import('@azure/event-hubs');
      this.producer = new EventHubProducerClient(this.fqdn, this.eventHubName, this.credential);
    }
    let batch = await this.producer.createBatch();
    let n = 0;
    while (n < count) {
      for (const ev of randomTransaction()) {
        // Send the JSON as raw bytes, the way a Kafka producer (CES) does.
        const msg = { body: Buffer.from(JSON.stringify(ev), 'utf8'), properties: { synthetic: 'true' } };
        if (!batch.tryAdd(msg)) {
          await this.producer.sendBatch(batch);
          batch = await this.producer.createBatch();
          batch.tryAdd(msg);
        }
        n++;
      }
    }
    if (batch.count > 0) await this.producer.sendBatch(batch);
    this.sent += n;
    return n;
  }

  async close() { await this.producer?.close(); }
}
