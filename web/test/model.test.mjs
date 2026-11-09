import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildClock, buildModel, CAT, FLAG } from '../lib/model.mjs';
import { ZONES } from '../zones.mjs';

const char = { first: { level: 1 }, sessions: [{ start: 1000, last: 1100 }, { start: 5000, last: 5050 }] };

test('the clock does not count the gap between sessions', () => {
  const { clockAt, total, sessions } = buildClock(char);
  assert.equal(total, 150);
  assert.deepEqual(sessions.map((s) => s.c0), [0, 100]);
  assert.equal(clockAt(1000), 0);
  assert.equal(clockAt(1060), 60);
  assert.equal(clockAt(3000), 100);
  assert.equal(clockAt(5000), 100);
  assert.equal(clockAt(5030), 130);
});

test('the clock before the first session and after the last', () => {
  const { clockAt } = buildClock(char);
  assert.equal(clockAt(5), 0);
  assert.equal(clockAt(99999), 150);
  assert.equal(clockAt(NaN), 0);
  const none = buildClock({});
  assert.equal(none.total, 1);
  assert.equal(none.clockAt(5), 0);
});

test('sessions sort by start, and a session with no end has length 0', () => {
  const { sessions, total } = buildClock({ sessions: [{ start: 50, last: 80 }, { start: 10 }, { start: 'x' }] });
  assert.deepEqual(sessions.map((s) => [s.start, s.end, s.c0]), [[10, 10, 0], [50, 80, 0]]);
  assert.equal(total, 30);
});

const trail = [
  { s: 5000, t: 5001, m: 1438, n: 2, pts: [[5001, 5000, 5000, 'm'], [5011, 5100, 5000, 'tc']] },
  { s: 1000, t: 1010, m: 1438, n: 2, pts: [[1010, 0, 0, '-'], [1020, 10000, 10000, 'g']] },
  { s: 1000, t: 1030, m: 99999, n: 3, pts: [[1030, 1, 1, ''], [1031, 1, 1, ''], [1032, 1, 1, '']] },
  { s: 1000, t: 1040, m: null, n: 1, pts: [[1040, null, null, '']] },
  { s: 1000, t: 1050, m: 1438, n: 2, pts: [[1050, null, 5, ''], [1060, 20, 20, '']] },
];

test('points are in world units, in time order, with chunk starts and an unplaced count', () => {
  const m = buildModel(char, [], trail);
  const p = m.points;
  assert.equal(p.count, 5);
  assert.deepEqual([...p.c], [10, 20, 60, 101, 111]);
  assert.deepEqual([...p.chunkStart], [0, 2, 3, 5]);
  assert.equal(m.unplaced, 5);
  assert.equal(p.f[1], FLAG.g);
  assert.equal(p.f[4], FLAG.t | FLAG.c);
  assert.ok(p.wx instanceof Float32Array && p.c instanceof Float64Array);
  assert.deepEqual([...p.m], [1438, 1438, 1438, 1438, 1438]);
  assert.ok(Math.abs(p.wx[0] - ZONES[1438].rect[0]) < 1e-3);
  assert.ok(Math.abs(p.wy[1] - ZONES[1438].rect[3]) < 1e-3);
});

test('a single point and no trail', () => {
  const one = buildModel(char, [], [{ m: 1438, pts: [[1010, 5000, 5000, '']] }]);
  assert.equal(one.points.count, 1);
  const none = buildModel(char, [], []);
  assert.equal(none.points.count, 0);
  assert.equal(none.unplaced, 0);
  assert.equal(buildModel(char, undefined, undefined).events.length, 0);
});

test('events carry the clock and their world position, null when not placed', () => {
  const steps = [
    { k: 'lv', t: 1010, level: 2, m: 1438, x: 5000, y: 5000 },
    { k: 'zo', t: 1020, zone: 'A', m: null, x: null, y: null },
    { k: 'di', t: 1030, area: null, m: 1438, x: 1, y: 1 },
    { k: 'di', t: 1031, area: 'Place', m: 1438, x: 1, y: 1 },
    { k: 'pl', t: 1040 },
  ];
  const m = buildModel(char, steps, []);
  assert.equal(m.events[0].c, 10);
  assert.ok(m.events[0].wx > 0);
  assert.equal(m.events[1].wx, null);
  assert.deepEqual(m.marks.map((e) => e.k + (e.area ?? '')), ['lv', 'diPlace']);
  assert.deepEqual(m.zo.map((e) => e.zone), ['A']);
  assert.equal(steps[0].c, undefined);
  assert.deepEqual(m.levels.map((l) => [l.c0, l.c1, l.level]), [[0, 10, 1], [10, 150, 2]]);
  assert.equal(CAT.lv, 'level');
});

test('dungeon spans run from dn to the next dx, or to the end', () => {
  const steps = [
    { k: 'dn', t: 1010, name: 'A' }, { k: 'dx', t: 1030, name: 'A' }, { k: 'dn', t: 5010, name: 'B' },
  ];
  const m = buildModel(char, steps, []);
  assert.deepEqual(m.spans.map((s) => [s.name, s.c0, s.c1]), [['A', 10, 30], ['B', 110, 150]]);
});

test('the purse curve anchors on the snapshot and walks back before it', () => {
  const c = { ...char, addons: { Memories_Economy: { snap: { 5: { money: 1000 } } }, Memories: { snap: { 5: { t: 1050 } } } } };
  const steps = [{ k: 'mn', t: 1010, delta: 100 }, { k: 'mn', t: 1040, delta: 50 }, { k: 'mn', t: 1070, delta: -30 }, { k: 'mn', t: 5010, delta: 5 }];
  const m = buildModel(c, steps, []);
  assert.equal(m.goldAbout, false);
  assert.deepEqual(m.gold, [
    { c: 0, v: 850 }, { c: 10, v: 950 }, { c: 40, v: 1000 }, { c: 50, v: 1000 }, { c: 70, v: 970 }, { c: 110, v: 975 },
  ]);
  assert.equal(m.goldMax, 1000);
});

test('the purse curve without a snapshot starts at 0 and is about', () => {
  const m = buildModel(char, [{ k: 'mn', t: 1010, delta: 40 }, { k: 'mn', t: 1020, delta: -100 }], []);
  assert.equal(m.goldAbout, true);
  assert.deepEqual(m.gold, [{ c: 0, v: 0 }, { c: 10, v: 40 }, { c: 20, v: 0 }]);
  assert.equal(buildModel({}, [], []).goldMax, 1);
});

test('the purse curve takes the anchor time from the lv record', () => {
  const c = { ...char, addons: { Memories_Economy: { snap: { 3: { money: 500 } } } } };
  const m = buildModel(c, [{ k: 'lv', t: 1020, level: 3 }, { k: 'mn', t: 1030, delta: 5 }], []);
  assert.equal(m.goldAbout, false);
  assert.deepEqual(m.gold.at(-1), { c: 30, v: 505 });
});

test('1,000,000 synthetic points build in under 2 seconds', () => {
  const pts = Array.from({ length: 20000 }, (_, i) => [1000 + (i % 90), 5000 + (i % 7) * 100, 5000, '']);
  const big = Array.from({ length: 50 }, (_, i) => ({ s: 1000, t: 1000 + i, m: 1438, n: pts.length, pts }));
  const t0 = performance.now();
  const m = buildModel(char, [], big);
  const ms = performance.now() - t0;
  assert.equal(m.points.count, 1_000_000);
  assert.ok(ms < 2000, `built in ${ms} ms`);
});

test('the real-shaped fixture builds', () => {
  const dir = new URL('./fixtures/nandu/', import.meta.url);
  const ch = JSON.parse(readFileSync(new URL('character.json', dir), 'utf8'));
  const steps = readFileSync(new URL('journey.jsonl', dir), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const tr = readFileSync(new URL('trail.jsonl', dir), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const m = buildModel(ch, steps, tr);
  assert.equal(m.events.length, steps.length);
  assert.equal(m.points.count, 3);
  assert.ok(m.total >= 1);
});
