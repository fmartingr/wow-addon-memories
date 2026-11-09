// The language of the page: the 6 codes, the choice between the server, the character and the browser, and t().
import en from '../i18n/en.mjs';

export const LANGS = ['en', 'de', 'fr', 'es', 'it', 'pt'];

const WOW = {
  enUS: 'en', enGB: 'en', deDE: 'de', frFR: 'fr', esES: 'es', esMX: 'es', itIT: 'it', ptBR: 'pt', ptPT: 'pt',
};

// The code of a GetLocale() value, or null for every other value (ruRU, koKR, a number, a long string).
export const langFromWow = (locale) => (typeof locale === 'string' && Object.hasOwn(WOW, locale) ? WOW[locale] : null);

// The language of the page. The server marks where its choice came from: a query or a cookie is the choice of the
// viewer and wins; a header or the default gives way to the language of the character's game client.
export function pickLang({ from, current, charLocale }) {
  const base = LANGS.includes(current) ? current : 'en';
  if (from === 'query' || from === 'cookie') return base;
  return langFromWow(charLocale) ?? base;
}

// The catalog of a language, or null when it cannot be loaded. The page then stays in English.
export async function loadCatalog(code, importer = (c) => import(`../i18n/${c}.mjs`)) {
  if (!LANGS.includes(code)) return null;
  try {
    const catalog = (await importer(code)).default;
    return catalog && typeof catalog === 'object' ? catalog : null;
  } catch {
    return null;
  }
}

let lang = 'en';
let catalog = en;

// setLang makes code the language of t(), fmtDate() and the other formatters. A missing catalog keeps English.
export function setLang(code, cat = null) {
  if (!cat || !LANGS.includes(code)) {
    lang = 'en';
    catalog = en;
  } else {
    lang = code;
    catalog = cat;
  }
  return lang;
}

export const currentLang = () => lang;

const pluralRules = new Map();

export function plural(n, forms, code = lang) {
  let rules = pluralRules.get(code);
  if (!rules) pluralRules.set(code, (rules = new Intl.PluralRules(code)));
  return forms[rules.select(n)] ?? forms.other;
}

const fill = (text, vars) => text.replace(/\{(\w+)\}/g, (m, name) => (vars && Object.hasOwn(vars, name) ? String(vars[name] ?? '') : m));

// own reads a key of an object without its prototype chain, so "__proto__" or "toString" give undefined.
export const own = (cat, key) => (Object.hasOwn(cat, key) ? cat[key] : undefined);

// The entry of key: the language, then English, then undefined.
const entry = (key) => own(catalog, key) ?? own(en, key);

// tr returns the text of key, or undefined when no catalog has it.
export function tr(key, vars) {
  const v = entry(key);
  if (v === undefined) return undefined;
  return fill(typeof v === 'string' ? v : plural(Number(vars?.n), v), vars);
}

// t returns plain text; a caller that builds HTML wraps it in esc(). A plural entry takes the count from vars.n.
export const t = (key, vars) => tr(key, vars) ?? key;
