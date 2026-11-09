import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import en from '../i18n/en.mjs';
import { LANGS, currentLang, langFromWow, loadCatalog, pickLang, plural, setLang, t, tr } from '../lib/i18n.mjs';

afterEach(() => setLang('en'));

const catalogs = {};
for (const code of LANGS) catalogs[code] = (await import(`../i18n/${code}.mjs`)).default;

const placeholders = (v) => [...(typeof v === 'string' ? v : Object.values(v).join(' ')).matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();
const shape = (v) => (typeof v === 'string' ? 'text' : 'plural');

test('langFromWow maps the WoW locales and nothing else', () => {
  const want = { enUS: 'en', enGB: 'en', deDE: 'de', frFR: 'fr', esES: 'es', esMX: 'es', itIT: 'it', ptBR: 'pt', ptPT: 'pt' };
  for (const [locale, code] of Object.entries(want)) assert.equal(langFromWow(locale), code, locale);
  for (const bad of ['ruRU', 'koKR', 'zhCN', 'zhTW', '', 'de', 'DEDE', undefined, null, 5, {}, ['deDE'], 'x'.repeat(1024), '__proto__', 'constructor']) {
    assert.equal(langFromWow(bad), null, String(bad).slice(0, 20));
  }
});

test('pickLang: the choice of the viewer wins, then the character, then the server language', () => {
  assert.equal(pickLang({ from: 'query', current: 'fr', charLocale: 'deDE' }), 'fr');
  assert.equal(pickLang({ from: 'cookie', current: 'en', charLocale: 'deDE' }), 'en');
  assert.equal(pickLang({ from: 'header', current: 'en', charLocale: 'deDE' }), 'de');
  assert.equal(pickLang({ from: 'default', current: 'en', charLocale: 'esMX' }), 'es');
  assert.equal(pickLang({ from: 'header', current: 'it', charLocale: 'ruRU' }), 'it');
  assert.equal(pickLang({ from: 'default', current: 'en', charLocale: undefined }), 'en');
  assert.equal(pickLang({ from: 'default', current: 'pt', charLocale: 42 }), 'pt');
  assert.equal(pickLang({ from: 'default', current: 'en', charLocale: 'x'.repeat(1024) }), 'en');
  assert.equal(pickLang({ from: 'cookie', current: 'xx', charLocale: 'deDE' }), 'en');
  assert.equal(pickLang({ from: undefined, current: undefined, charLocale: 'frFR' }), 'fr');
});

test('loadCatalog returns the catalog, or null when the import fails or is bad', async () => {
  const ok = await loadCatalog('de', async (c) => ({ default: { hello: c } }));
  assert.deepEqual(ok, { hello: 'de' });
  assert.equal(await loadCatalog('de', async () => { throw new Error('network'); }), null);
  assert.equal(await loadCatalog('de', async () => ({ default: null })), null);
  assert.equal(await loadCatalog('de', async () => ({})), null);
  assert.equal(await loadCatalog('ru', async () => ({ default: {} })), null);
  assert.equal(await loadCatalog('../x', async () => ({ default: {} })), null);
  assert.equal((await loadCatalog('fr')).tr, undefined);
  assert.equal((await loadCatalog('fr'))['tab.summary'], 'Résumé');
});

test('t() fills placeholders, falls back to English and then to the key', () => {
  assert.equal(t('head.level', { level: 7 }), 'Level 7');
  setLang('de', catalogs.de);
  assert.equal(currentLang(), 'de');
  assert.equal(t('head.level', { level: 7 }), 'Stufe 7');
  setLang('de', { 'tab.summary': 'Nur dieser' });
  assert.equal(t('tab.summary'), 'Nur dieser');
  assert.equal(t('tab.journey'), 'Journey map');
  assert.equal(t('no.such.key'), 'no.such.key');
  assert.equal(tr('no.such.key'), undefined);
  assert.equal(t('head.level'), 'Level {level}');
});

test('setLang keeps English when the catalog is missing or the code is unknown', () => {
  assert.equal(setLang('de', null), 'en');
  assert.equal(t('tab.summary'), 'Summary');
  assert.equal(setLang('ru', catalogs.de), 'en');
  assert.equal(currentLang(), 'en');
});

test('a placeholder value with markup stays text for esc() to escape', () => {
  setLang('de', catalogs.de);
  const text = t('note.deBy', { killer: '<script>alert(1)</script>' });
  assert.equal(text, 'Du bist gestorben. Getötet von <script>alert(1)</script>.');
});

test('a value that looks like a placeholder is not filled twice', () => {
  assert.equal(t('note.rp', { standing: '{faction}', faction: 'X' }), '{faction} with X');
});

test('plural() picks the CLDR form for 0, 1 and 2 in each language', () => {
  const forms = { one: 'one', other: 'other' };
  for (const code of LANGS) {
    assert.equal(plural(1, forms, code), 'one', code);
    assert.equal(plural(2, forms, code), 'other', code);
  }
  assert.equal(plural(0, forms, 'en'), 'other');
  assert.equal(plural(0, forms, 'fr'), 'one');
  assert.equal(plural(0, forms, 'pt'), 'one');
  assert.equal(plural(0, forms, 'de'), 'other');
  assert.equal(plural(1000000, forms, 'fr'), 'other');
  assert.equal(plural(1000000, { one: 'a', other: 'b', many: 'c' }, 'es'), 'c');
});

test('a plural entry takes its count from n, in every language', () => {
  for (const code of LANGS) {
    setLang(code, catalogs[code]);
    for (const n of [0, 1, 2, 5]) {
      const text = t('heat.cell.kills', { n });
      assert.match(text, new RegExp(`^${n} \\S+`), `${code} ${n}: ${text}`);
    }
  }
  assert.equal(t('heat.cell.kills', { n: 1 }).length < t('heat.cell.kills', { n: 2 }).length, true);
});

for (const code of LANGS) {
  test(`the ${code} catalog has the key set, the placeholders and the plural shape of English`, () => {
    const cat = catalogs[code];
    assert.deepEqual(Object.keys(cat).filter((k) => !(k in en)), [], 'keys that English lacks');
    assert.deepEqual(Object.keys(en).filter((k) => !(k in cat)), [], 'keys that the catalog lacks');
    for (const [key, value] of Object.entries(cat)) {
      assert.equal(shape(value), shape(en[key]), key);
      assert.deepEqual(placeholders(value), placeholders(en[key]), key);
      const texts = typeof value === 'string' ? [value] : Object.values(value);
      for (const text of texts) assert.ok(typeof text === 'string' && text.trim() !== '', key);
      if (typeof value !== 'string') {
        assert.ok(value.one && value.other, `${key} needs one and other`);
        assert.deepEqual(Object.keys(value).filter((f) => !['zero', 'one', 'two', 'few', 'many', 'other'].includes(f)), [], key);
      }
    }
  });
}

test('every non-English catalog starts with the machine translation note', () => {
  for (const code of LANGS.filter((c) => c !== 'en')) {
    const first = readFileSync(new URL(`../i18n/${code}.mjs`, import.meta.url), 'utf8').split('\n')[0];
    assert.equal(first, '// Machine translated. Corrections are welcome.', code);
  }
});

test('the English catalog holds the English text of the page', () => {
  assert.equal(en['tab.summary'], 'Summary');
  assert.equal(en['tip.purse'], 'Purse');
  assert.equal(en['note.cc'], 'Close call!');
});

test('a missing value fills as an empty text, never as "undefined"', () => {
  assert.equal(t('tip.hs', { to: undefined }), 'Returned to .');
  assert.equal(t('tip.hs', { to: null }), 'Returned to .');
  assert.equal(t('tip.hs', {}), 'Returned to {to}.');
});

test('a key that names an Object.prototype member is not a catalog entry', () => {
  for (const key of ['__proto__', 'constructor', 'toString', 'hasOwnProperty']) {
    assert.equal(tr(key), undefined, key);
    assert.equal(t(key), key, key);
  }
});
