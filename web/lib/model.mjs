// buildModel turns the journey into what the map and the timeline draw: the played clock, the trail points in world
// units, the events with their position, and the purse over time.
import { toWorld } from './geo.mjs';

// Marker category of each kind, and the lanes of the timeline as [category, icon kind]. The name of a lane is
// lane.<category> in the catalog.
export const CAT = {
  lv: 'level', de: 'danger', cc: 'danger', pk: 'danger', dn: 'dungeon', bo: 'dungeon', qt: 'quest', di: 'quest', hs: 'quest', tx: 'quest',
  ss: 'shot', ga: 'find', fs: 'find', op: 'find', pp: 'find', rl: 'find', rp: 'world', qa: 'world', hb: 'world', fp: 'world', bk: 'world',
  pt: 'world', rc: 'world',
};
export const LANES = [
  ['level', 'lv'], ['danger', 'de'], ['dungeon', 'dn'], ['quest', 'qt'], ['find', 'ga'], ['world', 'rp'], ['shot', 'ss'],
];

// Bits of the trail flags: ghost, taxi, combat, mounted.
export const FLAG = { g: 1, t: 2, c: 4, m: 8 };
const flagBits = (f) => {
  let bits = 0;
  if (typeof f === 'string') for (const ch of f) bits |= FLAG[ch] ?? 0;
  return bits;
};

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

export function buildClock(char) {
  const sessions = [...(char?.sessions ?? [])].filter((s) => isNum(s.start)).sort((a, b) => a.start - b.start);
  let acc = 0;
  const list = sessions.map((s) => {
    const end = Math.max(isNum(s.last) ? s.last : s.start, s.start);
    const out = { start: s.start, end, c0: acc, how: s.how };
    acc += end - s.start;
    return out;
  });
  const total = Math.max(acc, 1);
  // The clock value of a record time. A time between sessions belongs to the session before it; a time before the first
  // session gives 0; a time after the last gives the end of that session.
  const clockAt = (t) => {
    if (!list.length || !isNum(t)) return 0;
    let lo = 0, hi = list.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (list[mid].start <= t) lo = mid;
      else hi = mid - 1;
    }
    const s = list[lo];
    return s.c0 + Math.min(Math.max(t - s.start, 0), s.end - s.start);
  };
  return { sessions: list, total, clockAt };
}

function buildPoints(trail, clockAt) {
  const chunks = (trail ?? [])
    .map((ch) => ({ ch, pts: ch.pts ?? ch.points ?? [] }))
    .filter((c) => c.pts.length);
  chunks.sort((a, b) => (a.pts[0][0] ?? 0) - (b.pts[0][0] ?? 0));
  let unplaced = 0;
  let count = 0;
  const placed = chunks.filter((c) => {
    if (toWorld(c.ch.m, 0, 0)) {
      count += c.pts.length;
      return true;
    }
    unplaced += c.pts.length;
    return false;
  });
  const wx = new Float32Array(count), wy = new Float32Array(count), c = new Float64Array(count);
  const m = new Int32Array(count), lx = new Float32Array(count), ly = new Float32Array(count), f = new Uint8Array(count);
  const chunkStart = new Uint32Array(placed.length + 1);
  let n = 0;
  placed.forEach((chunk, ci) => {
    chunkStart[ci] = n;
    for (const p of chunk.pts) {
      const w = toWorld(chunk.ch.m, p[1], p[2]);
      if (!w) {
        unplaced++;
        continue;
      }
      wx[n] = w[0]; wy[n] = w[1]; c[n] = clockAt(p[0]);
      m[n] = chunk.ch.m; lx[n] = p[1]; ly[n] = p[2]; f[n] = flagBits(p[3]);
      n++;
    }
  });
  chunkStart[placed.length] = n;
  return { count: n, wx: wx.subarray(0, n), wy: wy.subarray(0, n), c: c.subarray(0, n), m: m.subarray(0, n), lx: lx.subarray(0, n), ly: ly.subarray(0, n), f: f.subarray(0, n), chunkStart, unplaced };
}

// The purse over time as steps { c, v }. It starts from the Economy snapshot of the highest level that has money, as
// deriveSummary does, and walks back from the anchor before it.
function buildGold(char, events, clockAt) {
  const snaps = char?.addons?.Memories_Economy?.snap ?? {};
  const level = Object.keys(snaps).map(Number).filter((l) => isNum(snaps[l]?.money)).sort((a, b) => b - a)[0];
  const deltas = events.filter((e) => e.k === 'mn' && isNum(e.delta));
  const snapT = level === undefined ? undefined : char.addons?.Memories?.snap?.[level]?.t ?? events.find((e) => e.k === 'lv' && e.level === level)?.t;
  const anchored = level !== undefined && isNum(snapT);
  const about = !anchored;
  const anchorC = anchored ? clockAt(snapT) : 0;
  const anchorMoney = anchored ? snaps[level].money : 0;
  const before = deltas.filter((e) => (anchored ? e.t <= snapT : false));
  const after = deltas.filter((e) => (anchored ? e.t > snapT : true));
  // Before the anchor: walk back from the anchor by taking each delta off, newest first.
  const back = [];
  let v = anchorMoney;
  for (let i = before.length - 1; i >= 0; i--) {
    back.push({ c: before[i].c, v });
    v = Math.max(0, v - before[i].delta);
  }
  const gold = [{ c: 0, v }];
  for (let i = back.length - 1; i >= 0; i--) gold.push({ c: back[i].c, v: back[i].v });
  if (anchored) gold.push({ c: anchorC, v: anchorMoney });
  let bal = anchorMoney;
  for (const e of after) {
    bal = Math.max(0, bal + e.delta);
    gold.push({ c: e.c, v: bal });
  }
  let goldMax = 1;
  for (const g of gold) if (g.v > goldMax) goldMax = g.v;
  return { gold, goldAbout: about, goldMax };
}

export function buildModel(char, steps, trail) {
  const { sessions, total, clockAt } = buildClock(char);
  const events = (steps ?? []).map((s) => {
    const w = toWorld(s.m, s.x, s.y);
    return { ...s, c: clockAt(s.t), wx: w ? w[0] : null, wy: w ? w[1] : null };
  });
  const points = buildPoints(trail, clockAt);
  const spans = [];
  for (const dn of events.filter((e) => e.k === 'dn')) {
    const dx = events.find((e) => e.k === 'dx' && e.t >= dn.t);
    spans.push({ c0: dn.c, c1: dx ? dx.c : total, name: dn.name, dn, dx });
  }
  const levels = [{ c0: 0, level: char?.first?.level ?? 1 }];
  for (const e of events) if (e.k === 'lv' && isNum(e.level)) levels.push({ c0: e.c, level: e.level });
  levels.forEach((l, i) => {
    l.c1 = i + 1 < levels.length ? levels[i + 1].c0 : total;
  });
  const marks = events.filter((e) => CAT[e.k] && !(e.k === 'di' && !e.area) && e.wx !== null);
  return {
    char, sessions, total, clockAt, events, points, spans, levels, marks,
    unplaced: points.unplaced,
    zo: events.filter((e) => e.k === 'zo'),
    sz: events.filter((e) => e.k === 'sz'),
    ...buildGold(char, events, clockAt),
  };
}
