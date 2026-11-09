// The Journey map tab: the world map with the trail and the markers, and the playback of the journey with a transport,
// a timeline, a follow camera, a journal log, tooltips, toasts and a zone banner. Ported from the first viewer
// ("Memories Chronicle"). The playhead and the selected event are in the hash.
import { screenshotUrl } from '../lib/data.mjs';
import { clamp, clock, coinsHtml, esc, fmtDate, fmtDay, moneyText } from '../lib/format.mjs';
import { boundsOf } from '../lib/geo.mjs';
import { EVENT_COLOURS, NOTE, noteOf, tipHtml } from '../lib/events.mjs';
import { buildModel, CAT, FLAG, LANES } from '../lib/model.mjs';
import { advance, crossed, eventId, findEvent, goldAt, levelAt, placeAt, posAt, SPEEDS, spanAt } from '../lib/playback.mjs';
import { ZONES } from '../zones.mjs';
import { icon } from './icons.mjs';
import { MapView, MAX_S, nextZoom } from './mapview.mjs';
import { createSheet } from './shell.mjs';

const FEED_MAX = 200;
const TOAST_MAX = 3;

// The bounds [x0, x1, y0, y1] of each chunk of the trail, in one array of 4 numbers for each chunk.
export function chunkBounds(points) {
  const n = points.chunkStart.length - 1;
  const out = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) {
    const a = points.chunkStart[i], b = points.chunkStart[i + 1];
    const bb = boundsOf(points.wx.subarray(a, b), points.wy.subarray(a, b)) ?? [0, 0, 0, 0];
    out.set(bb, i * 4);
  }
  return out;
}

const trailColour = (f) => (f & FLAG.g ? '#8fd4ff' : f & FLAG.t ? '#ffe28a' : f & FLAG.c ? '#ff5a43' : '#fff3c4');

// drawTrail strokes the trail up to the clock uptoC in two passes: a dark casing, then the colour. With dimRest it first
// draws the rest of the trail as a thin dim line. A line breaks between chunks, at a gap of more than 30 played seconds
// and at a jump on the map. It skips the chunks that are off the screen and the points that are less than 1.2 px from
// the last one drawn, so that a trail of a million points costs one pass over what is visible.
export function drawTrail(ctx, view, model, bounds, uptoC = Infinity, dimRest = false) {
  const P = model.points;
  const n = P.chunkStart.length - 1;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const sx = (wx) => (wx - view.x) * view.s + view.w / 2;
  const sy = (wy) => (wy - view.y) * view.s + view.h / 2;
  const passes = dimRest ? [-1, 0, 1] : [0, 1];
  for (const pass of passes) {
    const limit = pass < 0 ? Infinity : uptoC;
    for (let ci = 0; ci < n; ci++) {
      const b = ci * 4;
      if (sx(bounds[b + 1]) < -10 || sx(bounds[b]) > view.w + 10 || sy(bounds[b + 3]) < -10 || sy(bounds[b + 2]) > view.h + 10) continue;
      let run = null;
      let px = 0, py = 0, last = -1;
      for (let i = P.chunkStart[ci]; i < P.chunkStart[ci + 1]; i++) {
        if (P.c[i] > limit) break;
        const x = sx(P.wx[i]), y = sy(P.wy[i]);
        const cut = last < 0 || P.c[i] - P.c[last] > 30 || Math.hypot(P.lx[i] - P.lx[last], P.ly[i] - P.ly[last]) > 400 + (P.f[i] & FLAG.t ? 1000 : 0);
        const lastOfChunk = i === P.chunkStart[ci + 1] - 1 || P.c[i + 1] > limit;
        if (!cut && !lastOfChunk && P.f[i] === P.f[last] && Math.abs(x - px) + Math.abs(y - py) < 1.2) continue;
        const dashed = pass >= 0 && (P.f[i] & FLAG.t) !== 0;
        const colour = pass < 0 ? 'rgba(255,243,196,0.3)' : pass ? trailColour(P.f[i]) : 'rgba(20,10,2,0.85)';
        const style = colour + dashed;
        if (cut || style !== run) {
          if (run !== null) ctx.stroke();
          ctx.beginPath();
          ctx.strokeStyle = colour;
          ctx.lineWidth = pass < 0 ? 1.6 : pass ? 2.2 : 4.4;
          ctx.setLineDash(dashed ? [6, 5] : []);
          if (cut) ctx.moveTo(x, y);
          else {
            ctx.moveTo(px, py);
            ctx.lineTo(x, y);
          }
          run = style;
        } else {
          ctx.lineTo(x, y);
        }
        px = x; py = y; last = i;
      }
      if (run !== null) ctx.stroke();
    }
  }
  ctx.setLineDash([]);
}

// drawMarks draws the event markers that pass the filter and returns the hit list [{ x, y, r, ev }].
export function drawMarks(ctx, view, model, show, uptoC = Infinity, now = 0) {
  const hits = [];
  const r = clamp(5 + view.rel * 0.6, 6, 9);
  for (const e of model.marks) {
    if (e.c > uptoC || show[CAT[e.k]] === false || e.k === 'dx') continue;
    const sx = (e.wx - view.x) * view.s + view.w / 2, sy = (e.wy - view.y) * view.s + view.h / 2;
    if (sx < -20 || sy < -20 || sx > view.w + 20 || sy > view.h + 20) continue;
    const age = uptoC - e.c;
    const pulse = age >= 0 && age < 6 ? 1 + 0.5 * Math.sin(now / 90) * (1 - age / 6) : 1;
    const ox = e.k === 'ss' ? r * 1.7 : e.k === 'bo' ? r * 0.8 * (((e.encounter || 0) % 3) - 1) : 0;
    const oy = e.k === 'ss' ? -r * 1.2 : e.k === 'bo' ? -r * 1.4 : 0;
    icon(ctx, e.k, sx + ox, sy + oy, r * pulse, 1);
    hits.push({ x: sx + ox, y: sy + oy, r: r + 3, ev: e });
  }
  return hits;
}

function drawPlayer(ctx, view, pos, span, now) {
  if (!pos) return;
  const sx = (pos.wx - view.x) * view.s + view.w / 2, sy = (pos.wy - view.y) * view.s + view.h / 2;
  const ghost = (pos.f & FLAG.g) !== 0, pulse = 0.5 + 0.5 * Math.sin(now / 280);
  const colour = ghost ? '#8fd4ff' : span ? '#c58cff' : '#ffd100';
  const grd = ctx.createRadialGradient(sx, sy, 0, sx, sy, 26 + pulse * 6);
  grd.addColorStop(0, colour + 'cc');
  grd.addColorStop(1, colour + '00');
  ctx.fillStyle = grd;
  ctx.beginPath();
  ctx.arc(sx, sy, 32, 0, 6.2832);
  ctx.fill();
  ctx.lineWidth = 2.5;
  ctx.strokeStyle = '#0c0803';
  ctx.fillStyle = colour;
  ctx.beginPath();
  ctx.arc(sx, sy, 7, 0, 6.2832);
  ctx.fill();
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(sx, sy, 3, 0, 6.2832);
  ctx.fillStyle = '#fff';
  ctx.fill();
  if (span) {
    ctx.strokeStyle = '#c58cff';
    ctx.lineWidth = 2;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.arc(sx, sy, 14 + pulse * 2, 0, 6.2832);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.font = '700 12px Cinzel, serif';
    ctx.textAlign = 'center';
    ctx.lineWidth = 3.5;
    ctx.strokeStyle = 'rgba(10,6,2,0.9)';
    ctx.fillStyle = '#e4c8ff';
    ctx.strokeText('Inside ' + span.name, sx, sy + 30);
    ctx.fillText('Inside ' + span.name, sx, sy + 30);
  }
}

const TL = { L: 84, R: 14, ruler: 16, band: 22, lane: 20, gold: 44 };

// drawTimeline paints the timeline: the played clock ruler, the level bands, one lane for each marker category, the
// purse curve and the playhead. In a canvas that is less than 120 px high it paints a compact form: the bands, one lane
// with every marker, and the purse curve.
export function drawTimeline(ctx, w, h, dpr, model, state) {
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);
  const hits = [];
  const compact = h < 120;
  const L = compact ? 6 : TL.L, x0 = L, x1 = w - TL.R, span = Math.max(1, x1 - x0);
  const cx = (c) => x0 + (c / model.total) * span;
  const c = state.c;
  const yBand = compact ? 0 : TL.ruler, bandH = compact ? 14 : TL.band;
  const yLanes = compact ? bandH + 2 : yBand + bandH + 4;
  const laneY = (n) => yLanes + n * TL.lane;
  const lanes = compact ? 1 : LANES.length;
  const gy = laneY(lanes), gh = compact ? Math.max(12, h - gy) : TL.gold;
  ctx.font = '500 11px Alegreya Sans, sans-serif';
  ctx.textBaseline = 'middle';
  if (!compact) {
    const step = [60, 300, 600, 900, 1800, 3600].find((s) => (s * span) / model.total >= 64) ?? 3600;
    ctx.fillStyle = '#a79f91';
    ctx.strokeStyle = '#a79f9166';
    ctx.textAlign = 'center';
    for (let s = 0; s <= model.total; s += step) {
      const x = cx(s);
      ctx.beginPath();
      ctx.moveTo(x, yBand - 4);
      ctx.lineTo(x, yBand);
      ctx.stroke();
      ctx.fillText(Math.floor(s / 3600) + ':' + String(Math.floor((s % 3600) / 60)).padStart(2, '0'), x, 6);
    }
  }
  model.levels.forEach((l, n) => {
    const a = cx(l.c0), b = cx(l.c1), cur = c >= l.c0 && c < l.c1;
    ctx.fillStyle = cur ? '#6a4a10' : n % 2 ? '#2b2012' : '#3a2a16';
    ctx.fillRect(a, yBand, Math.max(1, b - a), bandH);
    ctx.strokeStyle = '#00000088';
    ctx.strokeRect(a + 0.5, yBand + 0.5, Math.max(1, b - a), bandH);
    if (b - a > 26) {
      ctx.fillStyle = cur ? '#ffd100' : '#d8c590';
      ctx.textAlign = 'center';
      ctx.font = `700 ${compact ? 9 : 11}px Cinzel, serif`;
      ctx.fillText('Lv ' + l.level, (a + b) / 2, yBand + bandH / 2 + 1);
    }
  });
  if (!compact) {
    LANES.forEach(([cat, label, ic], n) => {
      const y = laneY(n), on = state.show[cat] !== false;
      ctx.fillStyle = n % 2 ? '#ffffff08' : '#00000030';
      ctx.fillRect(0, y, w, TL.lane);
      ctx.globalAlpha = on ? 1 : 0.35;
      icon(ctx, ic, 14, y + TL.lane / 2, 5.5);
      ctx.font = '700 10.5px Cinzel, serif';
      ctx.fillStyle = '#d8c590';
      ctx.textAlign = 'left';
      ctx.fillText(label, 28, y + TL.lane / 2 + 1);
      ctx.globalAlpha = 1;
    });
  }
  model.sessions.forEach((s, n) => {
    const x = cx(s.c0);
    ctx.strokeStyle = '#ffd10055';
    ctx.setLineDash([3, 4]);
    ctx.beginPath();
    ctx.moveTo(x, yBand - (compact ? 0 : 2));
    ctx.lineTo(x, gy + gh);
    ctx.stroke();
    ctx.setLineDash([]);
    if (n && !compact) {
      ctx.fillStyle = '#e7c46a';
      ctx.textAlign = 'left';
      ctx.font = '500 10px Alegreya Sans, sans-serif';
      ctx.fillText(fmtDay(s.start), x + 3, gy + gh + 0);
    }
  });
  if (!compact && state.show.dungeon !== false) {
    for (const s of model.spans) {
      const y = laneY(2) + TL.lane / 2, a = cx(s.c0), b = cx(s.c1);
      ctx.fillStyle = '#7a3fc0aa';
      ctx.strokeStyle = '#c58cff';
      ctx.lineWidth = 1;
      ctx.fillRect(a, y - 5, Math.max(3, b - a), 10);
      ctx.strokeRect(a + 0.5, y - 4.5, Math.max(3, b - a), 9);
      hits.push({ x: (a + b) / 2, y, w: Math.max(3, b - a) / 2, h: 6, ev: s.dn });
    }
  }
  for (const e of model.events) {
    const cat = CAT[e.k];
    if (!cat || e.k === 'dn' || e.k === 'dx' || state.show[cat] === false || (e.k === 'di' && !e.area)) continue;
    const x = cx(e.c), y = (compact ? laneY(0) : laneY(LANES.findIndex((l) => l[0] === cat))) + (compact ? 10 : TL.lane / 2);
    icon(ctx, e.k, x, y, compact ? 3.5 : 5, e.c <= c ? 1 : 0.55);
    hits.push({ x, y, w: 6, h: 8, ev: e });
  }
  // The purse as a step curve scaled to its peak.
  const base = gy + gh - 4, top = gy + (compact ? 2 : 14), vy = (v) => base - (v / model.goldMax) * (base - top), hx = cx(c);
  ctx.fillStyle = '#00000030';
  ctx.fillRect(0, gy, w, gh);
  if (!compact) {
    ctx.beginPath();
    ctx.arc(14, gy + gh / 2, 5, 0, 6.2832);
    ctx.fillStyle = '#f5c518';
    ctx.fill();
    ctx.strokeStyle = '#000';
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.font = '700 10.5px Cinzel, serif';
    ctx.fillStyle = '#d8c590';
    ctx.textAlign = 'left';
    ctx.fillText('Gold', 28, gy + gh / 2 + 1);
  }
  const curve = new Path2D();
  let pv = model.gold[0].v;
  curve.moveTo(x0, vy(pv));
  for (const p of model.gold) {
    curve.lineTo(cx(p.c), vy(pv));
    curve.lineTo(cx(p.c), vy(p.v));
    pv = p.v;
  }
  curve.lineTo(x1, vy(pv));
  const area = new Path2D(curve);
  area.lineTo(x1, base);
  area.lineTo(x0, base);
  area.closePath();
  const grad = ctx.createLinearGradient(0, top, 0, base);
  grad.addColorStop(0, 'rgba(255,209,0,0.45)');
  grad.addColorStop(1, 'rgba(255,209,0,0.05)');
  ctx.fillStyle = grad;
  ctx.fill(area);
  ctx.strokeStyle = 'rgba(255,209,0,0.35)';
  ctx.lineWidth = 1.5;
  ctx.stroke(curve);
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, gy, hx, gh);
  ctx.clip();
  ctx.strokeStyle = '#ffd100';
  ctx.lineWidth = 2;
  ctx.stroke(curve);
  ctx.restore();
  ctx.fillStyle = '#ffd100';
  ctx.strokeStyle = '#000';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.arc(hx, vy(goldAt(model, c)), 3.5, 0, 6.2832);
  ctx.fill();
  ctx.stroke();
  if (!compact) {
    ctx.font = '500 10px Alegreya Sans, sans-serif';
    ctx.fillStyle = '#e7c46a';
    ctx.textAlign = 'right';
    ctx.fillText('peak ' + moneyText(model.goldMax) + (model.goldAbout ? ' (about)' : ''), x1 - 2, gy + 8);
  }
  ctx.fillStyle = '#ffd10014';
  ctx.fillRect(x0, yBand, hx - x0, gy + gh - yBand);
  ctx.strokeStyle = '#ffd100';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(hx, compact ? 0 : 2);
  ctx.lineTo(hx, gy + gh);
  ctx.stroke();
  ctx.fillStyle = '#ffd100';
  ctx.strokeStyle = '#000';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(hx - 6, 0);
  ctx.lineTo(hx + 6, 0);
  ctx.lineTo(hx, 9);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  return { hits, gold: { y0: gy, y1: gy + gh }, x0, x1 };
}

// Sets --c from data-c on each element below root (the CSP blocks style attributes, the CSSOM is allowed).
export function paintData(root) {
  for (const el of root.querySelectorAll('[data-c]')) el.style.setProperty('--c', el.dataset.c);
}

const reducedMotion = () => globalThis.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;

export function createJourneyTab(panel, ctx) {
  const $ = (id) => panel.querySelector('#' + id);
  const state = { c: 0, playing: false, speed: 1, follow: false, followScale: null, show: {}, sel: null };
  let model = null, bounds = null, view = null, logEvents = [];
  let active = false, raf = 0, last = 0;
  let mapHits = [], tl = { hits: [], gold: { y0: 0, y1: 0 }, x0: 0, x1: 0 };
  let tw = 0, th = 0, tdpr = 1;
  let lastPlace = null, lastFeed = '';
  let toastTimers = new Set();
  let bannerTimer = 0, lightboxAt = 0, detailEv = null;
  const tlCanvas = $('tl'), tlCtx = tlCanvas.getContext('2d');
  const stage = $('journeyStage');

  /* ---------------------------------------------------------------- hash */
  function pushParams() {
    if (!active || !view) return;
    const p = { x: view.cam.x, y: view.cam.y, z: view.cam.s };
    if (state.c >= 1) p.at = Math.floor(state.c);
    if (state.sel) p.ev = eventId(state.sel);
    ctx.setParams('journey', p);
  }

  /* ---------------------------------------------------------------- tooltips, detail, lightbox, toasts */
  function placeBox(el, x, y, host, above) {
    const r = host.getBoundingClientRect(), st = stage.getBoundingClientRect();
    let px = r.left - st.left + x + 14, py = r.top - st.top + y + 14;
    if (above) py = r.top - st.top + y - el.offsetHeight - 16;
    el.style.left = clamp(px, 8, Math.max(8, st.width - el.offsetWidth - 8)) + 'px';
    el.style.top = clamp(py, 8, Math.max(8, st.height - el.offsetHeight - 8)) + 'px';
  }
  function showTip(html, x, y, host, el = $('tip'), above = false) {
    el.innerHTML = html;
    paintData(el);
    el.hidden = false;
    placeBox(el, x, y, host, above);
  }
  const hideTip = () => {
    $('tip').hidden = true;
  };
  const shotOf = (e) => (e.k === 'ss' && e.screenshot ? screenshotUrl(ctx.data, e.screenshot) : null);

  function closeDetail() {
    detailEv = null;
    $('detail').hidden = true;
  }
  function openShot(e) {
    const url = shotOf(e);
    const img = $('lightboxImg');
    img.hidden = false;
    img.onerror = () => {
      img.hidden = true;
      $('lightboxCap').textContent = 'Screenshot not uploaded';
    };
    if (url) img.src = url;
    else img.onerror();
    if (url) $('lightboxCap').textContent = 'Screenshot: ' + (e.why ?? '') + ' · ' + fmtDate(e.t);
    $('lightbox').hidden = false;
    lightboxAt = performance.now();
    hideTip();
  }
  function closeShot() {
    $('lightbox').hidden = true;
    $('lightboxImg').removeAttribute('src');
  }

  function selectEvent(e) {
    state.sel = e;
    pushParams();
    view.invalidate();
    drawTl();
  }
  // A click on an event shows its detail and leaves the journey where it is. A screenshot opens its picture instead.
  function pickEvent(e, x, y, host, above = false) {
    selectEvent(e);
    if (e.k === 'ss' && e.screenshot) {
      closeDetail();
      openShot(e);
      return;
    }
    detailEv = e;
    hideTip();
    showTip('<button type="button" class="x" aria-label="Close details" title="Close">×</button>' + tipHtml(model, e, null), x, y, host, $('detail'), above);
  }

  function toast(text, colour) {
    const d = document.createElement('div');
    d.className = 'toast';
    d.style.setProperty('--c', colour);
    d.textContent = text;
    const box = $('toasts');
    box.append(d);
    while (box.children.length > TOAST_MAX) box.firstChild.remove();
    const t = setTimeout(() => {
      d.remove();
      toastTimers.delete(t);
    }, 3500);
    toastTimers.add(t);
  }
  function flash() {
    if (reducedMotion()) return;
    const f = $('flash');
    f.classList.remove('go');
    void f.offsetWidth;
    f.classList.add('go');
  }
  function notifyCrossed(from, to) {
    if (to <= from || to - from > 90) return;
    const list = crossed(model, from, to).filter((e) => NOTE[e.k] && state.show[CAT[e.k]] !== false);
    for (const e of list.slice(-TOAST_MAX)) {
      const [text, colour] = noteOf(e);
      toast(text, colour);
    }
    if (list.some((e) => e.k === 'ss')) flash();
  }

  /* ---------------------------------------------------------------- hud and log */
  function showBanner(zone, sub) {
    const b = $('banner');
    $('bZone').textContent = zone;
    $('bSub').textContent = sub;
    b.classList.remove('show');
    clearTimeout(bannerTimer);
    if (!zone) return;
    void b.offsetWidth;
    b.classList.add('show');
    bannerTimer = setTimeout(() => b.classList.remove('show'), 3200);
  }

  function feedItems() {
    const idx = logEvents.findIndex((e) => e.c > state.c);
    const upto = idx < 0 ? logEvents.length : idx;
    const out = [];
    for (let i = upto - 1; i >= 0 && out.length < FEED_MAX; i--) if (state.show[CAT[logEvents[i].k]] !== false) out.push(i);
    return out;
  }
  function renderFeed() {
    const items = feedItems();
    const key = items.length + ':' + (items[0] ?? -1) + ':' + Object.values(state.show).join();
    if (key === lastFeed) return;
    lastFeed = key;
    const feed = $('feed');
    if (!items.length) {
      feed.innerHTML = '<li class="empty"><span class="sub">Nothing yet. Press play.</span></li>';
      return;
    }
    feed.innerHTML = items
      .map((i) => {
        const e = logEvents[i];
        const [text, colour] = noteOf(e);
        return `<li data-i="${i}"><span class="t">${esc(clock(e.c))}</span><span class="txt" data-c="${esc(colour)}">${esc(text)}</span></li>`;
      })
      .join('');
    paintData(feed);
  }

  function updateHud() {
    const c = state.c;
    const span = spanAt(model, c);
    const place = placeAt(model, c);
    $('rTime').textContent = clock(c) + ' / ' + clock(model.total);
    $('rWhere').textContent =
      'Level ' + levelAt(model, c) + (span ? ', inside ' + span.name : place.zone ? ', ' + place.zone + (place.sub ? ' (' + place.sub + ')' : '') : '');
    $('rGold').innerHTML = coinsHtml(goldAt(model, c));
    $('zLevel').textContent = view.levelName();
    const key = place.zone + '|' + place.sub;
    if (key !== lastPlace) {
      lastPlace = key;
      showBanner(place.zone, place.sub);
    }
    renderFeed();
  }

  /* ---------------------------------------------------------------- camera */
  function zoneFitScale(z) {
    const r = z.rect;
    return Math.min(0.7 * Math.min(view.vw / (r[1] - r[0]), view.vh / (r[3] - r[2])), MAX_S);
  }
  function followCamera() {
    if (!state.follow) return;
    const pos = posAt(model, state.c);
    if (!pos) return;
    const z = ZONES[pos.m];
    const auto = pos.f & FLAG.t ? view.sFit * 2.6 : z ? zoneFitScale(z) : view.sFit * 2.6;
    view.setCamera({ x: pos.wx, y: pos.wy, s: state.followScale ?? auto }, { ease: true, notify: false });
  }
  function setFollow(on) {
    state.follow = on;
    if (!on) state.followScale = null;
    const b = $('follow');
    b.classList.toggle('on', on);
    b.setAttribute('aria-pressed', String(on));
  }

  /* ---------------------------------------------------------------- loop */
  function drawTl() {
    if (!tw || !model) return;
    tl = drawTimeline(tlCtx, tw, th, tdpr, model, state);
  }
  function frame(now) {
    raf = 0;
    if (!active || document.hidden) return;
    const dt = Math.min((now - last) / 1000, 0.1);
    last = now;
    if (state.playing) {
      const prev = state.c;
      const next = advance(state, dt, model.total);
      state.c = next.c;
      notifyCrossed(prev, next.c);
      if (!next.playing) syncPlay(false);
    }
    followCamera();
    updateHud();
    view.invalidate();
    drawTl();
    if (state.playing) raf = requestAnimationFrame(frame);
  }
  function kick() {
    if (raf || !active) return;
    last = performance.now();
    raf = requestAnimationFrame(frame);
  }
  function syncPlay(on) {
    state.playing = on;
    const b = $('play');
    b.textContent = on ? '❚❚' : '▶';
    b.setAttribute('aria-label', on ? 'Pause' : 'Play');
    b.title = on ? 'Pause (Space)' : 'Play (Space)';
    if (!on) pushParams();
  }
  function setPlaying(on) {
    if (on && state.c >= model.total - 0.5) seek(0, false);
    if (on && state.c < 1 && !state.follow) setFollow(true);
    syncPlay(on);
    kick();
  }
  function seek(c, push = true) {
    state.c = clamp(c, 0, model.total);
    if (push) pushParams();
    kick();
  }
  function setSpeed(s) {
    state.speed = s;
    panel.querySelectorAll('[data-speed]').forEach((b) => {
      const on = Number(b.dataset.speed) === s;
      b.classList.toggle('on', on);
      b.setAttribute('aria-pressed', String(on));
    });
    $('speedCycle').textContent = s + '×';
  }

  /* ---------------------------------------------------------------- setup */
  function sizeTimeline() {
    tdpr = globalThis.devicePixelRatio || 1;
    const w = tlCanvas.clientWidth, h = tlCanvas.clientHeight;
    if (!w || !h) return;
    tw = w;
    th = h;
    tlCanvas.width = Math.round(w * tdpr);
    tlCanvas.height = Math.round(h * tdpr);
    drawTl();
  }

  function onKey(e) {
    if (!active) return;
    if (!$('lightbox').hidden) {
      if (e.code === 'Escape') closeShot();
      return;
    }
    if (e.code === 'Escape') closeDetail();
    if (e.target.matches?.('input, select, textarea') || e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.code === 'Space' && !e.target.closest?.('button, a')) {
      e.preventDefault();
      setPlaying(!state.playing);
    } else if (e.code === 'ArrowRight') seek(state.c + 15 * state.speed);
    else if (e.code === 'ArrowLeft') seek(state.c - 15 * state.speed);
  }

  function init() {
    model = buildModel(ctx.data.char, ctx.data.steps, ctx.data.trail);
    bounds = chunkBounds(model.points);
    logEvents = model.events.filter((e) => CAT[e.k] && !(e.k === 'di' && !e.area));
    createSheet($('journeySheet'));
    paintData($('journeySheet'));
    view = new MapView($('journeyMap'), {
      world: globalThis.WORLD ?? null,
      zones: ZONES,
      onCamera: () => {
        $('zLevel').textContent = view.levelName();
        if (!state.playing) pushParams();
      },
      onUser: () => setFollow(false),
      onTap: (x, y) => {
        const h = mapHits.find((q) => Math.hypot(q.x - x, q.y - y) <= q.r);
        if (h) pickEvent(h.ev, x, y, $('journeyMap'));
        else closeDetail();
      },
      onHover: (x, y) => {
        if (x === null) return hideTip();
        const h = mapHits.find((q) => Math.hypot(q.x - x, q.y - y) <= q.r);
        if (h && h.ev !== detailEv) showTip(tipHtml(model, h.ev, shotOf(h.ev)), x, y, $('journeyMap'));
        else hideTip();
        $('journeyMap').style.cursor = h ? 'pointer' : '';
      },
    });
    view.draw((c, v, now) => {
      drawTrail(c, v, model, bounds, state.c, state.c < model.total);
      mapHits = drawMarks(c, v, model, state.show, state.c, now);
      if (state.sel?.wx != null) {
        const sx = (state.sel.wx - v.x) * v.s + v.w / 2, sy = (state.sel.wy - v.y) * v.s + v.h / 2;
        c.strokeStyle = '#fff';
        c.lineWidth = 2;
        c.beginPath();
        c.arc(sx, sy, 13, 0, 6.2832);
        c.stroke();
      }
      drawPlayer(c, v, posAt(model, state.c), spanAt(model, state.c), now);
    });

    new ResizeObserver(sizeTimeline).observe(tlCanvas);

    $('play').addEventListener('click', () => setPlaying(!state.playing));
    $('rew').addEventListener('click', () => {
      setPlaying(false);
      seek(0);
      setFollow(false);
      view.fitWorld({ ease: true });
    });
    panel.querySelectorAll('[data-speed]').forEach((b) => b.addEventListener('click', () => setSpeed(Number(b.dataset.speed))));
    $('speedCycle').addEventListener('click', () => setSpeed(SPEEDS[(SPEEDS.indexOf(state.speed) + 1) % SPEEDS.length]));
    panel.querySelectorAll('[data-cat]').forEach((i) =>
      i.addEventListener('change', () => {
        state.show[i.dataset.cat] = i.checked;
        kick();
      }),
    );
    const zoom = (dir) => {
      if (state.follow) {
        state.followScale = nextZoom(state.followScale ?? view.cam.s, dir, view.vw, view.vh);
        kick();
      } else view.stepZoom(dir);
    };
    $('zIn').addEventListener('click', () => zoom(1));
    $('zOut').addEventListener('click', () => zoom(-1));
    $('follow').addEventListener('click', () => {
      setFollow(!state.follow);
      kick();
    });
    $('zWorld').addEventListener('click', () => {
      setFollow(false);
      view.fitWorld({ ease: true });
    });

    $('detail').addEventListener('click', (e) => {
      if (e.target.closest('.x')) {
        closeDetail();
        state.sel = null;
        pushParams();
        view.invalidate();
        drawTl();
      }
    });
    $('lightbox').addEventListener('click', () => {
      if (performance.now() - lightboxAt > 250) closeShot();
    });
    $('feed').addEventListener('click', (e) => {
      const li = e.target.closest('li[data-i]');
      const ev = li && logEvents[Number(li.dataset.i)];
      if (!ev) return;
      seek(ev.c, false);
      pickEvent(ev, 12, 12, stage, false);
    });

    let scrub = false;
    const tlPoint = (e) => {
      const r = tlCanvas.getBoundingClientRect();
      return [e.clientX - r.left, e.clientY - r.top];
    };
    const clockAtX = (x) => clamp((x - tl.x0) / Math.max(1, tl.x1 - tl.x0), 0, 1) * model.total;
    const tlHit = (x, y) => [...tl.hits].reverse().find((h) => Math.abs(h.x - x) <= h.w && Math.abs(h.y - y) <= h.h) ?? null;
    tlCanvas.addEventListener('pointerdown', (e) => {
      const [x, y] = tlPoint(e);
      const h = tlHit(x, y);
      if (h) {
        pickEvent(h.ev, x + tlCanvas.getBoundingClientRect().left - stage.getBoundingClientRect().left - 14, y, tlCanvas, true);
        return;
      }
      closeDetail();
      scrub = true;
      tlCanvas.setPointerCapture?.(e.pointerId);
      seek(clockAtX(x), false);
    });
    tlCanvas.addEventListener('pointermove', (e) => {
      const [x, y] = tlPoint(e);
      if (scrub) {
        seek(clockAtX(x), false);
        hideTip();
        return;
      }
      if (e.pointerType !== 'mouse') return;
      const h = tlHit(x, y);
      const sx = x + tlCanvas.getBoundingClientRect().left - stage.getBoundingClientRect().left - 14;
      if (!h && y >= tl.gold.y0 && y <= tl.gold.y1 && x >= tl.x0 && x <= tl.x1) {
        const c = clockAtX(x);
        showTip(`<b class="tip-title" data-c="#ffd100">Purse</b><div class="coins">${coinsHtml(goldAt(model, c))}</div><div class="dim">${esc(clock(c))} played</div>`, sx, y, tlCanvas, $('tip'), true);
      } else if (h && h.ev !== detailEv) showTip(tipHtml(model, h.ev, shotOf(h.ev)), sx, y, tlCanvas, $('tip'), true);
      else hideTip();
    });
    const endScrub = () => {
      if (scrub) {
        scrub = false;
        pushParams();
      }
    };
    tlCanvas.addEventListener('pointerup', endScrub);
    tlCanvas.addEventListener('pointercancel', endScrub);
    tlCanvas.addEventListener('pointerleave', hideTip);
    window.addEventListener('keydown', onKey);
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) kick();
    });
    setSpeed(1);
  }

  // Apply the parameters of a link. A missing one keeps the current state; the first time it is the default.
  function apply(first, p) {
    if (Number.isFinite(p.at)) state.c = clamp(p.at, 0, model.total);
    const ev = p.ev ? findEvent(model, p.ev) : null;
    const hasCam = Number.isFinite(p.x) && Number.isFinite(p.y) && Number.isFinite(p.z);
    // A link with any parameter sets the selection; a tab switch with none keeps it.
    if (Object.keys(p).length) state.sel = ev;
    if (hasCam) {
      setFollow(false);
      view.setCamera({ x: p.x, y: p.y, s: p.z }, { notify: false });
    } else if (ev && ev.wx !== null) {
      setFollow(false);
      view.setCamera({ x: ev.wx, y: ev.wy, s: view.sFit * 7 }, { notify: false });
    } else if (first) {
      view.fitBounds(model.points.count ? boundsOf(model.points.wx, model.points.wy) : null, { notify: false });
    }
  }

  return {
    show(route) {
      const first = !model;
      if (first) init();
      active = true;
      view.resize();
      sizeTimeline();
      apply(first, route.params);
      lastPlace = null;
      lastFeed = '';
      updateHud();
      view.invalidate();
      drawTl();
      if (!first || Object.keys(route.params).length === 0) pushParams();
    },
    hide() {
      if (!model) return;
      if (state.playing) syncPlay(false);
      active = false;
      closeDetail();
      hideTip();
      closeShot();
      toastTimers.forEach(clearTimeout);
      toastTimers.clear();
      $('toasts').replaceChildren();
      cancelAnimationFrame(raf);
      raf = 0;
    },
  };
}
