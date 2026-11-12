import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildModel } from '../lib/model.mjs';
import { chunkBounds, drawMarks, drawTrail } from '../ui/journey.mjs';

// A canvas context that counts its drawing calls.
const fakeCtx = () => {
  const calls = { stroke: 0, lineTo: 0, moveTo: 0 };
  const noop = () => {};
  return new Proxy({ calls }, {
    get: (t, k) => (k in t ? t[k] : k === 'stroke' ? () => calls.stroke++ : k === 'lineTo' ? () => calls.lineTo++ : k === 'moveTo' ? () => calls.moveTo++ : noop),
    set: () => true,
  });
};

const char = { sessions: [{ start: 1000, last: 2000 }] };
const view = { x: 500, y: 330, s: 1.5, w: 800, h: 600, rel: 1.5 };

test('chunkBounds holds the bounds of each chunk', () => {
  const m = buildModel(char, [], [
    { m: 1438, pts: [[1000, 0, 0, ''], [1001, 10000, 10000, '']] },
    { m: 1438, pts: [[1100, 5000, 5000, '']] },
  ]);
  const b = chunkBounds(m.points);
  assert.equal(b.length, 8);
  assert.ok(b[1] > b[0] && b[3] > b[2]);
  assert.equal(b[4], b[5]);
});

test('drawTrail draws a trail and skips chunks that are off the screen', () => {
  const m = buildModel(char, [], [{ m: 1438, pts: [[1000, 0, 0, ''], [1002, 5000, 5000, ''], [1004, 10000, 10000, 'c']] }]);
  const b = chunkBounds(m.points);
  const ctx = fakeCtx();
  drawTrail(ctx, { ...view, x: m.points.wx[0], y: m.points.wy[0] }, m, b);
  assert.ok(ctx.calls.stroke > 0);
  const off = fakeCtx();
  drawTrail(off, { ...view, x: 5000, y: 5000 }, m, b);
  assert.equal(off.calls.stroke, 0);
});

test('drawTrail stops at the playhead clock', () => {
  const m = buildModel(char, [], [{ m: 1438, pts: [[1000, 4000, 4000, ''], [1010, 4100, 4000, ''], [1020, 4200, 4000, '']] }]);
  const b = chunkBounds(m.points);
  const all = fakeCtx(), part = fakeCtx();
  const v = { ...view, x: m.points.wx[0], y: m.points.wy[0], s: 40 };
  drawTrail(all, v, m, b);
  drawTrail(part, v, m, b, 10);
  assert.ok(part.calls.lineTo < all.calls.lineTo);
});

test('drawTrail draws a million points in under a second when they are off the screen or dense', () => {
  const pts = Array.from({ length: 20000 }, (_, i) => [1000 + (i % 900), 5000 + (i % 7) * 10, 5000 + (i % 5) * 10, '']);
  const big = Array.from({ length: 50 }, () => ({ m: 1438, pts }));
  const m = buildModel(char, [], big);
  const b = chunkBounds(m.points);
  const ctx = fakeCtx();
  const t0 = performance.now();
  drawTrail(ctx, { x: m.points.wx[0], y: m.points.wy[0], s: 0.6, w: 800, h: 600, rel: 1 }, m, b);
  assert.ok(performance.now() - t0 < 1000);
});

test('drawMarks returns hits for the visible marks that pass the filter', () => {
  const steps = [{ k: 'lv', t: 1010, level: 2, m: 1438, x: 5000, y: 5000 }, { k: 'de', t: 1020, m: 1438, x: 5000, y: 5000 }];
  const m = buildModel(char, steps, []);
  const v = { x: m.marks[0].wx, y: m.marks[0].wy, s: 5, w: 800, h: 600, rel: 3 };
  assert.equal(drawMarks(fakeCtx(), v, m, {}).length, 2);
  assert.equal(drawMarks(fakeCtx(), v, m, { danger: false }).length, 1);
  assert.equal(drawMarks(fakeCtx(), v, m, {}, 5).length, 0);
  assert.equal(drawMarks(fakeCtx(), { ...v, x: 0, y: 0 }, m, {}).length, 0);
});

class FakePath {
  moveTo() {}
  lineTo() {}
  closePath() {}
}

test('drawTimeline returns hits for the markers and the purse band, in the full and the compact form', async () => {
  globalThis.Path2D = FakePath;
  const { drawTimeline } = await import('../ui/journey.mjs');
  const c = { ...char, addons: { Memories_Economy: { snap: { 5: { money: 500 } } }, Memories: { snap: { 5: { t: 1100 } } } } };
  const steps = [
    { k: 'lv', t: 1010, level: 2 }, { k: 'de', t: 1020 }, { k: 'dn', t: 1030, name: 'D' }, { k: 'dx', t: 1060 }, { k: 'ss', t: 1070 },
    { k: 'mn', t: 1080, delta: 20 }, { k: 'di', t: 1090 },
  ];
  const m = buildModel(c, steps, []);
  const ctx = new Proxy({}, { get: (t, k) => (k === 'createLinearGradient' ? () => ({ addColorStop() {} }) : () => {}), set: () => true });
  const full = drawTimeline(ctx, 900, 224, 1, m, { c: 50, show: { danger: false } });
  assert.ok(full.hits.some((h) => h.ev.k === 'lv'));
  assert.ok(!full.hits.some((h) => h.ev.k === 'de'), 'a hidden category has no hit');
  assert.ok(full.hits.some((h) => h.ev.k === 'dn'), 'a dungeon span has a hit');
  assert.ok(!full.hits.some((h) => h.ev.k === 'di'));
  assert.ok(full.gold.y1 > full.gold.y0 && full.x1 > full.x0);
  const compact = drawTimeline(ctx, 360, 64, 2, m, { c: 0, show: {} });
  assert.ok(compact.hits.length >= 3);
  assert.ok(compact.gold.y1 - compact.gold.y0 >= 12);
});

test('the ruler step grows with the length of the journey', async () => {
  const { rulerStep } = await import('../ui/journey.mjs');
  assert.equal(rulerStep(3600, 1000), 300);
  assert.equal(rulerStep(8 * 3600, 800), 3600);
  const long = rulerStep(864000, 1000);
  assert.ok(long >= 86400 && (long * 1000) / 864000 >= 64);
  assert.ok((rulerStep(1e9, 1000) * 1000) / 1e9 >= 64);
});
