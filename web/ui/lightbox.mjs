// The full size view of a screenshot, shared by the tabs. A click or Escape closes it, and the focus goes back to the
// element that had it.
import { t } from '../lib/i18n.mjs';

// A click that arrives this soon after the open is the same tap that opened the view, so it does not close it.
const CLICK_GUARD_MS = 250;

export function createLightbox(doc = document) {
  const box = doc.getElementById('lightbox');
  const img = doc.getElementById('lightboxImg');
  const cap = doc.getElementById('lightboxCap');
  let openedAt = 0;
  let back = null;

  const isOpen = () => !box.hidden;
  function close() {
    if (!isOpen()) return;
    box.hidden = true;
    img.removeAttribute('src');
    back?.focus?.({ preventScroll: true });
    back = null;
  }
  function open(url, caption) {
    back = doc.activeElement;
    img.hidden = false;
    img.onerror = () => {
      img.hidden = true;
      cap.textContent = t('lightbox.missing');
    };
    if (url) {
      img.src = url;
      cap.textContent = caption;
    } else img.onerror();
    box.hidden = false;
    openedAt = performance.now();
    box.focus?.({ preventScroll: true });
  }

  box.tabIndex = -1;
  box.addEventListener('click', () => {
    if (performance.now() - openedAt > CLICK_GUARD_MS) close();
  });
  // The capture on the document runs before the keyboard listeners of the tabs on the window, so Escape closes only
  // the view.
  doc.addEventListener(
    'keydown',
    (e) => {
      if (!isOpen()) return;
      if (e.code === 'Escape') close();
      e.stopPropagation();
    },
    true,
  );
  return { open, close, isOpen };
}
