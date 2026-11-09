// The Heatmaps tab: one layer at a time over the map. The layer, the profession filter and the camera are in the hash.
import { esc, fmtDur } from '../lib/format.mjs';
import { boundsOf } from '../lib/geo.mjs';
import { binGrid, blur, colourise, layerById, layerPoints, LAYERS, rampTable } from '../lib/heat.mjs';
import { ZONES } from '../zones.mjs';
import { paintData } from './journey.mjs';
import { MapView } from './mapview.mjs';
import { createSheet } from './shell.mjs';

const CELL = 6;

export const legendText = (count) => `${count.toLocaleString('en-US')} on the map`;

// What a cell holds, for the tooltip: a duration for Presence, else a count.
export function cellText(layer, weight) {
  if (layer.id === 'presence') return fmtDur(weight) + ' (' + Math.round(weight) + ' s)';
  const n = Math.round(weight);
  return n + ' ' + layer.unit;
}

export function createHeatmapsTab(panel, ctx) {
  const $ = (id) => panel.querySelector('#' + id);
  let view = null, model = null;
  let layerId = 'presence', prof = 'all';
  let points = null, table = null, grid = null, heat = null, heatKey = '';
  let active = false;
  const off = document.createElement('canvas');

  function loadLayer() {
    const layer = layerById(layerId);
    points = layerPoints(model, layer.id, { prof });
    table = rampTable(layer.colour);
    heatKey = '';
    $('profPicker').hidden = layer.id !== 'gathering';
    const ramp = $('legendRamp').getContext('2d');
    const img = ramp.createImageData(160, 1);
    for (let x = 0; x < 160; x++) img.data.set(table.subarray(Math.round((x / 159) * 255) * 4, Math.round((x / 159) * 255) * 4 + 4), x * 4);
    ramp.clearRect(0, 0, 160, 10);
    off.width = 160;
    off.height = 1;
    off.getContext('2d').putImageData(img, 0, 0);
    ramp.imageSmoothingEnabled = false;
    ramp.drawImage(off, 0, 0, 160, 10);
    $('legendCount').textContent = legendText(points.count);
    $('legendUnplaced').textContent = points.unplaced ? `${points.unplaced.toLocaleString('en-US')} with no map position (instances)` : '';
    $('legendEmpty').textContent = points.count ? '' : 'No records for this layer.';
    view?.invalidate();
  }

  // The heat of the current view is binned, blurred and coloured once for each view, layer and filter.
  function paint(ctx2d, v) {
    if (!points?.count) return;
    const key = [v.x, v.y, v.s, v.w, v.h, layerId, prof].join('|');
    if (key !== heatKey) {
      heatKey = key;
      grid = binGrid(points, v, CELL);
      const out = colourise(blur(grid, 2), table);
      off.width = grid.cols;
      off.height = grid.rows;
      off.getContext('2d').putImageData(new ImageData(out, grid.cols, grid.rows), 0, 0);
      heat = true;
    }
    if (!heat) return;
    ctx2d.save();
    ctx2d.globalAlpha = 0.85;
    ctx2d.imageSmoothingEnabled = true;
    ctx2d.imageSmoothingQuality = 'high';
    ctx2d.drawImage(off, 0, 0, grid.cols, grid.rows, 0, 0, grid.cols * CELL, grid.rows * CELL);
    ctx2d.restore();
  }

  // The weight of the 3 x 3 cells around a screen point.
  function weightAt(x, y) {
    if (!grid) return 0;
    const c0 = Math.floor(x / CELL), r0 = Math.floor(y / CELL);
    let sum = 0;
    for (let r = r0 - 1; r <= r0 + 1; r++) for (let c = c0 - 1; c <= c0 + 1; c++) if (r >= 0 && c >= 0 && r < grid.rows && c < grid.cols) sum += grid.data[r * grid.cols + c];
    return sum;
  }
  function showWeight(x, y) {
    const tip = $('hTip');
    const w = x === null ? 0 : weightAt(x, y);
    if (!(w > 0)) {
      tip.hidden = true;
      return;
    }
    const layer = layerById(layerId);
    tip.innerHTML = `<b class="tip-title" data-c="${esc(layer.colour)}">${esc(layer.label)}</b><div>${esc(cellText(layer, w))}</div>`;
    paintData(tip);
    tip.hidden = false;
    const st = tip.parentElement.getBoundingClientRect();
    tip.style.left = Math.max(8, Math.min(x + 14, st.width - tip.offsetWidth - 8)) + 'px';
    tip.style.top = Math.max(8, Math.min(y + 14, st.height - tip.offsetHeight - 8)) + 'px';
  }

  function params() {
    const p = { x: view.cam.x, y: view.cam.y, z: view.cam.s };
    if (layerId === 'gathering') p.prof = prof;
    return p;
  }
  function pushParams() {
    if (active && view) ctx.setParams('heatmaps', params(), layerId);
  }

  function fitLayer() {
    view.fitBounds(points.count ? boundsOf(points.wx, points.wy, points.count) : null, { notify: false });
  }

  function init() {
    model = ctx.model();
    createSheet($('heatSheet'));
    paintData($('heatSheet'));
    view = new MapView($('heatMap'), {
      world: globalThis.WORLD ?? null,
      zones: ZONES,
      onCamera: () => {
        $('hLevel').textContent = view.levelName();
        pushParams();
      },
      onTap: (x, y) => showWeight(x, y),
      onHover: (x, y) => showWeight(x, y),
    });
    view.draw((c, v) => paint(c, v));
    $('hIn').addEventListener('click', () => view.stepZoom(1));
    $('hOut').addEventListener('click', () => view.stepZoom(-1));
    $('hWorld').addEventListener('click', () => view.fitWorld({ ease: true }));
    panel.querySelectorAll('input[name="heatLayer"]').forEach((i) =>
      i.addEventListener('change', () => {
        layerId = i.value;
        loadLayer();
        pushParams();
      }),
    );
    panel.querySelectorAll('input[name="heatProf"]').forEach((i) =>
      i.addEventListener('change', () => {
        prof = i.value;
        loadLayer();
        pushParams();
      }),
    );
  }

  const check = (name, value) => {
    for (const i of panel.querySelectorAll(`input[name="${name}"]`)) i.checked = i.value === value;
  };

  return {
    show(route) {
      const first = !model;
      if (first) init();
      active = true;
      const p = route.params;
      const before = layerId;
      layerId = LAYERS.some((l) => l.id === route.layer) ? route.layer : 'presence';
      const layerChanged = before !== layerId;
      // A tab switch has no parameters and keeps the filter and the camera; a link sets them.
      const keep = !first && Object.keys(p).length === 0;
      prof = layerId === 'gathering' ? (p.prof ?? (keep ? prof : 'all')) : 'all';
      check('heatLayer', layerId);
      check('heatProf', prof);
      view.resize();
      loadLayer();
      if (Number.isFinite(p.x) && Number.isFinite(p.y) && Number.isFinite(p.z)) view.setCamera({ x: p.x, y: p.y, s: p.z }, { notify: false });
      else if (!keep || layerChanged) fitLayer();
      $('hLevel').textContent = view.levelName();
      view.invalidate();
      pushParams();
    },
    hide() {
      active = false;
      if ($('hTip')) $('hTip').hidden = true;
    },
  };
}
