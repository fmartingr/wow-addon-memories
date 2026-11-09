// The frame: tab buttons with keyboard support, and the bottom sheet that holds the side panels on a phone.

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
