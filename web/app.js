(function () {
'use strict';

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const pad = (n) => String(n).padStart(2, '0');
const fmtTime = (t) => new Date(t * 1000).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
const fmtDur = (s) => { s = Math.max(0, Math.round(s)); return Math.floor(s / 3600) + 'h ' + pad(Math.floor(s % 3600 / 60)) + 'm'; };
const KINDS = window.KINDS || {};
const META = new Set(['addon', 'k', 'm', 'p', 'session', 't', 'x', 'y', 'screenshot', 'notes']);
const TONE = { de: 'death', hc: 'death', cc: 'death', gh: 'death', lv: 'level', qt: 'good', di: 'good', ra: 'rare', bo: 'rare', wb: 'rare', ss: 'info', dn: 'info', dx: 'info' };

let ROOT = 'characters/';
let C = null; // { entry, char, steps, trail, mapNames }
let hidden = new Set();

async function getJson(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(url + ': ' + r.status);
  return r.json();
}
async function getJsonl(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(url + ': ' + r.status);
  return (await r.text()).split('\n').filter(Boolean).map((l) => JSON.parse(l));
}

async function init() {
  let index;
  try { index = await getJson(ROOT + 'index.json'); }
  catch (e) { $('#status').textContent = 'No data. Run "make web-data WOW_DIR=..." and open this page through a web server. ' + e.message; return; }
  const list = index.characters || [];
  const sel = $('#character');
  sel.innerHTML = list.map((c) => `<option value="${esc(c.id)}">${esc(c.name)} — ${esc(c.realm)} (${esc(c.region)})</option>`).join('');
  sel.disabled = !list.length;
  sel.onchange = () => { location.hash = sel.value; };
  window.onhashchange = () => load(index, location.hash.slice(1));
  load(index, location.hash.slice(1));
}

async function load(index, id) {
  const list = index.characters || [];
  const entry = list.find((c) => c.id === id) || list.find((c) => c.id === index.default_character) || list[0];
  if (!entry) { $('#status').textContent = 'No characters in index.json.'; return; }
  if (location.hash.slice(1) !== entry.id) { location.hash = entry.id; return; }
  $('#character').value = entry.id;
  $('#status').textContent = 'Loading…';
  try {
    const [char, steps, trail] = await Promise.all([
      getJson(ROOT + entry.character),
      getJsonl(ROOT + entry.journey),
      getJsonl(ROOT + entry.trail),
    ]);
    steps.sort((a, b) => a.t - b.t);
    const mapNames = {};
    steps.forEach((s) => { if (s.k === 'zo' && s.m && s.zone) mapNames[s.m] = s.zone; });
    C = { entry, char, steps, trail, mapNames };
    hidden = new Set();
    $('#status').textContent = '';
    render();
  } catch (e) { $('#status').textContent = 'Load failed: ' + e.message; }
}

function render() {
  const { entry, char, steps } = C;
  $('#card').hidden = $('#tabs').hidden = false;
  $('#cName').textContent = char.name;
  $('#cLine').textContent = [char.race, char.class, char.faction, char.realmLabel || char.realm, char.region, char.flags && char.flags.hardcore ? 'Hardcore' : ''].filter(Boolean).join(' · ');
  const played = (char.sessions || []).reduce((n, s) => n + Math.max(0, (s.played1 || 0) - (s.played0 || 0)), 0);
  const stats = [['Level', char.level], ['Journal lines', entry.steps], ['Sessions', entry.sessions], ['Trail points', entry.trailPoints],
    ['Screenshots', entry.screenshots], ['Played (sessions)', fmtDur(played)], ['From', steps.length ? fmtTime(entry.start) : '—'], ['To', steps.length ? fmtTime(entry.end) : '—']];
  $('#cStats').innerHTML = stats.map(([k, v]) => `<div><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('');
  renderChips();
  renderFeed();
  renderMapSelect();
  renderSessions();
  renderCounts();
}

function kindLabel(k) { return KINDS[k] ? KINDS[k].name : 'Unknown kind (' + k + ')'; }
function kindGroup(k) { return KINDS[k] ? KINDS[k].addon.replace('Memories_', '') + ' · ' + KINDS[k].group : ''; }

function renderChips() {
  const seen = {};
  C.steps.forEach((s) => { seen[s.k] = (seen[s.k] || 0) + 1; });
  $('#chips').innerHTML = Object.keys(seen).sort().map((k) =>
    `<button class="chip ${hidden.has(k) ? '' : 'on'}" data-k="${esc(k)}" title="${esc(kindLabel(k))}">${esc(k)} ${seen[k]}</button>`).join('');
  $('#chips').onclick = (e) => {
    const k = e.target.dataset.k;
    if (!k) return;
    hidden.has(k) ? hidden.delete(k) : hidden.add(k);
    renderChips();
    renderFeed();
  };
}

function fields(s) {
  const out = [];
  for (const [k, v] of Object.entries(s)) {
    if (META.has(k) || v === null || v === '') continue;
    out.push(`<span><b>${esc(k)}</b>${esc(typeof v === 'object' ? JSON.stringify(v) : v)}</span>`);
  }
  (s.notes || []).forEach((n) => out.push(`<span><b>${esc(n.source)}</b>${esc(n.note)}</span>`));
  return out.join('');
}

function renderFeed() {
  const q = $('#search').value.trim().toLowerCase();
  const rows = C.steps.filter((s) => !hidden.has(s.k) && (!q || (kindLabel(s.k) + ' ' + JSON.stringify(s)).toLowerCase().includes(q)));
  const shown = rows.slice(0, 1000);
  $('#feedInfo').textContent = `${rows.length} of ${C.steps.length} lines` + (rows.length > shown.length ? ' (first 1000 shown)' : '');
  $('#feed').innerHTML = shown.map((s) => {
    const img = s.screenshot ? `<img loading="lazy" src="${esc(ROOT + C.entry.path + '/' + s.screenshot)}" alt="Screenshot ${esc(s.file || '')}">` : '';
    return `<li><span class="t">${esc(fmtTime(s.t))}</span>
      <span class="k k-${TONE[s.k] || ''}">${esc(kindLabel(s.k))}<small>${esc(kindGroup(s.k))}</small></span>
      <span class="f">${fields(s)}${img}</span></li>`;
  }).join('');
}

function mapName(m) { return (C.mapNames[m] ? C.mapNames[m] + ' · ' : '') + 'map ' + m; }

function renderMapSelect() {
  const n = {};
  C.trail.forEach((ch) => { n[ch.m] = (n[ch.m] || 0) + (ch.pts || []).length; });
  const ids = Object.keys(n).sort((a, b) => n[b] - n[a]);
  $('#mapSel').innerHTML = ids.map((m) => `<option value="${esc(m)}">${esc(mapName(m))} (${n[m]} points)</option>`).join('');
  drawMap();
}

function drawMap() {
  const cv = $('#map'), g = cv.getContext('2d'), W = cv.width, H = cv.height;
  g.fillStyle = '#0d1a24'; g.fillRect(0, 0, W, H);
  g.strokeStyle = '#ffffff12'; g.lineWidth = 1;
  for (let i = 1; i < 10; i++) { g.beginPath(); g.moveTo(i * W / 10, 0); g.lineTo(i * W / 10, H); g.moveTo(0, i * H / 10); g.lineTo(W, i * H / 10); g.stroke(); }
  const m = $('#mapSel').value;
  const chunks = C.trail.filter((ch) => String(ch.m) === m);
  const px = (x) => x / 10000 * W, py = (y) => y / 10000 * H;
  g.lineWidth = 2; g.lineJoin = 'round'; g.strokeStyle = '#ffd100';
  chunks.forEach((ch) => {
    g.beginPath();
    (ch.pts || []).forEach(([, x, y], i) => (i ? g.lineTo(px(x), py(y)) : g.moveTo(px(x), py(y))));
    g.stroke();
  });
  const evs = C.steps.filter((s) => String(s.m) === m && s.x != null && s.y != null && TONE[s.k]);
  evs.forEach((s) => {
    g.fillStyle = { death: '#ff6a58', level: '#ffd100', good: '#6fdc5a', rare: '#b66cf0', info: '#5ea2ff' }[TONE[s.k]];
    g.beginPath(); g.arc(px(s.x), py(s.y), 5, 0, 7); g.fill();
    g.strokeStyle = '#000'; g.lineWidth = 1; g.stroke();
  });
  $('#mapInfo').textContent = `${chunks.length} trail stretches, ${evs.length} marked events (deaths, levels, quests, bosses, dungeons, screenshots)`;
}

function renderSessions() {
  const rows = (C.char.sessions || []).slice().sort((a, b) => a.start - b.start);
  $('#sessions').innerHTML = '<tr><th>#</th><th>Start</th><th>Length</th><th>How</th><th>Played</th><th>Computer</th></tr>' +
    rows.map((s, i) => `<tr><td>${i + 1}</td><td>${esc(fmtTime(s.start))}</td><td>${esc(fmtDur((s.last || s.start) - s.start))}</td><td>${esc(s.how || '')}</td>
      <td>${s.played0 != null ? esc(fmtDur(s.played0) + ' → ' + fmtDur(s.played1)) : ''}</td><td>${esc(s.computer || '')}</td></tr>`).join('');
}

function flat(o, prefix, out) {
  for (const [k, v] of Object.entries(o || {})) {
    if (v && typeof v === 'object') flat(v, prefix ? prefix + ' / ' + k : k, out);
    else out.push([prefix ? prefix + ' / ' + k : k, v]);
  }
  return out;
}

function renderCounts() {
  const parts = [];
  for (const [addon, data] of Object.entries(C.char.addons || {})) {
    const counts = flat(data.counts, '', []);
    const snap = Object.entries(data.snap || {}).sort((a, b) => a[0] - b[0]);
    if (!counts.length && !snap.length) continue;
    parts.push(`<h3>${esc(addon)} <span class="sub">schema ${esc(data.schema)} · written by ${esc(data.writtenBy)}</span></h3>`);
    if (counts.length) parts.push('<table>' + counts.map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join('') + '</table>');
    if (snap.length) parts.push('<table><tr><th>Level</th><th>Snapshot</th></tr>' + snap.map(([l, v]) => `<tr><td>${esc(l)}</td><td>${esc(JSON.stringify(v))}</td></tr>`).join('') + '</table>');
  }
  $('#counts').innerHTML = parts.join('') || '<p class="sub">No counts.</p>';
}

$('#tabs').onclick = (e) => {
  const t = e.target.dataset.tab;
  if (!t) return;
  document.querySelectorAll('#tabs button').forEach((b) => b.classList.toggle('on', b === e.target));
  ['journey', 'map', 'sessions', 'counts'].forEach((n) => { $('#tab-' + n).hidden = n !== t; });
  if (t === 'map') drawMap();
};
$('#search').oninput = () => C && renderFeed();
$('#mapSel').onchange = drawMap;
$('#feed').onclick = (e) => {
  if (e.target.tagName !== 'IMG') return;
  $('#shot img').src = e.target.src;
  $('#shot').hidden = false;
};
$('#shot').onclick = () => { $('#shot').hidden = true; };

init();
})();
