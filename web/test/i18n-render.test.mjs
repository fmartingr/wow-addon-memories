import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildModel } from '../lib/model.mjs';
import { noteOf, NOTE, tipHtml } from '../lib/events.mjs';
import { deriveSummary, standingName } from '../lib/summary.mjs';
import { LANGS, setLang } from '../lib/i18n.mjs';
import { slotLabel } from '../lib/gear.mjs';
import { className, fmtDate, fmtDay, fmtDur, moneyText, qualityName, raceName } from '../lib/format.mjs';
import { paint, summaryHtml } from '../ui/summary.mjs';
import { dollHtml } from '../ui/gear.mjs';
import { deriveGear } from '../lib/gear.mjs';
import { levelName } from '../ui/mapview.mjs';
import { applyTexts, syncPicker } from '../ui/shell.mjs';
import { errorText, loadCharacter } from '../lib/data.mjs';

afterEach(() => setLang('en'));

const catalogs = {};
for (const code of LANGS) catalogs[code] = (await import(`../i18n/${code}.mjs`)).default;
const use = (code) => setLang(code, catalogs[code]);

const HOSTILE = '<img src=x onerror=alert(1)>';
const char = { first: { level: 1 }, sessions: [{ start: 1000, last: 1200 }] };
const load = (dir) => {
  const u = (f) => new URL(`./fixtures/${dir}/${f}`, import.meta.url);
  return {
    char: JSON.parse(readFileSync(u('character.json'), 'utf8')),
    steps: readFileSync(u('journey.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)),
  };
};

test('XSS: the tooltip and the toast of each hostile event are text in every language', () => {
  const steps = Object.keys(NOTE).map((k, i) => ({
    k, t: 1010 + i, m: 1438, x: 1, y: 1, name: HOSTILE, title: HOSTILE, killer: HOSTILE, place: HOSTILE, zone: HOSTILE, area: HOSTILE, to: HOSTILE, from: HOSTILE,
    why: HOSTILE, result: HOSTILE, prof: HOSTILE, node: HOSTILE, who: HOSTILE, faction: HOSTILE, label: HOSTILE, home: HOSTILE, family: HOSTILE, itype: HOSTILE,
    class: HOSTILE, level: HOSTILE, klevel: HOSTILE, seconds: HOSTILE, size: HOSTILE, xp: HOSTILE, roll: HOSTILE, success: 1, quality: 3, count: 2, item: 5,
  }));
  steps.push({ k: 'zo', t: 1005, zone: HOSTILE });
  const m = buildModel(char, steps, []);
  for (const code of LANGS) {
    use(code);
    for (const e of m.events) {
      const html = tipHtml(m, e, '/safe/shot.jpg');
      assert.doesNotMatch(html, /<img src=x/i, `${code} ${e.k}`);
      assert.doesNotMatch(html, /onerror=alert\(1\)>/, `${code} ${e.k}`);
      assert.doesNotMatch(html, /\{\w+\}/, `${code} ${e.k} has a placeholder left`);
      const [text] = noteOf(e);
      assert.doesNotMatch(text, /\{\w+\}/, `${code} ${e.k}`);
    }
  }
});

test('XSS: the hostile character page in German escapes every value', () => {
  use('de');
  const { char: c, steps } = load('hostile');
  const s = deriveSummary(c, steps);
  const html = summaryHtml(s) + dollHtml(deriveGear(c, steps), null);
  assert.doesNotMatch(html, /<img src=x/i);
  assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt;/);
  assert.match(html, /Selbstgefunden/);
  assert.match(html, /Allianz/);
  assert.match(html, /Fertigkeiten/);
  const el = { querySelectorAll: () => [] };
  paint(el);
});

test('the events read in German, French and Spanish with the same values', () => {
  const m = buildModel(char, [{ k: 'zo', t: 1005, zone: 'Teldrassil' }, { k: 'lv', t: 1010, level: 4 }, { k: 'rp', t: 1030, faction: 'F', standing: 6 }, { k: 'de', t: 1040, killer: 'Wolf' }], []);
  use('de');
  assert.deepEqual(noteOf(m.events[1]), ['Stufe 4', '#ffd100']);
  assert.equal(noteOf(m.events[2])[0], 'Wohlwollend bei F');
  assert.equal(noteOf(m.events[3])[0], 'Du bist gestorben. Getötet von Wolf.');
  assert.match(tipHtml(m, m.events[1]), /Du hast eine neue Stufe erreicht\./);
  assert.match(tipHtml(m, m.events[1]), /Teldrassil/);
  use('fr');
  assert.equal(noteOf(m.events[1])[0], 'Niveau 4');
  assert.equal(noteOf(m.events[2])[0], 'Honoré auprès de F');
  use('es');
  assert.equal(noteOf(m.events[2])[0], 'Honorable con F');
  setLang('en');
  assert.equal(noteOf(m.events[2])[0], 'Honored with F');
});

test('class, race, slot, quality, standing and layer names follow the language', () => {
  use('es');
  assert.equal(className('HUNTER'), 'Cazador');
  assert.equal(className('hunter'), 'Cazador');
  assert.equal(raceName('NightElf'), 'Elfo de la noche');
  assert.equal(slotLabel(5), 'Pecho');
  assert.equal(qualityName(4), 'Épico');
  assert.equal(qualityName(99), 'Calidad desconocida');
  assert.equal(standingName(8), 'Exaltado');
  assert.equal(standingName(0), '');
  assert.equal(levelName(1, 800, 600), 'Mundo');
  use('de');
  assert.equal(raceName('Scourge'), 'Untoter');
  assert.equal(className('NOPE'), 'Nope');
  assert.equal(raceName('NewRace'), 'New Race');
  setLang('en');
  assert.equal(className('HUNTER'), 'Hunter');
  assert.equal(raceName('Scourge'), 'Undead');
  assert.equal(slotLabel(5), 'Chest');
});

test('money uses the coin letters of the language', () => {
  assert.equal(moneyText(123456), '12g 34s 56c');
  use('de');
  assert.equal(moneyText(123456), '12G 34S 56K');
  use('fr');
  assert.equal(moneyText(123456), '12po 34pa 56pc');
  use('it');
  assert.equal(moneyText(5), '5r');
});

test('dates, days and durations follow the language', () => {
  const time = Date.UTC(2026, 10, 9, 15, 30) / 1000;
  setLang('en');
  const en = fmtDate(time);
  use('de');
  const de = fmtDate(time);
  assert.notEqual(en, de);
  assert.equal(de, new Date(time * 1000).toLocaleString('de', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }));
  assert.equal(fmtDay(time, 'fr'), new Date(time * 1000).toLocaleDateString('fr', { month: 'short', day: 'numeric' }));
  assert.equal(fmtDur(3725), '1 Std. 02 Min.');
});

test('summaryHtml of the fixture shows German text and the German number format', () => {
  use('de');
  const { char: c, steps } = load('nandu');
  const html = summaryHtml(deriveSummary(c, steps));
  for (const want of ['Spielzeit', 'Stufe 10 Nachtelf', 'Jäger', 'Sitzungen (1)']) assert.ok(html.includes(want), want);
  assert.doesNotMatch(html, /Time played/);
});

test('the English summary of the fixture is unchanged', () => {
  const { char: c, steps } = load('nandu');
  const html = summaryHtml(deriveSummary(c, steps));
  for (const want of ['Time played', 'Level 10 Night Elf', 'Hunter', 'Sessions (1)', 'Purse']) assert.ok(html.includes(want), want);
});

test('data errors are translated', async () => {
  use('de');
  await assert.rejects(loadCharacter('http://x/a/entry.json', async () => ({ ok: false, status: 404 })), /Der Server antwortete mit 404/);
  const body = { ok: true, json: async () => ({}), text: async () => 'not json' };
  await assert.rejects(loadCharacter('http://x/a/entry.json', async (url) => (String(url).endsWith('journey.jsonl') ? body : { ...body, json: async () => ({}) })), /Zeile 1 ist kein gültiges JSON/);
  setLang('en');
  await assert.rejects(loadCharacter('http://x/a/entry.json', async () => ({ ok: false, status: 404 })), /entry\.json: the server answered 404/);
});

test('a data error thrown before the catalog loads shows in the page language', async () => {
  const err = await loadCharacter('http://x/a/entry.json', async () => ({ ok: false, status: 404 })).catch((e) => e);
  use('de');
  assert.match(errorText(err), /Der Server antwortete mit 404/);
  assert.equal(errorText(new Error('network down')), 'network down');
});

test('the enemy player tooltip names the class in the page language', () => {
  use('es');
  const model = buildModel(char, [], []);
  assert.match(tipHtml(model, { k: 'pk', result: 'won', name: 'Foe', level: 60, class: 'WARRIOR', c: 0, t: 0 }), /Guerrero/);
});

// A tiny DOM: elements that record text, attributes and dataset.
const el = (attrs = {}) => {
  const e = { dataset: {}, attrs: { ...attrs }, textContent: '', setAttribute: (k, v) => (e.attrs[k] = String(v)), getAttribute: (k) => e.attrs[k] ?? null, removeAttribute: (k) => delete e.attrs[k] };
  for (const [k, v] of Object.entries(attrs)) if (k.startsWith('data-')) e.dataset[k.slice(5).replace(/-(\w)/g, (_, c) => c.toUpperCase())] = v;
  return e;
};
const root = (list) => ({ querySelectorAll: (sel) => list.filter((e) => e.attrs[sel.slice(1, -1)] !== undefined) });

test('applyTexts fills the text, the aria-label and the title of the static page', () => {
  const text = el({ 'data-i18n': 'tab.summary' });
  const aria = el({ 'data-i18n-aria': 'btn.zoomIn' });
  const title = el({ 'data-i18n-title': 'btn.play.title' });
  const page = root([text, aria, title]);
  use('fr');
  applyTexts(page);
  assert.equal(text.textContent, 'Résumé');
  assert.equal(aria.attrs['aria-label'], 'Zoom avant');
  assert.equal(title.attrs.title, 'Lecture (Espace)');
  setLang('en');
  applyTexts(page);
  assert.equal(text.textContent, 'Summary');
});

test('applyTexts shows a key as text, never as markup', () => {
  const e = el({ 'data-i18n': '<img src=x onerror=alert(1)>' });
  applyTexts(root([e]));
  assert.equal(e.textContent, '<img src=x onerror=alert(1)>');
});

test('the picker keeps the hash and marks the page language', () => {
  const links = LANGS.map((code) => el({ hreflang: code, href: `?lang=${code}` }));
  const nav = { querySelectorAll: () => links };
  syncPicker(nav, 'de', '#journey?x=1&y=2');
  assert.deepEqual(links.map((a) => a.attrs.href), LANGS.map((c) => `?lang=${c}#journey?x=1&y=2`));
  assert.deepEqual(links.map((a) => a.attrs['aria-current']), LANGS.map((c) => (c === 'de' ? 'true' : undefined)));
  syncPicker(nav, 'en', '');
  assert.equal(links[0].attrs.href, '?lang=en');
  assert.equal(links[0].attrs['aria-current'], 'true');
  assert.equal(links[1].attrs['aria-current'], undefined);
  links.push(el({ hreflang: 'ru', href: 'x' }));
  syncPicker(nav, 'en', '#a');
  assert.equal(links.at(-1).attrs.href, 'x');
});
