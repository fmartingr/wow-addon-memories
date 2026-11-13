// The Screenshots tab: a grid of the screenshots of the character, oldest first, with their notes. A click opens the
// full size view.
import { screenshotUrl } from '../lib/data.mjs';
import { shotCaption, shotEvents, shotWhy } from '../lib/events.mjs';
import { esc, fmtDate } from '../lib/format.mjs';
import { t } from '../lib/i18n.mjs';

export function shotsHtml(items) {
  if (!items.length) return `<p class="shots-empty">${esc(t('shots.empty'))}</p>`;
  const cells = items
    .map(({ e, url }, i) => {
      const why = shotWhy(e);
      const label = shotCaption(e);
      const pic = url
        ? `<img src="${esc(url)}" alt="" loading="lazy" decoding="async">`
        : `<span class="shot-missing">${esc(t('lightbox.missing'))}</span>`;
      return `<li><button type="button" class="shot-card" data-i="${i}" aria-label="${esc(label)}"><span class="shot-thumb">${pic}</span>${
        why ? `<span class="shot-note">${esc(why)}</span>` : ''
      }<span class="shot-date">${esc(fmtDate(e.t))}</span></button></li>`;
    })
    .join('');
  return `<ul class="shots">${cells}</ul>`;
}

export function createScreenshotsTab(panel, ctx) {
  let items = null;

  function build() {
    items = shotEvents(ctx.data.steps).map((e) => ({ e, url: screenshotUrl(ctx.data, e.screenshot) }));
    panel.innerHTML = shotsHtml(items);
    // A file that fails to load shows the same text as the full size view.
    panel.addEventListener(
      'error',
      (ev) => {
        const img = ev.target;
        if (!(img instanceof HTMLImageElement)) return;
        const note = document.createElement('span');
        note.className = 'shot-missing';
        note.textContent = t('lightbox.missing');
        img.replaceWith(note);
      },
      true,
    );
    panel.addEventListener('click', (ev) => {
      const card = ev.target.closest?.('.shot-card');
      const item = card && items[Number(card.dataset.i)];
      if (item) ctx.lightbox.open(item.url, shotCaption(item.e));
    });
  }

  return {
    show() {
      if (!items) build();
    },
    hide() {
      ctx.lightbox.close();
    },
  };
}
