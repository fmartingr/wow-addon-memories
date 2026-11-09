import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '../..');
const script = join(repo, 'scripts/theme-parity.mjs');

// A copy of the files that the check reads, so a test can change them.
function copy() {
  const dir = mkdtempSync(join(tmpdir(), 'parity-'));
  for (const f of ['web/base.css', 'web/style.css', 'web/lib/format.mjs', 'app/pubspec.yaml', 'app/assets/fonts/OFL.txt', 'docs/theme-parity.json']) {
    mkdirSync(dirname(join(dir, f)), { recursive: true });
    cpSync(join(repo, f), join(dir, f));
  }
  cpSync(join(repo, 'app/lib/src'), join(dir, 'app/lib/src'), { recursive: true });
  return dir;
}

const run = (dir) => spawnSync('node', [script, '--json'], { env: { ...process.env, THEME_PARITY_ROOT: dir }, encoding: 'utf8' });
const change = (dir, file, from, to) => {
  const p = join(dir, file);
  const text = readFileSync(p, 'utf8');
  assert.ok(text.includes(from), `${file} has ${from}`);
  writeFileSync(p, text.replace(from, to));
};

test('the website and the app themes match', () => {
  const r = spawnSync('node', [script, '--json'], { encoding: 'utf8' });
  const out = JSON.parse(r.stdout);
  assert.deepEqual(out.rows.filter((x) => !x.ok), []);
  assert.equal(r.status, 0);
  assert.ok(out.rows.length > 60);
});

test('a token that changes on the web only is found', () => {
  const dir = copy();
  try {
    change(dir, 'web/base.css', '--gold: #d5a64f;', '--gold: #d5a64e;');
    const out = JSON.parse(run(dir).stdout);
    assert.ok(out.rows.some((r) => r.area === 'tokens' && r.item === 'gold' && !r.ok));
    assert.equal(run(dir).status, 1);
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test('a component value that changes in the app only is found', () => {
  const dir = copy();
  try {
    change(dir, 'app/lib/src/theme/ak_theme.dart', '0xFF4A3818', '0xFF4A3819');
    const out = JSON.parse(run(dir).stdout);
    assert.ok(out.rows.some((r) => r.area === 'components' && r.item.startsWith('btn #4a3818') && !r.ok));
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test('a new web component that the manifest does not list is found', () => {
  const dir = copy();
  try {
    writeFileSync(join(dir, 'web/base.css'), readFileSync(join(dir, 'web/base.css'), 'utf8') + '\n.badge { color: red; }\n');
    const out = JSON.parse(run(dir).stdout);
    assert.ok(out.rows.some((r) => r.area === 'coverage' && r.item === '.badge' && !r.ok));
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test('a hard-coded colour in a screen is found', () => {
  const dir = copy();
  try {
    writeFileSync(join(dir, 'app/lib/src/ui/extra.dart'), 'final c = Color(0xFF123456);\n');
    const out = JSON.parse(run(dir).stdout);
    assert.ok(out.rows.some((r) => r.area === 'hard-coded' && r.item.endsWith('extra.dart') && !r.ok));
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test('a missing font file in the app is found', () => {
  const dir = copy();
  try {
    change(dir, 'app/pubspec.yaml', 'assets/fonts/Cinzel-Variable.ttf', 'assets/fonts/Other.ttf');
    const out = JSON.parse(run(dir).stdout);
    assert.ok(out.rows.some((r) => r.area === 'fonts' && r.item.startsWith('Cinzel') && !r.ok));
  } finally {
    rmSync(dir, { recursive: true });
  }
});
