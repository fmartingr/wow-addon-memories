// The text of a note that the player wrote in the game. A link to an item or a quest is a token: {item:ID:Name} or
// {quest:ID:Title}. Every value goes through esc(); a link is built only from a whole number and a fixed address.
import { esc } from './format.mjs';
import { questUrl, wowheadUrl } from './gear.mjs';

const TOKEN = /\{(item|quest):(\d+):([^{}]*)\}/g;

// parseNote splits the text in parts: { text }, { item, name } or { quest, title }. A token with an id that is not a
// whole number above 0 stays text.
export function parseNote(text) {
  const parts = [];
  let last = 0;
  const source = String(text ?? '');
  for (const m of source.matchAll(TOKEN)) {
    const id = Number(m[2]);
    if (!Number.isSafeInteger(id) || id <= 0) continue;
    if (m.index > last) parts.push({ text: source.slice(last, m.index) });
    parts.push(m[1] === 'item' ? { item: id, name: m[3] } : { quest: id, title: m[3] });
    last = m.index + m[0].length;
  }
  if (last < source.length) parts.push({ text: source.slice(last) });
  return parts;
}

// The text with each token as its name.
export const plainNote = (text) =>
  parseNote(text).map((p) => p.text ?? p.name ?? p.title).join('');

// noteHtml makes the HTML of a note. flavor is the flavor of the character (null for the classic database).
export function noteHtml(text, flavor = null, code) {
  return parseNote(text).map((p) => {
    if (p.text !== undefined) return esc(p.text);
    const url = p.item ? wowheadUrl(p.item, code, flavor) : questUrl(p.quest, code, flavor);
    const label = esc(p.name ?? p.title);
    return url ? `<a class="wh-link" href="${esc(url)}" target="_blank" rel="noopener noreferrer" data-wh-rename-link="false" data-wh-icon-add="false">${label}</a>` : label;
  }).join('');
}
