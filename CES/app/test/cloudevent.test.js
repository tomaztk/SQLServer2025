import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toEnvelope, isCesEnvelope, decodeChange, SegmentAssembler } from '../src/cloudevent.js';
import { buildCesEvent, randomTransaction } from '../src/synthetic.js';

// Verbatim UPDATE example from the Microsoft Learn "JSON message format" page.
const DOC_UPDATE = String.raw`{
  "specversion": "1.0",
  "type": "com.microsoft.SQL.CES.DML.V1",
  "source": "\/",
  "id": "19221db1-a1b5-4ec7-8937-3fdf9d762abb",
  "logicalid": "1bf2756a-c15f-4d2e-a2d5-7d3f9dbf85b0:000000B1000009300009:00000000000000000001",
  "time": "2026-08-07T16:30:10.123Z",
  "datacontenttype": "application\/json",
  "operation": "UPD",
  "segmentindex": 0,
  "finalsegment": true,
  "data": "{\"eventsource\":{\"db\":\"EmployeesDb\",\"schema\":\"dbo\",\"tbl\":\"Employees\",\"cols\":[{\"name\":\"Id\",\"type\":\"int\",\"index\":0},{\"name\":\"FirstName\",\"type\":\"nvarchar(50)\",\"index\":1},{\"name\":\"LastName\",\"type\":\"nvarchar(50)\",\"index\":2},{\"name\":\"SignupDate\",\"type\":\"datetime2(7)\",\"index\":3}],\"pkkey\":[{\"columnname\":\"Id\",\"value\":\"8\"}],\"transaction\":{\"commitlsn\":\"000000B1:00000930:0009\",\"beginlsn\":\"000000B1:00000930:0002\",\"sequencenumber\":1,\"finalevent\":false,\"committime\":\"2026-08-07T16:30:10.123Z\"}},\"eventrow\":{\"old\":\"{\\\"Id\\\":\\\"8\\\",\\\"FirstName\\\":\\\"Nikola\\\",\\\"LastName\\\":\\\"Nikolic\\\",\\\"SignupDate\\\":\\\"2026-08-07 16:25:00.8833333\\\"}\",\"current\":\"{\\\"Id\\\":\\\"8\\\",\\\"FirstName\\\":\\\"Nikola\\\",\\\"LastName\\\":\\\"Nikolic-Smith\\\",\\\"SignupDate\\\":\\\"2026-08-07 16:25:00.8833333\\\"}\"}}"
}`;

test('decodes the documented UPDATE example delivered as raw Kafka bytes', () => {
  const env = toEnvelope(Buffer.from(DOC_UPDATE, 'utf8'), {});
  assert.ok(isCesEnvelope(env));
  const c = decodeChange(env);
  assert.equal(c.operation, 'UPD');
  assert.equal(c.fullTable, 'dbo.Employees');
  assert.equal(c.db, 'EmployeesDb');
  assert.deepEqual(c.pk, { Id: '8' });
  assert.equal(c.transaction.commitLsn, '000000B1:00000930:0009');
  assert.equal(c.transaction.sequenceNumber, 1);
  assert.equal(c.old.LastName, 'Nikolic');
  assert.equal(c.current.LastName, 'Nikolic-Smith');
  assert.deepEqual(c.changedColumns, ['LastName']);
  assert.equal(c.columns.length, 4);
});

test('decodes when the body is already a string or object', () => {
  assert.equal(decodeChange(toEnvelope(DOC_UPDATE)).operation, 'UPD');
  assert.equal(decodeChange(toEnvelope(JSON.parse(DOC_UPDATE))).operation, 'UPD');
});

test('INSERT has empty old image, DELETE has empty current image', () => {
  const ins = decodeChange(buildCesEvent({ table: 'Customers', operation: 'INS', current: { CustomerId: '7', FirstName: 'Ana' } }));
  assert.deepEqual(ins.old, {});
  assert.equal(ins.current.FirstName, 'Ana');
  assert.deepEqual(ins.pk, { CustomerId: '7' });
  const del = decodeChange(buildCesEvent({ table: 'Customers', operation: 'DEL', oldRow: { CustomerId: '7' } }));
  assert.deepEqual(del.current, {});
  assert.deepEqual(del.pk, { CustomerId: '7' });
});

test('binary content mode (ce_* Kafka headers) is understood', () => {
  const structured = JSON.parse(DOC_UPDATE);
  const headers = {};
  for (const [k, v] of Object.entries(structured)) if (k !== 'data') headers[`ce_${k}`] = Buffer.from(String(v));
  const env = toEnvelope(Buffer.from(structured.data), headers);
  assert.ok(isCesEnvelope(env));
  assert.equal(env.segmentindex, 0);
  assert.equal(env.finalsegment, true);
  assert.equal(decodeChange(env).current.LastName, 'Nikolic-Smith');
});

test('non-CES messages are ignored', () => {
  assert.equal(isCesEnvelope(toEnvelope(Buffer.from('hello'))), false);
  assert.equal(isCesEnvelope(toEnvelope({ specversion: '1.0', type: 'other.event' })), false);
});

test('segment reassembly joins split messages in segmentindex order', () => {
  const full = JSON.parse(DOC_UPDATE);
  const d = full.data;
  const parts = [d.slice(0, 100), d.slice(100, 400), d.slice(400)];
  const segs = parts.map((p, i) => ({ ...full, id: `seg-${i}`, data: p, segmentindex: i, finalsegment: i === parts.length - 1 }));
  const a = new SegmentAssembler();
  assert.equal(a.push(segs[2]), null);   // out of order on purpose
  assert.equal(a.push(segs[0]), null);
  const done = a.push(segs[1]);
  assert.ok(done);
  const c = decodeChange(done);
  assert.equal(c.segments, 3);
  assert.equal(c.current.LastName, 'Nikolic-Smith');
  assert.equal(a.pendingCount, 0);
});

test('synthetic transactions share one commit LSN with increasing sequence numbers', () => {
  for (let i = 0; i < 50; i++) {
    const tx = randomTransaction().map(decodeChange);
    assert.equal(new Set(tx.map(c => c.transaction.commitLsn)).size, 1);
    tx.forEach((c, j) => assert.equal(c.transaction.sequenceNumber, tx.length === 1 ? 1 : j + 1));
  }
});
