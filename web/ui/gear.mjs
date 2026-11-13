// The paper doll: the 19 gear slots as Wowhead links, and the detail of the selected slot.
import { esc, qualityColour, qualityName } from '../lib/format.mjs';
import { SLOTS, slotLabel, wowheadUrl } from '../lib/gear.mjs';
import { t } from '../lib/i18n.mjs';

const WIDGET = 'https://wow.zamimg.com/js/tooltips.js';
let widget = null;

// loadWidget adds the Wowhead script once: first the settings file, then the script. A load error leaves the plain links.
export function loadWidget(doc = document) {
  if (widget) return widget;
  const add = (src) =>
    new Promise((resolve, reject) => {
      const el = doc.createElement('script');
      el.src = src;
      el.onload = resolve;
      el.onerror = () => reject(new Error('could not load ' + src));
      doc.head.append(el);
    });
  widget = add('/_/wowhead.js').then(() => add(WIDGET));
  widget.catch(() => {});
  return widget;
}

const refreshWidget = () => globalThis.$WowheadPower?.refreshLinks?.();

function slotHtml(s, selected, flavor) {
  const sel = selected === s.slot ? ' selected' : '';
  const label = `<span class="slot-label">${esc(slotLabel(s.slot))}</span>`;
  const url = wowheadUrl(s.item, undefined, flavor);
  if (!url) {
    return `<div class="slot-cell">${label}<button type="button" class="slot empty${sel}" data-slot="${s.slot}" aria-label="${esc(t('gear.empty', { slot: slotLabel(s.slot) }))}"></button></div>`;
  }
  const q = Number.isInteger(s.quality) && s.quality >= 0 && s.quality <= 5 ? ` q${s.quality}` : '';
  return `<div class="slot-cell">${label}<a class="slot${q}${sel}" data-slot="${s.slot}" href="${url}" target="_blank" rel="noopener noreferrer">${esc(t('gear.item', { id: s.item }))}</a></div>`;
}

function detailHtml(s, flavor) {
  if (!s) return '';
  const title = esc(slotLabel(s.slot));
  const url = wowheadUrl(s.item, undefined, flavor);
  if (!url) return `<h4>${title}</h4><p class="sub">${esc(t('gear.nothing'))}</p>`;
  return `<h4>${title}</h4><p>${esc(t('gear.item', { id: s.item }))} <span class="q-name q${Number.isInteger(s.quality) ? s.quality : 1}">${esc(s.quality == null ? '' : qualityName(s.quality))}</span></p>
<p><a class="wh-link" href="${url}" target="_blank" rel="noopener noreferrer" data-wh-rename-link="false" data-wh-icon-add="false">${esc(t('gear.open'))}</a></p>`;
}

export function paintDoll(root) {
  for (const el of root.querySelectorAll('a.slot[class*=" q"]')) {
    const m = /\bq(\d)\b/.exec(el.className);
    if (m) el.style.setProperty('--c', qualityColour(Number(m[1])));
  }
  for (const el of root.querySelectorAll('.q-name')) {
    const m = /\bq(\d)\b/.exec(el.className);
    if (m) el.style.setProperty('--c', qualityColour(Number(m[1])));
  }
}

export function dollHtml(gear, selected, flavor = null) {
  const order = (name) => SLOTS.filter((s) => s.side === name).map((s) => gear.find((g) => g.slot === s.n));
  const column = (name) => `<div class="doll-col ${name}">${order(name).map((s) => slotHtml(s, selected, flavor)).join('')}</div>`;
  return `<h3 class="panel-title">${esc(t('gear.title'))}</h3>
<div class="doll">${column('left')}${column('right')}</div>
<div class="doll-bottom">${order('bottom').map((s) => slotHtml(s, selected, flavor)).join('')}</div>
<div class="slot-detail" aria-live="polite">${detailHtml(gear.find((g) => g.slot === selected), flavor)}</div>`;
}

// mountPaperDoll renders into el. show(slot) must run when the Summary tab is visible: it loads the widget the first
// time there is an item to show, and selects the slot of the hash.
export function mountPaperDoll(el, gear, { setParams, data }) {
  const flavor = data?.char?.flavor ?? null;
  el.classList.add('panel', 'paperdoll');
  let selected = null;
  const hasItems = gear.some((g) => g.item > 0);
  const render = () => {
    el.innerHTML = dollHtml(gear, selected, flavor);
    paintDoll(el);
    refreshWidget();
  };
  const select = (n, fromHash) => {
    selected = n;
    render();
    if (!fromHash) setParams('summary', n ? { slot: n } : {});
  };
  el.addEventListener('click', (e) => {
    const slot = e.target.closest?.('.slot');
    if (!slot) return;
    if (e.ctrlKey || e.metaKey || e.shiftKey || e.button === 1) return;
    e.preventDefault();
    select(Number(slot.dataset.slot), false);
  });
  render();
  return {
    show(slot) {
      if (hasItems) loadWidget().then(refreshWidget, () => {});
      const n = Number.isInteger(slot) ? slot : null;
      if (n !== selected) select(n, true);
    },
  };
}
