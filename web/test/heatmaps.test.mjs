import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { cellText, legendText } from '../ui/heatmaps.mjs';
import { layerById } from '../lib/heat.mjs';
import { setLang } from '../lib/i18n.mjs';
import de from '../i18n/de.mjs';

afterEach(() => setLang('en'));

test('presence shows a duration and the other layers a count', () => {
  assert.equal(cellText(layerById('presence'), 3725), '1h 02m (3725 s)');
  assert.equal(cellText(layerById('kills'), 3.2), '3 kills');
  assert.equal(cellText(layerById('gathering'), 2), '2 finds');
  assert.equal(legendText(1234567), '1,234,567 on the map');
});

test('the legend says 1 kill and 2 kills', () => {
  assert.equal(cellText(layerById('kills'), 1), '1 kill');
  assert.equal(cellText(layerById('kills'), 0.6), '1 kill');
  assert.equal(cellText(layerById('kills'), 2), '2 kills');
  assert.equal(cellText(layerById('fishing'), 1), '1 catch');
  assert.equal(cellText(layerById('fishing'), 2), '2 catches');
});

test('the legend follows the page language', () => {
  setLang('de', de);
  assert.equal(cellText(layerById('kills'), 1), '1 Kill');
  assert.equal(cellText(layerById('presence'), 3725), '1 Std. 02 Min. (3725 s)');
  assert.equal(legendText(1234567), '1.234.567 auf der Karte');
});
