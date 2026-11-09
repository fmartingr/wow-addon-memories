// The Summary tab. summaryHtml makes the markup from the derived numbers; every data value goes through esc().
import { className, classColour, clamp, coinsHtml, esc, fmtDate, fmtDur, fmtNum, raceName } from '../lib/format.mjs';
import { t, tr } from '../lib/i18n.mjs';
import { mountPaperDoll } from './gear.mjs';

function plateHtml(p, purse) {
  const faction = p.faction === 'Alliance' ? 'alliance' : p.faction === 'Horde' ? 'horde' : 'other';
  const tags = [
    p.faction && `<li class="tag faction ${faction}">${esc(tr('faction.' + p.faction) ?? p.faction)}</li>`,
    p.hardcore && `<li class="tag hardcore">${esc(t('plate.hardcore'))}</li>`,
    p.selfFound && `<li class="tag selffound">${esc(t('plate.selfFound'))}</li>`,
  ].filter(Boolean);
  const facts = [
    [t('plate.realm'), p.realm && p.region ? t('head.realm', { realm: p.realm, region: p.region }) : p.realm || p.region],
    [t('plate.zone'), p.zone],
    [t('plate.guild'), p.guild ? `${p.guild.guild}${p.guild.rank ? ` (${p.guild.rank})` : ''}` : ''],
    [t('plate.pvp'), p.pvp],
  ].filter(([, v]) => v);
  const initial = [...String(p.name || '?')][0];
  return `<section class="panel plate" aria-label="${esc(t('plate.aria'))}">
  <div class="plate-head">
    <div class="avatar" data-class="${esc(p.class)}" aria-hidden="true">${esc(initial)}</div>
    <div class="plate-title">
      <h2 class="char-name">${esc(p.name)}${p.surname ? ` <span class="surname">${esc(p.surname)}</span>` : ''}</h2>
      <p class="char-line">${p.level != null ? `${esc(t('plate.level', { level: p.level }))} ` : ''}${esc(raceName(p.race))} <span class="cls" data-class="${esc(p.class)}">${esc(className(p.class))}</span></p>
    </div>
  </div>
  ${tags.length ? `<ul class="tags">${tags.join('')}</ul>` : ''}
  <dl class="facts">${facts.map(([k, v]) => `<div><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('')}</dl>
  <div class="purse"><span class="label">${esc(t('plate.purse'))}</span> <span class="coins" aria-label="${esc(t('plate.purse'))}">${coinsHtml(purse.copper)}</span>${purse.about ? ` <span class="note">${esc(t('plate.about'))}</span>` : ''}</div>
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
  return `<section class="panel"><h3 class="panel-title">${esc(t('skills.title'))}</h3>${body}</section>`;
}

function reputationHtml(list) {
  if (!list.length) return '';
  const rows = list
    .map(
      (r) => `<li><span class="bar-name">${esc(r.faction)}</span><span class="meter standing s${Number(r.standing) || 0}" data-p="${r.progress.toFixed(4)}" role="meter" aria-valuenow="${Math.round(r.progress * 100)}" aria-valuemin="0" aria-valuemax="100"><span class="fill"></span><span class="meter-text">${esc(r.label)}</span></span></li>`,
    )
    .join('');
  return `<section class="panel"><h3 class="panel-title">${esc(t('rep.title'))}</h3><ul class="bars">${rows}</ul></section>`;
}

function statsHtml(s, talents) {
  const cells = [
    [t('stat.played'), fmtDur(s.played)],
    [t('stat.sessions'), fmtNum(s.sessions)],
    [t('stat.days'), fmtNum(s.days)],
    [t('stat.first'), s.firstSeen ? fmtDate(s.firstSeen) : '—'],
    [t('stat.last'), s.lastSeen ? fmtDate(s.lastSeen) : '—'],
    [t('stat.levels'), fmtNum(s.levels)],
    [t('stat.quests'), fmtNum(s.quests)],
    [t('stat.areas'), fmtNum(s.areas)],
    [t('stat.zones'), fmtNum(s.zones)],
    [t('stat.kills'), fmtNum(s.kills) + (s.killsFromCounts ? '*' : '')],
    [t('stat.deaths'), fmtNum(s.deaths)],
    [t('stat.dungeons'), fmtNum(s.dungeons)],
    [t('stat.bosses'), fmtNum(s.bosses)],
    [t('stat.gathered'), fmtNum(s.gathered)],
    [t('stat.fished'), fmtNum(s.fished)],
    [t('stat.loot'), fmtNum(s.loot)],
    [t('stat.flights'), fmtNum(s.flights)],
    [t('stat.screenshots'), fmtNum(s.screenshots)],
    [t('stat.distance'), t('stat.yd', { n: fmtNum(s.distance) })],
    [t('stat.earned'), `<span class="coins">${coinsHtml(s.earned)}</span>`, true],
    [t('stat.spent'), `<span class="coins">${coinsHtml(s.spent)}</span>`, true],
  ];
  if (talents) cells.push([t('stat.talents'), t('stat.talentsValue', { spent: fmtNum(talents.spent), free: fmtNum(talents.unspent) })]);
  const grid = cells.map(([k, v, raw]) => `<div class="stat"><dt>${esc(k)}</dt><dd>${raw ? v : esc(v)}</dd></div>`).join('');
  const note = s.killsFromCounts ? `<p class="note">${esc(t('stat.killsNote'))}</p>` : '';
  return `<section class="panel"><h3 class="panel-title">${esc(t('stats.title'))}</h3><dl class="stats">${grid}</dl>${note}</section>`;
}

function sessionsHtml(sessions) {
  if (!sessions.length) return '';
  const rows = sessions
    .map(
      (s) => `<tr><td>${esc(fmtDate(s.start))}</td><td>${esc(fmtDur(s.length))}</td><td>${esc(s.how == null ? '' : tr('session.' + s.how) ?? s.how)}</td></tr>`,
    )
    .join('');
  return `<details class="panel sessions"><summary>${esc(t('sessions.title', { n: sessions.length }))}</summary><div class="table-wrap"><table><thead><tr><th>${esc(t('sessions.start'))}</th><th>${esc(t('sessions.length'))}</th><th>${esc(t('sessions.how'))}</th></tr></thead><tbody>${rows}</tbody></table></div></details>`;
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

export function mountSummary(panel, summary, gear, ctx) {
  panel.innerHTML = summaryHtml(summary);
  paint(panel);
  const doll = mountPaperDoll(panel.querySelector('#paperdoll'), gear, ctx);
  return {
    show(route) {
      ctx.legal.textContent = t('legal.site') + (gear.some((g) => g.item > 0) ? ' ' + t('legal.wowhead') : '');
      doll.show(route.params.slot);
    },
    hide() {
      ctx.legal.textContent = '';
    },
  };
}
