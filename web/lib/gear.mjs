// The 19 gear slots and the item in each, derived from the gear snapshots and the equip records.
import { t } from './i18n.mjs';

// side: where the slot sits on the paper doll.
export const SLOTS = [
  { n: 1, key: 'head', side: 'left' },
  { n: 2, key: 'neck', side: 'left' },
  { n: 3, key: 'shoulder', side: 'left' },
  { n: 15, key: 'back', side: 'left' },
  { n: 5, key: 'chest', side: 'left' },
  { n: 4, key: 'shirt', side: 'left' },
  { n: 19, key: 'tabard', side: 'left' },
  { n: 9, key: 'wrist', side: 'left' },
  { n: 10, key: 'hands', side: 'right' },
  { n: 6, key: 'waist', side: 'right' },
  { n: 7, key: 'legs', side: 'right' },
  { n: 8, key: 'feet', side: 'right' },
  { n: 11, key: 'finger1', side: 'right' },
  { n: 12, key: 'finger2', side: 'right' },
  { n: 13, key: 'trinket1', side: 'right' },
  { n: 14, key: 'trinket2', side: 'right' },
  { n: 16, key: 'mainhand', side: 'bottom' },
  { n: 17, key: 'offhand', side: 'bottom' },
  { n: 18, key: 'ranged', side: 'bottom' },
];

export const slotLabel = (n) => {
  const slot = SLOTS.find((s) => s.n === n);
  return slot ? t('slot.' + slot.key) : '';
};

const itemId = (v) => {
  const text = String(v ?? '');
  if (!/^\d+$/.test(text)) return 0;
  const n = Number(text);
  return Number.isSafeInteger(n) ? n : 0;
};

function parseIds(text) {
  const parts = typeof text === 'string' ? text.split(',') : [];
  return Array.from({ length: 19 }, (_, i) => itemId(parts[i]));
}

const lastOf = (steps, kind) => {
  for (let i = steps.length - 1; i >= 0; i--) if (steps[i].k === kind) return steps[i];
  return null;
};

// The snapshot of the highest level that has a gear string, with the time that it was taken (-Infinity when unknown).
function snapshotGear(char, steps) {
  const snaps = char?.addons?.Memories_Economy?.snap;
  if (!snaps || typeof snaps !== 'object') return null;
  const levels = Object.keys(snaps).map(Number).filter(Number.isFinite).sort((a, b) => b - a);
  for (const level of levels) {
    const gear = snaps[level]?.gear;
    if (typeof gear !== 'string') continue;
    const t = char.addons?.Memories?.snap?.[level]?.t ?? steps.find((s) => s.k === 'lv' && s.level === level)?.t;
    return { ids: parseIds(gear), t: Number.isFinite(t) ? t : -Infinity };
  }
  return null;
}

export function deriveGear(char, steps) {
  const list = steps ?? [];
  const ge = lastOf(list, 'ge');
  const fromRecord = ge ? { ids: parseIds(ge.ids), t: Number.isFinite(ge.t) ? ge.t : -Infinity } : null;
  const fromSnap = snapshotGear(char, list);
  const base = fromRecord && (!fromSnap || fromRecord.t >= fromSnap.t) ? fromRecord : (fromSnap ?? { ids: parseIds(''), t: -Infinity });
  const items = [...base.ids];
  const equips = list.filter((s) => s.k === 'eq' && Number.isInteger(s.slot) && s.slot >= 1 && s.slot <= 19 && Number.isSafeInteger(s.item) && s.item >= 0);
  for (const e of equips) if (e.t > base.t) items[e.slot - 1] = e.item;
  return items.map((item, i) => {
    const q = equips.findLast((e) => e.slot === i + 1 && e.item === item)?.quality;
    return { slot: i + 1, item, quality: Number.isInteger(q) ? q : null };
  });
}

export function wowheadUrl(id) {
  return Number.isSafeInteger(id) && id > 0 ? 'https://www.wowhead.com/classic/item=' + id : null;
}
