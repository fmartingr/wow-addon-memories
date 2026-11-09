// The Summary tab. summaryHtml makes the markup from the derived numbers; every data value goes through esc().
import { className, classColour, clamp, coinsHtml, esc, fmtDate, fmtDur, raceName } from '../lib/format.mjs';

const num = (n) => (Number.isFinite(n) ? Math.round(n).toLocaleString('en-US') : '0');

function plateHtml(p, purse) {
  const faction = p.faction === 'Alliance' ? 'alliance' : p.faction === 'Horde' ? 'horde' : 'other';
  const tags = [
    p.faction && `<li class="tag faction ${faction}">${esc(p.faction)}</li>`,
    p.hardcore && '<li class="tag hardcore">Hardcore</li>',
    p.selfFound && '<li class="tag selffound">Self-found</li>',
  ].filter(Boolean);
  const facts = [
    ['Realm', p.realm && p.region ? `${p.realm} (${p.region})` : p.realm || p.region],
    ['Zone', p.zone],
    ['Guild', p.guild ? `${p.guild.guild}${p.guild.rank ? ` (${p.guild.rank})` : ''}` : ''],
    ['PvP rank', p.pvp],
  ].filter(([, v]) => v);
  const initial = [...String(p.name || '?')][0];
  return `<section class="panel plate" aria-label="Character">
  <div class="plate-head">
    <div class="avatar" data-class="${esc(p.class)}" aria-hidden="true">${esc(initial)}</div>
    <div class="plate-title">
      <h2 class="char-name">${esc(p.name)}${p.surname ? ` <span class="surname">${esc(p.surname)}</span>` : ''}</h2>
      <p class="char-line">${p.level != null ? `Level ${esc(p.level)} ` : ''}${esc(raceName(p.race))} <span class="cls" data-class="${esc(p.class)}">${esc(className(p.class))}</span></p>
    </div>
  </div>
  ${tags.length ? `<ul class="tags">${tags.join('')}</ul>` : ''}
  <dl class="facts">${facts.map(([k, v]) => `<div><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('')}</dl>
  <div class="purse"><span class="label">Purse</span> <span class="coins" aria-label="Purse">${coinsHtml(purse.copper)}</span>${purse.about ? ' <span class="note">about</span>' : ''}</div>
</section>`;
}

function skillsHtml(groups) {
  if (!groups.length) return '';
  const body = groups
    .map(
      (g) => `<section class="skill-group"><h4>${esc(g.group)}</h4><ul class="bars">${g.skills
        .map((s) => {
          const p = s.max > 0 ? clamp(s.rank / s.max, 0, 1) : 0;
          return `<li><span class="bar-name">${esc(s.name)}</span><span class="meter" data-p="${p.toFixed(4)}" role="meter" aria-valuenow="${esc(s.rank)}" aria-valuemin="0" aria-valuemax="${esc(s.max)}"><span class="fill"></span><span class="meter-text">${esc(s.rank)} / ${esc(s.max)}</span></span></li>`;
        })
        .join('')}</ul></section>`,
    )
    .join('');
  return `<section class="panel"><h3 class="panel-title">Skills</h3>${body}</section>`;
}

function reputationHtml(list) {
  if (!list.length) return '';
  const rows = list
    .map(
      (r) => `<li><span class="bar-name">${esc(r.faction)}</span><span class="meter standing s${Number(r.standing) || 0}" data-p="${r.progress.toFixed(4)}" role="meter" aria-valuenow="${Math.round(r.progress * 100)}" aria-valuemin="0" aria-valuemax="100"><span class="fill"></span><span class="meter-text">${esc(r.label)}</span></span></li>`,
    )
    .join('');
  return `<section class="panel"><h3 class="panel-title">Reputation</h3><ul class="bars">${rows}</ul></section>`;
}

function statsHtml(s, talents) {
  const cells = [
    ['Time played', fmtDur(s.played)],
    ['Sessions', num(s.sessions)],
    ['Days played', num(s.days)],
    ['First seen', s.firstSeen ? fmtDate(s.firstSeen) : '—'],
    ['Last seen', s.lastSeen ? fmtDate(s.lastSeen) : '—'],
    ['Levels gained', num(s.levels)],
    ['Quests done', num(s.quests)],
    ['Areas found', num(s.areas)],
    ['Zones visited', num(s.zones)],
    ['Creatures killed', num(s.kills) + (s.killsFromCounts ? '*' : '')],
    ['Deaths', num(s.deaths)],
    ['Dungeons entered', num(s.dungeons)],
    ['Bosses defeated', num(s.bosses)],
    ['Items gathered', num(s.gathered)],
    ['Fish caught', num(s.fished)],
    ['Loot found', num(s.loot)],
    ['Flights taken', num(s.flights)],
    ['Screenshots', num(s.screenshots)],
    ['Distance on foot', num(s.distance) + ' yd'],
    ['Gold earned', `<span class="coins">${coinsHtml(s.earned)}</span>`, true],
    ['Gold spent', `<span class="coins">${coinsHtml(s.spent)}</span>`, true],
  ];
  if (talents) cells.push(['Talent points', `${num(talents.spent)} spent, ${num(talents.unspent)} free`]);
  const grid = cells.map(([k, v, raw]) => `<div class="stat"><dt>${esc(k)}</dt><dd>${raw ? v : esc(v)}</dd></div>`).join('');
  const note = s.killsFromCounts ? '<p class="note">* From the kill counter. The journal holds fewer kills.</p>' : '';
  return `<section class="panel"><h3 class="panel-title">Journey</h3><dl class="stats">${grid}</dl>${note}</section>`;
}

function sessionsHtml(sessions) {
  if (!sessions.length) return '';
  const rows = sessions
    .map(
      (s) => `<tr><td>${esc(fmtDate(s.start))}</td><td>${esc(fmtDur(s.length))}</td><td>${esc(s.how ?? '')}</td></tr>`,
    )
    .join('');
  return `<details class="panel sessions"><summary>Sessions (${sessions.length})</summary><div class="table-wrap"><table><thead><tr><th>Start</th><th>Length</th><th>Started by</th></tr></thead><tbody>${rows}</tbody></table></div></details>`;
}

export function summaryHtml(summary) {
  const left = plateHtml(summary.plate, summary.purse) + '<div id="paperdoll" class="paperdoll-slot"></div>';
  const mid = skillsHtml(summary.skills) + reputationHtml(summary.reputation);
  const right = statsHtml(summary.stats, summary.talents) + sessionsHtml(summary.sessions);
  return `<div class="summary-grid"><div class="col">${left}</div><div class="col">${mid}</div><div class="col">${right}</div></div>`;
}

// Dynamic colours and bar widths are set through the CSSOM, because the page policy blocks style attributes.
export function paint(root) {
  for (const el of root.querySelectorAll('[data-class]')) el.style.setProperty('--c', classColour(el.dataset.class));
  for (const el of root.querySelectorAll('[data-p]')) el.style.setProperty('--p', Number(el.dataset.p) * 100 + '%');
}

export function mountSummary(panel, summary) {
  panel.innerHTML = summaryHtml(summary);
  paint(panel);
}
