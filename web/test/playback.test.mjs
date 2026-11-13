import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildModel } from '../lib/model.mjs';
import { advance, BASE_RATE, crossed, eventId, findEvent, goldAt, lastBefore, levelAt, placeAt, posAt, spanAt, zoneChange } from '../lib/playback.mjs';
import { noteOf, NOTE, shotCaption, tipHtml } from '../lib/events.mjs';
import { ZONES } from '../zones.mjs';

const char = { first: { level: 1 }, sessions: [{ start: 1000, last: 1200 }] };
const HOSTILE = '<img src=x onerror=alert(1)>';

test('advance moves the playhead at each speed and stops at the end', () => {
  for (const speed of [1, 2, 4, 8, 16]) {
    const s = advance({ c: 0, speed, playing: true }, 0.5, 1000);
    assert.equal(s.c, 0.5 * BASE_RATE * speed);
    assert.equal(s.playing, true);
  }
  const end = advance({ c: 190, speed: 16, playing: true }, 1, 200);
  assert.equal(end.c, 200);
  assert.equal(end.playing, false);
  assert.equal(advance({ c: 5, speed: 1, playing: true }, -1, 100).c, 5);
});

const trail = [
  { m: 1438, pts: [[1000, 0, 0, ''], [1100, 3000, 0, ''], [1110, 3000, 3000, 't']] },
  { m: 1438, pts: [[1150, 9000, 9000, '']] },
];

test('posAt holds at the start and the end, interpolates in a chunk, and holds at a chunk end', () => {
  const m = buildModel(char, [], trail);
  const first = posAt(m, -5);
  assert.equal(first.lx, 0);
  assert.equal(posAt(m, 9999).lx, 9000);
  const mid = posAt(m, 99);
  assert.ok(mid.lx > 0 && mid.lx <= 3000);
  assert.equal(posAt(m, 100).lx, 3000);
  assert.equal(posAt(m, 30).lx, 900);
  const atChunkEnd = posAt(m, 120);
  assert.equal(atChunkEnd.lx, 3000);
  assert.equal(atChunkEnd.ly, 3000);
  assert.equal(posAt(buildModel(char, [], []), 5), null);
});

test('posAt moves toward the next point at the end of a gap', () => {
  const m = buildModel(char, [], [{ m: 1438, pts: [[1000, 1000, 1000, ''], [1100, 1300, 1000, '']] }]);
  const early = posAt(m, 50);
  assert.equal(early.lx, 1000);
  const late = posAt(m, 99.5);
  assert.ok(late.lx > 1000 && late.lx < 1300);
});

test('goldAt before and after the anchor, and levelAt', () => {
  const c = { ...char, addons: { Memories_Economy: { snap: { 5: { money: 1000 } } }, Memories: { snap: { 5: { t: 1100 } } } } };
  const steps = [{ k: 'mn', t: 1050, delta: 100 }, { k: 'lv', t: 1060, level: 2 }, { k: 'mn', t: 1150, delta: 20 }, { k: 'lv', t: 1180, level: 3 }];
  const m = buildModel(c, steps, []);
  assert.equal(goldAt(m, 0), 900);
  assert.equal(goldAt(m, 49), 900);
  assert.equal(goldAt(m, 50), 1000);
  assert.equal(goldAt(m, 100), 1000);
  assert.equal(goldAt(m, 150), 1020);
  assert.equal(goldAt(m, 9999), 1020);
  assert.equal(levelAt(m, 0), 1);
  assert.equal(levelAt(m, 60), 2);
  assert.equal(levelAt(m, 100), 2);
  assert.equal(levelAt(m, 180), 3);
});

test('crossed includes the start and excludes the end', () => {
  const steps = [10, 20, 30, 40].map((c) => ({ k: 'lv', t: 1000 + c, level: c }));
  const m = buildModel(char, steps, []);
  assert.deepEqual(crossed(m, 20, 40).map((e) => e.level), [20, 30]);
  assert.deepEqual(crossed(m, 0, 10).map((e) => e.level), []);
  assert.deepEqual(crossed(m, 0, 10.5).map((e) => e.level), [10]);
  assert.deepEqual(crossed(m, 40, 20), []);
  assert.deepEqual(crossed(m, 5, 5), []);
});

test('2,000 events in one second of clock are all crossed in order', () => {
  const steps = Array.from({ length: 2000 }, (_, i) => ({ k: 'ga', t: 1010, n: i }));
  const m = buildModel(char, steps, []);
  assert.equal(crossed(m, 0, 20).length, 2000);
});

test('findEvent returns the first event of a duplicate t.k', () => {
  const steps = [{ k: 'lv', t: 5, level: 1 }, { k: 'lv', t: 5, level: 2 }, { k: 'zo', t: 5, zone: 'A' }];
  const m = buildModel(char, steps, []);
  assert.equal(findEvent(m, '5.lv').level, 1);
  assert.equal(findEvent(m, '5.zo').zone, 'A');
  assert.equal(findEvent(m, '6.lv'), null);
  assert.equal(findEvent(m, 'bad'), null);
  assert.equal(eventId(steps[0]), '5.lv');
});

test('zoneChange reports a new zone or subzone only', () => {
  const steps = [{ k: 'zo', t: 1010, zone: 'A' }, { k: 'sz', t: 1020, sub: 'a1' }, { k: 'zo', t: 1100, zone: 'B' }];
  const m = buildModel(char, steps, []);
  assert.deepEqual(zoneChange(m, 0, 15), { zone: 'A', sub: '' });
  assert.deepEqual(zoneChange(m, 15, 25), { zone: 'A', sub: 'a1' });
  assert.equal(zoneChange(m, 25, 50), null);
  assert.deepEqual(zoneChange(m, 25, 150), { zone: 'B', sub: '' });
  assert.deepEqual(placeAt(m, 0), { zone: '', sub: '' });
  assert.equal(lastBefore(m.zo, 0), null);
});

test('spanAt finds the dungeon span of a clock value', () => {
  const m = buildModel(char, [{ k: 'dn', t: 1010, name: 'D' }, { k: 'dx', t: 1030 }], []);
  assert.equal(spanAt(m, 20).name, 'D');
  assert.equal(spanAt(m, 50), null);
});

test('XSS: the tooltip of each hostile event has no markup from the data', () => {
  const kinds = Object.keys(NOTE);
  const steps = kinds.map((k, i) => ({
    k, t: 1010 + i, m: 1438, x: 1, y: 1, name: HOSTILE, title: HOSTILE, killer: HOSTILE, place: HOSTILE, zone: HOSTILE, area: HOSTILE, to: HOSTILE, from: HOSTILE,
    why: HOSTILE, result: HOSTILE, prof: HOSTILE, node: HOSTILE, who: HOSTILE, faction: HOSTILE, label: HOSTILE, home: HOSTILE, family: HOSTILE, itype: HOSTILE,
    text: HOSTILE, class: HOSTILE, level: HOSTILE, klevel: HOSTILE, seconds: HOSTILE, size: HOSTILE, xp: HOSTILE, roll: HOSTILE, success: 1, quality: 3, count: 2, item: 5,
  }));
  steps.push({ k: 'zo', t: 1005, zone: HOSTILE });
  const m = buildModel(char, steps, []);
  for (const e of m.events) {
    const html = tipHtml(m, e, '/safe/shot.jpg');
    assert.doesNotMatch(html, /<img src=x/i, e.k);
    assert.doesNotMatch(html, /onerror=alert\(1\)>/, e.k);
    const [text] = noteOf(e);
    assert.equal(typeof text, 'string');
  }
});

test('tipHtml shows the screenshot only for a given URL and escapes it', () => {
  const m = buildModel(char, [{ k: 'ss', t: 1010, why: 'by hand', result: 'ok', screenshot: 'x' }], []);
  assert.match(tipHtml(m, m.events[0], '/a/b.jpg'), /<img class="shot" src="\/a\/b\.jpg"/);
  assert.doesNotMatch(tipHtml(m, m.events[0], null), /<img/);
  assert.doesNotMatch(tipHtml(m, m.events[0], '"><script>'), /<script>/);
  assert.doesNotMatch(tipHtml(m, m.events[0]), /style=/);
});

test('tipHtml and noteOf for common kinds', () => {
  const m = buildModel(char, [{ k: 'zo', t: 1005, zone: 'Teldrassil' }, { k: 'lv', t: 1010, level: 4 }, { k: 'xx', t: 1020 }, { k: 'rp', t: 1030, faction: 'F', standing: 5 }], []);
  assert.match(tipHtml(m, m.events[1]), /Level 4/);
  assert.match(tipHtml(m, m.events[1]), /Teldrassil/);
  assert.match(tipHtml(m, m.events[3]), /Friendly/);
  assert.deepEqual(noteOf(m.events[1]), ['Level 4', '#ffd100']);
  assert.equal(noteOf(m.events[2])[0], 'xx');
  assert.ok(ZONES[1438]);
});

test('a screenshot shows the note of another addon and no text when manual', () => {
  const withNote = { k: 'ss', why: 'by hand', result: 'ok', notes: [{ source: 'Paparazzi', note: 'Level up, Boss kill' }] };
  assert.match(NOTE.ss(withNote)[0], /Level up, Boss kill/);
  assert.doesNotMatch(NOTE.ss(withNote)[0], /by hand/);
  assert.doesNotMatch(NOTE.ss({ k: 'ss', why: 'by hand', result: 'ok' })[0], /by hand/);
});

test('a screenshot tooltip shows the note of another addon with no result code', () => {
  const m = buildModel(char, [{ t: 1100, k: 'ss', why: 'by hand', result: 'ok', notes: [{ source: 'Paparazzi', note: 'Death' }] }], []);
  const html = tipHtml(m, m.events[0], '/shot.jpg');
  assert.match(html, /Death/);
  assert.doesNotMatch(html, /\(ok\)|by hand/);
  assert.match(html, /<img class="shot" src="\/shot\.jpg"/);
  const auto = tipHtml(m, { ...m.events[0], notes: undefined, why: 'level 2' }, null);
  assert.match(auto, /level 2/);
  assert.doesNotMatch(auto, /\(ok\)/);
});

test('the lightbox caption is the note of the screenshot, or only the date for a manual shot', () => {
  const noted = shotCaption({ t: 1100, why: 'by hand', notes: [{ source: 'Paparazzi', note: 'Death' }] });
  assert.match(noted, /Death/);
  assert.doesNotMatch(noted, /by hand/);
  const manual = shotCaption({ t: 1100, why: 'by hand' });
  assert.doesNotMatch(manual, /by hand/);
  assert.match(manual, /^Screenshot · /);
  assert.match(shotCaption({ t: 1100, why: 'level 2' }), /Screenshot: level 2 · /);
});
