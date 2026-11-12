import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { ICON_FILES, iconUrl } from '../lib/eventicons.mjs';

const webDir = new URL('../', import.meta.url);

test('every kind of the catalog has an icon, and every icon has its file', () => {
  const catalog = readFileSync(new URL('kinds.js', webDir), 'utf8');
  const kinds = [...catalog.matchAll(/^ "(\w+)": \{$/gm)].map((m) => m[1]);
  assert.ok(kinds.length > 50);
  for (const kind of kinds) assert.ok(ICON_FILES[kind], kind);
  for (const file of Object.values(ICON_FILES)) assert.ok(existsSync(new URL('icons/' + file + '.png', webDir)), file);
});

test('iconUrl gives the served path of an icon, and null for an unknown kind', () => {
  assert.equal(iconUrl('lv'), '/_/icons/level_up.png');
  assert.equal(iconUrl('de'), '/_/icons/died.png');
  assert.equal(iconUrl('zz'), null);
  assert.equal(iconUrl('toString'), null);
});

test('icon draws the coin once it loads, a grey disc before, and asks for a redraw on load', async () => {
  const made = [];
  globalThis.Image = class {
    constructor() {
      made.push(this);
      this.complete = false;
      this.naturalWidth = 0;
    }
  };
  try {
    const { icon, onIconsLoaded, COIN } = await import('../ui/icons.mjs?coin');
    const calls = [];
    const ctx = new Proxy({}, {
      get: (t, k) => (k in t ? t[k] : (...args) => calls.push([k, ...args])),
      set: (t, k, v) => { t[k] = v; return true; },
    });
    let redraws = 0;
    onIconsLoaded(() => redraws++);
    icon(ctx, 'lv', 100, 50, 10, 0.5);
    assert.equal(made.length, 1);
    assert.equal(made[0].src, '/_/icons/level_up.png');
    assert.ok(calls.some((c) => c[0] === 'arc'));
    assert.ok(!calls.some((c) => c[0] === 'drawImage'));
    made[0].complete = true;
    made[0].naturalWidth = 64;
    made[0].onload();
    assert.equal(redraws, 1);
    calls.length = 0;
    icon(ctx, 'lv', 100, 50, 10);
    assert.equal(made.length, 1);
    assert.deepEqual(calls.find((c) => c[0] === 'drawImage'), ['drawImage', made[0], 100 - 5 * COIN, 50 - 5 * COIN, 10 * COIN, 10 * COIN]);
    calls.length = 0;
    icon(ctx, 'zz', 0, 0, 4);
    assert.equal(made.length, 1);
    assert.ok(calls.some((c) => c[0] === 'arc'));
  } finally {
    delete globalThis.Image;
  }
});
