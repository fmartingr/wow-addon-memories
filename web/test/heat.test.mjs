import { test } from 'node:test';
import assert from 'node:assert/strict';
import { binGrid, blur, colourise, layerById, LAYERS, layerPoints, rampTable } from '../lib/heat.mjs';
import { buildModel } from '../lib/model.mjs';

const char = { sessions: [{ start: 1000, last: 5000 }] };
const at = { m: 1438, x: 5000, y: 5000 };
const steps = [
  { k: 'ki', t: 1010, ...at }, { k: 'ki', t: 1011, ...at }, { k: 'ki', t: 1012, m: null, x: null, y: null },
  { k: 'de', t: 1020, ...at }, { k: 'hc', t: 1021, ...at },
  { k: 'ga', t: 1030, prof: 'Mining', ...at }, { k: 'ga', t: 1031, prof: 'Herbalism', ...at }, { k: 'ga', t: 1032, prof: 'Skinning', ...at },
  { k: 'ga', t: 1033, prof: 'Fishing', ...at }, { k: 'ga', t: 1034, ...at }, { k: 'ga', t: 1035, prof: 'Mining', m: null },
  { k: 'fs', t: 1040, ...at }, { k: 'qt', t: 1050, ...at }, { k: 'lo', t: 1060, ...at }, { k: 'op', t: 1061, ...at },
];
const trail = [
  { m: 1438, pts: [[1000, 100, 100, ''], [1010, 200, 100, ''], [1100, 300, 100, '']] },
  { m: 1438, pts: [[1200, 900, 900, '']] },
  { m: 99999, pts: [[1300, 1, 1, ''], [1301, 1, 1, '']] },
];
const model = buildModel(char, steps, trail);

test('layerPoints counts the records of each layer and the ones with no map position', () => {
  const n = (id, o) => {
    const p = layerPoints(model, id, o);
    return [p.count, p.unplaced, p.wx.length, p.w.length];
  };
  assert.deepEqual(n('kills'), [2, 1, 2, 2]);
  assert.deepEqual(n('deaths'), [2, 0, 2, 2]);
  assert.deepEqual(n('fishing'), [1, 0, 1, 1]);
  assert.deepEqual(n('quests'), [1, 0, 1, 1]);
  assert.deepEqual(n('loot'), [2, 0, 2, 2]);
  assert.deepEqual(n('gathering'), [5, 1, 5, 5]);
});

test('the gathering filters keep their profession', () => {
  const c = (prof) => layerPoints(model, 'gathering', { prof }).count;
  assert.equal(c('all'), 5);
  assert.equal(c(undefined), 5);
  assert.equal(c('mining'), 1);
  assert.equal(c('herbalism'), 1);
  assert.equal(c('skinning'), 1);
  assert.equal(c('other'), 2);
  assert.equal(layerPoints(model, 'gathering', { prof: 'mining' }).unplaced, 1);
  assert.equal(layerPoints(model, 'kills', { prof: 'mining' }).count, 2, 'prof is ignored on another layer');
});

test('presence weighs the seconds to the next point, at most 30, and 2 at a chunk end', () => {
  const p = layerPoints(model, 'presence');
  assert.equal(p.count, 4);
  assert.deepEqual([...p.w], [10, 30, 2, 2]);
  assert.equal(p.unplaced, 2);
});

test('an unknown layer is presence, and each layer has a colour', () => {
  assert.equal(layerById('nope').id, 'presence');
  assert.ok(LAYERS.every((l) => /^#[0-9a-f]{6}$/.test(l.colour)));
  assert.equal(layerPoints(buildModel(char, [], []), 'kills').count, 0);
});

const view = { x: 50, y: 50, s: 4, w: 100, h: 80 };
const pts = (list) => ({ count: list.length, wx: Float32Array.from(list.map((p) => p[0])), wy: Float32Array.from(list.map((p) => p[1])), w: Float32Array.from(list.map((p) => p[2])) });

test('binGrid puts a point in the right cell and skips points outside the view', () => {
  const g = binGrid(pts([[50, 50, 3], [50, 50, 2], [1000, 1000, 9], [-1000, 5, 9]]), view, 10);
  assert.equal(g.cols, 10);
  assert.equal(g.rows, 8);
  assert.equal(g.data[4 * 10 + 5], 5);
  assert.equal(g.max, 5);
  assert.equal(g.data.reduce((a, b) => a + b, 0), 5);
});

test('binGrid keeps the sum of the weights that are on the screen', () => {
  const list = Array.from({ length: 500 }, (_, i) => [40 + (i % 20), 40 + (i % 13), 1 + (i % 3)]);
  const g = binGrid(pts(list), view, 6);
  assert.equal(g.data.reduce((a, b) => a + b, 0), list.reduce((a, p) => a + p[2], 0));
});

test('all points in one cell give a max above 0 and no division by zero', () => {
  const g = binGrid(pts([[50, 50, 1], [50.1, 50.1, 1]]), view, 6);
  assert.equal(g.max, 2);
  const out = colourise(g, rampTable('#ff0000'));
  assert.ok(out.some((v) => v > 0));
  assert.equal(colourise({ cols: 2, rows: 2, data: new Float32Array(4), max: 0 }, rampTable('#ff0000')).every((v) => v === 0), true);
});

test('blur keeps the sum within 1 percent for a point away from the edge', () => {
  const g = binGrid(pts([[50, 50, 100]]), view, 6);
  const b = blur(g, 2);
  const sum = b.data.reduce((a, c) => a + c, 0);
  assert.ok(Math.abs(sum - 100) / 100 < 0.01, `sum ${sum}`);
  assert.ok(b.max < g.max);
  assert.equal(g.data.reduce((a, c) => a + c, 0), 100, 'the input grid is not changed');
  assert.equal(blur({ cols: 1, rows: 1, data: new Float32Array(1), max: 0 }, 2).max, 0);
});

test('colourise gives alpha 0 for 0 and the light tip for max', () => {
  const table = rampTable('#ff0000');
  const grid = { cols: 3, rows: 1, data: Float32Array.from([0, 1, 100]), max: 100 };
  const out = colourise(grid, table);
  assert.equal(out[3], 0);
  assert.ok(out[7] > 0 && out[7] < 255);
  assert.equal(out[11], 255);
  assert.ok(out[9] > 150, 'the tip is lighter than the hue');
  assert.deepEqual([...table.slice(0, 4)], [255, 0, 0, 0]);
});

test('1,000,000 points bin and blur in under 2 seconds', () => {
  const n = 1_000_000;
  const big = { count: n, wx: new Float32Array(n), wy: new Float32Array(n), w: new Float32Array(n).fill(1) };
  for (let i = 0; i < n; i++) {
    big.wx[i] = 40 + (i % 1000) / 50;
    big.wy[i] = 40 + (i % 777) / 50;
  }
  const t0 = performance.now();
  const g = binGrid(big, { x: 50, y: 50, s: 10, w: 800, h: 600 }, 6);
  colourise(blur(g, 2), rampTable('#ffd100'));
  const ms = performance.now() - t0;
  assert.ok(ms < 2000, `${ms} ms`);
  assert.equal(g.data.reduce((a, b) => a + b, 0), n);
});
