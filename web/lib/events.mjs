// How an event reads to a person: the tooltip, the toast line and the colours. Every value from the data goes through
// esc(). The only markup that is not text is built from numbers and fixed strings.
import { clock, esc, fmtDate, moneyText, qualityColour } from './format.mjs';
import { lastBefore } from './playback.mjs';
import { standingName } from './summary.mjs';

export const EVENT_COLOURS = {
  lv: '#ffd100', de: '#ff5a43', cc: '#ff8a1c', pk: '#ff6b57', dn: '#c58cff', bo: '#e0486b', qt: '#ffd100', di: '#5ec9ff', hs: '#6fa6ff', tx: '#6fa6ff',
  ss: '#dfe8f3', ga: '#35c9a0', fs: '#4fa8e0', op: '#c28a49', pp: '#a77ad0', rl: '#f2ead6', rp: '#3fbf6a', qa: '#ffd100', hb: '#e08a3c', fp: '#6fa6ff',
  bk: '#c9a06a', pt: '#7acb4a', rc: '#e8d9a8',
};

const itemColour = (q) => qualityColour(Number.isInteger(q) ? q : 1);
const itemLabel = (e) => e.name || (e.item ? 'item ' + e.item : 'an item');
const withCount = (e) => itemLabel(e) + (e.count > 1 ? ' x' + e.count : '');
const standing = (e) => e.label || standingName(e.standing) || 'standing ' + e.standing;
const kindOf = (e) => (e.how === 'chest' ? 'Chest' : 'Container');

// The toast and log line of each kind: [text, colour].
export const NOTE = {
  lv: (e) => ['Level ' + e.level, EVENT_COLOURS.lv],
  de: (e) => ['You died.' + (e.killer ? ' Killed by ' + e.killer + '.' : ''), EVENT_COLOURS.de],
  ss: (e) => ['Screenshot: ' + e.why, EVENT_COLOURS.ss],
  dn: (e) => ['Entered ' + e.name, EVENT_COLOURS.dn],
  bo: (e) => [e.name + (e.success ? ' defeated' : ': fight lost'), EVENT_COLOURS.bo],
  hs: (e) => ['Hearthstone to ' + e.to, EVENT_COLOURS.hs],
  tx: (e) => ['Flight to ' + e.to, EVENT_COLOURS.tx],
  cc: () => ['Close call!', EVENT_COLOURS.cc],
  pk: (e) => [(e.result === 'won' ? 'Defeated ' : 'Killed by ') + e.name, EVENT_COLOURS.pk],
  qt: (e) => ['Quest done: ' + (e.title || 'a quest'), EVENT_COLOURS.qt],
  di: (e) => ['Discovered ' + e.area, EVENT_COLOURS.di],
  ga: (e) => ['Gathered ' + withCount(e), itemColour(e.quality)],
  fs: (e) => ['Caught ' + withCount(e), itemColour(e.quality)],
  op: (e) => [e.how === 'chest' ? 'Chest opened' : 'Opened ' + (e.name || 'a container'), EVENT_COLOURS.op],
  pp: (e) => ['Picked a pocket: ' + itemLabel(e), itemColour(e.quality)],
  rl: (e) => [(e.type === 'greed' ? 'Greed' : 'Need') + (e.won === 1 ? ' won: ' : e.won === 0 ? ' lost: ' : ': ') + itemLabel(e), itemColour(e.quality)],
  rp: (e) => [standing(e) + ' with ' + e.faction, EVENT_COLOURS.rp],
  qa: (e) => ['Accepted ' + (e.title || 'a quest'), EVENT_COLOURS.qa],
  hb: (e) => ['Home is now ' + e.home, EVENT_COLOURS.hb],
  fp: (e) => ['Flight path: ' + e.node, EVENT_COLOURS.fp],
  bk: (e) => ['Read ' + e.title, EVENT_COLOURS.bk],
  pt: (e) => ['Tamed ' + (e.name || 'a beast'), EVENT_COLOURS.pt],
  rc: (e) => ['Recipe: ' + e.name, EVENT_COLOURS.rc],
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
  const when = `<div class="dim">${esc(fmtDate(e.t))}, ${clock(e.c)} played</div>`;
  let title = e.k, body = '', col = EVENT_COLOURS[e.k] ?? '#ffd100';
  switch (e.k) {
    case 'lv': title = 'Level ' + e.level; body = '<div>You reached a new level.</div>'; break;
    case 'de': title = 'You died'; body = `<div>Killed by ${esc(e.killer || 'something')}${e.klevel ? ` (level ${esc(e.klevel)})` : ''}.</div>` + (e.place && e.place !== 'world' ? `<div>In ${esc(e.place)}.</div>` : ''); break;
    case 'cc': title = 'Close call'; body = `<div>Low health for ${esc(e.seconds || '?')} s. You lived.</div>`; break;
    case 'pk': title = e.result === 'won' ? 'Enemy player defeated' : 'Killed by enemy player'; body = `<div>${esc(e.name)}, level ${esc(e.level || '?')} ${esc(e.class || '')}</div>`; break;
    case 'dn': title = e.name; body = `<div>${esc(e.itype || 'dungeon')} entered (${esc(e.size || '?')} players).</div>`; break;
    case 'bo': title = e.name; body = `<div>Boss ${e.success ? 'defeated' : 'fight lost'} in ${e.seconds ? esc(clock(e.seconds).replace(/^0:/, '')) : '?'}.</div><div class="dim">${esc(e.place)}</div>`; break;
    case 'qt': title = e.title || 'Quest'; body = `<div>Quest completed.</div><div>${esc(e.xp || 0)} XP, ${esc(moneyText(e.money))}</div>`; break;
    case 'di': title = e.area; body = `<div>New area discovered (${esc(e.xp || 0)} XP).</div>`; break;
    case 'hs': title = 'Hearthstone'; body = `<div>Returned to ${esc(e.to)}.</div>`; break;
    case 'tx': title = 'Flight'; body = `<div>${esc(e.from)} to ${esc(e.to)} (${esc(moneyText(e.cost))}).</div>`; break;
    case 'ss': title = 'Screenshot'; body = `<div>${esc(e.why)} (${esc(e.result)})</div>` + (shotUrl ? `<img class="shot" src="${esc(shotUrl)}" alt="">` : ''); break;
    case 'ga': title = withCount(e); col = itemColour(e.quality); body = `<div>${esc(e.prof || 'Gathering')}${e.node && e.node !== '?' ? ' from ' + esc(e.node) : ''}.</div><div class="dim">${e.why === 'rare' ? 'A rare find.' : 'The first of this item.'}</div>`; break;
    case 'fs': title = withCount(e); col = itemColour(e.quality); body = `<div>Caught while fishing.</div><div class="dim">${e.why === 'rare' ? 'A rare catch.' : 'The first of this catch.'}</div>`; break;
    case 'op': title = e.name && e.name !== '?' ? e.name : kindOf(e); body = `<div>${kindOf(e)} opened.</div>`; break;
    case 'pp': title = 'Pocket picked'; col = itemColour(e.quality); body = `<div>${esc(itemLabel(e))} from ${esc(e.who && e.who !== '?' ? e.who : 'a target')}.</div>`; break;
    case 'rl': {
      const res = e.won === 1 ? 'won' : e.won === 0 ? 'lost' : 'result not seen';
      title = itemLabel(e); col = itemColour(e.quality);
      body = `<div>${e.type === 'greed' ? 'Greed' : 'Need'} roll ${e.roll != null ? esc(e.roll) + ', ' : ''}${res}.</div>`;
      break;
    }
    case 'rp': title = e.faction; body = `<div>Reputation: ${esc(standing(e))}.</div>`; break;
    case 'qa': title = e.title || 'Quest'; body = '<div>Quest accepted.</div>'; break;
    case 'hb': title = 'New home'; body = `<div>Hearthstone bound to ${esc(e.home)}.</div>`; break;
    case 'fp': title = e.node; body = '<div>Flight path learned.</div>'; break;
    case 'bk': title = e.title; body = '<div>Read for the first time.</div>'; break;
    case 'pt': title = e.name || 'Beast'; body = `<div>Tamed a ${esc(e.family || 'beast')}${e.level ? ' (level ' + esc(e.level) + ')' : ''}.</div>`; break;
    case 'rc': title = e.name; body = '<div>Recipe learned.</div>'; break;
  }
  return `<b class="tip-title" data-c="${esc(col)}">${esc(title)}</b>${body}${where}${when}`;
}
