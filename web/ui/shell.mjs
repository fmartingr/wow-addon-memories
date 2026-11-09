// The frame: tab buttons with keyboard support, and the bottom sheet that holds the side panels on a phone.
import { LANGS, t } from '../lib/i18n.mjs';

// applyTexts fills the static text of the page from the catalog: data-i18n sets the text, data-i18n-aria the aria-label
// and data-i18n-title the title. The values are text, never markup.
export function applyTexts(root = document) {
  for (const el of root.querySelectorAll('[data-i18n]')) el.textContent = t(el.dataset.i18n);
  for (const el of root.querySelectorAll('[data-i18n-aria]')) el.setAttribute('aria-label', t(el.dataset.i18nAria));
  for (const el of root.querySelectorAll('[data-i18n-title]')) el.setAttribute('title', t(el.dataset.i18nTitle));
}

// pickerHref is the link of a language in the picker. The other query parameters and the hash (tab, camera, selection)
// go along, and the server keeps them across its redirect.
export const pickerHref = (code, hash = '', search = '') => {
  const query = new URLSearchParams(search);
  query.set('lang', code);
  return `?${query}${hash}`;
};

// syncPicker points each link of the picker at its language with the current query and hash, and marks the page
// language.
export function syncPicker(nav, lang, hash = '', search = '') {
  for (const a of nav.querySelectorAll('a[hreflang]')) {
    const code = a.getAttribute('hreflang');
    if (!LANGS.includes(code)) continue;
    a.setAttribute('href', pickerHref(code, hash, search));
    if (code === lang) a.setAttribute('aria-current', 'true');
    else a.removeAttribute('aria-current');
  }
}

export const SHEET_STATES = ['peek', 'half', 'full'];

export function mountShell({ onTab }) {
  const tablist = document.querySelector('[role="tablist"]');
  const buttons = [...tablist.querySelectorAll('[role="tab"]')];
  const panels = new Map(buttons.map((b) => [b.dataset.tab, document.getElementById(b.getAttribute('aria-controls'))]));

  buttons.forEach((b) => b.addEventListener('click', () => onTab(b.dataset.tab)));
  tablist.addEventListener('keydown', (e) => {
    const i = buttons.indexOf(document.activeElement);
    if (i < 0) return;
    const to = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: buttons.length - 1 }[e.key];
    if (to === undefined) return;
    e.preventDefault();
    buttons[(to + buttons.length) % buttons.length].focus();
  });

  return {
    show(tab) {
      for (const b of buttons) {
        const on = b.dataset.tab === tab;
        b.setAttribute('aria-selected', String(on));
        b.tabIndex = on ? 0 : -1;
        panels.get(b.dataset.tab).hidden = !on;
      }
      document.body.dataset.tab = tab;
    },
    panel: (tab) => panels.get(tab),
  };
}

// createSheet makes el a bottom sheet with the states peek, half and full. The handle cycles through the states, and a
// drag on the handle moves to the next state in the direction of the drag. On a wide screen the CSS makes it a side panel.
export function createSheet(el) {
  const handle = el.querySelector('.sheet-handle');
  let state = 'peek';
  const set = (next) => {
    if (!SHEET_STATES.includes(next)) return;
    state = next;
    el.dataset.state = next;
    handle?.setAttribute('aria-expanded', String(next !== 'peek'));
  };
  set(el.dataset.state ?? 'peek');
  if (handle) {
    let startY = null;
    let moved = false;
    handle.addEventListener('pointerdown', (e) => {
      startY = e.clientY;
      moved = false;
      handle.setPointerCapture?.(e.pointerId);
    });
    handle.addEventListener('pointermove', (e) => {
      if (startY === null || moved || Math.abs(e.clientY - startY) < 24) return;
      moved = true;
      const i = SHEET_STATES.indexOf(state) + (e.clientY < startY ? 1 : -1);
      set(SHEET_STATES[Math.min(SHEET_STATES.length - 1, Math.max(0, i))]);
    });
    handle.addEventListener('pointerup', () => {
      startY = null;
    });
    handle.addEventListener('pointercancel', () => {
      startY = null;
    });
    handle.addEventListener('click', () => {
      if (moved) {
        moved = false;
        return;
      }
      set(SHEET_STATES[(SHEET_STATES.indexOf(state) + 1) % SHEET_STATES.length]);
    });
  }
  return { set, state: () => state };
}
