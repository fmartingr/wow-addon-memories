import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cellText, legendText } from '../ui/heatmaps.mjs';
import { layerById } from '../lib/heat.mjs';

test('presence shows a duration and the other layers a count', () => {
  assert.equal(cellText(layerById('presence'), 3725), '1h 02m (3725 s)');
  assert.equal(cellText(layerById('kills'), 3.2), '3 kills');
  assert.equal(cellText(layerById('gathering'), 1), '1 finds');
  assert.equal(legendText(1234567), '1,234,567 on the map');
});
