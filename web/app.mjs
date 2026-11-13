// Entry module of the character page: loads the data, reads the hash and shows the tab.
import { errorText, loadCharacter } from './lib/data.mjs';
import { formatHash, parseHash } from './lib/router.mjs';
import { className, raceName } from './lib/format.mjs';
import { deriveGear } from './lib/gear.mjs';
import { currentLang, loadCatalog, pickLang, setLang, t } from './lib/i18n.mjs';
import { deriveSummary } from './lib/summary.mjs';
import { applyTexts, mountShell, syncPicker } from './ui/shell.mjs';
import { buildModel } from './lib/model.mjs';
import { createHeatmapsTab } from './ui/heatmaps.mjs';
import { createJourneyTab } from './ui/journey.mjs';
import { createLightbox } from './ui/lightbox.mjs';
import { createScreenshotsTab } from './ui/screenshots.mjs';
import { mountSummary } from './ui/summary.mjs';

const REPLACE_EVERY_MS = 500;
const $ = (id) => document.getElementById(id);
const status = $('status');

// useLang loads the catalog of a code, makes it the language of the page and fills the static text. A catalog that
// cannot load leaves English.
async function useLang(code) {
  setLang(code, code === 'en' ? null : await loadCatalog(code));
  document.documentElement.lang = currentLang();
  applyTexts();
}

// The picker links keep the query and the hash of the page. The tabs change the hash with history.pushState and
// history.replaceState, which fire no event, so the links also read it when a pointer or the keyboard reaches them.
// The returned function marks the page language again after a change.
function mountPicker() {
  const nav = $('langPicker');
  if (!nav) return () => {};
  const sync = () => syncPicker(nav, currentLang(), location.hash, location.search);
  sync();
  window.addEventListener('hashchange', sync);
  for (const type of ['pointerover', 'focusin', 'click', 'auxclick']) nav.addEventListener(type, sync);
  return sync;
}

async function main() {
  const html = document.documentElement;
  const serverLang = html.lang;
  const entry = document.body.dataset.entry;
  // The character downloads while the catalog loads.
  const loading = entry ? loadCharacter(new URL(entry, location.href), (url) => fetch(url)) : null;
  loading?.catch(() => {});
  await useLang(serverLang);
  const markLang = mountPicker();
  if (!entry) {
    status.textContent = t('app.open');
    return;
  }
  let data;
  try {
    data = await loading;
  } catch (err) {
    status.textContent = t('app.loadError', { error: errorText(err) });
    return;
  }
  const code = pickLang({ from: html.dataset.langFrom, current: serverLang, charLocale: data.char?.locale });
  // A server language whose catalog failed is not asked for twice.
  if (code !== serverLang && code !== currentLang()) {
    await useLang(code);
    markLang();
  }
  const summary = deriveSummary(data.char, data.steps);
  const p = summary.plate;
  $('headName').textContent = p.name || 'Memories';
  $('headLine').textContent = [
    p.level != null && t('head.level', { level: p.level }),
    raceName(p.race),
    className(p.class),
    p.realm && p.region ? t('head.realm', { realm: p.realm, region: p.region }) : p.realm,
  ]
    .filter(Boolean)
    .join(' ');

  let route = parseHash(location.hash);
  let heatLayer = route.layer ?? 'presence';
  let last = 0;
  let timer = 0;
  let pending = null;
  const applyReplace = () => {
    timer = 0;
    last = Date.now();
    history.replaceState(null, '', formatHash(pending));
    route = pending;
    if (route.tab === 'heatmaps') heatLayer = route.layer;
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
  let model = null;
  // The map tabs share one model; it is built when the first of them opens.
  const getModel = () => (model ??= buildModel(data.char, data.steps, data.trail));
  const ctx = { data, summary, setParams, status, legal: $('legal'), model: getModel, lightbox: createLightbox() };

  const shell = mountShell({
    onTab(tab) {
      if (tab === route.tab) return;
      if (pending) {
        clearTimeout(timer);
        applyReplace();
      }
      history.pushState(null, '', formatHash({ tab, layer: tab === 'heatmaps' ? heatLayer : null, params: {} }));
      show();
    },
  });
  const tabs = {
    summary: mountSummary(shell.panel('summary'), summary, deriveGear(data.char, data.steps), ctx),
    journey: createJourneyTab(shell.panel('journey'), ctx),
    heatmaps: createHeatmapsTab(shell.panel('heatmaps'), ctx),
    screenshots: createScreenshotsTab(shell.panel('screenshots'), ctx),
  };

  let shown = null;
  function show() {
    clearTimeout(timer);
    timer = 0;
    pending = null;
    route = parseHash(location.hash);
    if (route.tab === 'heatmaps') heatLayer = route.layer;
    if (shown && shown !== route.tab) tabs[shown].hide();
    shell.show(route.tab);
    shown = route.tab;
    tabs[route.tab].show(route, ctx);
  }
  window.addEventListener('hashchange', show);
  show();
}

main();
