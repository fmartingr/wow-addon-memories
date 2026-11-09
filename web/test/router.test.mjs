import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatHash, parseHash } from '../lib/router.mjs';

test('each row of the hash table parses and formats', () => {
  const rows = [
    ['#summary?slot=5', { tab: 'summary', layer: null, params: { slot: 5 } }],
    ['#journey?x=500.5&y=300.0&z=2.50', { tab: 'journey', layer: null, params: { x: 500.5, y: 300, z: 2.5 } }],
    ['#journey?at=120&ev=1793530060.zo', { tab: 'journey', layer: null, params: { at: 120, ev: '1793530060.zo' } }],
    ['#heatmaps/gathering?x=10.0&y=20.0&z=1.00&prof=mining', { tab: 'heatmaps', layer: 'gathering', params: { x: 10, y: 20, z: 1, prof: 'mining' } }],
    ['#heatmaps/fishing', { tab: 'heatmaps', layer: 'fishing', params: {} }],
    ['#summary', { tab: 'summary', layer: null, params: {} }],
  ];
  for (const [hash, want] of rows) {
    assert.deepEqual(parseHash(hash), want, hash);
    assert.equal(formatHash(want), hash, hash);
  }
});

test('out-of-range and non-numeric values drop', () => {
  assert.deepEqual(parseHash('#summary?slot=99').params, {});
  assert.deepEqual(parseHash('#summary?slot=0').params, {});
  assert.deepEqual(parseHash('#summary?slot=abc').params, {});
  assert.deepEqual(parseHash('#summary?slot=').params, {});
  assert.deepEqual(parseHash('#journey?x=NaN&z=-1').params, {});
  assert.deepEqual(parseHash('#journey?x=9999&y=-3&z=0&z=41').params, {});
  assert.deepEqual(parseHash('#journey?x=0x10&y=1e2').params, {});
  assert.deepEqual(parseHash('#journey?at=-5&ev=bad').params, {});
  assert.deepEqual(parseHash('#journey?ev=12.ZZ').params, {});
  assert.deepEqual(parseHash('#heatmaps/gathering?prof=evil').params, {});
  assert.deepEqual(parseHash('#journey?x=0&y=0&z=40').params, { x: 0, y: 0, z: 40 });
});

test('unknown keys and keys of another tab drop', () => {
  assert.deepEqual(parseHash('#journey?slot=3&foo=bar&at=4').params, { at: 4 });
  assert.deepEqual(parseHash('#summary?x=3').params, {});
});

test('unknown tab and layer fall back', () => {
  for (const h of ['', '#', '#unknown', 'summary', '#/x']) assert.equal(parseHash(h).tab, 'summary', h);
  assert.equal(parseHash('#heatmaps/nope').layer, 'presence');
  assert.equal(parseHash('#heatmaps').layer, 'presence');
  assert.equal(parseHash('#journey/kills').layer, null);
  assert.equal(parseHash(undefined).tab, 'summary');
});

test('prof is kept for gathering only', () => {
  assert.deepEqual(parseHash('#heatmaps/kills?prof=mining').params, {});
  assert.equal(formatHash({ tab: 'heatmaps', layer: 'kills', params: { prof: 'mining' } }), '#heatmaps/kills');
});

test('formatHash drops bad values and fills the layer', () => {
  assert.equal(formatHash({ tab: 'heatmaps', layer: 'nope', params: {} }), '#heatmaps/presence');
  assert.equal(formatHash({ tab: 'nope', params: { slot: 2 } }), '#summary?slot=2');
  assert.equal(formatHash({ tab: 'journey', params: { x: 5000, at: 3 } }), '#journey?at=3');
  assert.equal(formatHash({ tab: 'journey', params: { z: 1.234, y: 3.26, x: 1 } }), '#journey?x=1.0&y=3.3&z=1.23');
  assert.equal(formatHash({ tab: 'summary', params: { slot: null } }), '#summary');
  assert.equal(formatHash({ tab: 'summary' }), '#summary');
});

test('formatHash(parseHash(h)) is stable', () => {
  for (const h of [
    '#journey?z=3&x=1&y=2', '#heatmaps', '#summary?slot=19&zzz=1', '#journey?ev=5.de&at=7', '#heatmaps/gathering?prof=other&z=0.5', '#nothing?x=1',
  ]) {
    const once = formatHash(parseHash(h));
    assert.equal(formatHash(parseHash(once)), once, h);
  }
});

test('a hash value never carries markup into the parsed values', () => {
  const p = parseHash('#journey?ev=%3Cimg%20src%3Dx%3E&at=1');
  assert.deepEqual(p.params, { at: 1 });
});
