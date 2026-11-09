// Entry module of the character page: loads the data, reads the hash and shows the tab.
import { loadCharacter } from './lib/data.mjs';
import { formatHash, parseHash } from './lib/router.mjs';
import { className, raceName } from './lib/format.mjs';
import { deriveGear } from './lib/gear.mjs';
import { deriveSummary } from './lib/summary.mjs';
import { mountShell } from './ui/shell.mjs';
import { mountSummary } from './ui/summary.mjs';

const REPLACE_EVERY_MS = 500;
const $ = (id) => document.getElementById(id);
const status = $('status');

function stubTab(panel) {
  panel.textContent = 'This tab is not built yet.';
  return { show() {}, hide() {} };
}

async function main() {
  const entry = document.body.dataset.entry;
  if (!entry) {
    status.textContent = 'Open a character link.';
    return;
  }
  let data;
  try {
    data = await loadCharacter(new URL(entry, location.href), (url) => fetch(url));
  } catch (err) {
    status.textContent = 'This character could not be loaded. ' + err.message;
    return;
  }
  const summary = deriveSummary(data.char, data.steps);
  const p = summary.plate;
  $('headName').textContent = p.name || 'Memories';
  $('headLine').textContent =
    [p.level != null && 'Level ' + p.level, raceName(p.race), className(p.class), p.realm && p.region ? `${p.realm} (${p.region})` : p.realm]
      .filter(Boolean)
      .join(' ');

  let route = parseHash(location.hash);
  let last = 0;
  let timer = 0;
  let pending = null;
  const applyReplace = () => {
    timer = 0;
    last = Date.now();
    history.replaceState(null, '', formatHash(pending));
    route = pending;
    pending = null;
  };
  // A tab moves the camera or the playhead many times a second. The URL is replaced at most once each 500 ms and the
  // last call always lands.
  const setParams = (tab, params, layer = route.layer) => {
    if (tab !== route.tab) return;
    pending = { tab, layer, params: { ...params } };
    const wait = last + REPLACE_EVERY_MS - Date.now();
    if (wait <= 0) applyReplace();
    else if (!timer) timer = setTimeout(applyReplace, wait);
  };
  const ctx = { data, summary, setParams, status, legal: $('legal') };

  const shell = mountShell({
    onTab(tab) {
      if (tab === route.tab) return;
      history.pushState(null, '', formatHash({ tab, layer: tab === 'heatmaps' ? route.layer : null, params: {} }));
      show();
    },
  });
  const tabs = {
    summary: mountSummary(shell.panel('summary'), summary, deriveGear(data.char, data.steps), ctx),
    journey: stubTab(shell.panel('journey'), ctx),
    heatmaps: stubTab(shell.panel('heatmaps'), ctx),
  };

  let shown = null;
  function show() {
    clearTimeout(timer);
    timer = 0;
    pending = null;
    route = parseHash(location.hash);
    if (shown && shown !== route.tab) tabs[shown].hide();
    shell.show(route.tab);
    shown = route.tab;
    tabs[route.tab].show(route, ctx);
  }
  window.addEventListener('hashchange', show);
  show();
}

main();
