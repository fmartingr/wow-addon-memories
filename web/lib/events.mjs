// How an event reads to a person: the tooltip, the toast line and the colours. Every value from the data goes through
// esc(). The only markup that is not text is built from numbers and fixed strings.
import { className, clock, esc, fmtDate, fmtNum, moneyText, qualityColour } from './format.mjs';
import { PROFESSIONS } from './heat.mjs';
import { t, tr } from './i18n.mjs';
import { lastBefore } from './playback.mjs';
import { standingName } from './summary.mjs';

export const EVENT_COLOURS = {
  lv: '#ffd100', de: '#ff5a43', cc: '#ff8a1c', pk: '#ff6b57', dn: '#c58cff', bo: '#e0486b', qt: '#ffd100', di: '#5ec9ff', hs: '#6fa6ff', tx: '#6fa6ff',
  ss: '#dfe8f3', ga: '#35c9a0', fs: '#4fa8e0', op: '#c28a49', pp: '#a77ad0', rl: '#f2ead6', rp: '#3fbf6a', qa: '#ffd100', hb: '#e08a3c', fp: '#6fa6ff',
  bk: '#c9a06a', pt: '#7acb4a', rc: '#e8d9a8',
};

const itemColour = (q) => qualityColour(Number.isInteger(q) ? q : 1);
const itemLabel = (e) => e.name || (e.item ? t('fallback.itemId', { id: e.item }) : t('fallback.item'));
const withCount = (e) => itemLabel(e) + (e.count > 1 ? ' x' + e.count : '');
const standing = (e) => standingName(e.standing) || e.label || t('standing.unknown', { n: e.standing });
const kindOf = (e) => (e.how === 'chest' ? t('kind.chest') : t('kind.container'));
// ga.prof is the English token of the addon; a known one reads as prof.<id> of the catalog.
const PROF_IDS = new Map(Object.entries(PROFESSIONS).map(([id, token]) => [token, id]));
const profName = (prof) => (PROF_IDS.has(prof) ? t('prof.' + PROF_IDS.get(prof)) : prof);
// e.itype is the instance type token of the addon: party or raid.
const itypeName = (itype) => (itype ? tr('itype.' + itype) ?? itype : t('fallback.dungeon'));

// The catalog key of the toast of a need or greed roll.
const rollKey = (e) => 'note.rl' + (e.type === 'greed' ? 'Greed' : 'Need') + (e.won === 1 ? 'Won' : e.won === 0 ? 'Lost' : '');

// The toast and log line of each kind: [text, colour].
export const NOTE = {
  lv: (e) => [t('note.lv', { level: e.level }), EVENT_COLOURS.lv],
  de: (e) => [e.killer ? t('note.deBy', { killer: e.killer }) : t('note.de'), EVENT_COLOURS.de],
  ss: (e) => [t('note.ss', { why: e.why }), EVENT_COLOURS.ss],
  dn: (e) => [t('note.dn', { name: e.name }), EVENT_COLOURS.dn],
  bo: (e) => [t(e.success ? 'note.boWin' : 'note.boLose', { name: e.name }), EVENT_COLOURS.bo],
  hs: (e) => [t('note.hs', { to: e.to }), EVENT_COLOURS.hs],
  tx: (e) => [t('note.tx', { to: e.to }), EVENT_COLOURS.tx],
  cc: () => [t('note.cc'), EVENT_COLOURS.cc],
  pk: (e) => [t(e.result === 'won' ? 'note.pkWon' : 'note.pkLost', { name: e.name }), EVENT_COLOURS.pk],
  qt: (e) => [t('note.qt', { title: e.title || t('fallback.quest') }), EVENT_COLOURS.qt],
  di: (e) => [t('note.di', { area: e.area }), EVENT_COLOURS.di],
  ga: (e) => [t('note.ga', { item: withCount(e) }), itemColour(e.quality)],
  fs: (e) => [t('note.fs', { item: withCount(e) }), itemColour(e.quality)],
  op: (e) => [e.how === 'chest' ? t('note.opChest') : t('note.op', { name: e.name || t('fallback.container') }), EVENT_COLOURS.op],
  pp: (e) => [t('note.pp', { item: itemLabel(e) }), itemColour(e.quality)],
  rl: (e) => [t(rollKey(e), { item: itemLabel(e) }), itemColour(e.quality)],
  rp: (e) => [t('note.rp', { standing: standing(e), faction: e.faction }), EVENT_COLOURS.rp],
  qa: (e) => [t('note.qa', { title: e.title || t('fallback.quest') }), EVENT_COLOURS.qa],
  hb: (e) => [t('note.hb', { home: e.home }), EVENT_COLOURS.hb],
  fp: (e) => [t('note.fp', { node: e.node }), EVENT_COLOURS.fp],
  bk: (e) => [t('note.bk', { title: e.title }), EVENT_COLOURS.bk],
  pt: (e) => [t('note.pt', { name: e.name || t('fallback.beast') }), EVENT_COLOURS.pt],
  rc: (e) => [t('note.rc', { name: e.name }), EVENT_COLOURS.rc],
};

export function noteOf(e) {
  const n = NOTE[e.k];
  return n ? n(e) : [e.title || e.k, '#eadcb4'];
}

// tipHtml makes the tooltip and the detail of an event. shotUrl is the URL of its screenshot or null. The title carries
// its colour in data-c, which the page sets through the CSSOM, because the page policy blocks style attributes.
export function tipHtml(model, e, shotUrl = null) {
  const z = lastBefore(model.zo, e.c);
  const where = z ? `<div class="dim">${esc(z.zone)}</div>` : '';
  const when = `<div class="dim">${esc(t('tip.when', { date: fmtDate(e.t), clock: clock(e.c) }))}</div>`;
  // line() is one sentence of the body. t() gives plain text, so esc() also escapes the values that fill the placeholders.
  const line = (key, vars, cls = '') => `<div${cls ? ` class="${cls}"` : ''}>${esc(t(key, vars))}</div>`;
  let title = e.k, body = '', col = EVENT_COLOURS[e.k] ?? '#ffd100';
  switch (e.k) {
    case 'lv': title = t('tip.lvTitle', { level: e.level }); body = line('tip.lv'); break;
    case 'de':
      title = t('tip.deTitle');
      body = line(e.klevel ? 'tip.deLevel' : 'tip.de', { killer: e.killer || t('fallback.something'), klevel: e.klevel }) +
        (e.place && e.place !== 'world' ? line('tip.deIn', { place: e.place }) : '');
      break;
    case 'cc': title = t('tip.ccTitle'); body = line('tip.cc', { seconds: e.seconds || '?' }); break;
    case 'pk': title = t(e.result === 'won' ? 'tip.pkWonTitle' : 'tip.pkLostTitle'); body = line('tip.pk', { name: e.name, level: e.level || '?', class: className(e.class) }); break;
    case 'dn': title = e.name; body = line('tip.dn', { itype: itypeName(e.itype), size: e.size || '?' }); break;
    case 'bo': title = e.name; body = line(e.success ? 'tip.boWin' : 'tip.boLose', { time: e.seconds ? clock(e.seconds).replace(/^0:/, '') : '?' }) + `<div class="dim">${esc(e.place)}</div>`; break;
    case 'qt': title = e.title || t('fallback.questTitle'); body = line('tip.qt') + `<div>${esc(t('tip.qtReward', { xp: fmtNum(e.xp), money: moneyText(e.money) }))}</div>`; break;
    case 'di': title = e.area; body = line('tip.di', { xp: fmtNum(e.xp) }); break;
    case 'hs': title = t('tip.hsTitle'); body = line('tip.hs', { to: e.to }); break;
    case 'tx': title = t('tip.txTitle'); body = line('tip.tx', { from: e.from, to: e.to, cost: moneyText(e.cost) }); break;
    case 'ss': title = t('tip.ssTitle'); body = line('tip.ss', { why: e.why, result: e.result }) + (shotUrl ? `<img class="shot" src="${esc(shotUrl)}" alt="">` : ''); break;
    case 'ga': {
      title = withCount(e); col = itemColour(e.quality);
      const prof = e.prof ? profName(e.prof) : t('fallback.gathering');
      body = (e.node && e.node !== '?' ? line('tip.gaFrom', { prof, node: e.node }) : line('tip.ga', { prof })) + line(e.why === 'rare' ? 'tip.gaRare' : 'tip.gaFirst', {}, 'dim');
      break;
    }
    case 'fs': title = withCount(e); col = itemColour(e.quality); body = line('tip.fs') + line(e.why === 'rare' ? 'tip.fsRare' : 'tip.fsFirst', {}, 'dim'); break;
    case 'op': title = e.name && e.name !== '?' ? e.name : kindOf(e); body = line(e.how === 'chest' ? 'tip.opChest' : 'tip.opContainer'); break;
    case 'pp': title = t('tip.ppTitle'); col = itemColour(e.quality); body = line('tip.pp', { item: itemLabel(e), who: e.who && e.who !== '?' ? e.who : t('fallback.target') }); break;
    case 'rl': {
      const result = t(e.won === 1 ? 'tip.rlWon' : e.won === 0 ? 'tip.rlLost' : 'tip.rlUnseen');
      const kind = t(e.type === 'greed' ? 'tip.rlGreed' : 'tip.rlNeed');
      title = itemLabel(e); col = itemColour(e.quality);
      body = e.roll != null ? line('tip.rlRolled', { kind, roll: e.roll, result }) : line('tip.rlPlain', { kind, result });
      break;
    }
    case 'rp': title = e.faction; body = line('tip.rp', { standing: standing(e) }); break;
    case 'qa': title = e.title || t('fallback.questTitle'); body = line('tip.qa'); break;
    case 'hb': title = t('tip.hbTitle'); body = line('tip.hb', { home: e.home }); break;
    case 'fp': title = e.node; body = line('tip.fp'); break;
    case 'bk': title = e.title; body = line('tip.bk'); break;
    case 'pt': title = e.name || t('fallback.beastTitle'); body = line(e.level ? 'tip.ptLevel' : 'tip.pt', { family: e.family || t('fallback.family'), level: e.level }); break;
    case 'rc': title = e.name; body = line('tip.rc'); break;
  }
  return `<b class="tip-title" data-c="${esc(col)}">${esc(title)}</b>${body}${where}${when}`;
}
