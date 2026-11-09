// The hash of the page: #<tab>[/<layer>][?<params>]. See the hash format table of the redesign spec.
import { H, W } from '../zones.mjs';

export const TABS = ['summary', 'journey', 'heatmaps'];
export const LAYERS = ['presence', 'kills', 'deaths', 'gathering', 'fishing', 'quests', 'loot'];
export const PROFS = ['all', 'mining', 'herbalism', 'skinning', 'other'];

const NUMBER = /^-?\d+(\.\d+)?$/;
const INTEGER = /^\d+$/;

const number = (v, min, max, minOpen) => {
  if (!NUMBER.test(v)) return undefined;
  const n = Number(v);
  return Number.isFinite(n) && (minOpen ? n > min : n >= min) && n <= max ? n : undefined;
};

const integer = (v, min, max) => {
  if (!INTEGER.test(v)) return undefined;
  const n = Number(v);
  return Number.isSafeInteger(n) && n >= min && n <= max ? n : undefined;
};

// Each key has the tabs it belongs to, a reader that returns undefined for a bad value, and a writer.
const PARAMS = {
  slot: { tabs: ['summary'], read: (v) => integer(v, 1, 19), write: String },
  x: { tabs: ['journey', 'heatmaps'], read: (v) => number(v, 0, W), write: (n) => n.toFixed(1) },
  y: { tabs: ['journey', 'heatmaps'], read: (v) => number(v, 0, H), write: (n) => n.toFixed(1) },
  z: { tabs: ['journey', 'heatmaps'], read: (v) => number(v, 0, 40, true), write: (n) => n.toFixed(2) },
  at: { tabs: ['journey'], read: (v) => integer(v, 0, Number.MAX_SAFE_INTEGER), write: String },
  ev: {
    tabs: ['journey'],
    read: (v) => (/^\d{1,15}\.[a-z]{2,3}$/.test(v) ? v : undefined),
    write: String,
  },
  prof: { tabs: ['heatmaps'], read: (v) => (PROFS.includes(v) ? v : undefined), write: String },
};

export function parseHash(hash) {
  const raw = String(hash ?? '').replace(/^#/, '');
  const q = raw.indexOf('?');
  const path = q < 0 ? raw : raw.slice(0, q);
  const query = q < 0 ? '' : raw.slice(q + 1);
  const [t, l] = path.split('/');
  const tab = TABS.includes(t) ? t : 'summary';
  const layer = tab === 'heatmaps' ? (LAYERS.includes(l) ? l : 'presence') : null;
  const params = {};
  const found = new URLSearchParams(query);
  for (const [key, spec] of Object.entries(PARAMS)) {
    if (!spec.tabs.includes(tab) || !found.has(key)) continue;
    if (key === 'prof' && layer !== 'gathering') continue;
    const value = spec.read(found.get(key));
    if (value !== undefined) params[key] = value;
  }
  return { tab, layer, params };
}

export function formatHash({ tab, layer, params }) {
  const t = TABS.includes(tab) ? tab : 'summary';
  const l = t === 'heatmaps' ? (LAYERS.includes(layer) ? layer : 'presence') : null;
  const out = new URLSearchParams();
  for (const [key, spec] of Object.entries(PARAMS)) {
    const v = params?.[key];
    if (!spec.tabs.includes(t) || v === undefined || v === null) continue;
    if (key === 'prof' && l !== 'gathering') continue;
    const written = spec.write(v);
    if (spec.read(written) !== undefined) out.set(key, written);
  }
  const query = out.toString().replaceAll('%2E', '.');
  return '#' + t + (l ? '/' + l : '') + (query ? '?' + query : '');
}
