import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { shotEvents } from '../lib/events.mjs';
import { setLang } from '../lib/i18n.mjs';
import { formatHash, parseHash } from '../lib/router.mjs';
import { shotsHtml } from '../ui/screenshots.mjs';

afterEach(() => setLang('en'));

const steps = [
  { k: 'ss', t: 1700000000, screenshot: 'a.jpg', why: 'by hand' },
  { k: 'lv', t: 1700000001, level: 2 },
  { k: 'ss', t: 1700000002 },
  { k: 'ss', t: 1700000003, screenshot: 'b.jpg', notes: [{ note: 'Hogger <b>down</b>' }] },
];

test('shotEvents keeps the screenshot records that name a file, in order', () => {
  assert.deepEqual(shotEvents(steps).map((e) => e.screenshot), ['a.jpg', 'b.jpg']);
});

test('shotsHtml shows each thumbnail, the escaped note of a noted shot and no note for a manual shot', () => {
  const html = shotsHtml(shotEvents(steps).map((e) => ({ e, url: e.screenshot === 'a.jpg' ? '/c/a.jpg' : null })));
  assert.equal(html.match(/<li>/g).length, 2);
  assert.match(html, /<img src="\/c\/a\.jpg" alt="" loading="lazy"/);
  assert.match(html, /<span class="shot-missing">Screenshot not uploaded<\/span>/);
  assert.equal(html.match(/class="shot-note"/g).length, 1);
  assert.match(html, /Hogger &lt;b&gt;down&lt;\/b&gt;/);
  assert.doesNotMatch(html, /<b>down/);
});

test('shotsHtml says so when there are no screenshots', () => {
  setLang('de', { 'shots.empty': 'Keine' });
  assert.equal(shotsHtml([]), '<p class="shots-empty">Keine</p>');
});

test('the screenshots tab has its own hash and drops the map parameters', () => {
  assert.deepEqual(parseHash('#screenshots?x=1&slot=2'), { tab: 'screenshots', layer: null, params: {} });
  assert.equal(formatHash({ tab: 'screenshots', params: { z: 2 } }), '#screenshots');
});
