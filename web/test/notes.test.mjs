import { test } from 'node:test';
import assert from 'node:assert/strict';
import { noteHtml, parseNote, plainNote } from '../lib/notes.mjs';
import { noteOf, tipHtml } from '../lib/events.mjs';
import { questUrl } from '../lib/gear.mjs';
import { buildModel } from '../lib/model.mjs';
import { setLang } from '../lib/i18n.mjs';

const char = { sessions: [{ start: 1000, last: 2000 }] };

test('parseNote splits text, item tokens and quest tokens', () => {
  assert.deepEqual(parseNote('plain'), [{ text: 'plain' }]);
  assert.deepEqual(parseNote('buy {item:19019:Thunderfury} for {quest:77:A Quest}!'), [
    { text: 'buy ' }, { item: 19019, name: 'Thunderfury' }, { text: ' for ' }, { quest: 77, title: 'A Quest' }, { text: '!' },
  ]);
  assert.deepEqual(parseNote('{item:1:a}{item:2:b}'), [{ item: 1, name: 'a' }, { item: 2, name: 'b' }]);
  assert.deepEqual(parseNote(''), []);
  assert.deepEqual(parseNote(undefined), []);
});

test('parseNote keeps a bad id, a half token and a stray brace as text', () => {
  for (const text of ['{item:0:x}', '{item:99999999999999999999:x}', '{item:12:x', '{ item:12:x }', 'a { b', '{quest:-1:x}', '{item:1e3:x}']) {
    assert.deepEqual(parseNote(text), [{ text }], text);
  }
});

test('plainNote gives each token as its name', () => {
  assert.equal(plainNote('see {item:1:Sword} and {quest:2:Rats}'), 'see Sword and Rats');
});

test('noteHtml links an item and a quest to Wowhead for the flavor and the language', () => {
  setLang('en');
  assert.equal(
    noteHtml('a {item:19019:Thunderfury}', null),
    'a <a class="wh-link" href="https://www.wowhead.com/classic/item=19019" target="_blank" rel="noopener noreferrer" data-wh-rename-link="false" data-wh-icon-add="false">Thunderfury</a>',
  );
  assert.match(noteHtml('{quest:77:A Quest}', 'forever'), /href="https:\/\/www\.wowhead\.com\/forever\/quest=77"/);
  assert.match(noteHtml('{item:5:x}', null, 'de'), /href="https:\/\/www\.wowhead\.com\/classic\/de\/item=5"/);
  assert.match(noteHtml('{quest:5:x}', 'classic', 'zz'), /href="https:\/\/www\.wowhead\.com\/classic\/quest=5"/);
});

test('questUrl accepts a positive safe integer only', () => {
  assert.equal(questUrl(12, 'en'), 'https://www.wowhead.com/classic/quest=12');
  for (const bad of [0, -1, 1.5, NaN, '12', null, undefined]) assert.equal(questUrl(bad), null, String(bad));
});

test('noteHtml escapes all text, names and attributes, and adds no style', () => {
  const evil = '<img src=x onerror=alert(1)>';
  const html = noteHtml(`${evil} {item:5:${evil}} {quest:6:"><script>}`, null);
  assert.doesNotMatch(html, /<img|<script/i);
  assert.doesNotMatch(html, /style=/);
  assert.match(html, /rel="noopener noreferrer"/);
});

test('the event of a note has a line, a tooltip with links, and a fallback for no text', () => {
  setLang('en');
  const steps = [
    { k: 'un', t: 1010, text: 'Get {item:19019:Thunderfury}' },
    { k: 'un', t: 1020, text: '' },
    { k: 'un', t: 1030, text: 'x'.repeat(80) },
  ];
  const m = buildModel(char, steps, []);
  const [a, b, c] = m.events;
  assert.equal(noteOf(a)[0], 'Note: Get Thunderfury');
  assert.equal(noteOf(b)[0], 'Note: a note without text');
  assert.equal(noteOf(c)[0], 'Note: ' + 'x'.repeat(60) + '…');
  const tip = tipHtml(m, a, null);
  assert.match(tip, /href="https:\/\/www\.wowhead\.com\/classic\/item=19019"/);
  assert.match(tip, /class="tip-title"[^>]*>Note</);
  assert.match(tipHtml(m, b, null), /a note without text/);
  assert.doesNotMatch(tip, /style=/);
});

test('a forever character links to the forever database', () => {
  setLang('en');
  const m = buildModel({ ...char, flavor: 'forever' }, [{ k: 'un', t: 1010, text: '{quest:9:Q}' }], []);
  assert.match(tipHtml(m, m.events[0], null), /wowhead\.com\/forever\/quest=9/);
});
