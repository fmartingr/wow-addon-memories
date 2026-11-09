// Takes a PNG picture of a web page with a headless Firefox (WebDriver BiDi), for the theme parity review.
// Usage: node scripts/theme-shot.mjs <url> <out.png> [width=1000] [height=900] [waitMs=1500]
// It starts its own Firefox with a private profile and stops only that one.
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [url, out, w = '1000', h = '900', wait = '1500'] = process.argv.slice(2);
if (!url || !out) {
  console.error('usage: node scripts/theme-shot.mjs <url> <out.png> [width] [height] [waitMs]');
  process.exit(2);
}
// A free port: the system gives one and it is closed again before Firefox opens it.
const port = await new Promise((res) => {
  const srv = createServer().listen(0, '127.0.0.1', () => {
    const { port } = srv.address();
    srv.close(() => res(port));
  });
});
const profile = mkdtempSync(join(tmpdir(), 'theme-shot-'));
const ff = spawn('firefox', ['--headless', '--no-remote', '--profile', profile, `--remote-debugging-port=${port}`], {
  env: { ...process.env, MOZ_REMOTE_ALLOW_SYSTEM_ACCESS: '1' },
  stdio: 'ignore',
});
const stop = () => {
  ff.kill();
  rmSync(profile, { recursive: true, force: true });
};
ff.on('error', (e) => {
  console.error('could not start firefox: ' + e.message);
  stop();
  process.exit(2);
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function connect() {
  for (let i = 0; i < 60; i++) {
    try {
      const ws = new WebSocket(`ws://127.0.0.1:${port}/session`);
      await new Promise((res, rej) => {
        ws.onopen = res;
        ws.onerror = rej;
      });
      return ws;
    } catch {
      await sleep(500);
    }
  }
  throw new Error('Firefox did not open its remote port');
}

try {
  const ws = await connect();
  let id = 0;
  const pending = new Map();
  ws.onmessage = (m) => {
    const d = JSON.parse(m.data);
    const p = pending.get(d.id);
    if (!p) return;
    pending.delete(d.id);
    d.type === 'error' ? p.rej(new Error(d.error + ': ' + d.message)) : p.res(d.result);
  };
  const send = (method, params = {}) =>
    new Promise((res, rej) => {
      const i = ++id;
      pending.set(i, { res, rej });
      ws.send(JSON.stringify({ id: i, method, params }));
    });
  await send('session.new', { capabilities: {} });
  const { context } = await send('browsingContext.create', { type: 'tab' });
  await send('browsingContext.setViewport', { context, viewport: { width: +w, height: +h }, devicePixelRatio: 1 });
  await send('browsingContext.navigate', { context, url, wait: 'complete' });
  await sleep(+wait);
  const shot = await send('browsingContext.captureScreenshot', { context, origin: 'viewport' });
  writeFileSync(out, Buffer.from(shot.data, 'base64'));
  console.log('wrote ' + out);
  ws.close();
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
} finally {
  stop();
}
