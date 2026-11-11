// SQL Server 2025 Change Event Streaming - monitor & simulator web app.
//
//   SQL Server (CES) ──Kafka──▶ Event Hubs ──▶ [consumer] ──▶ EventStore ──SSE──▶ browser
//                                   ▲
//   browser ──POST──▶ [simulator] ──┴── DML over TDS into SQL Server
//
// Telemetry must be configured before other modules load, so the app is started via dynamic import.
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  const { useAzureMonitor } = await import('@azure/monitor-opentelemetry');
  useAzureMonitor();
}

const { default: express } = await import('express');
const path = await import('node:path');
const { fileURLToPath } = await import('node:url');
const { config } = await import('./src/config.js');
const { EventStore } = await import('./src/store.js');
const { Simulator, SCENARIOS } = await import('./src/simulator.js');
const { readSqlHealth } = await import('./src/sqlHealth.js');
const { randomTransaction, SyntheticPublisher } = await import('./src/synthetic.js');
const { decodeChange } = await import('./src/cloudevent.js');

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const store = new EventStore({ capacity: 1000, windowSeconds: 300 });
const simulator = new Simulator({ config });
let consumer = null;
let publisher = null;
let mockTimer = null;
let mockRate = 3;

// ------------------------------------------------------------------ data sources
async function startLive() {
  const { DefaultAzureCredential } = await import('@azure/identity');
  const { CesConsumer } = await import('./src/consumer.js');
  const credential = new DefaultAzureCredential();
  consumer = new CesConsumer({ config, credential, store });
  publisher = new SyntheticPublisher({ fqdn: config.eventHubFqdn, eventHubName: config.eventHubName, credential });
  try { await consumer.start(); }
  catch (e) { store.recordConsumerError(`Consumer failed to start: ${e.message}`); console.error(e); }
}

function startMock() {
  // Feeds CES-shaped CloudEvents straight into the store: lets you see the UI without Azure.
  const tick = () => {
    // pretend the transaction committed a little earlier, so the latency KPIs have something to show
    const commit = Date.now() - 150 - Math.floor(Math.random() * 450);
    const enq = commit + 60 + Math.floor(Math.random() * 250);
    const partitionId = String(Math.floor(Math.random() * 4));
    for (const env of randomTransaction()) {
      const change = decodeChange(env);
      change.time = new Date(commit).toISOString();
      store.addChange(change, { partitionId, offset: String(store.total * 512), sequenceNumber: store.total, enqueuedTime: enq, synthetic: true });
    }
    mockTimer = setTimeout(tick, Math.max(30, 1000 / mockRate * (0.5 + Math.random())));
  };
  tick();
}

// ------------------------------------------------------------------ http
const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '64kb' }));
app.use(express.static(path.join(__dirname, 'public'), { maxAge: '5m' }));

const requireAdmin = (req, res, next) => {
  if (!config.adminToken || req.get('x-admin-token') === config.adminToken) return next();
  res.status(401).json({ error: 'Missing or wrong x-admin-token (see ADMIN_TOKEN app setting).' });
};
const wrap = fn => (req, res) => Promise.resolve(fn(req, res)).catch(e => res.status(500).json({ error: e.message }));

app.get('/healthz', (_req, res) => res.json({ ok: true }));

app.get('/api/config', (_req, res) => res.json({
  mode: config.mode,
  eventHub: config.mode === 'live' ? `${config.eventHubFqdn}/${config.eventHubName}` : null,
  consumerGroup: config.consumerGroup,
  startPosition: config.startPosition,
  checkpointing: !!config.checkpointBlobEndpoint,
  sqlTarget: simulator.configured ? `${config.sql.server}/${config.sql.database}` : null,
  streamGroup: config.streamGroup,
  adminTokenRequired: !!config.adminToken,
  scenarios: SCENARIOS,
}));

app.get('/api/stream', (req, res) => store.attach(res));
app.get('/api/stats', (_req, res) => res.json(store.stats()));
app.get('/api/events', (req, res) => res.json(store.recent({
  limit: Math.min(1000, Number(req.query.limit) || 200), table: req.query.table, op: req.query.op,
})));
app.get('/api/consumer', (_req, res) => res.json({
  mode: config.mode, ...(consumer?.info() ?? { state: config.mode === 'mock' ? 'mock' : 'stopped' }),
  errors: store.consumerErrors.slice(0, 20),
}));

app.get('/api/simulator', (_req, res) => res.json(config.mode === 'mock'
  ? { ...simulator.status(), configured: true, mock: true, running: !!mockTimer, rate: mockRate }
  : simulator.status()));

app.post('/api/simulator/start', requireAdmin, wrap(async (req, res) => {
  if (config.mode === 'mock') { mockRate = Number(req.body?.rate) || mockRate; if (!mockTimer) startMock(); return res.json({ running: true, rate: mockRate }); }
  simulator.start(req.body?.rate);
  res.json(simulator.status());
}));
app.post('/api/simulator/stop', requireAdmin, (_req, res) => {
  if (config.mode === 'mock') { clearTimeout(mockTimer); mockTimer = null; return res.json({ running: false }); }
  simulator.stop(); res.json(simulator.status());
});
app.post('/api/simulator/rate', requireAdmin, (req, res) => {
  if (config.mode === 'mock') { mockRate = Number(req.body?.rate) || mockRate; return res.json({ rate: mockRate }); }
  simulator.setRate(req.body?.rate); res.json(simulator.status());
});
app.post('/api/simulator/burst', requireAdmin, wrap(async (req, res) => {
  if (config.mode === 'mock') { for (let i = 0; i < (Number(req.body?.count) || 50); i++) for (const e of randomTransaction()) store.addChange(decodeChange(e), { synthetic: true }); return res.json({ ok: true }); }
  const ok = await simulator.burst(req.body?.count);
  res.json({ ok, ...simulator.status() });
}));
app.post('/api/simulator/scenario/:name', requireAdmin, wrap(async (req, res) => {
  if (config.mode === 'mock') { for (const e of randomTransaction()) store.addChange(decodeChange(e), { synthetic: true }); return res.json({ ok: true }); }
  const rows = await simulator.runScenario(req.params.name);
  res.json({ rows, ...simulator.status() });
}));

app.post('/api/synthetic', requireAdmin, wrap(async (req, res) => {
  if (!publisher) return res.status(400).json({ error: 'Synthetic publishing needs live mode (EVENTHUB_FQDN).' });
  const sent = await publisher.send(Math.min(500, Number(req.body?.count) || 10));
  res.json({ sent, totalSent: publisher.sent });
}));

let healthCache = null;
app.get('/api/health/sql', wrap(async (_req, res) => {
  if (config.mode === 'mock' || !simulator.configured) return res.json({ configured: false, mode: config.mode });
  if (!healthCache || Date.now() - healthCache.t > 5000) {
    try {
      healthCache = { t: Date.now(), data: { configured: true, ...(await readSqlHealth(() => simulator.getPool())) } };
    } catch (e) {
      healthCache = { t: Date.now(), data: { configured: true, error: `Cannot reach SQL Server: ${e.message}` } };
    }
  }
  res.json(healthCache.data);
}));

app.post('/api/reset-stats', requireAdmin, (_req, res) => { store.reset(); res.json({ ok: true }); });

// ------------------------------------------------------------------ boot
const server = app.listen(config.port, () => {
  console.log(`CES monitor listening on :${config.port} (mode=${config.mode})`);
});

if (config.mode === 'live') await startLive();
else startMock();
if (config.simulatorAutostart && config.mode === 'live' && simulator.configured) simulator.start();

const shutdown = async () => {
  console.log('shutting down');
  server.close();
  clearTimeout(mockTimer);
  await Promise.allSettled([consumer?.stop(), publisher?.close(), simulator.close()]);
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
