// The Journey map tab: the world map with the whole trail and the event markers.
import { clamp } from '../lib/format.mjs';
import { boundsOf } from '../lib/geo.mjs';
import { buildModel, CAT, FLAG } from '../lib/model.mjs';
import { ZONES } from '../zones.mjs';
import { icon } from './icons.mjs';
import { MapView } from './mapview.mjs';

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

// drawTrail strokes the trail in two passes: a dark casing, then the colour. A line breaks between chunks, at a gap of
// more than 30 played seconds, and at a jump on the map. It skips the chunks that are off the screen and the points that
// are less than 1.2 px from the last one drawn, so that a trail of a million points costs one pass over what is visible.
export function drawTrail(ctx, view, model, bounds, uptoC = Infinity) {
  const P = model.points;
  const n = P.chunkStart.length - 1;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const sx = (wx) => (wx - view.x) * view.s + view.w / 2;
  const sy = (wy) => (wy - view.y) * view.s + view.h / 2;
  for (const pass of [0, 1]) {
    for (let ci = 0; ci < n; ci++) {
      const b = ci * 4;
      if (sx(bounds[b + 1]) < -10 || sx(bounds[b]) > view.w + 10 || sy(bounds[b + 3]) < -10 || sy(bounds[b + 2]) > view.h + 10) continue;
      let run = null;
      let px = 0, py = 0, last = -1;
      for (let i = P.chunkStart[ci]; i < P.chunkStart[ci + 1]; i++) {
        if (P.c[i] > uptoC) break;
        const x = sx(P.wx[i]), y = sy(P.wy[i]);
        const cut =
          last < 0 || P.c[i] - P.c[last] > 30 || Math.hypot(P.lx[i] - P.lx[last], P.ly[i] - P.ly[last]) > 400 + (P.f[i] & FLAG.t ? 1000 : 0);
        const lastOfChunk = i === P.chunkStart[ci + 1] - 1;
        if (!cut && !lastOfChunk && P.f[i] === P.f[last] && Math.abs(x - px) + Math.abs(y - py) < 1.2) continue;
        const colour = pass ? trailColour(P.f[i]) : 'rgba(20,10,2,0.85)';
        const dashed = (P.f[i] & FLAG.t) !== 0;
        const style = colour + dashed;
        if (cut || style !== run) {
          if (run !== null) ctx.stroke();
          ctx.beginPath();
          ctx.strokeStyle = colour;
          ctx.lineWidth = pass ? 2.2 : 4.4;
          ctx.setLineDash(dashed ? [6, 5] : []);
          if (!cut) ctx.moveTo(px, py);
          else ctx.moveTo(x, y);
          if (!cut) ctx.lineTo(x, y);
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

// drawMarks draws the event markers that pass the filter, and returns the hit list [{ x, y, r, ev }].
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

export function createJourneyTab(panel, ctx) {
  const $ = (id) => panel.querySelector('#' + id);
  const canvas = $('journeyMap');
  let model = null;
  let bounds = null;
  let view = null;
  let params = {};
  let shown = false;

  const notify = (cam) => {
    $('zLevel').textContent = view.levelName();
    if (!shown) return;
    params = { ...params, x: cam.x, y: cam.y, z: cam.s };
    ctx.setParams('journey', params);
  };

  function init() {
    model = buildModel(ctx.data.char, ctx.data.steps, ctx.data.trail);
    bounds = chunkBounds(model.points);
    view = new MapView(canvas, { world: globalThis.WORLD ?? null, zones: ZONES, onCamera: notify });
    view.draw((c, v) => {
      drawTrail(c, v, model, bounds);
      drawMarks(c, v, model, {});
    });
    $('zIn').addEventListener('click', () => view.stepZoom(1));
    $('zOut').addEventListener('click', () => view.stepZoom(-1));
    $('zWorld').addEventListener('click', () => view.fitWorld());
  }

  // The camera of a link, else the bounds of the trail, else the world.
  function placeCamera(p) {
    const fit = model.points.count ? boundsOf(model.points.wx, model.points.wy) : null;
    if (Number.isFinite(p.x) && Number.isFinite(p.y) && Number.isFinite(p.z)) view.setCamera({ x: p.x, y: p.y, s: p.z }, { notify: false });
    else view.fitBounds(fit, { notify: false });
    $('zLevel').textContent = view.levelName();
  }

  return {
    show(route) {
      shown = false;
      if (!model) init();
      view.resize();
      params = { ...route.params };
      placeCamera(params);
      shown = true;
      view.invalidate();
    },
    hide() {
      shown = false;
    },
  };
}
