import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boundsOf, toWorld, zoneAt } from '../lib/geo.mjs';
import { CONT, ZONES } from '../zones.mjs';

const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} vs ${b}`);

test('toWorld maps the corners of Teldrassil and Elwynn onto their rectangles', () => {
  for (const id of [1438, 1429]) {
    const r = ZONES[id].rect;
    const [ax, ay] = toWorld(id, 0, 0);
    const [bx, by] = toWorld(id, 10000, 10000);
    near(ax, r[0]); near(ay, r[2]); near(bx, r[1]); near(by, r[3]);
    const [cx, cy] = toWorld(id, 5000, 5000);
    near(cx, (r[0] + r[1]) / 2); near(cy, (r[2] + r[3]) / 2);
  }
});

test('toWorld gives null for an unknown map and for null coordinates', () => {
  assert.equal(toWorld(99999, 1, 1), null);
  assert.equal(toWorld(null, 1, 1), null);
  assert.equal(toWorld(1438, null, 5), null);
  assert.equal(toWorld(1438, 5, undefined), null);
  assert.equal(toWorld(1438, NaN, 5), null);
});

test('zoneAt picks the zone over the continent, and the continent outside every zone', () => {
  const [x, y] = toWorld(1438, 5000, 5000);
  assert.equal(zoneAt(x, y), 1438);
  const [cx, cy] = toWorld(1414, 100, 100);
  assert.ok([1414, 1411, 1412, 1413].includes(zoneAt(cx, cy)));
  assert.equal(zoneAt(-1000, -1000), null);
  const k = CONT[1414];
  assert.notEqual(zoneAt(k[0] + 0.1, k[2] + 0.1), undefined);
});

test('boundsOf', () => {
  assert.equal(boundsOf(new Float32Array(0), new Float32Array(0)), null);
  assert.deepEqual(boundsOf([5, 1, 9], [2, 8, 3]), [1, 9, 2, 8]);
  assert.deepEqual(boundsOf([5], [2]), [5, 5, 2, 2]);
});
