// MapView draws the world map on a canvas and moves its camera: art and tiles when the art is installed, a parchment
// grid with the zone outlines when it is not. Ported from the first viewer ("Memories Chronicle"). The camera is
// { x, y, s }: the world point at the middle of the canvas and the scale in CSS pixels for each world unit.
import { CONT, H, W, ZONES } from '../zones.mjs';
import { clamp } from '../lib/format.mjs';
import { currentLang, own, t } from '../lib/i18n.mjs';
import ZONE_NAMES from '../i18n/zones.mjs';

export const MAX_S = 40;

// The official name of a zone in a language; a zone with no translation shows its English name. A mapId that is not in
// the zone table has no name.
export function zoneName(mapId, code = currentLang(), zones = ZONES) {
  const zone = own(zones, mapId);
  if (!zone) return '';
  return own(own(ZONE_NAMES, code) ?? {}, mapId) ?? zone.name ?? '';
}

/* ---------------------------------------------------------------- pure camera helpers
   v is a view { x, y, s, w, h }: the camera and the canvas size in CSS pixels. */
export const w2s = (v, wx, wy) => [(wx - v.x) * v.s + v.w / 2, (wy - v.y) * v.s + v.h / 2];
export const s2w = (v, sx, sy) => [(sx - v.w / 2) / v.s + v.x, (sy - v.h / 2) / v.s + v.y];

// The scale at which the whole world picture fits the canvas.
export const fitScale = (w, h) => Math.min(Math.max(w, 1) / W, Math.max(h, 1) / H);

export const fitWorld = (w, h) => ({ x: W / 2, y: H / 2, s: fitScale(w, h) });

// The camera that frames bounds [x0, x1, y0, y1] with a margin. A single point gets a minimum extent.
export function fitBounds(bounds, w, h, fill = 0.8) {
  const [x0, x1, y0, y1] = bounds;
  const bw = Math.max(x1 - x0, 12), bh = Math.max(y1 - y0, 12);
  const s = Math.min(fill * Math.min(Math.max(w, 1) / bw, Math.max(h, 1) / bh), MAX_S);
  return clampCamera({ x: (x0 + x1) / 2, y: (y0 + y1) / 2, s }, w, h);
}

// clampCamera keeps the scale between 0.9 times the fit scale and MAX_S, and keeps the view on the world.
export function clampCamera(cam, w, h) {
  const s = clamp(Number.isFinite(cam.s) ? cam.s : fitScale(w, h), fitScale(w, h) * 0.9, MAX_S);
  const hw = w / s / 2, hh = h / s / 2;
  return {
    x: clamp(Number.isFinite(cam.x) ? cam.x : W / 2, Math.min(hw, W / 2), Math.max(W - hw, W / 2)),
    y: clamp(Number.isFinite(cam.y) ? cam.y : H / 2, Math.min(hh, H / 2), Math.max(H - hh, H / 2)),
    s,
  };
}

// zoomAround sets the scale to s and keeps the world point under the screen point (ax, ay) where it is.
export function zoomAround(cam, s, ax, ay, w, h) {
  const before = { ...cam, w, h };
  const [wx, wy] = s2w(before, ax, ay);
  const ns = clamp(s, fitScale(w, h) * 0.9, MAX_S);
  const after = { ...cam, s: ns, w, h };
  const [nx, ny] = s2w(after, ax, ay);
  return clampCamera({ x: cam.x + wx - nx, y: cam.y + wy - ny, s: ns }, w, h);
}

// pinchCamera is the camera while two fingers move: the scale follows the distance, and the world point that was under
// the first midpoint stays under the current midpoint.
export function pinchCamera(start, w, h, from, to) {
  const d0 = Math.hypot(from[1].x - from[0].x, from[1].y - from[0].y) || 1;
  const d1 = Math.hypot(to[1].x - to[0].x, to[1].y - to[0].y) || 1;
  const s = clamp(start.s * (d1 / d0), fitScale(w, h) * 0.9, MAX_S);
  const [wx, wy] = s2w({ ...start, w, h }, (from[0].x + from[1].x) / 2, (from[0].y + from[1].y) / 2);
  const mx = (to[0].x + to[1].x) / 2, my = (to[0].y + to[1].y) / 2;
  return clampCamera({ x: wx - (mx - w / 2) / s, y: wy - (my - h / 2) / s, s }, w, h);
}

// The name of the zoom level: World, Continent or Zone.
export const levelName = (s, w, h) => {
  const f = fitScale(w, h);
  return t(s < f * 1.7 ? 'zoom.world' : s < f * 4 ? 'zoom.continent' : 'zoom.zone');
};

// The scale steps of the zoom buttons, from the world view to the closest zoom.
export const zoomSteps = (w, h) => {
  const f = fitScale(w, h);
  return [f, f * 2.6, f * 7, f * 18, f * 45].filter((x) => x < MAX_S * 0.9).concat(MAX_S);
};

export function nextZoom(s, dir, w, h) {
  const lv = zoomSteps(w, h);
  return dir > 0 ? (lv.find((x) => x > s * 1.12) ?? MAX_S) : ([...lv].reverse().find((x) => x < s / 1.12) ?? lv[0]);
}

/* ---------------------------------------------------------------- shared caches */
const VIEWS = new Set();
const TILES = { cache: new Map(), max: 420 };
const ART = {};
const smooth = (v, a, b) => {
  const t = clamp((v - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};
const invalidateAll = () => VIEWS.forEach((v) => v.invalidate());

function getTile(layer, L, x, y) {
  const key = layer.dir + '/' + L + '/' + x + '_' + y;
  let t = TILES.cache.get(key);
  if (t) {
    TILES.cache.delete(key);
    TILES.cache.set(key, t);
    return t.ok ? t.img : null;
  }
  if (!layer.set(L).has(x + '_' + y)) return null;
  const img = new Image();
  t = { img, ok: false };
  img.onload = () => {
    t.ok = true;
    invalidateAll();
  };
  img.src = '/_/map/' + layer.dir + '/' + L + '/' + x + '_' + y + '.webp';
  TILES.cache.set(key, t);
  if (TILES.cache.size > TILES.max) TILES.cache.delete(TILES.cache.keys().next().value);
  return null;
}

function getArt(name, src) {
  if (!ART[name]) {
    const img = new Image();
    ART[name] = { img, ok: false };
    img.onload = () => {
      ART[name].ok = true;
      invalidateAll();
    };
    img.src = src;
  }
  return ART[name].ok ? ART[name].img : null;
}

const tileLayer = (dir, spec) => {
  const sets = {};
  return { dir, ppu0: spec.ppu0, top: spec.top, size: spec.size, set: (L) => (sets[L] ??= new Set(spec.tiles?.[L] ?? [])) };
};

const reducedMotion = () => globalThis.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;

export class MapView {
  constructor(canvas, { world = null, zones = ZONES, onCamera, onTap, onHover, onUser } = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.world = world;
    this.zones = zones;
    this.on = { camera: onCamera, tap: onTap, hover: onHover, user: onUser };
    this.cam = null;
    this.target = null;
    this.vw = 0;
    this.vh = 0;
    this.dpr = 1;
    this.painter = null;
    this.raf = 0;
    this.last = 0;
    this.pointers = new Map();
    this.down = null;
    this.pinch = null;
    this.layers = world
      ? {
          zone: tileLayer('tiles', { ppu0: world.ppu0, top: world.top, tiles: world.tiles }),
          mini: world.mini ? tileLayer('mini', world.mini) : null,
        }
      : null;
    this.size = world?.size ?? 512;

    canvas.classList.add('map-canvas');
    this.notice = null;
    if (!world) {
      this.notice = document.createElement('p');
      this.notice.className = 'map-notice';
      this.notice.textContent = t('map.noArt');
      canvas.parentElement?.append(this.notice);
    }
    this.legal = document.createElement('p');
    this.legal.className = 'legal map-legal';
    this.legal.textContent = t('legal.map');
    (canvas.closest('.map-wrap') ?? canvas.parentElement).append(this.legal);

    VIEWS.add(this);
    this.bind();
    this.resize();
  }

  /* ---------------------------------------------------------------- size and camera */
  resize() {
    const dpr = globalThis.devicePixelRatio || 1;
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    if (!w || !h) return;
    const oldFit = this.vw ? fitScale(this.vw, this.vh) : null;
    this.dpr = dpr;
    this.vw = w;
    this.vh = h;
    this.canvas.width = Math.max(1, Math.round(w * dpr));
    this.canvas.height = Math.max(1, Math.round(h * dpr));
    if (!this.cam) this.cam = fitWorld(w, h);
    else if (oldFit && Math.abs(this.cam.s - oldFit) < 1e-6) this.cam = fitWorld(w, h);
    else this.cam = clampCamera(this.cam, w, h);
    this.invalidate();
  }

  get sFit() {
    return fitScale(this.vw || 1, this.vh || 1);
  }

  view() {
    return { x: this.cam.x, y: this.cam.y, s: this.cam.s, w: this.vw, h: this.vh, dpr: this.dpr, sFit: this.sFit, rel: this.cam.s / this.sFit };
  }

  levelName() {
    return levelName(this.cam.s, this.vw, this.vh);
  }

  // setCamera moves the camera. With ease it moves toward the camera over the next frames, unless the user prefers
  // reduced motion. notify is false for a move that the caller reports itself.
  setCamera(cam, { ease = false, notify = true } = {}) {
    const next = clampCamera({ ...this.cam, ...cam }, this.vw, this.vh);
    if (ease && !reducedMotion()) {
      this.target = next;
    } else {
      this.target = null;
      this.cam = next;
    }
    this.invalidate();
    if (notify) this.on.camera?.(this.cam);
  }

  fitWorld(opts) {
    this.setCamera(fitWorld(this.vw, this.vh), opts);
  }

  fitBounds(bounds, opts) {
    this.setCamera(bounds ? fitBounds(bounds, this.vw, this.vh) : fitWorld(this.vw, this.vh), opts);
  }

  stepZoom(dir) {
    this.on.user?.();
    this.setCamera({ s: nextZoom(this.cam.s, dir, this.vw, this.vh) }, { ease: true });
  }

  zoomBy(factor, ax = this.vw / 2, ay = this.vh / 2) {
    this.target = null;
    this.cam = zoomAround(this.cam, this.cam.s * factor, ax, ay, this.vw, this.vh);
    this.invalidate();
    this.on.camera?.(this.cam);
  }

  w2s(wx, wy) {
    return w2s({ ...this.cam, w: this.vw, h: this.vh }, wx, wy);
  }

  s2w(sx, sy) {
    return s2w({ ...this.cam, w: this.vw, h: this.vh }, sx, sy);
  }

  /* ---------------------------------------------------------------- drawing */
  // draw sets the function that paints over the map, fn(ctx, view, now), and schedules a frame.
  draw(fn) {
    this.painter = fn;
    this.invalidate();
  }

  invalidate() {
    if (!this.raf && this.vw) this.raf = requestAnimationFrame((now) => this.frame(now));
  }

  frame(now) {
    this.raf = 0;
    const dt = Math.min((now - (this.last || now)) / 1000, 0.1);
    this.last = now;
    let more = false;
    if (this.target) {
      const k = 1 - Math.exp(-dt * 6);
      const t = this.target, c = this.cam;
      const ls = Math.exp(Math.log(c.s) + (Math.log(t.s) - Math.log(c.s)) * k);
      const next = clampCamera({ x: c.x + (t.x - c.x) * k, y: c.y + (t.y - c.y) * k, s: ls }, this.vw, this.vh);
      const done = Math.abs(next.x - t.x) * next.s < 0.3 && Math.abs(next.y - t.y) * next.s < 0.3 && Math.abs(Math.log(next.s / t.s)) < 0.01;
      this.cam = done ? t : next;
      if (done) this.target = null;
      else more = true;
      this.on.camera?.(this.cam);
    }
    const ctx = this.ctx;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    this.drawBase(ctx);
    this.painter?.(ctx, this.view(), now);
    const g = ctx.createRadialGradient(this.vw / 2, this.vh / 2, Math.min(this.vw, this.vh) * 0.5, this.vw / 2, this.vh / 2, Math.max(this.vw, this.vh) * 0.8);
    g.addColorStop(0, 'rgba(0,0,0,0)');
    g.addColorStop(1, 'rgba(0,0,0,0.35)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, this.vw, this.vh);
    if (more) this.invalidate();
  }

  drawBase(ctx) {
    const { vw, vh } = this;
    if (!this.world) return this.drawFallback(ctx);
    const g = ctx.createRadialGradient(vw / 2, vh / 2, 0, vw / 2, vh / 2, Math.max(vw, vh) * 0.75);
    g.addColorStop(0, '#1d3342');
    g.addColorStop(1, '#0b161f');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, vw, vh);
    this.graticule(ctx, '#8fc4dc14');
    const rel = this.cam.s / this.sFit;
    this.drawArt(ctx, getArt('world', '/_/map/art/world.webp'), [0, W, 0, H], 1);
    const ca = smooth(rel, 1.3, 2.1);
    for (const id of Object.keys(CONT)) this.drawArt(ctx, getArt('c' + id, '/_/map/art/cont_' + id + '.webp'), CONT[id], ca);
    this.drawTiles(ctx, this.layers.zone, smooth(rel, 2.7, 3.7));
    this.drawTiles(ctx, this.layers.mini, smooth(this.cam.s, 9, 15) * 0.92);
  }

  graticule(ctx, colour) {
    ctx.strokeStyle = colour;
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let x = 0; x <= W; x += 100) {
      const [sx] = this.w2s(x, 0);
      ctx.moveTo(sx, 0);
      ctx.lineTo(sx, this.vh);
    }
    for (let y = 0; y <= H; y += 100) {
      const [, sy] = this.w2s(0, y);
      ctx.moveTo(0, sy);
      ctx.lineTo(this.vw, sy);
    }
    ctx.stroke();
  }

  // The parchment grid and the zone outlines, for a server with no map art.
  drawFallback(ctx) {
    const { vw, vh } = this;
    ctx.fillStyle = '#cdb98a';
    ctx.fillRect(0, 0, vw, vh);
    const [wx0, wy0] = this.w2s(0, 0), [wx1, wy1] = this.w2s(W, H);
    ctx.fillStyle = '#e0d0a4';
    ctx.fillRect(wx0, wy0, wx1 - wx0, wy1 - wy0);
    this.graticule(ctx, 'rgba(90,60,20,0.22)');
    const rel = this.cam.s / this.sFit;
    ctx.lineJoin = 'round';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const lang = currentLang();
    for (const [mapId, z] of Object.entries(this.zones)) {
      const [x0, x1, y0, y1] = z.rect;
      const [ax, ay] = this.w2s(x0, y0), [bx, by] = this.w2s(x1, y1);
      if (bx < 0 || by < 0 || ax > vw || ay > vh) continue;
      const zone = z.type === 3;
      ctx.strokeStyle = zone ? 'rgba(110,60,20,0.75)' : 'rgba(60,40,15,0.5)';
      ctx.lineWidth = zone ? 1.4 : 2;
      ctx.strokeRect(ax, ay, bx - ax, by - ay);
      if ((zone && bx - ax > 60) || (!zone && rel < 2.5)) {
        ctx.font = (zone ? '600 12px' : '700 15px') + ' Cinzel, Georgia, serif';
        ctx.fillStyle = zone ? 'rgba(70,40,10,0.9)' : 'rgba(70,40,10,0.55)';
        ctx.fillText(zoneName(mapId, lang, this.zones), (ax + bx) / 2, zone ? (ay + by) / 2 : ay + 14);
      }
    }
  }

  drawArt(ctx, img, rect, alpha) {
    if (!img || alpha <= 0.01) return;
    const [ax, ay] = this.w2s(rect[0], rect[2]), [bx, by] = this.w2s(rect[1], rect[3]);
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(img, ax, ay, bx - ax, by - ay);
    ctx.restore();
  }

  // Tile layers are pyramids of 512 px tiles. Level L has ppu0 * 2^L px for each world unit. The level drawn is the first
  // one that is sharp enough; a tile still loading shows from the nearest loaded ancestor.
  drawTiles(ctx, layer, alpha) {
    if (!layer || alpha <= 0.01) return;
    const { cam, vw, vh, dpr } = this;
    const L = clamp(Math.ceil(Math.log2((cam.s * dpr) / layer.ppu0)), 0, layer.top);
    const u = this.size / (layer.ppu0 * 2 ** L), px = u * cam.s;
    const [x0, y0] = this.s2w(0, 0), [x1, y1] = this.s2w(vw, vh);
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    for (let ty = Math.max(0, Math.floor(y0 / u)); ty <= Math.floor(y1 / u); ty++) {
      for (let tx = Math.max(0, Math.floor(x0 / u)); tx <= Math.floor(x1 / u); tx++) {
        if (!layer.set(L).has(tx + '_' + ty)) continue;
        const [sx, sy] = this.w2s(tx * u, ty * u);
        const img = getTile(layer, L, tx, ty);
        if (img) {
          ctx.drawImage(img, sx, sy, px + 0.7, px + 0.7);
          continue;
        }
        for (let d = 1; d <= L; d++) {
          const a = getTile(layer, L - d, tx >> d, ty >> d);
          if (a) {
            const n = 2 ** d, s = this.size / n;
            ctx.drawImage(a, (tx & (n - 1)) * s, (ty & (n - 1)) * s, s, s, sx, sy, px + 0.7, px + 0.7);
            break;
          }
        }
      }
    }
    ctx.restore();
  }

  /* ---------------------------------------------------------------- input */
  bind() {
    const c = this.canvas;
    c.style.touchAction = 'none';
    this.resizer = new ResizeObserver(() => this.resize());
    this.resizer.observe(c);
    const pos = (e) => {
      const r = c.getBoundingClientRect();
      return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    c.addEventListener('pointerdown', (e) => {
      const p = pos(e);
      this.pointers.set(e.pointerId, p);
      c.setPointerCapture?.(e.pointerId);
      if (this.pointers.size === 1) {
        this.down = { ...p, cx: this.cam.x, cy: this.cam.y, moved: false };
      } else if (this.pointers.size === 2) {
        this.down.moved = true;
        this.pinch = { start: { ...this.cam }, from: [...this.pointers.values()].map((q) => ({ ...q })) };
        this.on.user?.();
      }
    });
    c.addEventListener('pointermove', (e) => {
      const p = pos(e);
      if (!this.pointers.has(e.pointerId)) {
        if (e.pointerType === 'mouse') this.on.hover?.(p.x, p.y, e);
        return;
      }
      this.pointers.set(e.pointerId, p);
      if (this.pinch && this.pointers.size >= 2) {
        const now = [...this.pointers.values()].slice(0, 2);
        this.target = null;
        this.cam = pinchCamera(this.pinch.start, this.vw, this.vh, this.pinch.from, now);
        this.invalidate();
        this.on.camera?.(this.cam);
        return;
      }
      const d = this.down;
      if (!d) return;
      const dx = p.x - d.x, dy = p.y - d.y;
      if (!d.moved && Math.hypot(dx, dy) > 4) {
        d.moved = true;
        c.classList.add('drag');
        this.on.user?.();
        this.on.hover?.(null);
      }
      if (d.moved) {
        this.target = null;
        this.cam = clampCamera({ ...this.cam, x: d.cx - dx / this.cam.s, y: d.cy - dy / this.cam.s }, this.vw, this.vh);
        this.invalidate();
        this.on.camera?.(this.cam);
      }
    });
    const up = (e) => {
      const p = pos(e);
      this.pointers.delete(e.pointerId);
      if (this.pointers.size < 2) this.pinch = null;
      // When one finger of a pinch lifts, the other starts a new drag from the current camera.
      if (this.pointers.size === 1) {
        const [rest] = this.pointers.values();
        this.down = { ...rest, cx: this.cam.x, cy: this.cam.y, moved: true };
      }
      if (this.pointers.size === 0) {
        const d = this.down;
        this.down = null;
        c.classList.remove('drag');
        if (d && !d.moved && e.type === 'pointerup') this.on.tap?.(p.x, p.y, e);
      }
    };
    c.addEventListener('pointerup', up);
    c.addEventListener('pointercancel', up);
    c.addEventListener('pointerleave', (e) => {
      if (!this.pointers.has(e.pointerId)) this.on.hover?.(null);
    });
    c.addEventListener(
      'wheel',
      (e) => {
        e.preventDefault();
        const p = pos(e);
        this.on.user?.();
        this.zoomBy(Math.exp(-e.deltaY * 0.0016), p.x, p.y);
      },
      { passive: false },
    );
  }
}
