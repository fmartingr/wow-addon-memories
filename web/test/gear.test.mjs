import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SLOTS, deriveGear, slotLabel, wowheadUrl } from '../lib/gear.mjs';
import { setLang } from '../lib/i18n.mjs';
import de from '../i18n/de.mjs';
import { dollHtml, loadWidget, mountPaperDoll, paintDoll } from '../ui/gear.mjs';

const ids = (...pairs) => {
  const a = Array(19).fill(0);
  for (const [slot, item] of pairs) a[slot - 1] = item;
  return a.join(',');
};
const items = (gear) => gear.filter((g) => g.item).map((g) => [g.slot, g.item]);

test('SLOTS has the 19 slots, each once, on a side', () => {
  assert.deepEqual(SLOTS.map((s) => s.n).sort((a, b) => a - b), Array.from({ length: 19 }, (_, i) => i + 1));
  assert.deepEqual(SLOTS.filter((s) => s.side === 'left').map((s) => s.n), [1, 2, 3, 15, 5, 4, 19, 9]);
  assert.deepEqual(SLOTS.filter((s) => s.side === 'right').map((s) => s.n), [10, 6, 7, 8, 11, 12, 13, 14]);
  assert.deepEqual(SLOTS.filter((s) => s.side === 'bottom').map((s) => s.n), [16, 17, 18]);
  assert.equal(slotLabel(5), 'Chest');
  assert.equal(slotLabel(99), '');
});

test('no ge, no snapshot and no eq gives 19 empty slots', () => {
  const g = deriveGear({}, []);
  assert.equal(g.length, 19);
  assert.deepEqual(items(g), []);
  assert.ok(g.every((s) => s.quality === null));
  assert.equal(deriveGear(undefined, undefined).length, 19);
});

test('the last ge record gives the base, and a later eq wins', () => {
  const steps = [
    { k: 'ge', t: 10, ids: ids([5, 1111]) },
    { k: 'ge', t: 20, ids: ids([5, 1380], [1, 49]) },
    { k: 'eq', t: 30, slot: 5, item: 2222, quality: 2 },
  ];
  const g = deriveGear({}, steps);
  assert.deepEqual(items(g), [[1, 49], [5, 2222]]);
  assert.equal(g[4].quality, 2);
  assert.equal(g[0].quality, null);
  assert.equal(deriveGear({}, steps.slice(0, 2))[4].item, 1380);
});

test('an eq before the last ge loses', () => {
  const steps = [{ k: 'eq', t: 5, slot: 5, item: 9, quality: 1 }, { k: 'ge', t: 10, ids: ids([5, 1380]) }];
  assert.equal(deriveGear({}, steps)[4].item, 1380);
  assert.equal(deriveGear({}, steps)[4].quality, null);
});

test('a snapshot newer than the last ge wins, and an older one loses', () => {
  const char = (t) => ({ addons: { Memories_Economy: { snap: { 10: { gear: ids([1, 77]) } } }, Memories: { snap: { 10: { t } } } } });
  const steps = [{ k: 'ge', t: 100, ids: ids([1, 49]) }];
  assert.equal(deriveGear(char(200), steps)[0].item, 77);
  assert.equal(deriveGear(char(50), steps)[0].item, 49);
});

test('the snapshot of the highest level with gear is used, with the lv time as a fallback', () => {
  const char = { addons: { Memories_Economy: { snap: { 4: { gear: ids([1, 1]) }, 6: { gear: ids([1, 6]) }, 8: { money: 3 } } } } };
  assert.equal(deriveGear(char, [])[0].item, 6);
  const steps = [{ k: 'lv', level: 6, t: 500 }, { k: 'eq', t: 400, slot: 1, item: 9 }, { k: 'eq', t: 600, slot: 2, item: 8 }];
  assert.deepEqual(items(deriveGear(char, steps)), [[1, 6], [2, 8]]);
});

test('bad ids are 0, and extra or missing parts are handled', () => {
  const g = deriveGear({}, [{ k: 'ge', t: 1, ids: 'abc,-1,1e9,9007199254740993, 12 ,7,8' + ',0'.repeat(30) }]);
  assert.deepEqual(items(g), [[6, 7], [7, 8]]);
  assert.equal(g.length, 19);
  assert.equal(deriveGear({}, [{ k: 'ge', t: 1, ids: '5,6' }]).length, 19);
  assert.deepEqual(items(deriveGear({}, [{ k: 'ge', t: 1, ids: 5 }])), []);
});

test('eq for slot 0, slot 20 or a bad item is ignored; item 0 unequips', () => {
  const steps = [
    { k: 'ge', t: 1, ids: ids([3, 33]) },
    { k: 'eq', t: 2, slot: 0, item: 5 }, { k: 'eq', t: 2, slot: 20, item: 5 }, { k: 'eq', t: 2, slot: 4, item: -1 }, { k: 'eq', t: 2, slot: 4, item: 'x' },
    { k: 'eq', t: 3, slot: 3, item: 0 },
  ];
  assert.deepEqual(items(deriveGear({}, steps)), []);
});

test('wowheadUrl accepts a positive safe integer only', () => {
  assert.equal(wowheadUrl(6948), 'https://www.wowhead.com/classic/item=6948');
  for (const bad of [0, -1, 1.5, NaN, '12', null, undefined, 9007199254740993, '1"><img>']) assert.equal(wowheadUrl(bad), null, String(bad));
});

test('dollHtml makes a link for each item and a button for each empty slot', () => {
  const gear = deriveGear({}, [{ k: 'ge', t: 1, ids: ids([5, 1380], [16, 2947]) }, { k: 'eq', t: 2, slot: 5, item: 1380, quality: 2 }]);
  const html = dollHtml(gear, 5);
  assert.equal((html.match(/<a class="slot/g) ?? []).length, 2);
  assert.equal((html.match(/<button type="button" class="slot empty/g) ?? []).length, 17);
  assert.match(html, /href="https:\/\/www\.wowhead\.com\/classic\/item=1380"/);
  assert.match(html, /class="slot q2 selected"[^>]*>Item 1380</);
  assert.match(html, /rel="noopener noreferrer"/);
  assert.match(html, /Open on Wowhead/);
  assert.match(html, /Item 1380 <span class="q-name q2">Uncommon/);
  assert.doesNotMatch(html, /style=/);
  assert.match(dollHtml(gear, 1), /Nothing equipped/);
  assert.doesNotMatch(dollHtml(gear, null), /Open on Wowhead/);
});

test('a hostile item id never reaches the markup', () => {
  const html = dollHtml(deriveGear({}, [{ k: 'ge', t: 1, ids: '"><img src=x onerror=alert(1)>,5' }]), null);
  assert.doesNotMatch(html, /<img/);
  assert.match(html, /item=5"/);
});

// A tiny element that records what the paper doll does.
const fakeRoot = () => {
  const listeners = {};
  const el = {
    classList: { add() {} },
    innerHTML: '',
    addEventListener: (type, fn) => (listeners[type] = fn),
    querySelectorAll: () => [],
  };
  return { el, click: (target, extra = {}) => { let prevented = false; listeners.click({ target, preventDefault: () => (prevented = true), ctrlKey: false, metaKey: false, shiftKey: false, ...extra }); return prevented; } };
};

test('a click on a slot selects it, sets the hash and does not follow the link', () => {
  const calls = [];
  const { el, click } = fakeRoot();
  mountPaperDoll(el, deriveGear({}, [{ k: 'ge', t: 1, ids: ids([5, 1380]) }]), { setParams: (...a) => calls.push(a) });
  const slot = { dataset: { slot: '5' } };
  assert.equal(click({ closest: () => slot }), true);
  assert.deepEqual(calls, [['summary', { slot: 5 }]]);
  assert.match(el.innerHTML, /slot q\d? ?selected|selected/);
  assert.equal(click({ closest: () => slot }, { ctrlKey: true }), false);
  assert.equal(click({ closest: () => null }), false);
  assert.equal(calls.length, 1);
});

test('show selects the slot of the hash without setting the hash', () => {
  const calls = [];
  const { el } = fakeRoot();
  const doll = mountPaperDoll(el, deriveGear({}, []), { setParams: (...a) => calls.push(a) });
  doll.show(3);
  assert.match(el.innerHTML, /Nothing equipped/);
  doll.show(undefined);
  assert.doesNotMatch(el.innerHTML, /Nothing equipped/);
  assert.deepEqual(calls, []);
});

test('the widget loads the settings file first and the script second, once', async () => {
  const added = [];
  const doc = { createElement: () => ({}), head: { append: (el) => { added.push(el.src); queueMicrotask(() => el.onload()); } } };
  const first = loadWidget(doc);
  assert.equal(loadWidget(doc), first);
  await first;
  assert.deepEqual(added, ['/_/wowhead.js', 'https://wow.zamimg.com/js/tooltips.js']);
});

test('paintDoll sets the quality colour through the CSSOM', () => {
  const set = [];
  const el = (className) => ({ className, style: { setProperty: (k, v) => set.push([k, v]) } });
  paintDoll({ querySelectorAll: (sel) => (sel.startsWith('a.slot') ? [el('slot q4 selected'), el('slot')] : [el('q-name q2')]) });
  assert.deepEqual(set, [['--c', '#a335ee'], ['--c', '#1eff00']]);
});

test('wowheadUrl points at the Wowhead page in the page language', () => {
  assert.equal(wowheadUrl(19019, 'en'), 'https://www.wowhead.com/classic/item=19019');
  for (const code of ['de', 'fr', 'es', 'it', 'pt']) assert.equal(wowheadUrl(19019, code), `https://www.wowhead.com/classic/${code}/item=19019`);
  assert.equal(wowheadUrl(19019), 'https://www.wowhead.com/classic/item=19019');
});

test('wowheadUrl gives the English URL for an unknown code and no link for a bad id', () => {
  for (const bad of ['ru', 'xx', '', 'DE', 'de/../x', '"><img>', null, undefined, 5, {}, '__proto__']) {
    assert.equal(wowheadUrl(19019, bad), 'https://www.wowhead.com/classic/item=19019', String(bad));
  }
  for (const bad of [0, -1, 1.5, NaN, '12', null, undefined]) assert.equal(wowheadUrl(bad, 'de'), null, String(bad));
});

test('the paper doll links to the Wowhead page of the page language', () => {
  const gear = deriveGear({}, [{ k: 'ge', t: 1, ids: ids([5, 1380]) }]);
  setLang('de', de);
  try {
    const html = dollHtml(gear, 5);
    assert.equal((html.match(/href="https:\/\/www\.wowhead\.com\/classic\/de\/item=1380"/g) ?? []).length, 2);
    assert.doesNotMatch(html, /classic\/item=/);
  } finally {
    setLang('en');
  }
  assert.match(dollHtml(gear, 5), /classic\/item=1380"/);
});

test('wowheadUrl uses the forever database for the forever flavor only', () => {
  assert.equal(wowheadUrl(248005, 'en', 'forever'), 'https://www.wowhead.com/forever/item=248005');
  assert.equal(wowheadUrl(248005, 'de', 'forever'), 'https://www.wowhead.com/forever/de/item=248005');
  for (const flavor of ['wow', 'classic', null, undefined]) assert.equal(wowheadUrl(1380, 'en', flavor), 'https://www.wowhead.com/classic/item=1380');
  assert.equal(wowheadUrl(0, 'en', 'forever'), null);
});

test('the paper doll links to the forever database for a forever character', () => {
  const gear = deriveGear({}, [{ k: 'ge', t: 1, ids: ids([16, 248005]) }]);
  assert.match(dollHtml(gear, 16, 'forever'), /wowhead\.com\/forever\/item=248005"/);
});
