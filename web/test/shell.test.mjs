import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createSheet, SHEET_STATES } from '../ui/shell.mjs';

// A handle and a sheet that record their listeners.
const fake = (state) => {
  const on = {};
  const handle = { addEventListener: (t, f) => (on[t] = f), setPointerCapture() {}, setAttribute: (k, v) => (handle[k] = v) };
  const el = { dataset: state ? { state } : {}, querySelector: () => handle };
  return { el, handle, on };
};

test('the sheet starts in peek, and the handle cycles the states', () => {
  const { el, handle, on } = fake();
  const sheet = createSheet(el);
  assert.equal(sheet.state(), 'peek');
  assert.equal(el.dataset.state, 'peek');
  on.click();
  assert.equal(sheet.state(), 'half');
  assert.equal(handle['aria-expanded'], 'true');
  on.click();
  assert.equal(sheet.state(), 'full');
  on.click();
  assert.equal(sheet.state(), 'peek');
  assert.equal(handle['aria-expanded'], 'false');
});

test('a drag up goes to the next state, a drag down to the previous, and the click after a drag is ignored', () => {
  const { el, on } = fake('half');
  const sheet = createSheet(el);
  on.pointerdown({ clientY: 300, pointerId: 1 });
  on.pointermove({ clientY: 310 });
  assert.equal(sheet.state(), 'half');
  on.pointermove({ clientY: 200 });
  assert.equal(sheet.state(), 'full');
  on.pointermove({ clientY: 100 });
  assert.equal(sheet.state(), 'full');
  on.pointerup();
  on.click();
  assert.equal(sheet.state(), 'full');
  on.pointerdown({ clientY: 100, pointerId: 1 });
  on.pointermove({ clientY: 200 });
  on.pointerup();
  assert.equal(sheet.state(), 'half');
  on.pointerdown({ clientY: 100, pointerId: 1 });
  on.pointermove({ clientY: 200 });
  on.pointercancel();
  on.pointermove({ clientY: 400 });
  assert.equal(sheet.state(), 'peek');
});

test('set ignores an unknown state', () => {
  const { el } = fake();
  const sheet = createSheet(el);
  sheet.set('nope');
  assert.equal(sheet.state(), 'peek');
  assert.deepEqual(SHEET_STATES, ['peek', 'half', 'full']);
});
