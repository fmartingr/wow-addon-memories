// Heat maps: the points of a layer, a binning on the screen grid, a blur and a colour ramp. The code works on typed
// arrays in one pass, so that a trail of a million points costs one loop.

const hex = (c) => [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];

// colour: the hue of the layer. kinds: the journal kinds that the layer counts; presence has none (it uses the trail).
// The name of a layer is layer.<id> in the catalog.
export const LAYERS = [
  { id: 'presence', colour: '#ffd100', kinds: [] },
  { id: 'kills', colour: '#ff5a43', kinds: ['ki'] },
  { id: 'deaths', colour: '#c58cff', kinds: ['de', 'hc'] },
  { id: 'gathering', colour: '#35c9a0', kinds: ['ga'] },
  { id: 'fishing', colour: '#4fa8e0', kinds: ['fs'] },
  { id: 'quests', colour: '#f2a93b', kinds: ['qt'] },
  { id: 'loot', colour: '#9ad65f', kinds: ['lo', 'op'] },
];

export const layerById = (id) => LAYERS.find((l) => l.id === id) ?? LAYERS[0];

// The values are the English tokens that the addon writes to ga.prof. The label of a profession is prof.<id>.
export const PROFESSIONS = { mining: 'Mining', herbalism: 'Herbalism', skinning: 'Skinning' };

const keepProf = (e, prof) => {
  if (!prof || prof === 'all') return true;
  const known = Object.values(PROFESSIONS);
  return prof === 'other' ? !known.includes(e.prof) : e.prof === PROFESSIONS[prof];
};

// layerPoints returns { wx, wy, w, count, unplaced } for a layer. Presence weighs each trail point by the seconds to the
// next point of the same chunk, at most 30; the last point of a chunk weighs 2, the default trail rate. The other layers
// weigh 1 for each record. A record with no map position (inside an instance) counts as unplaced.
export function layerPoints(model, layerId, { prof } = {}) {
  const layer = layerById(layerId);
  if (layer.id === 'presence') {
    const P = model.points;
    const w = new Float32Array(P.count);
    const cs = P.chunkStart;
    for (let ci = 0; ci + 1 < cs.length; ci++) {
      const end = cs[ci + 1];
      for (let i = cs[ci]; i < end; i++) w[i] = i + 1 < end ? Math.min(30, Math.max(0, P.c[i + 1] - P.c[i])) : 2;
    }
    return { wx: P.wx, wy: P.wy, w, count: P.count, unplaced: model.unplaced };
  }
  const events = model.events.filter((e) => layer.kinds.includes(e.k) && (layer.id !== 'gathering' || keepProf(e, prof)));
  const placed = events.filter((e) => e.wx !== null);
  const wx = Float32Array.from(placed, (e) => e.wx);
  const wy = Float32Array.from(placed, (e) => e.wy);
  return { wx, wy, w: new Float32Array(placed.length).fill(1), count: placed.length, unplaced: events.length - placed.length };
}

// binGrid adds the weight of each point into a grid of cell x cell CSS pixels over the screen. view is { x, y, s, w, h }.
// A point outside the screen is skipped.
export function binGrid(points, view, cell = 6) {
  const cols = Math.max(1, Math.ceil(view.w / cell)), rows = Math.max(1, Math.ceil(view.h / cell));
  const data = new Float32Array(cols * rows);
  const ox = view.w / 2 - view.x * view.s, oy = view.h / 2 - view.y * view.s;
  let max = 0;
  for (let i = 0; i < points.count; i++) {
    const sx = points.wx[i] * view.s + ox, sy = points.wy[i] * view.s + oy;
    if (sx < 0 || sy < 0 || sx >= view.w || sy >= view.h) continue;
    const k = Math.floor(sy / cell) * cols + Math.floor(sx / cell);
    const v = (data[k] += points.w[i]);
    if (v > max) max = v;
  }
  return { cols, rows, data, max };
}

// One pass of a box blur along rows or columns, with zero outside the grid.
function boxPass(src, dst, cols, rows, radius, byRow) {
  const len = byRow ? cols : rows, lines = byRow ? rows : cols, size = 2 * radius + 1;
  const stride = byRow ? 1 : cols, step = byRow ? cols : 1;
  for (let line = 0; line < lines; line++) {
    const base = line * step;
    let sum = 0;
    for (let i = 0; i < Math.min(radius, len); i++) sum += src[base + i * stride];
    for (let i = 0; i < len; i++) {
      if (i + radius < len) sum += src[base + (i + radius) * stride];
      if (i - radius - 1 >= 0) sum -= src[base + (i - radius - 1) * stride];
      dst[base + i * stride] = sum / size;
    }
  }
}

// blur returns a new grid: 3 passes of a box blur on rows and columns, an approximation of a Gaussian.
export function blur(grid, radius = 2) {
  const { cols, rows } = grid;
  let a = Float32Array.from(grid.data), b = new Float32Array(a.length);
  for (let pass = 0; pass < 3; pass++) {
    boxPass(a, b, cols, rows, radius, true);
    boxPass(b, a, cols, rows, radius, false);
  }
  let max = 0;
  for (let i = 0; i < a.length; i++) if (a[i] > max) max = a[i];
  return { cols, rows, data: a, max };
}

// rampTable makes 256 RGBA entries for a layer colour: transparent, the colour, then a light tip.
export function rampTable(colour) {
  const [r, g, b] = hex(colour);
  const tip = [r, g, b].map((v) => v + (255 - v) * 0.7);
  const stops = [
    [0, [r, g, b, 0]],
    [0.3, [r, g, b, 120]],
    [0.7, [r, g, b, 225]],
    [1, [...tip, 255]],
  ];
  const out = new Uint8ClampedArray(256 * 4);
  for (let i = 0; i < 256; i++) {
    const t = i / 255;
    let k = 1;
    while (k < stops.length - 1 && t > stops[k][0]) k++;
    const [t0, c0] = stops[k - 1], [t1, c1] = stops[k];
    const u = (t - t0) / (t1 - t0);
    for (let j = 0; j < 4; j++) out[i * 4 + j] = c0[j] + (c1[j] - c0[j]) * u;
  }
  return out;
}

// colourise returns RGBA bytes for a grid. The ramp index is log1p(v) / log1p(max), so that one busy cell does not hide
// the rest. A cell with no weight is transparent.
export function colourise(grid, table) {
  const out = new Uint8ClampedArray(grid.cols * grid.rows * 4);
  const top = Math.log1p(grid.max);
  if (!(top > 0)) return out;
  for (let i = 0; i < grid.data.length; i++) {
    const v = grid.data[i];
    if (!(v > 1e-4)) continue;
    const idx = Math.min(255, Math.round((Math.log1p(v) / top) * 255)) * 4;
    out[i * 4] = table[idx];
    out[i * 4 + 1] = table[idx + 1];
    out[i * 4 + 2] = table[idx + 2];
    out[i * 4 + 3] = table[idx + 3];
  }
  return out;
}
