import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { loadCharacter, screenshotUrl } from '../lib/data.mjs';

const dir = new URL('./fixtures/nandu/', import.meta.url);
const BASE = 'https://example.test/wow/eu/brumamar/nandu/data/';

// A fetch over the fixture folder, with overrides: { name: text | status number }.
const fakeFetch = (over = {}) => async (url) => {
  const name = String(url).slice(BASE.length);
  const o = over[name];
  if (typeof o === 'number') return { ok: false, status: o };
  let text;
  if (typeof o === 'string') text = o;
  else if (readdirSync(dir).includes(name)) text = readFileSync(new URL(name, dir), 'utf8');
  else return { ok: false, status: 404 };
  return { ok: true, status: 200, text: async () => text, json: async () => JSON.parse(text) };
};

test('the three files load, with the root of the folder', async () => {
  const d = await loadCharacter(BASE + 'entry.json', fakeFetch());
  assert.equal(d.root, BASE);
  assert.equal(d.char.name, 'Ñandú');
  assert.equal(d.steps.length, 15);
  assert.equal(d.trail.length, 1);
  assert.equal(d.entry.path, '.');
});

test('steps are sorted by time and stay stable on equal times', async () => {
  const text = [{ t: 5, k: 'b' }, { t: 1, k: 'a' }, { t: 5, k: 'c' }, { t: 3, k: 'd' }].map((r) => JSON.stringify(r)).join('\n') + '\n\n';
  const d = await loadCharacter(BASE + 'entry.json', fakeFetch({ 'journey.jsonl': text }));
  assert.deepEqual(d.steps.map((s) => s.k), ['a', 'd', 'b', 'c']);
});

test('a bad JSONL line names its file and line', async () => {
  const text = '{"t":1}\n{"t":2\n{"t":3}\n';
  await assert.rejects(loadCharacter(BASE + 'entry.json', fakeFetch({ 'journey.jsonl': text })), /journey\.jsonl: line 2 is not valid JSON/);
});

test('a missing file names the file and the status', async () => {
  await assert.rejects(loadCharacter(BASE + 'entry.json', fakeFetch({ 'trail.jsonl': 404 })), /trail\.jsonl: the server answered 404/);
  await assert.rejects(loadCharacter(BASE + 'entry.json', fakeFetch({ 'character.json': 500 })), /character\.json: the server answered 500/);
  await assert.rejects(loadCharacter(BASE + 'entry.json', fakeFetch({ 'entry.json': 404 })), /entry\.json: the server answered 404/);
});

test('an entry that points outside its folder is refused', async () => {
  const entry = JSON.stringify({ path: '.', character: '//evil.test/c.json' });
  await assert.rejects(loadCharacter(BASE + 'entry.json', fakeFetch({ 'entry.json': entry })), /outside the character folder/);
  const up = JSON.stringify({ path: '.', journey: '../other/journey.jsonl' });
  await assert.rejects(loadCharacter(BASE + 'entry.json', fakeFetch({ 'entry.json': up })), /outside the character folder/);
});

test('an entry with no file names uses the standard names', async () => {
  const d = await loadCharacter(BASE + 'entry.json', fakeFetch({ 'entry.json': '{"path":"."}' }));
  assert.equal(d.steps.length, 15);
});

test('an empty journey loads', async () => {
  const d = await loadCharacter(BASE + 'entry.json', fakeFetch({ 'journey.jsonl': '', 'trail.jsonl': '\n' }));
  assert.deepEqual(d.steps, []);
  assert.deepEqual(d.trail, []);
});

test('screenshotUrl joins the root and the file and refuses odd names', () => {
  const d = { root: BASE, entry: { path: '.' } };
  assert.equal(screenshotUrl(d, 'screenshots/a.jpg'), BASE + 'screenshots/a.jpg');
  assert.equal(screenshotUrl({ root: BASE, entry: { path: 'x' } }, 'screenshots/a.jpg'), BASE + 'x/screenshots/a.jpg');
  assert.equal(screenshotUrl(d, '../a.jpg'), null);
  assert.equal(screenshotUrl(d, 'a b.jpg'), null);
  assert.equal(screenshotUrl(d, '"><img src=x>'), null);
  assert.equal(screenshotUrl(d, undefined), null);
});
