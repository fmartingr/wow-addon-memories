// Pure playback logic: the playhead, the position, the purse and the level at a clock value, and the events that the
// playhead passes. The clock is the played seconds of the journey (see buildClock).
import { clamp } from './format.mjs';
import { FLAG } from './model.mjs';

export const BASE_RATE = 40; // played seconds for each real second at 1x
export const SPEEDS = [1, 2, 4, 8, 16];

// advance moves the playhead by dt real seconds and stops at the end. It returns the next state.
export function advance(state, dtSec, total) {
  const c = Math.min(total, state.c + Math.max(0, dtSec) * BASE_RATE * state.speed);
  return { ...state, c, playing: state.playing && c < total };
}

// The last index i of the ascending numbers a(i) with a(i) <= v, or -1.
function upperIndex(length, a, v) {
  let lo = 0, hi = length - 1, r = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (a(mid) <= v) {
      r = mid;
      lo = mid + 1;
    } else hi = mid - 1;
  }
  return r;
}

export function goldAt(model, c) {
  const i = upperIndex(model.gold.length, (k) => model.gold[k].c, c);
  return model.gold[Math.max(0, i)].v;
}

export function levelAt(model, c) {
  const i = upperIndex(model.levels.length, (k) => model.levels[k].c0, c);
  return model.levels[Math.max(0, i)].level;
}

// The last element of arr (ascending by c) with c <= value, or null.
export function lastBefore(arr, c) {
  const i = upperIndex(arr.length, (k) => arr[k].c, c);
  return i < 0 ? null : arr[i];
}

export const spanAt = (model, c) => model.spans.find((s) => c >= s.c0 && c <= s.c1) ?? null;

export const eventId = (e) => e.t + '.' + e.k;

export function findEvent(model, id) {
  const dot = String(id).indexOf('.');
  if (dot < 1) return null;
  const t = Number(id.slice(0, dot)), k = id.slice(dot + 1);
  return model.events.find((e) => e.t === t && e.k === k) ?? null;
}

// The events with from <= c < to, so a playhead that stops on an event does not report it twice.
export function crossed(model, from, to) {
  if (!(to > from)) return [];
  const ev = model.events;
  let lo = 0, hi = ev.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (ev[mid].c < from) lo = mid + 1;
    else hi = mid;
  }
  const out = [];
  for (let i = lo; i < ev.length && ev[i].c < to; i++) out.push(ev[i]);
  return out;
}

// The zone and subzone at clock c.
export function placeAt(model, c) {
  const z = lastBefore(model.zo, c);
  const s = lastBefore(model.sz, c);
  return { zone: z ? z.zone : '', sub: s && z && s.c >= z.c ? s.sub : '' };
}

// zoneChange returns the new place when the zone or subzone at `to` differs from the one at `from`, else null.
export function zoneChange(model, from, to) {
  const a = placeAt(model, from), b = placeAt(model, to);
  return a.zone === b.zone && a.sub === b.sub ? null : b;
}

// The position of the player at clock c, as { wx, wy, m, f, lx, ly } with f the flag bits, or null with no trail.
// The recorder drops samples while the player stands still, so a gap is dwell time and the move happens at its end.
// Between two chunks the player holds at the end of the first.
export function posAt(model, c) {
  const P = model.points;
  if (!P.count) return null;
  const at = (i, f = P.f[i]) => ({ wx: P.wx[i], wy: P.wy[i], m: P.m[i], f, lx: P.lx[i], ly: P.ly[i] });
  if (c <= P.c[0]) return at(0);
  if (c >= P.c[P.count - 1]) return at(P.count - 1);
  const lo = upperIndex(P.count, (k) => P.c[k], c);
  const hi = lo + 1;
  const cs = P.chunkStart;
  const chunkEnd = cs[upperIndex(cs.length, (k) => cs[k], lo) + 1];
  if (hi >= chunkEnd) return at(lo);
  const dt = P.c[hi] - P.c[lo];
  const dl = Math.hypot(P.lx[hi] - P.lx[lo], P.ly[hi] - P.ly[lo]);
  const per = P.f[lo] & FLAG.t ? 110 : P.f[lo] & FLAG.g ? 44 : 30;
  const travel = Math.min(dt, 2 * Math.max(1, dl / per));
  if (travel <= 0) return at(lo);
  const u = clamp((c - (P.c[hi] - travel)) / travel, 0, 1);
  const lerp = (a, b) => a + (b - a) * u;
  return {
    wx: lerp(P.wx[lo], P.wx[hi]), wy: lerp(P.wy[lo], P.wy[hi]), m: u > 0.5 ? P.m[hi] : P.m[lo], f: P.f[lo],
    lx: lerp(P.lx[lo], P.lx[hi]), ly: lerp(P.ly[lo], P.ly[hi]),
  };
}
