import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { deriveSummary, reputationProgress, standingName } from '../lib/summary.mjs';
import { paint, summaryHtml } from '../ui/summary.mjs';

const load = (dir) => {
  const u = (f) => new URL(`./fixtures/${dir}/${f}`, import.meta.url);
  const char = JSON.parse(readFileSync(u('character.json'), 'utf8'));
  const steps = readFileSync(u('journey.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  return { char, steps };
};

test('the plate of the fixture', () => {
  const { char, steps } = load('nandu');
  const s = deriveSummary(char, steps);
  assert.equal(s.plate.name, 'Ñandú');
  assert.equal(s.plate.class, 'HUNTER');
  assert.equal(s.plate.race, 'NightElf');
  assert.equal(s.plate.level, 10);
  assert.equal(s.plate.region, 'EU');
  assert.equal(s.plate.zone, 'Bosque de Elwynn');
  assert.equal(s.plate.hardcore, false);
  assert.equal(s.plate.guild, null);
  assert.equal(s.stats.sessions, 1);
  assert.equal(s.stats.screenshots, steps.filter((r) => r.k === 'ss' && r.screenshot).length);
  assert.equal(s.sessions.length, 1);
  assert.ok(s.sessions[0].length >= 0);
});

test('the zone falls back to the snapshot, and the pvp title to its snapshot', () => {
  const char = { addons: { Memories: { snap: { 3: { zone: 'Teldrassil' }, 5: { gap: 1 }, 6: null } }, Memories_Social: { snap: { 4: { pvp: { title: 'Civil' } } } } } };
  const s = deriveSummary(char, []);
  assert.equal(s.plate.zone, 'Teldrassil');
  assert.equal(s.plate.pvp, 'Civil');
  assert.equal(deriveSummary(char, [{ k: 'zo', zone: 'Durotar', t: 1 }, { k: 'rk', title: 'Private', t: 1 }]).plate.zone, 'Durotar');
  assert.equal(deriveSummary(char, [{ k: 'rk', title: 'Private', t: 1 }]).plate.pvp, 'Private');
});

test('the guild follows the last gu record; a group leave does not clear it', () => {
  const steps = [{ k: 'gu', guild: 'Old', rank: 'Member', t: 1 }, { k: 'gu', guild: 'New', rank: 'Boss', t: 2 }, { k: 'gl', name: 'Someone', t: 3 }];
  assert.deepEqual(deriveSummary({}, steps).plate.guild, { guild: 'New', rank: 'Boss' });
  assert.equal(deriveSummary({}, [...steps, { k: 'gu', guild: '', t: 4 }]).plate.guild, null);
});

test('flags', () => {
  const s = deriveSummary({ flags: { hardcore: true, selfFoundAllowed: true }, realm: 'brumamar', realmLabel: 'Bruma' }, []);
  assert.equal(s.plate.hardcore, true);
  assert.equal(s.plate.selfFound, true);
  assert.equal(s.plate.realm, 'Bruma');
  assert.equal(deriveSummary({ realm: 'brumamar' }, []).plate.realm, 'brumamar');
});

const economy = (level, money) => ({ Memories_Economy: { snap: { [level]: { money } } }, Memories: { snap: { [level]: { t: 100 } } } });

test('the purse anchors on the snapshot and adds later deltas', () => {
  const steps = [{ k: 'mn', delta: 500, t: 50 }, { k: 'mn', delta: 30, t: 150 }, { k: 'mn', delta: -10, t: 200 }];
  const p = deriveSummary({ addons: economy(11, 1000) }, steps).purse;
  assert.deepEqual(p, { copper: 1020, about: false });
});

test('the purse uses the highest level with money', () => {
  const char = { addons: { ...economy(11, 1000), Memories_Economy: { snap: { 10: { money: 5 }, 11: { money: 1000 }, 12: { gear: 'x' } } } } };
  assert.equal(deriveSummary(char, []).purse.copper, 1000);
});

test('the purse takes the anchor time from the lv record when the snapshot has no time', () => {
  const char = { addons: { Memories_Economy: { snap: { 5: { money: 100 } } } } };
  const steps = [{ k: 'mn', delta: 7, t: 10 }, { k: 'lv', level: 5, t: 20 }, { k: 'mn', delta: 3, t: 30 }];
  assert.deepEqual(deriveSummary(char, steps).purse, { copper: 103, about: false });
});

test('the purse is about when there is no snapshot, and never below zero', () => {
  assert.deepEqual(deriveSummary({}, [{ k: 'mn', delta: 40, t: 1 }, { k: 'mn', delta: -10, t: 2 }]).purse, { copper: 30, about: true });
  assert.deepEqual(deriveSummary({}, [{ k: 'mn', delta: -40, t: 1 }]).purse, { copper: 0, about: true });
  assert.deepEqual(deriveSummary({}, []).purse, { copper: 0, about: true });
  const char = { addons: { Memories_Economy: { snap: { 5: { money: 10 } } } } };
  assert.deepEqual(deriveSummary(char, [{ k: 'mn', delta: -90, t: 1 }]).purse, { copper: 10, about: true });
  assert.equal(deriveSummary({ addons: economy(11, 10) }, [{ k: 'mn', delta: -999, t: 500 }]).purse.copper, 0);
});

test('skills merge the snapshot with later sk records and keep unknown skills in Other', () => {
  const char = { addons: { Memories_Character: { snap: { 10: { skills: 'Armas:Dagas=50/50;Lenguas:Lengua: común=300/300;broken;Armas:Hacha=x/5;Armas:Maza=3' } } } } };
  const steps = [{ k: 'sk', name: 'Dagas', rank: 60, max: 75, t: 1 }, { k: 'sk', name: 'Pesca', rank: 2, max: 75, t: 2 }, { k: 'sk', name: 'Pesca', rank: 9, max: 75, t: 3 }];
  const s = deriveSummary(char, steps).skills;
  assert.deepEqual(s.map((g) => g.group), ['Armas', 'Lenguas', 'Other']);
  assert.deepEqual(s[0].skills, [{ name: 'Dagas', rank: 60, max: 75 }]);
  assert.deepEqual(s[1].skills, [{ name: 'Lengua: común', rank: 300, max: 300 }]);
  assert.deepEqual(s[2].skills, [{ name: 'Pesca', rank: 9, max: 75 }]);
  assert.deepEqual(deriveSummary({}, []).skills, []);
});

test('reputation progress at the edges', () => {
  assert.equal(reputationProgress(4, 0), 0);
  assert.ok(Math.abs(reputationProgress(4, 2999) - 2999 / 3000) < 1e-9);
  assert.equal(reputationProgress(5, 3000), 0);
  assert.ok(Math.abs(reputationProgress(8, 42999) - 0.999) < 1e-9);
  assert.equal(reputationProgress(1, -42000), 0);
  assert.equal(reputationProgress(5, 99999), 1);
  assert.equal(reputationProgress(5, undefined), 0);
});

test('an unknown standing is derived from the value', () => {
  assert.equal(reputationProgress(undefined, 3000), 0);
  assert.ok(Math.abs(reputationProgress(99, 6000) - 0.5) < 1e-9);
  assert.equal(reputationProgress(undefined, -50000), 0);
  assert.equal(reputationProgress(undefined, undefined), 0);
  assert.equal(standingName(6), 'Honored');
  assert.equal(standingName(0), '');
});

test('reputation keeps the last record of each faction, highest standing first', () => {
  const steps = [
    { k: 'rp', faction: 'B', standing: 4, value: 10, label: 'Neutral', t: 1 },
    { k: 'rp', faction: 'A', standing: 6, value: 9500, label: 'Honored', t: 2 },
    { k: 'rp', faction: 'B', standing: 5, value: 3500, t: 3 },
    { k: 'rp', faction: 'C', standing: 5, value: 4000, label: 'Friendly', t: 4 },
  ];
  const r = deriveSummary({}, steps).reputation;
  assert.deepEqual(r.map((x) => x.faction), ['A', 'B', 'C']);
  assert.equal(r[1].label, 'Friendly');
  assert.ok(r[0].progress > 0 && r[0].progress < 1);
});

test('talents', () => {
  assert.equal(deriveSummary({}, []).talents, null);
  assert.deepEqual(deriveSummary({}, [{ k: 'ta', spent: 3, unspent: 1, t: 1 }, { k: 'ta', spent: 5, unspent: 0, t: 2 }]).talents, { spent: 5, unspent: 0 });
});

test('kills come from the counter when it is larger', () => {
  const char = { addons: { Memories_Combat: { counts: { kills: { total: 30 } } } } };
  const s = deriveSummary(char, [{ k: 'ki', t: 1 }, { k: 'ki', t: 2 }]);
  assert.equal(s.stats.kills, 30);
  assert.equal(s.stats.killsFromCounts, true);
  const t = deriveSummary({ addons: { Memories_Combat: { counts: { kills: { total: 1 } } } } }, [{ k: 'ki', t: 1 }, { k: 'ki', t: 2 }]);
  assert.equal(t.stats.kills, 2);
  assert.equal(t.stats.killsFromCounts, false);
});

test('the other numbers', () => {
  const day = 86400 * 3;
  const char = {
    sessions: [{ start: 10 * day, last: 10 * day + 100, played0: 0, played1: 90 }, { start: 3 * day, last: 3 * day + 50, played0: -1, played1: 10 }, { start: 10 * day + 500, last: 10 * day + 400, played0: 5, played1: 2 }],
    addons: { Memories: { counts: { distance: { foot: 1234 } } } },
  };
  const steps = [
    { k: 'lv', t: 1 }, { k: 'qt', t: 1 }, { k: 'qt', t: 1 }, { k: 'di', t: 1 }, { k: 'zo', zone: 'A', t: 1 }, { k: 'zo', zone: 'A', t: 1 }, { k: 'zo', zone: 'B', t: 1 },
    { k: 'de', t: 1 }, { k: 'hc', t: 1 }, { k: 'dn', t: 1 }, { k: 'bo', success: 1, t: 1 }, { k: 'bo', success: 0, t: 1 }, { k: 'ga', t: 1 }, { k: 'fs', t: 1 },
    { k: 'lo', t: 1 }, { k: 'tx', t: 1 }, { k: 'ss', screenshot: 'screenshots/a.jpg', t: 1 }, { k: 'ss', t: 1 },
    { k: 'mn', delta: 100, t: 1 }, { k: 'mn', delta: -30, t: 1 }, { k: 'mn', delta: 20, t: 1 },
  ];
  const st = deriveSummary(char, steps).stats;
  assert.equal(st.played, 90 + 11 + 0);
  assert.equal(st.sessions, 3);
  assert.equal(st.days, 2);
  assert.equal(st.firstSeen, 3 * day);
  assert.equal(st.lastSeen, 10 * day + 400);
  assert.deepEqual([st.levels, st.quests, st.areas, st.zones, st.deaths, st.dungeons, st.bosses, st.gathered, st.fished, st.loot, st.flights, st.screenshots],
    [1, 2, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1]);
  assert.equal(st.distance, 1234);
  assert.equal(st.earned, 120);
  assert.equal(st.spent, 30);
});

test('sessions sort by start and carry their length', () => {
  const s = deriveSummary({ sessions: [{ start: 50, last: 80 }, { start: 10, last: 5 }, { start: 20 }] }, []).sessions;
  assert.deepEqual(s.map((x) => [x.start, x.length]), [[10, 0], [20, 0], [50, 30]]);
});

test('an empty character gives an empty summary', () => {
  const s = deriveSummary(undefined, undefined);
  assert.equal(s.plate.name, '');
  assert.equal(s.stats.sessions, 0);
  assert.equal(s.stats.firstSeen, null);
  assert.deepEqual(s.reputation, []);
  assert.equal(s.stats.days, 0);
});

test('XSS: hostile names do not survive as markup', () => {
  const { char, steps } = load('hostile');
  const html = summaryHtml(deriveSummary(char, steps));
  assert.doesNotMatch(html, /<img/i);
  assert.doesNotMatch(html, /<b>realm/);
  assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt;/);
  assert.match(html, /&amp;amp; &lt;b&gt;realm&lt;\/b&gt;/);
  assert.match(html, /&quot;quotes&quot;/);
  assert.doesNotMatch(html, /onerror=alert\(1\)>/);
});

test('summaryHtml shows each section for a full character', () => {
  const { char, steps } = load('nandu');
  const html = summaryHtml(deriveSummary(char, steps));
  for (const want of ['class="panel plate"', 'class="coins"', 'Journey', 'Sessions (1)', 'id="paperdoll"', 'Hunter', 'Night Elf']) assert.ok(html.includes(want), want);
});

test('paint sets colours and widths through the CSSOM', () => {
  const set = [];
  const el = (dataset) => ({ dataset, style: { setProperty: (k, v) => set.push([k, v]) } });
  const root = { querySelectorAll: (sel) => (sel === '[data-class]' ? [el({ class: 'HUNTER' })] : [el({ p: '0.5' })]) };
  paint(root);
  assert.deepEqual(set, [['--c', '#aad372'], ['--p', '50%']]);
});
