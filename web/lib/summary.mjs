// deriveSummary turns character.json and the journal records into the plain numbers that the Summary tab shows.

const STANDINGS = [
  { standing: 1, name: 'Hated', from: -42000, to: -6000 },
  { standing: 2, name: 'Hostile', from: -6000, to: -3000 },
  { standing: 3, name: 'Unfriendly', from: -3000, to: 0 },
  { standing: 4, name: 'Neutral', from: 0, to: 3000 },
  { standing: 5, name: 'Friendly', from: 3000, to: 9000 },
  { standing: 6, name: 'Honored', from: 9000, to: 21000 },
  { standing: 7, name: 'Revered', from: 21000, to: 42000 },
  { standing: 8, name: 'Exalted', from: 42000, to: 43000 },
];

export const standingName = (n) => STANDINGS.find((s) => s.standing === n)?.name ?? '';

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

function bandOf(standing, value) {
  const byStanding = STANDINGS.find((s) => s.standing === standing);
  if (byStanding) return byStanding;
  if (!isNum(value)) return STANDINGS[3];
  if (value <= STANDINGS[0].from) return STANDINGS[0];
  return [...STANDINGS].reverse().find((s) => value >= s.from) ?? STANDINGS[0];
}

export function reputationProgress(standing, value) {
  const band = bandOf(standing, value);
  if (!isNum(value)) return 0;
  return Math.min(1, Math.max(0, (value - band.from) / (band.to - band.from)));
}

// The snapshot of the highest level for which pick() finds a value, as { level, snap, value }.
function latestSnap(char, addon, pick) {
  const snaps = char?.addons?.[addon]?.snap;
  if (!snaps || typeof snaps !== 'object') return null;
  const levels = Object.keys(snaps).map(Number).filter(Number.isFinite).sort((a, b) => b - a);
  for (const level of levels) {
    const snap = snaps[level];
    const value = snap && typeof snap === 'object' ? pick(snap) : undefined;
    if (value !== undefined && value !== null) return { level, snap, value };
  }
  return null;
}

function lastOf(steps, ...kinds) {
  for (let i = steps.length - 1; i >= 0; i--) if (kinds.includes(steps[i].k)) return steps[i];
  return null;
}

function parseSkills(text) {
  const groups = new Map();
  if (typeof text !== 'string') return groups;
  for (const part of text.split(';')) {
    const colon = part.indexOf(':');
    const eq = part.lastIndexOf('=');
    const slash = part.indexOf('/', eq);
    if (colon < 1 || eq <= colon + 1 || slash < 0) continue;
    const rank = Number(part.slice(eq + 1, slash));
    const max = Number(part.slice(slash + 1));
    if (!Number.isFinite(rank) || !Number.isFinite(max)) continue;
    const group = part.slice(0, colon);
    if (!groups.has(group)) groups.set(group, new Map());
    groups.get(group).set(part.slice(colon + 1, eq), { rank, max });
  }
  return groups;
}

function derivePurse(char, steps) {
  const anchor = latestSnap(char, 'Memories_Economy', (s) => (isNum(s.money) ? s.money : undefined));
  const deltas = steps.filter((s) => s.k === 'mn' && isNum(s.delta));
  if (!anchor) return { copper: Math.max(0, deltas.reduce((a, s) => a + s.delta, 0)), about: true };
  const L = anchor.level;
  const snapT = char.addons?.Memories?.snap?.[L]?.t;
  const lv = steps.find((s) => s.k === 'lv' && s.level === L);
  const t = isNum(snapT) ? snapT : lv?.t;
  if (!isNum(t)) return { copper: Math.max(0, anchor.value), about: true };
  const later = deltas.filter((s) => s.t > t).reduce((a, s) => a + s.delta, 0);
  return { copper: Math.max(0, anchor.value + later), about: false };
}

function deriveSkills(char, steps) {
  const snap = latestSnap(char, 'Memories_Character', (s) => (typeof s.skills === 'string' ? s.skills : undefined));
  const groups = parseSkills(snap?.value);
  const known = new Map();
  for (const g of groups.values()) for (const [name, v] of g) known.set(name, v);
  const other = new Map();
  // The snapshot is rewritten on each skill check, so only a record that is newer than it can change a rank.
  const snapT = snap ? char?.addons?.Memories?.snap?.[snap.level]?.t : undefined;
  const latest = new Map();
  for (const s of steps) if (s.k === 'sk' && typeof s.name === 'string' && !(isNum(snapT) && s.t <= snapT)) latest.set(s.name, s);
  for (const [name, s] of latest) {
    const rank = isNum(s.rank) ? s.rank : 0;
    const max = isNum(s.max) ? s.max : rank;
    // The addon writes rank 0 and max 0 for a skill that the character no longer has.
    if (rank === 0 && max === 0) {
      known.delete(name);
      for (const g of groups.values()) g.delete(name);
      continue;
    }
    if (known.has(name)) Object.assign(known.get(name), { rank, max });
    else other.set(name, { rank, max });
  }
  for (const [group, g] of groups) if (!g.size) groups.delete(group);
  if (other.size) groups.set('Other', other);
  return [...groups].map(([group, skills]) => ({
    group,
    skills: [...skills].map(([name, v]) => ({ name, rank: v.rank, max: v.max })),
  }));
}

function deriveReputation(steps) {
  const latest = new Map();
  for (const s of steps) if (s.k === 'rp' && typeof s.faction === 'string') latest.set(s.faction, s);
  return [...latest.values()]
    .map((s) => ({
      faction: s.faction,
      label: typeof s.label === 'string' && s.label ? s.label : standingName(s.standing),
      standing: s.standing,
      value: s.value,
      progress: reputationProgress(s.standing, s.value),
    }))
    .sort((a, b) => (b.standing ?? 0) - (a.standing ?? 0) || a.faction.localeCompare(b.faction));
}

const dayKey = (t) => {
  const d = new Date(t * 1000);
  return d.getFullYear() + '-' + d.getMonth() + '-' + d.getDate();
};

function deriveStats(char, steps, sessions) {
  const count = (k) => steps.filter((s) => s.k === k).length;
  const killRecords = count('ki');
  const killsTotal = char?.addons?.Memories_Combat?.counts?.kills?.total;
  const fromCounts = isNum(killsTotal) && killsTotal > killRecords;
  const delta = (pick) => steps.filter((s) => s.k === 'mn' && isNum(s.delta) && pick(s.delta)).reduce((a, s) => a + Math.abs(s.delta), 0);
  const starts = sessions.map((s) => s.start).filter(isNum);
  const ends = sessions.map((s) => s.last).filter(isNum);
  const foot = char?.addons?.Memories?.counts?.distance?.foot;
  return {
    played: sessions.reduce((a, s) => a + Math.max(0, (s.played1 ?? 0) - (s.played0 ?? 0)), 0),
    sessions: sessions.length,
    days: new Set(starts.map(dayKey)).size,
    firstSeen: starts.length ? Math.min(...starts) : (char?.first?.t ?? null),
    lastSeen: ends.length ? Math.max(...ends) : null,
    levels: count('lv'),
    quests: count('qt'),
    areas: count('di'),
    zones: new Set(steps.filter((s) => s.k === 'zo' && s.zone).map((s) => s.zone)).size,
    kills: fromCounts ? killsTotal : killRecords,
    killsFromCounts: fromCounts,
    deaths: count('de') + count('hc'),
    dungeons: count('dn'),
    bosses: steps.filter((s) => s.k === 'bo' && s.success === 1).length,
    gathered: count('ga'),
    fished: count('fs'),
    loot: count('lo'),
    flights: count('tx'),
    screenshots: steps.filter((s) => s.k === 'ss' && s.screenshot).length,
    distance: isNum(foot) ? foot : 0,
    earned: delta((d) => d > 0),
    spent: delta((d) => d < 0),
  };
}

export function deriveSummary(char, steps) {
  const c = char ?? {};
  const list = steps ?? [];
  const zo = lastOf(list, 'zo');
  const gu = lastOf(list, 'gu');
  const rk = lastOf(list, 'rk');
  const zoneSnap = latestSnap(c, 'Memories', (s) => (typeof s.zone === 'string' ? s.zone : undefined));
  const pvpSnap = latestSnap(c, 'Memories_Social', (s) => (typeof s.pvp?.title === 'string' ? s.pvp.title : undefined));
  const ta = lastOf(list, 'ta');
  const sessions = [...(c.sessions ?? [])]
    .sort((a, b) => a.start - b.start)
    .map((s) => ({ ...s, length: Math.max(0, (s.last ?? s.start) - s.start) }));
  return {
    plate: {
      name: c.name ?? '',
      surname: c.surname ?? '',
      level: c.level ?? null,
      race: c.race ?? '',
      class: c.class ?? '',
      sex: c.sex ?? null,
      faction: c.faction ?? '',
      realm: c.realmLabel || c.realm || '',
      region: c.region ?? '',
      hardcore: c.flags?.hardcore === true,
      selfFound: c.flags?.selfFoundAllowed === true,
      zone: zo?.zone ?? zoneSnap?.value ?? '',
      guild: gu && gu.guild ? { guild: gu.guild, rank: gu.rank ?? '' } : null,
      pvp: rk ? (rk.title ?? '') : (pvpSnap?.value ?? ''),
    },
    purse: derivePurse(c, list),
    skills: deriveSkills(c, list),
    reputation: deriveReputation(list),
    talents: ta ? { spent: ta.spent ?? 0, unspent: ta.unspent ?? 0 } : null,
    stats: deriveStats(c, list, sessions),
    sessions,
  };
}
