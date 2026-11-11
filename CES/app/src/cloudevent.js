// Parsing of SQL Server Change Event Streaming (CES) CloudEvents.
// Format reference: https://learn.microsoft.com/sql/relational-databases/track-changes/change-event-streaming/message-format
//
// CES publishes over Kafka. When read with the Event Hubs (AMQP) SDK the body arrives as raw
// bytes, so everything here accepts Buffer | Uint8Array | string | object. Both CloudEvents
// content modes are handled: "structured" (whole CloudEvent JSON in the body - what CES sends
// today) and "binary" (attributes as ce_* headers, data in the body) to be future-proof.

const CES_TYPE_PREFIX = 'com.microsoft.SQL.CES.';

function bytesToString(v) {
  if (v == null) return v;
  if (typeof v === 'string') return v;
  if (Buffer.isBuffer(v)) return v.toString('utf8');
  if (v instanceof Uint8Array) return Buffer.from(v).toString('utf8');
  return v;
}

function tryJson(v) {
  if (typeof v !== 'string') return v;
  const s = v.trim();
  if (!(s.startsWith('{') || s.startsWith('['))) return v;
  try { return JSON.parse(s); } catch { return v; }
}

/** Kafka headers / AMQP application properties -> plain object with ce_ / ce- prefix stripped. */
export function normalizeHeaders(properties = {}) {
  const out = {};
  for (const [k, raw] of Object.entries(properties || {})) {
    const v = bytesToString(raw);
    const key = k.toLowerCase();
    if (key.startsWith('ce_') || key.startsWith('ce-')) out[key.slice(3)] = v;
    else if (key === 'content-type' || key === 'content_type') out.datacontenttype = v;
    else out[`$${k}`] = v; // keep other headers, marked
  }
  return out;
}

/**
 * Turns a raw Event Hubs message into a CloudEvent envelope (not yet decoded).
 * Returns null when the message is not a CES event.
 */
export function toEnvelope(body, properties = {}) {
  const parsed = tryJson(bytesToString(body));
  if (parsed && typeof parsed === 'object' && parsed.specversion) {
    return parsed; // structured mode
  }
  const h = normalizeHeaders(properties);
  if (h.specversion || h.type) {
    // binary mode: body is the data attribute
    const env = { ...h };
    env.data = parsed;
    if (typeof env.segmentindex === 'string') env.segmentindex = Number(env.segmentindex);
    if (typeof env.finalsegment === 'string') env.finalsegment = env.finalsegment === 'true';
    return env;
  }
  return null;
}

export function isCesEnvelope(env) {
  return !!env && typeof env.type === 'string' && env.type.startsWith(CES_TYPE_PREFIX);
}

function parseRowImage(v) {
  const o = tryJson(bytesToString(v));
  if (o && typeof o === 'object') return o;
  return {};
}

function decodeData(data) {
  // JSON encoding: "data" is a string holding JSON. Some readers hand it over already parsed,
  // and a byte array may show up as {type:'Buffer', data:[...]} or base64.
  let d = data;
  if (d && typeof d === 'object' && d.type === 'Buffer' && Array.isArray(d.data)) d = Buffer.from(d.data);
  d = bytesToString(d);
  if (typeof d === 'string') {
    const asJson = tryJson(d);
    if (typeof asJson === 'object') d = asJson;
    else {
      try { // base64 of JSON?
        const decoded = Buffer.from(d, 'base64').toString('utf8');
        const j = tryJson(decoded);
        if (typeof j === 'object') d = j;
      } catch { /* ignore */ }
    }
  }
  if (!d || typeof d !== 'object') {
    throw new Error('CES data attribute is not JSON. Is the stream group using @encoding = N\'JSON\'? (Binary/Avro is not decoded by this demo.)');
  }
  return d;
}

function diffColumns(oldRow, curRow) {
  const keys = new Set([...Object.keys(oldRow), ...Object.keys(curRow)]);
  const changed = [];
  for (const k of keys) {
    if (!(k in oldRow) || !(k in curRow)) continue;
    if (String(oldRow[k]) !== String(curRow[k])) changed.push(k);
  }
  return changed;
}

/** Envelope (complete, i.e. all segments joined) -> normalized change record for the UI. */
export function decodeChange(env) {
  const data = decodeData(env.data);
  const src = data.eventsource || {};
  const tx = src.transaction || {};
  const row = data.eventrow || {};
  const oldRow = parseRowImage(row.old);
  const current = parseRowImage(row.current);
  const pk = {};
  for (const p of src.pkkey || []) pk[p.columnname] = p.value;
  const op = String(env.operation || '').toUpperCase();
  return {
    id: env.id,
    logicalId: env.logicalid,
    type: env.type,
    source: env.source,
    time: env.time,
    operation: op,
    db: src.db,
    schema: src.schema,
    table: src.tbl,
    fullTable: src.schema && src.tbl ? `${src.schema}.${src.tbl}` : (src.tbl || '?'),
    columns: (src.cols || []).map(c => ({ name: c.name, type: c.type, index: c.index })),
    pk,
    pkText: Object.entries(pk).map(([k, v]) => `${k}=${v}`).join(', '),
    transaction: {
      commitLsn: tx.commitlsn,
      beginLsn: tx.beginlsn,
      sequenceNumber: tx.sequencenumber,
      commitTime: tx.committime,
    },
    old: oldRow,
    current,
    changedColumns: op === 'UPD' ? diffColumns(oldRow, current) : [],
    segments: env.__segments || 1,
  };
}

/**
 * Reassembles events that CES split into several messages (max_message_size_kb).
 * Segments share "logicalid"; "segmentindex" orders them; "finalsegment" marks the last one.
 */
export class SegmentAssembler {
  constructor({ ttlMs = 5 * 60_000 } = {}) {
    this.ttlMs = ttlMs;
    this.pending = new Map(); // logicalid -> { parts: Map<index, data>, last: index|null, first: env, at }
    this.expired = 0;
  }

  /** Returns a complete envelope, or null while segments are still missing. */
  push(env) {
    const idx = Number(env.segmentindex ?? 0);
    const final = env.finalsegment === undefined ? true : !!env.finalsegment;
    if (idx === 0 && final) return env; // the common case: not split

    const key = env.logicalid || env.id;
    let p = this.pending.get(key);
    if (!p) { p = { parts: new Map(), last: null, first: env, at: Date.now() }; this.pending.set(key, p); }
    p.parts.set(idx, env.data);
    if (idx === 0) p.first = env;
    if (final) p.last = idx;
    this.gc();
    if (p.last === null) return null;
    for (let i = 0; i <= p.last; i++) if (!p.parts.has(i)) return null;

    const chunks = [];
    for (let i = 0; i <= p.last; i++) {
      const c = p.parts.get(i);
      chunks.push(typeof c === 'string' ? c : bytesToString(c) ?? JSON.stringify(c));
    }
    this.pending.delete(key);
    return { ...p.first, data: chunks.join(''), segmentindex: 0, finalsegment: true, __segments: p.last + 1 };
  }

  gc() {
    const now = Date.now();
    for (const [k, p] of this.pending) {
      if (now - p.at > this.ttlMs) { this.pending.delete(k); this.expired++; }
    }
  }

  get pendingCount() { return this.pending.size; }
}
