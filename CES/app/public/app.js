// CES monitor front end: Server-Sent Events in, plain DOM + SVG out. No dependencies.
const $ = s => document.querySelector(s);
const OPS = ['INS', 'UPD', 'DEL'];
const OP_NAMES = { INS: 'Insert', UPD: 'Update', DEL: 'Delete' };
const OP_VARS = { INS: '--series-1', UPD: '--series-2', DEL: '--series-3' };
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtInt = n => (n ?? 0).toLocaleString('en-US');
const fmtMs = ms => ms == null ? '–' : ms < 1000 ? `${Math.round(ms)} ms` : `${(ms / 1000).toFixed(ms < 10000 ? 2 : 1)} s`;
const fmtTime = iso => { const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleTimeString('en-GB', { hour12: false }) + '.' + String(d.getMilliseconds()).padStart(3, '0'); };
const cssVar = name => getComputedStyle($('.viz-root')).getPropertyValue(name).trim();

const state = {
  config: null,
  events: [],          // newest first, max 500
  byId: new Map(),
  paused: false,
  stats: null,
  filterTable: '',
  filterOp: '',
  tables: new Set(),
  hoverIndex: null,
};

// ------------------------------------------------------------------ API helpers
function token() { return localStorage.getItem('ces-admin-token') || ''; }
async function post(url, body) {
  const r = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', 'x-admin-token': token() }, body: JSON.stringify(body || {}) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || r.statusText);
  return j;
}
function flash(msg, isErr) {
  const el = $('#sim-stats');
  el.dataset.flash = '1';
  el.innerHTML = `<span class="${isErr ? 'err' : ''}">${esc(msg)}</span>`;
  setTimeout(() => { delete el.dataset.flash; refreshSimulator(); }, 3500);
}

// ------------------------------------------------------------------ SSE
function connect() {
  const es = new EventSource('/api/stream');
  const conn = $('#conn');
  es.onopen = () => { conn.className = 'conn ok'; $('#conn-text').textContent = 'Live'; };
  es.onerror = () => { conn.className = 'conn bad'; $('#conn-text').textContent = 'Reconnecting'; };
  es.addEventListener('hello', e => {
    const d = JSON.parse(e.data);
    state.events = []; state.byId.clear();
    addEvents(d.recent.slice().reverse(), false);
    renderStats(d.stats);
  });
  es.addEventListener('changes', e => addEvents(JSON.parse(e.data), true));
  es.addEventListener('stats', e => renderStats(JSON.parse(e.data)));
  es.addEventListener('consumer-error', () => refreshConsumer());
}

function addEvents(list, fresh) {
  for (const ev of list) {
    state.events.unshift(ev);
    state.byId.set(ev.id + ev.receivedAt, ev);
    if (!state.tables.has(ev.fullTable)) {
      state.tables.add(ev.fullTable);
      const o = document.createElement('option'); o.value = o.textContent = ev.fullTable; $('#f-table').append(o);
    }
  }
  if (state.events.length > 500) {
    for (const ev of state.events.splice(500)) state.byId.delete(ev.id + ev.receivedAt);
  }
  if (!state.paused) renderFeed(fresh ? list.length : 0);
}

// ------------------------------------------------------------------ feed
function changeSummary(ev) {
  if (ev.operation === 'UPD') {
    const cols = ev.changedColumns.filter(c => c !== 'ModifiedAt');
    const shown = (cols.length ? cols : ev.changedColumns).slice(0, 2);
    if (!shown.length) return '<span class="sec">no column changed</span>';
    return shown.map(c => `${esc(c)}: <span class="sec">${esc(trim(ev.old[c]))}</span> <span class="arrow">→</span> ${esc(trim(ev.current[c]))}`).join(' · ')
      + (cols.length > 2 ? ` <span class="sec">+${cols.length - 2}</span>` : '');
  }
  const row = ev.operation === 'DEL' ? ev.old : ev.current;
  const keys = Object.keys(row).filter(k => !(k in ev.pk)).slice(0, 3);
  return keys.map(k => `<span class="sec">${esc(k)}</span> ${esc(trim(row[k]))}`).join(' · ');
}
const trim = v => { const s = v == null ? 'NULL' : String(v); return s.length > 28 ? s.slice(0, 27) + '…' : s; };
const shortLsn = lsn => lsn ? lsn.split(':').slice(0, 2).map(p => p.replace(/^0+(?=.)/, '')).join(':') : '–';

function renderFeed(freshCount = 0) {
  const list = state.events.filter(e => (!state.filterTable || e.fullTable === state.filterTable) && (!state.filterOp || e.operation === state.filterOp)).slice(0, 200);
  $('#feed-empty').hidden = list.length > 0;
  let prevLsn = null, alt = false;
  $('#feed').innerHTML = list.map((ev, i) => {
    const lsn = ev.transaction?.commitLsn;
    if (lsn !== prevLsn) { alt = !alt; prevLsn = lsn; }
    const tags = (ev.synthetic && state.config?.mode !== 'mock' ? '<span class="tag">synthetic</span>' : '') + (ev.duplicate ? '<span class="tag">dup</span>' : '') + (ev.segments > 1 ? `<span class="tag">${ev.segments} seg</span>` : '');
    return `<div class="feed-row${alt ? ' tx-alt' : ''}${i < freshCount ? ' fresh' : ''}" role="listitem" tabindex="0" data-key="${esc(ev.id + ev.receivedAt)}">
      <span class="mono sec">${fmtTime(ev.receivedAt)}</span>
      <span class="op ${esc(ev.operation)}">${esc(ev.operation)}</span>
      <span class="ellipsis">${esc(ev.fullTable)}${tags}</span>
      <span class="mono ellipsis">${esc(ev.pkText)}</span>
      <span class="ellipsis">${changeSummary(ev)}</span>
      <span class="mono ellipsis sec" title="commit LSN ${esc(lsn)}, sequence ${esc(ev.transaction?.sequenceNumber)}">${esc(shortLsn(lsn))} #${esc(ev.transaction?.sequenceNumber ?? '')}</span>
      <span class="num sec">${esc(ev.partitionId ?? '–')}</span>
      <span class="num">${fmtMs(ev.latencyMs)}</span>
    </div>`;
  }).join('');
}

$('#feed').addEventListener('click', e => { const r = e.target.closest('.feed-row'); if (r) openDrawer(state.byId.get(r.dataset.key)); });
$('#feed').addEventListener('keydown', e => { if (e.key === 'Enter') { const r = e.target.closest('.feed-row'); if (r) openDrawer(state.byId.get(r.dataset.key)); } });
$('#f-table').onchange = e => { state.filterTable = e.target.value; renderFeed(); };
$('#f-op').onchange = e => { state.filterOp = e.target.value; renderFeed(); };
$('#pause').onclick = e => { state.paused = !state.paused; e.target.setAttribute('aria-pressed', state.paused); e.target.textContent = state.paused ? 'Resume' : 'Pause'; if (!state.paused) renderFeed(); };
$('#clear').onclick = () => { state.events = []; state.byId.clear(); renderFeed(); };

// ------------------------------------------------------------------ drawer
function openDrawer(ev) {
  if (!ev) return;
  $('#drawer-title').innerHTML = `<span class="op ${esc(ev.operation)}">${esc(ev.operation)}</span> ${esc(ev.fullTable)} <span class="muted">${esc(ev.pkText)}</span>`;
  const cols = ev.columns.length ? ev.columns : Object.keys({ ...ev.old, ...ev.current }).map((name, index) => ({ name, type: '', index }));
  const cell = (row, c) => (c in row) ? (row[c] === null ? '<span class="null">NULL</span>' : esc(row[c])) : '<span class="null">–</span>';
  const changed = new Set(ev.changedColumns);
  $('#drawer-body').innerHTML = `
    <dl class="meta">
      <dt>Operation</dt><dd>${esc(OP_NAMES[ev.operation] || ev.operation)} (${esc(ev.operation)})</dd>
      <dt>Database</dt><dd>${esc(ev.db)}</dd>
      <dt>Commit time (time)</dt><dd>${esc(ev.time)}</dd>
      <dt>Enqueued in Event Hubs</dt><dd>${esc(ev.enqueuedTime ?? '–')} (${fmtMs(ev.publishLatencyMs)})</dd>
      <dt>Received here</dt><dd>${esc(ev.receivedAt)} (${fmtMs(ev.latencyMs)})</dd>
      <dt>Commit LSN</dt><dd>${esc(ev.transaction?.commitLsn)}</dd>
      <dt>Begin LSN</dt><dd>${esc(ev.transaction?.beginLsn)}</dd>
      <dt>Sequence # in tx</dt><dd>${esc(ev.transaction?.sequenceNumber)}</dd>
      <dt>Partition / offset</dt><dd>${esc(ev.partitionId ?? '–')} / ${esc(ev.offset ?? '–')} (seq ${esc(ev.sequenceNumber ?? '–')})</dd>
      <dt>CloudEvent id</dt><dd>${esc(ev.id)}</dd>
      <dt>logicalid</dt><dd>${esc(ev.logicalId)}</dd>
      <dt>type / source</dt><dd>${esc(ev.type)} · ${esc(ev.source)}</dd>
      <dt>Segments</dt><dd>${esc(ev.segments)}</dd>
    </dl>
    <h2 style="margin:6px 0 8px">Row images (eventrow.old → eventrow.current)</h2>
    <table class="tbl diff"><thead><tr><th>Column</th><th>Old</th><th>Current</th></tr></thead><tbody>
      ${cols.map(c => `<tr><td class="colname">${esc(c.name)}${c.type ? `<span class="type">${esc(c.type)}</span>` : ''}</td>
        <td class="${changed.has(c.name) ? 'changed' : ''}">${cell(ev.old, c.name)}</td>
        <td class="${changed.has(c.name) ? 'changed' : ''}">${cell(ev.current, c.name)}</td></tr>`).join('')}
    </tbody></table>
    <details style="margin-top:14px"><summary class="small muted">Normalized record (JSON)</summary><pre class="raw">${esc(JSON.stringify(ev, null, 2))}</pre></details>`;
  $('#drawer').classList.add('open'); $('#drawer').setAttribute('aria-hidden', 'false'); $('#drawer-backdrop').hidden = false;
  $('#drawer-close').focus();
}
function closeDrawer() { $('#drawer').classList.remove('open'); $('#drawer').setAttribute('aria-hidden', 'true'); $('#drawer-backdrop').hidden = true; }
$('#drawer-close').onclick = closeDrawer; $('#drawer-backdrop').onclick = closeDrawer;
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeDrawer(); });

// ------------------------------------------------------------------ KPIs + side tables
function renderStats(s) {
  state.stats = s;
  $('#k-total').textContent = fmtInt(s.total);
  $('#k-ops').textContent = `INS ${fmtInt(s.byOp.INS)} · UPD ${fmtInt(s.byOp.UPD)} · DEL ${fmtInt(s.byOp.DEL)}`;
  $('#k-rate').textContent = s.ratePerSec.toLocaleString('en-US', { maximumFractionDigits: 1 });
  $('#k-tx').textContent = fmtInt(s.transactions);
  $('#k-lat').textContent = s.latency.p50 == null ? '–' : `p50 ${fmtMs(s.latency.p50)}`;
  $('#k-lat95').textContent = `p95 ${fmtMs(s.latency.p95)} · ${fmtInt(s.latency.samples)} samples`;
  $('#k-pub').textContent = s.publishLatency.p50 == null ? '–' : `p50 ${fmtMs(s.publishLatency.p50)}`;
  $('#k-pub95').textContent = `p95 ${fmtMs(s.publishLatency.p95)}`;
  $('#k-dup').textContent = `${fmtInt(s.duplicates)} / ${fmtInt(s.parseErrors)}`;

  const tables = Object.entries(s.byTable).sort((a, b) => b[1].total - a[1].total);
  $('#tables tbody').innerHTML = tables.length
    ? tables.map(([t, c]) => `<tr><td>${esc(t)}</td><td class="num">${fmtInt(c.INS)}</td><td class="num">${fmtInt(c.UPD)}</td><td class="num">${fmtInt(c.DEL)}</td><td class="num"><b>${fmtInt(c.total)}</b></td></tr>`).join('')
    : '<tr><td colspan="5" class="muted">No events yet</td></tr>';

  const parts = Object.entries(s.partitions).sort((a, b) => Number(a[0]) - Number(b[0]));
  $('#partitions tbody').innerHTML = parts.length
    ? parts.map(([p, v]) => `<tr><td>${esc(p)}</td><td class="num">${fmtInt(v.count)}</td><td class="num">${esc(v.lastSequenceNumber ?? '–')}</td><td>${v.lastEnqueuedTime ? fmtTime(v.lastEnqueuedTime) : '–'}</td></tr>`).join('')
    : '<tr><td colspan="4" class="muted">No events yet</td></tr>';

  renderChart(s.series);
}

// ------------------------------------------------------------------ chart (SVG, hand-rolled)
function niceMax(v) {
  if (v <= 4) return 4;
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  for (const m of [1, 2, 2.5, 5, 10]) if (m * p >= v) return m * p;
  return 10 * p;
}

function renderChart(series) {
  const svg = $('#chart');
  const W = svg.clientWidth || 800, H = svg.clientHeight || 220;
  const m = { l: 34, r: 44, t: 8, b: 22 };
  const iw = W - m.l - m.r, ih = H - m.t - m.b;
  const max = niceMax(Math.max(1, ...series.flatMap(p => OPS.map(o => p[o]))));
  const x = i => m.l + (i / (series.length - 1)) * iw;
  const y = v => m.t + ih - (v / max) * ih;
  const colors = Object.fromEntries(OPS.map(o => [o, cssVar(OP_VARS[o])]));

  let g = '';
  for (let k = 0; k <= 4; k++) {
    const v = (max / 4) * k, yy = y(v);
    g += `<line class="gridline" x1="${m.l}" x2="${W - m.r}" y1="${yy}" y2="${yy}"/>`;
    g += `<text class="axis-label" x="${m.l - 6}" y="${yy + 4}" text-anchor="end">${Number.isInteger(v) ? v : v.toFixed(1)}</text>`;
  }
  for (const secAgo of [300, 240, 180, 120, 60, 0]) {
    const i = series.length - 1 - secAgo; if (i < 0) continue;
    g += `<text class="axis-label" x="${x(i)}" y="${H - 4}" text-anchor="${secAgo === 300 ? 'start' : secAgo === 0 ? 'end' : 'middle'}">${secAgo === 0 ? 'now' : `-${secAgo / 60}m`}</text>`;
  }
  // lines; end labels nudged apart so they never collide
  const ends = [];
  for (const o of OPS) {
    const d = series.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(p[o]).toFixed(1)}`).join('');
    g += `<path class="series" d="${d}" stroke="${colors[o]}"/>`;
    ends.push({ o, y: y(series.at(-1)[o]) });
  }
  ends.sort((a, b) => a.y - b.y);
  for (let i = 1; i < ends.length; i++) if (ends[i].y - ends[i - 1].y < 13) ends[i].y = ends[i - 1].y + 13;
  for (const e of ends) g += `<text class="end-label" x="${W - m.r + 6}" y="${e.y + 4}">${e.o}</text>`;

  // hover layer
  if (state.hoverIndex != null && series[state.hoverIndex]) {
    const i = state.hoverIndex, p = series[i];
    g += `<line class="crosshair" x1="${x(i)}" x2="${x(i)}" y1="${m.t}" y2="${m.t + ih}"/>`;
    for (const o of OPS) g += `<circle class="hover-dot" cx="${x(i)}" cy="${y(p[o])}" r="4.5" fill="${colors[o]}"/>`;
    const tip = $('#tooltip');
    tip.hidden = false;
    tip.innerHTML = `<div class="t-time">${new Date(p.t).toLocaleTimeString('en-GB', { hour12: false })}</div>`
      + OPS.map(o => `<div class="t-row"><span class="k"><span class="op ${o}"></span>${OP_NAMES[o]}</span><b>${p[o]}</b></div>`).join('')
      + `<div class="t-row"><span class="k">Total</span><b>${p.INS + p.UPD + p.DEL}</b></div>`;
    const left = x(i) + 14 + 160 > W ? x(i) - 14 - tip.offsetWidth : x(i) + 14;
    tip.style.left = `${left}px`; tip.style.top = `${m.t}px`;
  } else $('#tooltip').hidden = true;

  g += `<rect x="${m.l}" y="${m.t}" width="${iw}" height="${ih}" fill="transparent" id="hit"/>`;
  svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
  svg.innerHTML = g;
  svg.dataset.ml = m.l; svg.dataset.iw = iw; svg.dataset.n = series.length;

  // table view (accessibility): only seconds with activity
  const rows = series.filter(p => p.INS + p.UPD + p.DEL > 0).slice(-60).reverse();
  $('#chart-table').innerHTML = `<table class="tbl small"><thead><tr><th>Second</th>${OPS.map(o => `<th class="num">${o}</th>`).join('')}</tr></thead><tbody>${rows.map(p => `<tr><td>${new Date(p.t).toLocaleTimeString('en-GB', { hour12: false })}</td>${OPS.map(o => `<td class="num">${p[o]}</td>`).join('')}</tr>`).join('') || '<tr><td colspan="4" class="muted">No activity</td></tr>'}</tbody></table>`;
}

$('#chart').addEventListener('pointermove', e => {
  const svg = $('#chart'); const rect = svg.getBoundingClientRect();
  const ml = Number(svg.dataset.ml), iw = Number(svg.dataset.iw), n = Number(svg.dataset.n);
  const px = (e.clientX - rect.left) * ((svg.viewBox.baseVal?.width || rect.width) / rect.width);
  const i = Math.round(((px - ml) / iw) * (n - 1));
  state.hoverIndex = i >= 0 && i < n ? i : null;
  if (state.stats) renderChart(state.stats.series);
});
$('#chart').addEventListener('pointerleave', () => { state.hoverIndex = null; if (state.stats) renderChart(state.stats.series); });
window.addEventListener('resize', () => state.stats && renderChart(state.stats.series));

function renderLegend() {
  $('#legend').innerHTML = OPS.map(o => `<span><span class="sw" style="background:var(${OP_VARS[o]})"></span>${o} · ${OP_NAMES[o]}</span>`).join('');
}

// ------------------------------------------------------------------ simulator panel
async function refreshSimulator() {
  if ($('#sim-stats').dataset.flash) return;
  const s = await fetch('/api/simulator').then(r => r.json());
  $('#sim-state').textContent = s.running ? `running ${s.rate}/s` : 'stopped';
  $('#sim-toggle').textContent = s.running ? 'Stop' : 'Start';
  $('#sim-toggle').dataset.running = s.running;
  if (!$('#sim-rate').matches(':active')) { $('#sim-rate').value = s.rate; $('#sim-rate-out').textContent = s.rate; }
  const disabled = !s.configured;
  for (const b of document.querySelectorAll('#sim-toggle, #burst, #scenarios .btn')) b.disabled = disabled;
  $('#sim-target').innerHTML = s.mock
    ? 'Mock mode: synthetic CES events are generated in-process (no SQL Server, no Event Hubs).'
    : s.configured ? `Writes real DML transactions into <code>${esc(s.target)}</code>.` : 'SQL connection not configured (SQL_SERVER / SQL_USER / SQL_PASSWORD).';
  if (!s.mock) {
    const total = Object.values(s.counts || {}).reduce((a, b) => a + b, 0);
    $('#sim-stats').innerHTML = `${fmtInt(total)} transactions · ${fmtInt(s.rowsChanged)} rows changed · ${fmtInt(s.errors)} errors`
      + (s.lastError ? `<br><span class="err">Last error (${esc(s.lastError.scenario)}): ${esc(s.lastError.message)}</span>` : '');
  } else $('#sim-stats').textContent = '';
}

function renderScenarios(scenarios) {
  $('#scenarios').innerHTML = Object.entries(scenarios).map(([k, s]) => `<button class="btn small" data-scenario="${esc(k)}" title="${esc(s.ops)}">${esc(s.label)}</button>`).join('');
  $('#scenarios').onclick = async e => {
    const b = e.target.closest('[data-scenario]'); if (!b) return;
    try { const r = await post(`/api/simulator/scenario/${b.dataset.scenario}`); flash(r.rows != null ? `${b.textContent}: ${r.rows} rows in one transaction` : 'ok'); }
    catch (err) { flash(err.message, true); }
  };
}

$('#sim-toggle').onclick = async () => {
  try {
    if ($('#sim-toggle').dataset.running === 'true') await post('/api/simulator/stop');
    else await post('/api/simulator/start', { rate: Number($('#sim-rate').value) });
  } catch (e) { flash(e.message, true); }
  refreshSimulator();
};
$('#sim-rate').oninput = e => { $('#sim-rate-out').textContent = e.target.value; };
$('#sim-rate').onchange = e => post('/api/simulator/rate', { rate: Number(e.target.value) }).catch(err => flash(err.message, true));
$('#burst').onclick = async () => { try { const r = await post('/api/simulator/burst', { count: 50 }); flash(`Burst done${r.ok != null && r.ok !== true ? `: ${r.ok} transactions` : ''}`); } catch (e) { flash(e.message, true); } };
$('#synthetic').onclick = async () => { try { const r = await post('/api/synthetic', { count: 10 }); flash(`Published ${r.sent} synthetic events to Event Hubs`); } catch (e) { flash(e.message, true); } };
$('#token').oninput = e => localStorage.setItem('ces-admin-token', e.target.value);

// ------------------------------------------------------------------ health + consumer
function statusHtml(level, text) {
  const ic = { good: '✓', warning: '!', serious: '!', critical: '✕' }[level];
  return `<span class="status ${level}"><span class="ic" aria-hidden="true">${ic}</span>${esc(text)}</span>`;
}

async function refreshHealth() {
  let h;
  try { h = await fetch('/api/health/sql').then(r => r.json()); }
  catch (e) { $('#health').innerHTML = statusHtml('critical', e.message); return; }
  if (!h.configured) {
    $('#health').innerHTML = `<span class="muted">${h.mode === 'mock' ? 'Mock mode - no SQL Server connected.' : 'SQL connection not configured.'}</span>`;
    return;
  }
  if (h.error) { $('#health').innerHTML = statusHtml('critical', h.error); return; }
  const db = h.database || {};
  const streamed = (h.tables || []).filter(t => t.streamed);
  const logPct = h.log?.usedPercent != null ? Number(h.log.usedPercent) : null;
  const logLevel = logPct == null ? 'warning' : logPct > 80 ? 'critical' : logPct > 60 ? 'serious' : 'good';
  const errs = h.errors || [];
  $('#health').innerHTML = `<dl>
    <dt>Streaming</dt><dd>${db.is_event_stream_enabled ? statusHtml('good', 'Enabled') : statusHtml('critical', 'Disabled')}</dd>
    <dt>Database</dt><dd>${esc(db.name)} · ${esc(db.recovery_model_desc)}</dd>
    <dt>SQL Server</dt><dd>${esc(h.version?.version)} ${esc(h.version?.updateLevel || 'RTM')}</dd>
    <dt>Streamed tables</dt><dd>${streamed.length ? streamed.map(t => `${esc(t.schema)}.${esc(t.table)}`).join(', ') : statusHtml('warning', 'none')}</dd>
    <dt>Log used</dt><dd>${logPct == null ? '–' : `${statusHtml(logLevel, `${logPct.toFixed(1)} %`)} <span class="muted">of ${esc(h.log.totalMb)} MB</span><div class="meter"><span style="width:${Math.min(100, logPct)}%"></span></div>`}</dd>
    <dt>Log reuse wait</dt><dd><code>${esc(db.log_reuse_wait_desc)}</code></dd>
    <dt>Delivery errors</dt><dd>${errs.length ? statusHtml('critical', `${errs.length} recent`) : statusHtml('good', 'None')}</dd>
  </dl>
  ${errs.slice(0, 3).map(e => `<div class="errors"><div class="err-item">${esc(Object.entries(e).map(([k, v]) => `${k}: ${v}`).join(' · '))}</div></div>`).join('')}
  ${(h.problems || []).length ? `<div class="errors">${h.problems.map(p => `<div class="err-item">${esc(p)}</div>`).join('')}</div>` : ''}`;
}

async function refreshConsumer() {
  const c = await fetch('/api/consumer').then(r => r.json()).catch(() => null);
  if (!c) return;
  const claimed = Object.keys(c.partitions || {}).length;
  $('#consumer-state').textContent = c.mode === 'mock' ? 'mock' : `${c.state}${claimed ? ` · ${claimed} partitions` : ''}`;
  $('#consumer-errors').innerHTML = (c.errors || []).slice(0, 4).map(e => `<div class="err-item"><time>${fmtTime(e.at)}</time>${esc(e.message)}</div>`).join('');
}

// ------------------------------------------------------------------ boot
(async function init() {
  renderLegend();
  const cfg = await fetch('/api/config').then(r => r.json());
  state.config = cfg;
  $('#mode-badge').textContent = cfg.mode === 'mock' ? 'Mock data' : 'Live';
  $('#pipeline').textContent = cfg.mode === 'mock'
    ? 'Mock mode · synthetic CES CloudEvents generated in-process'
    : `${cfg.sqlTarget ?? 'SQL Server 2025'} → ${cfg.eventHub} · consumer group ${cfg.consumerGroup}`;
  if (cfg.mode === 'mock') $('#synthetic').hidden = true;
  if (cfg.adminTokenRequired) { $('#token-box').hidden = false; $('#token').value = token(); if (!token()) $('#token-box').open = true; }
  renderScenarios(cfg.scenarios);
  connect();
  refreshSimulator(); refreshHealth(); refreshConsumer();
  setInterval(refreshSimulator, 3000);
  setInterval(refreshHealth, 10000);
  setInterval(refreshConsumer, 5000);
  $('#health-refresh').onclick = refreshHealth;
})();
