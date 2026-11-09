import { test } from 'node:test';
import assert from 'node:assert/strict';
import { clampCamera, fitBounds, fitScale, fitWorld, levelName, MAX_S, nextZoom, pinchCamera, s2w, w2s, zoomAround, zoomSteps } from '../ui/mapview.mjs';
import { H, W } from '../zones.mjs';

const near = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) < eps, `${a} vs ${b}`);
const v = { x: 300, y: 200, s: 2, w: 800, h: 600 };

test('w2s and s2w are inverse', () => {
  const [sx, sy] = w2s(v, 123.4, 56.7);
  const [wx, wy] = s2w(v, sx, sy);
  near(wx, 123.4); near(wy, 56.7);
  assert.deepEqual(w2s(v, v.x, v.y), [v.w / 2, v.h / 2]);
  const [ax, ay] = s2w(v, 10, 20);
  const [bx, by] = w2s(v, ax, ay);
  near(bx, 10); near(by, 20);
});

test('zoomAround keeps the anchor point fixed', () => {
  const cam = { x: 500, y: 330, s: 1.2 };
  const before = s2w({ ...cam, w: 800, h: 600 }, 250, 180);
  const next = zoomAround(cam, 3, 250, 180, 800, 600);
  const after = s2w({ ...next, w: 800, h: 600 }, 250, 180);
  near(next.s, 3);
  near(before[0], after[0]); near(before[1], after[1]);
  const out = zoomAround(next, 1.5, 250, 180, 800, 600);
  const back = s2w({ ...out, w: 800, h: 600 }, 250, 180);
  near(before[0], back[0], 1e-6); near(before[1], back[1], 1e-6);
});

test('zoomAround limits the scale', () => {
  assert.equal(zoomAround({ x: 500, y: 330, s: 1 }, 9999, 0, 0, 800, 600).s, MAX_S);
  near(zoomAround({ x: 500, y: 330, s: 1 }, 0.0001, 0, 0, 800, 600).s, fitScale(800, 600) * 0.9);
});

test('clampCamera keeps the world in view', () => {
  const c = clampCamera({ x: -500, y: 9999, s: 4 }, 800, 600);
  const hw = 800 / 4 / 2, hh = 600 / 4 / 2;
  assert.ok(c.x - hw >= -1e-9 && c.x + hw <= W + 1e-9);
  assert.ok(c.y - hh >= -1e-9 && c.y + hh <= H + 1e-9);
  const wide = clampCamera({ x: 5, y: 5, s: fitScale(800, 600) * 0.9 }, 800, 600);
  near(wide.x, W / 2);
  const bad = clampCamera({ x: NaN, y: undefined, s: NaN }, 800, 600);
  assert.ok(Number.isFinite(bad.x) && Number.isFinite(bad.y) && bad.s > 0);
});

test('fitWorld frames the whole world on a phone and on a desktop', () => {
  for (const [w, h] of [[360, 500], [1440, 700]]) {
    const c = fitWorld(w, h);
    assert.deepEqual([c.x, c.y], [W / 2, H / 2]);
    assert.ok(W * c.s <= w + 1e-9 && H * c.s <= h + 1e-9);
    assert.ok(Math.abs(W * c.s - w) < 1e-6 || Math.abs(H * c.s - h) < 1e-6);
    assert.deepEqual(clampCamera(c, w, h).x, W / 2);
  }
  assert.ok(fitScale(0, 0) > 0);
});

test('fitBounds frames bounds, and a single point gets a scale in range', () => {
  const c = fitBounds([100, 200, 100, 150], 800, 600);
  near(c.x, 150); near(c.y, 125);
  assert.ok(c.s <= MAX_S && c.s > 0);
  const p = fitBounds([300, 300, 300, 300], 800, 600);
  assert.ok(p.s <= MAX_S && Number.isFinite(p.s));
  near(p.x, 300);
});

test('zoom steps and level names', () => {
  const steps = zoomSteps(800, 600);
  assert.ok(steps.every((s, i) => i === 0 || s > steps[i - 1]));
  assert.equal(steps.at(-1), MAX_S);
  const f = fitScale(800, 600);
  assert.equal(nextZoom(f, 1, 800, 600), steps[1]);
  assert.equal(nextZoom(f, -1, 800, 600), steps[0]);
  assert.equal(nextZoom(MAX_S, 1, 800, 600), MAX_S);
  assert.equal(levelName(f, 800, 600), 'World');
  assert.equal(levelName(f * 2.6, 800, 600), 'Continent');
  assert.equal(levelName(f * 10, 800, 600), 'Zone');
});

test('pinch scales by the distance ratio around the midpoint', () => {
  const start = { x: 500, y: 330, s: 2 };
  const from = [{ x: 300, y: 300 }, { x: 500, y: 300 }];
  const to = [{ x: 200, y: 300 }, { x: 600, y: 300 }];
  const c = pinchCamera(start, 800, 600, from, to);
  near(c.s, 4);
  const before = s2w({ ...start, w: 800, h: 600 }, 400, 300);
  const after = s2w({ ...c, w: 800, h: 600 }, 400, 300);
  near(before[0], after[0], 1e-6); near(before[1], after[1], 1e-6);
  const moved = pinchCamera(start, 800, 600, from, [{ x: 320, y: 300 }, { x: 520, y: 300 }]);
  near(moved.s, 2);
  assert.ok(moved.x < start.x);
  assert.ok(Number.isFinite(pinchCamera(start, 800, 600, [{ x: 1, y: 1 }, { x: 1, y: 1 }], to).s));
});
