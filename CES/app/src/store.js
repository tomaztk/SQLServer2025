// In-memory event store + live statistics + Server-Sent Events fan-out.
const OPS = ['INS', 'UPD', 'DEL'];

function percentile(sorted, p) {
  if (!sorted.length) return null;
  const i = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[i];
}

export class EventStore {
  constructor({ capacity = 1000, windowSeconds = 300 } = {}) {
    this.capacity = capacity;
    this.windowSeconds = windowSeconds;
    this.events = [];          // newest last
    this.clients = new Set();  // SSE responses
    this.pendingBroadcast = [];
    this.reset();
    this.flushTimer = setInterval(() => this.flush(), 250);
    this.statsTimer = setInterval(() => this.broadcast('stats', this.stats()), 1000);
    this.flushTimer.unref?.(); this.statsTimer.unref?.();
  }

  reset() {
    this.events = [];
    this.total = 0;
    this.byOp = { INS: 0, UPD: 0, DEL: 0 };
    this.byTable = {};
    this.partitions = {};
    this.buckets = new Map();     // epochSecond -> {INS, UPD, DEL}
    this.latencies = [];          // commit -> received (ms)
    this.publishLatencies = [];   // commit -> enqueued in Event Hubs (ms)
    this.seenIds = new Map();     // id -> true (bounded) for duplicate detection
    this.duplicates = 0;
    this.transactions = new Set();
    this.parseErrors = 0;
    this.nonCes = 0;
    this.synthetic = 0;
    this.lastEventAt = null;
    this.consumerErrors = [];
    this.startedAt = new Date().toISOString();
  }

  addChange(change, meta = {}) {
    const receivedAt = Date.now();
    const rec = {
      ...change,
      partitionId: meta.partitionId ?? null,
      offset: meta.offset ?? null,
      sequenceNumber: meta.sequenceNumber ?? null,
      enqueuedTime: meta.enqueuedTime ? new Date(meta.enqueuedTime).toISOString() : null,
      receivedAt: new Date(receivedAt).toISOString(),
      synthetic: change.source === '/synthetic' || meta.synthetic === true,
    };

    const commitMs = Date.parse(change.time);
    if (!Number.isNaN(commitMs)) {
      rec.latencyMs = receivedAt - commitMs;
      this.pushBounded(this.latencies, rec.latencyMs, 2000);
      if (meta.enqueuedTime) {
        rec.publishLatencyMs = new Date(meta.enqueuedTime).getTime() - commitMs;
        this.pushBounded(this.publishLatencies, rec.publishLatencyMs, 2000);
      }
    }

    // CES is at-least-once: the same source+id can be redelivered.
    const dupKey = `${change.source}|${change.id}`;
    if (this.seenIds.has(dupKey)) { this.duplicates++; rec.duplicate = true; }
    else {
      this.seenIds.set(dupKey, true);
      if (this.seenIds.size > 20000) this.seenIds.delete(this.seenIds.keys().next().value);
    }

    this.total++;
    if (rec.synthetic) this.synthetic++;
    if (OPS.includes(change.operation)) this.byOp[change.operation]++;
    const t = (this.byTable[change.fullTable] ??= { INS: 0, UPD: 0, DEL: 0, total: 0 });
    if (OPS.includes(change.operation)) t[change.operation]++;
    t.total++;

    if (rec.partitionId != null) {
      const p = (this.partitions[rec.partitionId] ??= { count: 0 });
      p.count++; p.lastOffset = rec.offset; p.lastSequenceNumber = rec.sequenceNumber; p.lastEnqueuedTime = rec.enqueuedTime;
    }

    if (change.transaction?.commitLsn) {
      this.transactions.add(change.transaction.commitLsn);
      if (this.transactions.size > 50000) this.transactions.delete(this.transactions.values().next().value);
    }

    const sec = Math.floor(receivedAt / 1000);
    const b = this.buckets.get(sec) ?? { INS: 0, UPD: 0, DEL: 0 };
    if (OPS.includes(change.operation)) b[change.operation]++;
    this.buckets.set(sec, b);
    this.trimBuckets(sec);

    this.events.push(rec);
    if (this.events.length > this.capacity) this.events.shift();
    this.lastEventAt = rec.receivedAt;
    this.pendingBroadcast.push(rec);
    return rec;
  }

  recordParseError(err, sample) {
    this.parseErrors++;
    this.recordConsumerError(`Parse error: ${err.message}`, sample);
  }

  recordConsumerError(message, detail) {
    this.consumerErrors.unshift({ at: new Date().toISOString(), message, detail: detail ? String(detail).slice(0, 2000) : undefined });
    this.consumerErrors.length = Math.min(this.consumerErrors.length, 50);
    this.broadcast('consumer-error', this.consumerErrors[0]);
  }

  pushBounded(arr, v, max) { arr.push(v); if (arr.length > max) arr.shift(); }

  trimBuckets(nowSec) {
    for (const k of this.buckets.keys()) {
      if (k < nowSec - this.windowSeconds) this.buckets.delete(k); else break;
    }
  }

  series() {
    const now = Math.floor(Date.now() / 1000);
    this.trimBuckets(now);
    const out = [];
    for (let s = now - this.windowSeconds + 1; s <= now; s++) {
      const b = this.buckets.get(s);
      out.push({ t: s * 1000, INS: b?.INS ?? 0, UPD: b?.UPD ?? 0, DEL: b?.DEL ?? 0 });
    }
    return out;
  }

  stats() {
    const lat = [...this.latencies].sort((a, b) => a - b);
    const pub = [...this.publishLatencies].sort((a, b) => a - b);
    const series = this.series();
    const last10 = series.slice(-10).reduce((n, p) => n + p.INS + p.UPD + p.DEL, 0) / 10;
    return {
      total: this.total,
      byOp: this.byOp,
      byTable: this.byTable,
      partitions: this.partitions,
      transactions: this.transactions.size,
      duplicates: this.duplicates,
      parseErrors: this.parseErrors,
      synthetic: this.synthetic,
      ratePerSec: Math.round(last10 * 10) / 10,
      latency: { p50: percentile(lat, 50), p95: percentile(lat, 95), max: lat.at(-1) ?? null, samples: lat.length },
      publishLatency: { p50: percentile(pub, 50), p95: percentile(pub, 95) },
      lastEventAt: this.lastEventAt,
      startedAt: this.startedAt,
      series,
      clients: this.clients.size,
    };
  }

  recent({ limit = 200, table, op } = {}) {
    let list = this.events;
    if (table) list = list.filter(e => e.fullTable === table);
    if (op) list = list.filter(e => e.operation === op);
    return list.slice(-limit).reverse();
  }

  // ---------------- SSE
  attach(res) {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    res.write('retry: 3000\n\n');
    this.clients.add(res);
    this.send(res, 'hello', { stats: this.stats(), recent: this.recent({ limit: 100 }) });
    const ping = setInterval(() => res.write(': ping\n\n'), 15000);
    res.on('close', () => { clearInterval(ping); this.clients.delete(res); });
  }

  send(res, event, data) { res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`); }

  broadcast(event, data) { for (const c of this.clients) this.send(c, event, data); }

  flush() {
    if (!this.pendingBroadcast.length) return;
    const batch = this.pendingBroadcast.splice(0, this.pendingBroadcast.length).slice(-200);
    this.broadcast('changes', batch);
  }
}
