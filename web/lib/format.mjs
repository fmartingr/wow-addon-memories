// Formatters shared by the tabs. Every function that makes HTML text goes through esc().
import { currentLang, t, tr } from './i18n.mjs';

const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ESCAPES[c]);

export const pad = (n) => String(n).padStart(2, '0');

const whole = (s) => (Number.isFinite(s) ? Math.max(0, Math.floor(s)) : 0);

export function clock(sec) {
  const s = whole(sec);
  return Math.floor(s / 3600) + ':' + pad(Math.floor((s % 3600) / 60)) + ':' + pad(s % 60);
}

export function fmtDur(sec) {
  const s = whole(sec);
  return t('dur.h', { h: Math.floor(s / 3600), m: pad(Math.floor((s % 3600) / 60)) });
}

export function fmtDate(time, lang = currentLang()) {
  if (!Number.isFinite(time)) return '';
  return new Date(time * 1000).toLocaleString(lang, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

export function fmtDay(time, lang = currentLang()) {
  if (!Number.isFinite(time)) return '';
  return new Date(time * 1000).toLocaleDateString(lang, { month: 'short', day: 'numeric' });
}

// A whole number in the digit grouping of the page language.
export const fmtNum = (n, lang = currentLang()) => Math.round(Number.isFinite(n) ? n : 0).toLocaleString(lang);

export function coins(copper) {
  const c = Number.isFinite(copper) ? Math.max(0, Math.round(copper)) : 0;
  return { g: Math.floor(c / 10000), s: Math.floor((c % 10000) / 100), c: c % 100 };
}

export function moneyText(copper) {
  const { g, s, c } = coins(copper);
  return (g ? g + t('coin.g') + ' ' : '') + (g || s ? s + t('coin.s') + ' ' : '') + c + t('coin.c');
}

export function coinsHtml(copper) {
  const { g, s, c } = coins(copper);
  return (g ? `<b>${g}</b><i class="coin cg"></i>` : '') + (g || s ? `<b>${s}</b><i class="coin cs"></i>` : '') + `<b>${c}</b><i class="coin cc"></i>`;
}

const CLASS_COLOURS = {
  WARRIOR: '#c69b6d', PALADIN: '#f48cba', HUNTER: '#aad372', ROGUE: '#fff468', PRIEST: '#ffffff',
  SHAMAN: '#0070dd', MAGE: '#3fc7eb', WARLOCK: '#8788ee', DRUID: '#ff7c0a',
};

export const classColour = (token) => CLASS_COLOURS[String(token ?? '').toUpperCase()] ?? '#e9e1d4';

export function className(token) {
  const text = String(token ?? '');
  return tr('class.' + text.toUpperCase()) ?? (text ? text[0].toUpperCase() + text.slice(1).toLowerCase() : '');
}

export function raceName(token) {
  const text = String(token ?? '');
  return tr('race.' + text) ?? text.replace(/([a-z])([A-Z])/g, '$1 $2');
}

const QUALITY_COLOURS = ['#9d9d9d', '#ffffff', '#1eff00', '#0070dd', '#a335ee', '#ff8000'];

export function qualityColour(q) {
  return Number.isInteger(q) && q >= 0 && q < QUALITY_COLOURS.length ? QUALITY_COLOURS[q] : QUALITY_COLOURS[1];
}

export function qualityName(q) {
  return Number.isInteger(q) && q >= 0 && q < QUALITY_COLOURS.length ? t('quality.' + q) : t('quality.unknown');
}

export function kindLabel(k, kinds) {
  return kinds?.[k]?.name ?? String(k);
}

export const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
