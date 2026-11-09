// Compares the website theme with the app theme and fails when they differ. Usage: node scripts/theme-parity.mjs [--json]
//
//   1. tokens     the colours of :root in web/base.css and app/lib/src/theme/tokens.dart
//   2. game       the class and quality colours of web/lib/format.mjs and tokens.dart
//   3. fonts      the font families and files of the website and of the app
//   4. components each entry of docs/theme-parity.json: its values must be in the CSS rule and in the Dart file
//                 (inside the scope of the entry when it has one)
//   5. coverage   each class that web/base.css styles is in the manifest, as a component or as web only
//   6. hard-coded no Color(0x...) or Colors.* in app/lib/src outside app/lib/src/theme (the screens use the theme)
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { camel, cssColours, cssFamily, listColours } from './gen-app-theme.mjs';

// THEME_PARITY_ROOT lets the test run the check on a changed copy of the files.
const root = process.env.THEME_PARITY_ROOT ?? join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => readFileSync(join(root, p), 'utf8');
const rows = [];
const add = (area, item, ok, detail = '') => rows.push({ area, item, ok, detail });

const baseCss = read('web/base.css');
const dart = read('app/lib/src/theme/tokens.dart');

// 1. tokens
const dartTokens = {};
for (const m of dart.matchAll(/static const Color (\w+) = Color\(0xFF([0-9A-F]{6})\);/g)) dartTokens[m[1]] = '#' + m[2].toLowerCase();
for (const [name, hex] of Object.entries(cssColours(baseCss))) {
  const have = dartTokens[camel(name)];
  add('tokens', name, have === hex, have ? `css ${hex}, app ${have}` : `css ${hex}, missing in the app`);
}
for (const name of Object.keys(dartTokens)) {
  const cssName = name.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase());
  if (!(cssName in cssColours(baseCss))) add('tokens', name, false, 'in the app, not in web/base.css');
}

// 2. game colours
const formatJs = read('web/lib/format.mjs');
const dartList = (name, re) => [...(new RegExp(`${name}[^=]*=\\s*(?:const )?[{\\[]([^}\\]]*)[}\\]]`).exec(dart)?.[1] ?? '').matchAll(re)];
const dartClasses = Object.fromEntries(dartList('classColours', /'([A-Z]+)':\s*Color\(0xFF([0-9A-F]{6})\)/g).map((m) => [m[1], '#' + m[2].toLowerCase()]));
for (const [k, hex] of listColours(formatJs, 'CLASS_COLOURS')) add('game', `class ${k}`, dartClasses[k] === hex, `web ${hex}, app ${dartClasses[k] ?? 'missing'}`);
const dartQuality = dartList('qualityColours', /Color\(0xFF([0-9A-F]{6})\)/g).map((m) => '#' + m[1].toLowerCase());
listColours(formatJs, 'QUALITY_COLOURS').forEach(([, hex], i) => add('game', `quality ${i}`, dartQuality[i] === hex, `web ${hex}, app ${dartQuality[i] ?? 'missing'}`));

// 3. fonts
const pubspec = read('app/pubspec.yaml');
const webFamilies = [...baseCss.matchAll(/@font-face\s*\{([^}]*)\}/g)]
  .map((m) => [/font-family:\s*'?([^';]+?)'?\s*;/.exec(m[1])?.[1], /url\('\/_\/fonts\/([^']+)\.woff2'\)/.exec(m[1])?.[1]])
  .filter(([family, file]) => family && file);
const appFiles = [...pubspec.matchAll(/asset: assets\/fonts\/([^\s]+)\.ttf/g)].map((m) => m[1]);
for (const [family, file] of webFamilies) add('fonts', `${family} ${file}`, appFiles.includes(file), appFiles.includes(file) ? 'in the app' : 'woff2 on the web, no ttf in the app');
for (const token of ['display', 'body']) {
  const web = cssFamily(baseCss, token);
  const app = new RegExp(`${token}Family = '([^']+)'`).exec(dart)?.[1];
  add('fonts', `${token} family`, web === app, `web ${web}, app ${app}`);
  add('fonts', `${web} declared in pubspec`, new RegExp(`family: ${web}`).test(pubspec), '');
}
add('fonts', 'OFL licence in the app', statSync(join(root, 'app/assets/fonts/OFL.txt')).isFile(), '');

// 4. components
const manifest = JSON.parse(read('docs/theme-parity.json'));
const rule = (css, selector) => {
  const at = css.indexOf(selector);
  if (at < 0) return null;
  return css.slice(at, css.indexOf('}', at) + 1);
};
const slice = (code, scope) => {
  if (!scope) return code;
  const from = code.indexOf(scope[0]);
  const to = code.indexOf(scope[1], from + 1);
  return from < 0 || to < 0 ? null : code.slice(from, to);
};
// The value as a whole word: "44px" does not match "440px", "radius = 5" does not match "radius = 50".
const has = (text, value) => new RegExp(`${value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![0-9a-zA-Z%.])`, 'i').test(text);
for (const c of manifest.components) {
  const css = rule(read(c.css.file), c.css.selector);
  const code = slice(read(c.dart.file), c.dart.scope);
  if (css === null) {
    add('components', c.name, false, `rule "${c.css.selector}" not found in ${c.css.file}`);
    continue;
  }
  if (code === null) {
    add('components', c.name, false, `scope ${JSON.stringify(c.dart.scope)} not found in ${c.dart.file}`);
    continue;
  }
  const symbol = c.dart.symbol.split(/[ (,]/)[0].split('.').pop();
  add('components', `${c.name} symbol ${symbol}`, read(c.dart.file).includes(symbol), c.dart.file);
  for (const v of c.values) add('components', `${c.name} ${v.css}`, has(css, v.css) && has(code, v.dart), `${c.css.file} / ${c.dart.file}`);
}
const appCode = ['app/lib/src/theme/ak_theme.dart', 'app/lib/src/theme/ak_widgets.dart'].map(read).join('\n');
for (const a of manifest.appOnly) add('components', `app only ${a.dart}`, appCode.includes(a.dart), 'listed in docs/theme-parity.json but not in the app theme');

// 5. coverage: each class in the head of a rule of web/base.css
const classesIn = (text) => [...text.matchAll(/\.([a-z][a-z0-9-]*)/g)].map((m) => m[1]);
const listed = new Set([
  ...manifest.components.flatMap((c) => [...classesIn(c.css.selector), ...(c.alsoCovers ?? [])]),
  ...manifest.webOnly.flatMap((w) => classesIn(w.css)),
]);
const seen = new Set();
for (const m of baseCss.replace(/\/\*[\s\S]*?\*\//g, '').matchAll(/([^{}]+)\{/g)) if (!m[1].trim().startsWith('@')) classesIn(m[1]).forEach((c) => seen.add(c));
for (const cls of seen) add('coverage', `.${cls}`, listed.has(cls), 'styled in web/base.css; list it in docs/theme-parity.json');
const webOnlyElements = manifest.webOnly.filter((w) => !w.css.startsWith('.')).map((w) => w.css);
for (const m of baseCss.matchAll(/^(code|pre|kbd|table|input|select|textarea)\b/gm)) add('coverage', m[1], webOnlyElements.includes(m[1]), 'an element styled in web/base.css; list it in docs/theme-parity.json');

// 6. hard-coded colours in the screens: nothing in app/lib outside the theme folder builds a Color
const walk = (dir) => readdirSync(dir).flatMap((f) => (statSync(join(dir, f)).isDirectory() ? walk(join(dir, f)) : [join(dir, f)]));
for (const file of walk(join(root, 'app/lib')).filter((f) => f.endsWith('.dart') && !relative(root, f).split(/[\\/]/).includes('theme'))) {
  const hits = [...readFileSync(file, 'utf8').matchAll(/\bColor\s*\(|Color\.(from|fromARGB|fromRGBO)\b|Colors\.(?!transparent)/g)];
  if (hits.length) add('hard-coded', relative(root, file).replaceAll('\\', '/'), false, `${hits.length} colour(s) outside the theme`);
}
add('hard-coded', 'screens use the theme', !rows.some((r) => r.area === 'hard-coded' && !r.ok), '');

const bad = rows.filter((r) => !r.ok);
if (process.argv.includes('--json')) console.log(JSON.stringify({ ok: bad.length === 0, rows }, null, 2));
else {
  for (const area of [...new Set(rows.map((r) => r.area))]) {
    const list = rows.filter((r) => r.area === area);
    console.log(`${area}: ${list.filter((r) => r.ok).length}/${list.length} match`);
  }
  for (const r of bad) console.log(`  MISMATCH [${r.area}] ${r.item}: ${r.detail}`);
  console.log(bad.length ? `theme parity: ${bad.length} difference(s)` : 'theme parity: the website and the app themes match');
}
process.exit(bad.length ? 1 : 0);
