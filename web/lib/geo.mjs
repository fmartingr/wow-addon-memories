// Map geometry. A zone's local coordinates run 0..10000 and map linearly onto its rectangle in world units.
import { ZONES } from '../zones.mjs';

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

export function toWorld(m, x, y, zones = ZONES) {
  const z = zones[m];
  if (!z || !isNum(x) || !isNum(y)) return null;
  const r = z.rect;
  return [r[0] + (x / 10000) * (r[1] - r[0]), r[2] + (y / 10000) * (r[3] - r[2])];
}

// zoneAt returns the id of the smallest zone (type 3) that holds the point, else the smallest other area, else null.
export function zoneAt(wx, wy, zones = ZONES) {
  let best = null;
  for (const [id, z] of Object.entries(zones)) {
    const [x0, x1, y0, y1] = z.rect;
    if (wx < x0 || wx > x1 || wy < y0 || wy > y1) continue;
    const area = (x1 - x0) * (y1 - y0);
    const zone = z.type === 3;
    if (!best || (zone && !best.zone) || (zone === best.zone && area < best.area)) best = { id: Number(id), area, zone };
  }
  return best ? best.id : null;
}

// The bounds [x0, x1, y0, y1] of the points that the arrays hold, or null when there are none.
export function boundsOf(wx, wy, count = wx.length) {
  if (!count) return null;
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  for (let i = 0; i < count; i++) {
    const x = wx[i], y = wy[i];
    if (x < x0) x0 = x;
    if (x > x1) x1 = x;
    if (y < y0) y0 = y;
    if (y > y1) y1 = y;
  }
  return [x0, x1, y0, y1];
}
