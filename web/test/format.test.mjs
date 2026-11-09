import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  className, classColour, clamp, clock, coins, coinsHtml, esc, fmtDate, fmtDay, fmtDur, kindLabel, moneyText, pad, qualityColour, qualityName, raceName,
} from '../lib/format.mjs';

test('esc escapes the five HTML characters and null', () => {
  assert.equal(esc(`<>&"'`), '&lt;&gt;&amp;&quot;&#39;');
  assert.equal(esc(null), '');
  assert.equal(esc(undefined), '');
  assert.equal(esc(12), '12');
});

test('coins splits copper into gold, silver and copper', () => {
  assert.deepEqual(coins(123456), { g: 12, s: 34, c: 56 });
  assert.deepEqual(coins(0), { g: 0, s: 0, c: 0 });
  assert.deepEqual(coins(-5), { g: 0, s: 0, c: 0 });
  assert.deepEqual(coins(NaN), { g: 0, s: 0, c: 0 });
  assert.equal(moneyText(123456), '12g 34s 56c');
  assert.equal(moneyText(5), '5c');
  assert.equal(moneyText(10005), '1g 0s 5c');
});

test('coinsHtml shows only the coins that count', () => {
  assert.match(coinsHtml(123456), /<b>12<\/b><i class="coin cg">.*<b>34<\/b>.*<b>56<\/b>/);
  assert.doesNotMatch(coinsHtml(7), /cg|cs/);
});

test('raceName maps tokens to names', () => {
  assert.equal(raceName('NightElf'), 'Night Elf');
  assert.equal(raceName('Scourge'), 'Undead');
  assert.equal(raceName('Orc'), 'Orc');
  assert.equal(raceName('BloodElf'), 'Blood Elf');
  assert.equal(raceName(undefined), '');
});

test('class helpers', () => {
  assert.equal(classColour('HUNTER'), '#aad372');
  assert.equal(classColour('hunter'), '#aad372');
  assert.equal(classColour('NOPE'), '#e9e1d4');
  assert.equal(className('HUNTER'), 'Hunter');
  assert.equal(className(''), '');
});

test('clock and fmtDur handle zero, negative and large values', () => {
  assert.equal(clock(0), '0:00:00');
  assert.equal(clock(-5), '0:00:00');
  assert.equal(clock(3725), '1:02:05');
  assert.equal(clock(360000), '100:00:00');
  assert.equal(clock(NaN), '0:00:00');
  assert.equal(fmtDur(0), '0h 00m');
  assert.equal(fmtDur(-1), '0h 00m');
  assert.equal(fmtDur(3725), '1h 02m');
  assert.equal(fmtDur(100 * 3600 + 59 * 60), '100h 59m');
  assert.equal(pad(3), '03');
});

test('dates', () => {
  assert.match(fmtDate(1793530000), /\d/);
  assert.equal(fmtDate(NaN), '');
  assert.match(fmtDay(1793530000), /\d/);
  assert.equal(fmtDay(undefined), '');
});

test('quality', () => {
  assert.equal(qualityColour(0), '#9d9d9d');
  assert.equal(qualityColour(4), '#a335ee');
  assert.equal(qualityColour(5), '#ff8000');
  assert.equal(qualityColour(9), '#ffffff');
  assert.equal(qualityColour(null), '#ffffff');
  assert.equal(qualityName(3), 'Rare');
  assert.equal(qualityName(99), 'Unknown quality');
});

test('kindLabel and clamp', () => {
  assert.equal(kindLabel('lv', { lv: { name: 'Level up' } }), 'Level up');
  assert.equal(kindLabel('zz', {}), 'zz');
  assert.equal(kindLabel('zz', undefined), 'zz');
  assert.equal(clamp(5, 0, 3), 3);
  assert.equal(clamp(-1, 0, 3), 0);
});
