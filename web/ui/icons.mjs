// Marker icons: the coin of each journal kind (web/icons/, the same icons as the addon's map). The map and the timeline
// share them. An icon that has not loaded yet, or a kind with no icon, shows as a plain grey disc.
import { iconUrl } from '../lib/eventicons.mjs';

// A coin is this many radii wide, so it covers the same space as a marker of radius r.
export const COIN = 2.4;

const images = new Map();
let changed = null;

// fn runs each time an icon finishes loading, so the map and the timeline can draw again.
export function onIconsLoaded(fn) {
  changed = fn;
}

function image(kind) {
  if (images.has(kind)) return images.get(kind);
  const url = iconUrl(kind);
  let img = null;
  if (url && typeof Image !== 'undefined') {
    img = new Image();
    img.onload = () => changed?.();
    img.src = url;
  }
  images.set(kind, img);
  return img;
}

export function icon(ctx, kind, x, y, r, alpha) {
  ctx.save();
  ctx.globalAlpha = alpha == null ? 1 : alpha;
  const img = image(kind);
  if (img && img.complete && img.naturalWidth > 0) {
    const d = r * COIN;
    ctx.drawImage(img, x - d / 2, y - d / 2, d, d);
  } else {
    ctx.beginPath();
    ctx.arc(x, y, r, 0, 6.2832);
    ctx.fillStyle = '#aaa';
    ctx.fill();
  }
  ctx.restore();
}
