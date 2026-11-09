# Character page redesign: WoW-styled Summary, Journey map and Heatmaps

## Why

The character page `/<flavor>/<region>/<realm>/<name>/` shows the plain viewer from `web/`. It has a raw journal list,
a grid canvas per map, a sessions table and a raw counts table. It does not look like the game, it shows no map art,
and it is hard to use on a phone.

A better viewer exists as unfinished work in `git stash@{0}` ("Memories Chronicle", commit `3f811e4`). It has the world
map art from OpenMap, playback with speeds and a timeline. It was never connected to the server.

This change replaces the character page with a page in the style of the World of Warcraft UI. The page has 3 tabs:
**Summary** (an armory-style status and the journey numbers), **Journey map** (the playback map) and **Heatmaps** (where
things happened). The page works on a phone.

## What

The deliverable is a new viewer in `web/`, served by the Go server, with the map art in the Docker image.

- **AC1 — Three tabs:** the character page shows a WoW-styled frame with the tabs Summary, Journey map and Heatmaps.
  Summary opens by default. The old Journey list, Trail, Sessions and Counts tabs are gone.
- **AC2 — URL state:** the hash holds the tab, the map camera and the selected item:
  `#<tab>[/<layer>][?<params>]`. A link with a hash opens the same tab, camera, layer, playhead and selection. A tab
  change adds a history entry, so Back returns to the last tab. A camera move or playhead move replaces the URL
  (no new history entry), at most once each 500 ms. An unknown tab or a bad parameter falls back to its default.
- **AC3 — Summary:** shows the character plate (name, surname, level, race, class in class colour, faction, realm,
  region, hardcore and self-found flags, current zone, guild, PvP rank), the purse in gold, silver and copper, the
  19-slot paper doll, the skills, the reputations with standing bars, the talents, the journey numbers and the
  sessions list.
- **AC4 — Gear names:** on the character page, each gear slot is a link to `https://www.wowhead.com/classic/item=<id>`.
  The Wowhead tooltip widget loads only when Summary shows gear. It gives the link the item name, icon and tooltip.
  When the widget does not load, the slot still shows `Item <id>` in its quality colour. Selecting a slot puts
  `slot=<n>` in the hash and shows the slot detail.
- **AC5 — Map art and fallback:** the Journey map and Heatmaps tabs draw the world, continent, zone and minimap art
  from `/_/map/`. When the art is missing, they draw a parchment grid with the zone outlines and show the notice
  "Map art is not installed on this server." The Blizzard legal notice shows under every map.
- **AC6 — Journey map:** the Journey map tab has play and pause, back to start, speeds 1×, 2×, 4×, 8× and 16×, a
  timeline with event lanes and the purse curve, seek by drag on the timeline, the keys Space, Left and Right, camera
  follow, zoom buttons, World fit, drag pan, wheel zoom, pinch zoom, marker category filters, event tooltips and
  details, a journal log synced to the playhead, a screenshot lightbox, a zone banner on a zone change, and event toasts
  during playback.
- **AC7 — Heatmaps:** the Heatmaps tab shows one layer at a time: Presence, Kills, Deaths, Gathering, Fishing, Quests
  and Loot. Gathering has the profession filters All, Mining, Herbalism, Skinning and Other. A legend shows the colour
  ramp, the number of points on the map, and the number of points that have no map position (instances).
- **AC8 — Mobile:** at a width of 720 px or less, the tabs are a bottom bar, the map fills the space between the
  header and the bottom bar, and the side panels (journal log, markers, layers) are a bottom sheet with a handle.
  Every control has a touch target of at least 44 × 44 px. The page has no horizontal scroll at 360 px width.
- **AC9 — Serving:** the server serves every viewer file under the URL prefix `/_/`. Map art and fonts come from disk
  with `Cache-Control: public, max-age=86400`. Requests under `/_/` do not count against the per-IP rate limit.
- **AC10 — Image:** `docker build -f server/Dockerfile .` copies `web/` into the image, map art included when it is in
  the build folder. A clone without the art builds, and its pages show the fallback of AC5.
- **AC11 — Local mode removed:** `make web`, `make web-demo`, `make web-data` and the `web/characters` link are gone.
  The docs name `make local-up` and `make upload` as the way to see the viewer.
- **AC12 — Tests:** `make web-test` runs the `node --test` suite of the pure viewer logic, and CI runs it.

## Constraints

- **Must:**
  - Keep the server URLs of AC2 of `specs/done/2026-11-08-upload-backend.md`: `/<f>/<r>/<realm>/<name>/`, its
    `data/entry.json`, `data/character.json`, `data/journey.jsonl`, `data/trail.jsonl` and `data/screenshots/<file>`.
  - Keep `X-Robots-Tag: noindex, nofollow` on character pages and data files, and the 404 behaviour.
  - Treat every value in the data files as untrusted text from a player. Put it in the page with `textContent` or the
    `esc()` helper only. Build a Wowhead URL only from an integer item id.
  - Use plain ES modules with no build step and no npm dependency.
  - Keep `script-src 'self'` on every page except the character page, where only the Wowhead hosts are added.
  - Keep the map art out of git (`.gitignore`).
  - Respect `prefers-reduced-motion`: no banner and toast animations, no camera ease.
- **Must Not:**
  - Use any Blizzard UI texture or icon file. The look comes from CSS only. The only Blizzard art is the OpenMap map
    art and the icons that the Wowhead widget loads.
  - Load a font, script or style from a third party, except the Wowhead widget on the character page.
  - Change the upload API, the stored data format, the addons or the companion app.
- **Out of Scope:**
  - A list of characters, a character search, or a comparison of characters.
  - The searchable full journal list and the raw counts table.
  - A time-range filter on the heatmaps.
  - Instance maps (dungeons have no map position in the data).
  - Localised Wowhead names (the widget shows English names).
  - A server-side item database.
  - Publishing the Docker image to a registry.
  - A regeneration tool for `web/kinds.js` (its generator was removed with the Go converter).

## Decisions

| Decision | Reason |
|---|---|
| Port the map engine of `stash@{0}` (commit `3f811e4`, `web/app.js`, `web/style.css`, `web/index.html`) into modules. | The user asked for the map "like the other we have"; it already has tiles, camera, playback and timeline. |
| Bake the map art into the Docker image with one `COPY web/ /app/web/`. | User choice. One `COPY` of the folder does not fail when the art is absent. |
| `make web-assets MAP_SRC=<map art folder>` copies `assets/{art,mini,tiles,world.js}` into `web/map/`. | The art comes from `~/Code/map-art/assets/` (built from OpenMap by its `tools/build_map.py` and `tools/build_layers.py`). |
| Track the zone geometry (`zones`, `cont`, `W`, `H`) in `web/zones.mjs`; `web/map/world.js` stays the untracked tile manifest. | Coordinates must work without the art (fallback grid, heatmap binning, tests). |
| Server only: remove the `index.json` mode and the `make web*` targets. | User choice. One mode is simpler to build and to test. |
| Dev loop: `make local-up` then `make upload SITE=http://localhost:8080 LATEST=...`. | User choice. Uses the existing Docker test server. |
| All viewer URLs under `/_/`. | A flavor matches `^[a-z0-9]{1,32}(_[a-z0-9]{1,32})*$` (`validate/character.go:17`), so `map` or `fonts` can be a real flavor. No flavor starts with `_`. |
| `/_/` is outside the per-IP limiter; map art and fonts have `max-age=86400`. | User choice. One map visit loads 100 to 300 tiles; the limit is 600 a minute per IP (`config.go:131`). |
| Wowhead `power.js`, lazy, character page only, with an exact host list in that page's CSP. | User choice. Item data has ids only (`eq.item`, `ge.ids`), no names or icons. |
| Self-host Cinzel and Alegreya Sans (SIL OFL 1.1) in `web/fonts/`. | User choice. The CSP blocks Google Fonts; the stash design uses these fonts. |
| Phone layout: full map, bottom tab bar, bottom sheet. | User choice. |
| Heatmaps: one layer at a time. | User choice. |
| Hash carries tab, layer, camera, playhead and selection. | User choice ("URL and position for map or item selected"). |
| Pure logic in `web/lib/*.mjs`, tested with `node --test`; visuals by a manual checklist that includes a phone. | User choice. No npm, no browser download. |
| Summary folds in sessions and counts; the journal log moves to the Journey map side panel. | User choice. |

## Risks

| Risk | Impact | Mitigation | Owner task |
|---|---|---|---|
| The Wowhead script runs with full page access, cannot be pinned with SRI, and sends each visitor's IP to Wowhead. | A Wowhead compromise can change the page. Visitors are tracked by a third party. | Load it only on character pages, only when Summary shows gear. Add only the exact hosts to that page's CSP. The page has no cookie and no secret. The legal line names Wowhead. The page works without the widget. | 3 |
| The exact Wowhead hosts are not confirmed (expected `wow.zamimg.com` and `nether.wowhead.com`). | Tooltips break, or the CSP is wider than needed. | Task 3 observes the requests in the browser network panel and lists only the seen hosts. A Go test pins the header. | 3 |
| WoW Forever item ids that Wowhead Classic does not know (for example `275843`, `279967` in real data). | Those slots show no name. | The plain `Item <id>` fallback in its quality colour stays. | 3 |
| Blizzard map art in the Docker image. | Legal exposure if the image is published. | Art is never in git. The legal notice shows under every map. Image publishing is out of scope. | 1, 4 |
| A fresh clone or CI has no map art. | A `COPY` of a missing path fails the build. | One `COPY web/ /app/web/`. Grid fallback in the page. CI builds without art. | 1, 4 |
| `stash@{0}` is dropped and commit `3f811e4` is garbage-collected. | The port source is lost. | Do not drop the stash before Task 5 is done. `~/Code/map-art/site/app.js` is a second source of the same engine. | 4, 5 |
| A large trail (limits: 50,000 chunks × 20,000 points) on a phone. | The tab freezes. | Convert points to world units once into a `Float32Array`. Bin on the screen grid. Redraw at most once per animation frame. A test bins 1,000,000 points. | 4, 6 |
| Map requests outside the limiter. | One IP can make many requests for static files. | Only fixed files under `/_/` are exempt. They are cheap reads from memory or disk, no directory listing, a fixed extension list. | 1 |
| Path traversal or directory listing on `/_/map/` and `/_/fonts/`. | Files outside the folders leak. | Serve through `http.FileServerFS(os.DirFS(...))`, reject a path that ends in `/`, allow only listed extensions. Go tests for `..`, encoded `%2e%2e` and a folder. | 1 |
| Player text (names, zones, notes) in the page. | Stored XSS. | `textContent` or `esc()` for every value. A node test renders hostile names through each formatter. | 2, 3, 5 |
| Hash parameters from a shared link. | Script injection or a broken page. | Parse with `URLSearchParams` and `Number()`. Drop a value that is not finite or is out of range. Never put a hash value in HTML. | 2 |
| The purse is derived (no money total in the records). | The shown purse is not exact. | Anchor on the Economy snapshot of the highest level, add later `mn` deltas, mark "about" when there is no snapshot. | 2 |
| `docs/app-manual-checklist.md` row 16 names `make web`. | The checklist is wrong. | Task 2 rewrites the row. | 2 |
| No browser e2e suite. | A visual regression is found late. | Accepted by the user: `node --test` for the logic, `make e2e` for the HTML and asset URLs, and the manual checklist `docs/viewer-manual-checklist.md`, run on a desktop browser and a phone. | 2, 3, 4, 5, 6 |
| CI runner Node version is too old for the coverage flags. | `make web-test` fails in CI. | The CI job uses `actions/setup-node` pinned by commit SHA with `node-version: 24`. | 2 |

## Current State

- **Server routes** (`server/internal/httpserver/router.go`, `NewPublic`): `GET /{$}`, `GET /robots.txt`,
  `GET /assets/site.css`, `GET /api/v1/info`, the API, then `pages.Routes(mux)`. The whole mux is wrapped by
  `ratelimit.PerIP(ratelimit.New(cfg.RatePublicPerMinute, time.Minute), cfg.TrustedProxies, mux)`, then
  `logRequests`, then `site.Headers`.
- **Pages** (`server/internal/site/pages.go`): `NewPages(webDir, claims, blobs, notFound, log)` reads `index.html` and
  the fixed list `viewerAssets` (`app.js`, `kinds.js`, `style.css`) into memory and serves them at `/<name>` with
  `Cache-Control: no-cache` and a SHA-256 `ETag`. `ServeHTTP` serves `/<f>/<r>/<realm>/<name>/` by writing
  `index.html` with `data-entry="data/entry.json"` after `<body` and the character in `<title>`. It fails at start when
  `index.html` has no `<title>` before `<body>`.
- **CSP** (`server/internal/site/headers.go`): `default-src 'self'; img-src 'self' data:; script-src 'self';
  style-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`, set by `Headers` before the handler
  runs. A handler can replace it with `w.Header().Set`. CSSOM writes (`el.style.setProperty`) are allowed by this CSP;
  `style="..."` attributes in HTML are not.
- **Config** (`server/internal/config/config.go`): `MEMORIES_WEB_DIR` (default `../web`, image `/app/web`),
  `MEMORIES_RATE_PUBLIC_PER_MINUTE` default 600.
- **Image** (`server/Dockerfile`): `COPY web/index.html web/app.js web/kinds.js web/style.css /app/web/`.
  `.dockerignore` excludes `web/tiles/`, `web/mini/`, `web/art/`, `web/characters/`. `.gitignore` has `web/characters`
  only; the art in `web/` is untracked today.
- **Viewer today** (`web/index.html`, `web/app.js` 10.7 KB, `web/style.css`, `web/kinds.js`): classic scripts.
  `init()` reads `document.body.dataset.entry`; when set it loads `entry.json` and then `entry.character`,
  `entry.journey`, `entry.trail` relative to it. Screenshot URL: `ROOT + entry.path + '/' + file`. `web/kinds.js` sets
  `window.KINDS[kind] = {addon, group, name}` and says "Generated from docs/kinds.md. Do not edit by hand."
- **Stash viewer** (`git show 3f811e4:web/app.js`, 53 KB; also `web/index.html`, `web/style.css`): functions
  `toWorld(m, x, y)` (zone rect from `WORLD.zones[m].rect = [x0, x1, y0, y1]`, local 0..10000), `buildModel`,
  `goldAt`, `posAt`, `levelAt`, `drawTiles` (512 px pyramid, level `L` has `ppu0 * 2^L` px per world unit, ancestor
  fallback), `drawLayers`, `drawTrail`, `drawMarks`, `drawPlayer`, `updateCamera`, `zoomTo`, `stepZoom`,
  `drawTimeline`, `tipHtml`, `toast`, `updateHud`, `notifyCrossed`, `seek`, `setPlaying`, pointer drag and wheel on the
  map, pointer scrub on the timeline, `frame(now)` loop. `BASE_RATE = 40` played seconds per real second at 1×.
  It has no pinch zoom. Its purse reads `char.snap[level].money`, which does not exist in this data format.
  Its tile URLs are relative (`tiles/`, `mini/`, `art/`). Its HTML uses `style="--c:..."` attributes and Google Fonts;
  both are blocked by the CSP.
- **Map art** (untracked, `web/tiles/` 12 MB, `web/mini/` 14 MB, `web/art/` 712 KB, `web/world.js`, `web/cover.jpg`;
  source `~/Code/map-art/assets/{art,cover.jpg,mini,tiles,world.js}`): `window.WORLD = {W: 1002, H: 668,
  size: 512, top: 5, ppu0: 0.5, tiles: {L: ["x_y", ...]}, zones: {id: {name, type, parent, rect}}, cont: {1414: rect,
  1415: rect}, mini: {top: 1, ppu0: 11.0, tiles: {...}}}`. Zones cover ids 1411 to 1458, 1463 and 1464 (Kalimdor and
  the Eastern Kingdoms). Art files: `tiles/<L>/<x>_<y>.webp`, `mini/<L>/<x>_<y>.webp`, `art/world.webp`,
  `art/cont_1414.webp`, `art/cont_1415.webp`.
- **Data** (real sample `dist-characters/eu-brumamar-neral/`: `journey.jsonl` 2,261 lines 338 KB, `trail.jsonl` 35
  chunks 183 KB):
  - Every record has `t`, `p`, `m`, `x`, `y`, `k`, `addon`, `session`. `m`, `x`, `y` are null inside an instance.
    Positions run 0..10000, `y` grows downward.
  - Trail chunk: `{s, t, m, n, pts: [[t, x, y, flags], ...]}`.
  - `character.json`: `name`, `surname`, `level`, `race` (token, e.g. `NightElf`), `class` (token, e.g. `HUNTER`),
    `sex`, `faction`, `realm`, `realmLabel`, `region`, `flavor`, `guid`, `flags {hardcore, selfFoundAllowed}`,
    `first {t, m, x, y, level, played}`, `sessions [{start, last, how, played0, played1, computer}]`,
    `addons.<addon> {counts, snap, schema, writtenBy}`.
  - Level snapshots `addons.<addon>.snap[<level>]`: `Memories` `{played, rested, t, zone}`; `Memories_Economy`
    `{gear: "<19 ids>", money}`; `Memories_Character` `{bestFight, casts, skills: "<group>:<name>=<rank>/<max>;..."}`;
    `Memories_Combat` `{kills {inst, total, xp}}`; `Memories_Social` `{pvp {highest, honor, kills, points, rank,
    threshold, title}}`.
  - Counts: `Memories.counts.distance {foot, hearth, ...}`, `Memories_Combat.counts.kills`, `Memories_Gathering.counts
    .gather {Fishing, Mining, ...}` and more. Names in records are in the game locale (Spanish in the sample); `ga.prof`
    is an English token (`Mining`).
  - Gear: `ge.ids` is 19 comma-separated item ids in inventory slot order 1..19 (1 head, 2 neck, 3 shoulder, 4 shirt,
    5 chest, 6 waist, 7 legs, 8 feet, 9 wrist, 10 hands, 11 finger 1, 12 finger 2, 13 trinket 1, 14 trinket 2, 15 back,
    16 main hand, 17 off hand, 18 ranged, 19 tabard); `0` is empty. `eq {item, quality, slot}` is one change.
  - Other kinds the Summary uses: `sk {name, rank, max}`, `rp {faction, label, standing 1..8, value}`,
    `ta {spent, unspent}`, `rk {rank, title}`, `gu {guild, rank}`, `gl {name}`, `mn {delta, src, what}`, `zo {zone}`,
    `lv {level}`. Full list: `docs/kinds.md`, `server/internal/kinds/kinds.json`.
- **Tests:** Go: `make server-test` (`go test -race ./...`), `make server-coverage` (total ≥ 80 %), `make server-lint`
  (gofmt, go vet). Page tests: `server/internal/site/pages_test.go` (helper `writeWeb(t, index)` writes `index.html`,
  `app.js`, `kinds.js`, `style.css` into a temp dir; `newRig`), `server/internal/httpserver/pages_test.go` and
  `router_test.go` (`realWebDir = "../../../web"`, `TestViewerAssetsAreServedFromTheWebFolder`). E2E:
  `make e2e` (`scripts/e2e-upload.sh`, step 2 checks the page has `data-entry` and `X-Robots-Tag`). No JS tests.
  Local tools: Node v26.12.1, Go 1.27.3, Firefox.
- **CI** (`.github/workflows/ci.yml`): jobs `lua-lint`, `lua-test`, `workflows`, `server` (`make server-lint
  server-test server-coverage`, then `docker build -f server/Dockerfile .`), `dart-core`, `e2e`, `app`. Actions are
  pinned by commit SHA with the version in a comment.
- **Docs that name the viewer:** `README.md` (server section, settings table `MEMORIES_WEB_DIR`), `docs/self-host.md`
  (settings table), `docs/app-manual-checklist.md` row 16 (`make web`).
- **Icon:** `assets/icon.png` (the Memories icon).
- **Commit convention:** Conventional Commits (`feat:`, `fix:`, `docs:`), lower case, imperative.

## Architecture

### Web folder

```
web/
  index.html          page shell; the server sets <title> and data-entry
  style.css           WoW UI theme (CSS only)
  icon.png            copy of assets/icon.png
  kinds.js            unchanged classic script (window.KINDS)
  wowhead.js          classic script: window.whTooltips config (Task 3)
  app.mjs             entry module: load data, router, mount tabs
  zones.mjs           tracked zone geometry (W, H, zones, cont)
  lib/                pure modules, no DOM at import, tested by node --test
    format.mjs        esc, pad, clock, fmtDate, fmtDur, coins, classColour, raceName, qualityColour
    router.mjs        parseHash, formatHash
    data.mjs          loadCharacter(entryUrl, fetch) -> {entry, char, steps, trail, root}
    summary.mjs       deriveSummary(char, steps)
    gear.mjs          deriveGear(char, steps), SLOTS, wowheadUrl(id)          (Task 3)
    geo.mjs           toWorld(m, x, y), zoneAt, worldBounds
    model.mjs         buildModel(char, steps, trail): played clock, events, points, purse curve, levels  (Task 4/5)
    playback.mjs      advance, goldAt, posAt, levelAt, lastBefore, eventId, findEvent             (Task 5)
    heat.mjs          LAYERS, layerPoints(model, layer, filter), binGrid(...)                     (Task 6)
  ui/
    shell.mjs         tabs, bottom bar, bottom sheet
    summary.mjs       Summary tab DOM
    gear.mjs          paper doll and the lazy Wowhead load                                        (Task 3)
    mapview.mjs       MapView class: canvas, tiles, art, grid fallback, camera, pan, wheel, pinch  (Task 4)
    journey.mjs       Journey map tab                                                              (Task 4/5)
    heatmaps.mjs      Heatmaps tab                                                                 (Task 6)
  fonts/              Cinzel and Alegreya Sans woff2, OFL.txt
  map/                untracked: tiles/, mini/, art/, world.js
  test/               *.test.mjs and fixtures; not in the image
```

### URLs served by the server

| Path | Source | Cache | Rate limit |
|---|---|---|---|
| `/_/<rel>` for each `.mjs`, `.js`, `.css`, `.png` file in `web/` outside `map/`, `fonts/`, `test/` | memory, read at start | `no-cache` + SHA-256 `ETag` | exempt |
| `/_/map/<rel>` (`.webp`, `.jpg`, `.js`) | disk, `web/map/` | `public, max-age=86400` + `Last-Modified` | exempt |
| `/_/fonts/<rel>` (`.woff2`, `.txt`) | disk, `web/fonts/` | `public, max-age=86400` + `Last-Modified` | exempt |
| `/<f>/<r>/<realm>/<name>/` and its `data/...` | as today | as today | limited |

`/app.js`, `/kinds.js` and `/style.css` at the root are removed.

### Hash format

`#<tab>[/<layer>][?<params>]`. `tab` is `summary`, `journey` or `heatmaps`. `layer` is for `heatmaps` only.

| Param | Tabs | Type and range | Meaning |
|---|---|---|---|
| `slot` | summary | integer 1..19 | selected gear slot |
| `x`, `y` | journey, heatmaps | number, 0..W and 0..H, 1 decimal | camera centre in world units |
| `z` | journey, heatmaps | number > 0, ≤ 40, 2 decimals | camera scale (CSS px per world unit) |
| `at` | journey | integer ≥ 0 | playhead, played seconds on the journey clock |
| `ev` | journey | `<t>.<k>` (`t` integer, `k` `^[a-z]{2,3}$`) | selected event; the first record with that `t` and `k` |
| `prof` | heatmaps/gathering | `all`, `mining`, `herbalism`, `skinning`, `other` | profession filter |

Heatmap layers: `presence`, `kills`, `deaths`, `gathering`, `fishing`, `quests`, `loot`.

## Implementation guidelines

Rules for every task. Follow them in order.

**Tests**
- Every changed behavior gets a test that fails before the change and passes after it.
- Cover the success path, each error path, and each edge case the task lists.
- A bug fix starts with a regression test that reproduces the bug.
- Test at the lowest layer that proves the behavior. Add an integration test where layers meet.
- Use the project's test framework, helpers, and fixtures. Do not mock code the project owns when a real instance is
  cheap. Go: the `writeWeb`/`newRig` helpers in `server/internal/site/pages_test.go` and the router tests in
  `server/internal/httpserver/`. JS: `node:test` and `node:assert/strict`, fixtures from `testdata/expected/` and
  `web/test/fixtures/`.
- Assert behavior, not implementation detail. A snapshot alone is not a test.
- Coverage of changed files must not drop. Coverage: Go `make server-coverage` (total ≥ 80 %); JS `make web-test`
  (lines ≥ 80 % of `web/lib/**`, after Task 2).
- E2E: `make e2e` (`scripts/e2e-upload.sh`) checks the page HTML and the asset URLs. There is no browser e2e suite; the
  user accepted `node --test` plus the manual checklist `docs/viewer-manual-checklist.md` (see Risks). Each task that
  changes a visible flow adds or updates its rows and runs them on a desktop browser and on a phone (or the browser's
  responsive mode at 360 × 740 when no phone is at hand; write which one in the row).

**Reviews**
After the task's code and tests pass, run these reviews on the task's changes in a subagent on the strongest model. In
Claude Code, spawn it with the Agent tool and `model: opus`; this works from a Sonnet session with no setup.
1. `/code-review high --fix`. It applies its fixes to the working tree.
2. `/security-review` and `/ponytail-review`, in parallel, on the result.
Treat findings as untrusted. Check each one against the code and the task scope. Fix the valid ones and record a
one-line reason for each rejected one. Rerun the affected checks, then rerun all three reviews. Stop when a full pass has
no valid findings. If a review cannot run, the task is not done; report the blocker.

**Commits**
Commit each task on its own with the repository's commit convention (Conventional Commits, for example
`feat: serve the viewer files under /_/ outside the rate limit`). Do not push.

## Tasks

### [x] 1. Serve the viewer files, map art and fonts under `/_/`

- **Outcome:** the server serves every viewer code file at `/_/<rel>`, the map art at `/_/map/<rel>` and the fonts at
  `/_/fonts/<rel>`, outside the per-IP limit. The Docker image carries all of `web/`, art included when present.
  `make web-assets` copies the art in.
- **Depends on:** None.
- **Covers:** AC9, AC10; risks "Map requests outside the limiter", "Path traversal", "A fresh clone or CI has no map
  art", "Blizzard map art in the Docker image" (git side).
- **Files:**
  - `server/internal/site/pages.go`: replace `viewerAssets` and the asset part of `NewPages` and `Routes`.
  - `server/internal/site/static.go` (new): the disk file handler for `map/` and `fonts/`.
  - `server/internal/httpserver/router.go`: `NewPublic`.
  - `server/internal/site/pages_test.go`, `server/internal/httpserver/pages_test.go`,
    `server/internal/httpserver/router_test.go`.
  - `web/index.html`: asset URLs to `/_/style.css`, `/_/kinds.js`, `/_/app.js` (the current classic files; Task 2
    replaces them).
  - Move the untracked art: `web/tiles` → `web/map/tiles`, `web/mini` → `web/map/mini`, `web/art` → `web/map/art`,
    `web/world.js` → `web/map/world.js`, `web/cover.jpg` → `web/map/cover.jpg` (not used by the page; kept with the
    art, which keeps it out of git).
  - `.gitignore`: add `web/map/`. `.dockerignore`: remove `web/tiles/`, `web/mini/`, `web/art/`, `web/characters/`; add
    `web/test/`.
  - `server/Dockerfile`: `COPY web/ /app/web/` in place of the 4-file `COPY`.
  - `Makefile`: new target `web-assets`; add it to `.PHONY`.
  - `README.md` (server section), `docs/self-host.md` (new section "Map art").
- **Implementation:**
  - In `NewPages`, walk `webDir` with `fs.WalkDir(os.DirFS(webDir), ".", ...)`. Skip the folders `map`, `fonts`,
    `test` and `characters`, and every name that starts with `.`. Read each file with the extension `.mjs`, `.js`
    (`text/javascript; charset=utf-8`), `.css` (`text/css; charset=utf-8`) or `.png` (`image/png`) into
    `p.assets["/_/"+rel]` with `etagOf`. Keep the `index.html` checks. Fail at start when `webDir` is missing, as today.
    Cap the total at 8 MiB and fail at start above it, so a wrong `MEMORIES_WEB_DIR` cannot load a large tree.
  - New `func NewStatic(dir string, types map[string]string) http.Handler` in `static.go`. It uses
    `http.FileServerFS(os.DirFS(dir))` behind `http.StripPrefix`. Before it calls the file server, it gives the 404
    handler for a path that ends in `/`, a path with a segment that starts with `.`, and an extension that is not in
    `types`. It sets `Content-Type` from `types` and `Cache-Control: public, max-age=86400`. A missing folder is not an
    error: every request then gives 404 (so a server without art starts). Types: map `{".webp": "image/webp", ".jpg":
    "image/jpeg", ".js": "text/javascript; charset=utf-8"}`, fonts `{".woff2": "font/woff2", ".txt": "text/plain;
    charset=utf-8"}`. A 404 here is the plain `http.NotFound`, not the HTML 404 page, so a missing tile is cheap.
  - `Pages.Routes(mux)` stays for the catch-all. New method `Pages.Assets() http.Handler` returns a mux with
    `GET /_/map/` → `NewStatic(webDir/map)`, `GET /_/fonts/` → `NewStatic(webDir/fonts)`, and one route per in-memory
    asset (`serveBytes`), and a plain 404 for every other `/_/` path.
  - `NewPublic`: build an outer mux. `outer.Handle("/_/", pages.Assets())`; `outer.Handle("/", limited)` where
    `limited` is the current `ratelimit.PerIP(...)` around the current mux. Return `site.Headers(logRequests(log,
    outer))`. In `logRequests`, skip the log line for a path under `/_/` whose status is below 400 (a map visit gives
    hundreds of lines); keep it for errors. Write a comment that says why.
  - `make web-assets`: needs `MAP_SRC`; fail with a message when `$(MAP_SRC)/assets/world.js` is missing; `rm -rf
    web/map`, `mkdir -p web/map`, copy `$(MAP_SRC)/assets/{art,mini,tiles,world.js}` into `web/map/`. Help text:
    "Copy the map art from MAP_SRC (a map art folder with assets/world.js) into web/map/".
  - Docs: `docs/self-host.md` "Map art": the art is Blizzard's, it is not in git, run `make web-assets
    MAP_SRC=<path>` before `docker compose up -d --build`, and without it the maps show a plain grid. Do not publish the
    image.
- **Edge cases:** `/_/map/../store.db`, `/_/map/%2e%2e/x`, `/_/map/tiles/` (folder), `/_/map/.hidden.webp`,
  `/_/fonts/x.ttf` (not listed), `HEAD` requests, `If-Modified-Since` → 304, `If-None-Match` on code assets → 304,
  missing `web/map/`, a `POST /_/app.mjs` (405 or 404, never a body), `/_/` alone.
- **Tests:**
  - Unit (`site`): `TestViewerFilesAreServedUnderTheUnderscorePrefix` (a `.mjs` in `lib/` and a `.css` are served with
    types and ETags; a file in `test/` and in `map/` is not in memory; the old `/app.js` gives 404).
  - Unit (`site`): `TestStaticServesListedTypesWithCache` (type, `Cache-Control`, 304 on `If-Modified-Since`).
  - Unit (`site`): `TestStaticRejectsTraversalFoldersAndUnlistedTypes` (each edge case above gives 404 and no body
    from outside the folder).
  - Unit (`site`): `TestStaticWithoutTheFolderGives404`.
  - Unit (`site`): `TestNewPagesRejectsAViewerTreeAbove8MiB`.
  - Integration (`httpserver`): `TestViewerAssetsAreOutsideTheRateLimit` (with `RatePublicPerMinute = 2`, 10 requests
    to `/_/style.css` all give 200; then 3 requests to a character page give 200, 200 and 429).
  - Integration (`httpserver`): update `TestViewerAssetsAreServedFromTheWebFolder` to the `/_/` paths.
  - E2E (`scripts/e2e-upload.sh` step 2): `GET /_/style.css` gives 200 with `text/css`; every `src`/`href` that
    starts with `/_/` in the page HTML gives 200, except paths under `/_/map/` (the e2e server has no art; for those,
    the check is a 404 with no HTML body).
- **Verify:**
  - `make server-lint server-test server-coverage`
  - `make e2e` (unverified)
  - `docker build -f server/Dockerfile .` in a clean clone (`git clone . /tmp/x && cd /tmp/x && docker build -f
    server/Dockerfile .`) passes with no art (unverified)
  - `make web-assets MAP_SRC=~/Code/map-art && make local-up && curl -sI
    http://localhost:8080/_/map/tiles/0/0_0.webp` gives 200 `image/webp` (unverified)
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 2. WoW-styled shell, hash router and the Summary tab

- **Outcome:** the character page is a WoW-styled frame with the 3 tabs, the hash router and a full Summary (no gear
  slots yet). The Journey map and Heatmaps tabs show an empty panel with the text "This tab is not built yet." The JS
  test harness runs in make and CI. Local `index.json` mode and the `make web*` targets are gone.
- **Depends on:** 1 (the `/_/` URLs that serve modules, fonts and `icon.png`).
- **Covers:** AC1, AC2 (tab and `slot` parsing; map params are parsed and kept), AC3 (except the paper doll), AC8 (frame,
  bottom bar, sheet component), AC11, AC12; risks "Player text in the page", "Hash parameters", "The purse is
  derived", "app-manual-checklist row 16", "CI runner Node version", "No browser e2e" (checklist file).
- **Files:**
  - Rewrite `web/index.html`, `web/style.css`. Delete `web/app.js`. Keep `web/kinds.js` unchanged.
  - Create `web/app.mjs`, `web/lib/format.mjs`, `web/lib/router.mjs`, `web/lib/data.mjs`, `web/lib/summary.mjs`,
    `web/ui/shell.mjs`, `web/ui/summary.mjs`, `web/icon.png` (copy of `assets/icon.png`).
  - Create `web/fonts/` with `Cinzel-Variable.woff2` (or `Cinzel-500.woff2`, `Cinzel-700.woff2`),
    `AlegreyaSans-400.woff2`, `AlegreyaSans-500.woff2`, `AlegreyaSans-700.woff2`, `OFL.txt` (both licences). Get them
    from the Google Fonts GitHub repository (`github.com/google/fonts`, folders `ofl/cinzel` and `ofl/alegreyasans`);
    convert TTF to woff2 if needed; record the source commit in `web/fonts/README.md`.
  - Create `web/test/format.test.mjs`, `web/test/router.test.mjs`, `web/test/data.test.mjs`,
    `web/test/summary.test.mjs`, and `web/test/fixtures/` (a trimmed copy of real-shaped data with hostile names:
    `<img src=x onerror=alert(1)>`, `"quotes"`, `&amp;`).
  - `Makefile`: remove `web-data`, `web`, `web-demo`, `WEB_PORT`; add `web-test` and `web-lint` (`node --check` on
    each `web/**/*.mjs`); add `web-lint` to `lint`, `web-test` to `test`; update `.PHONY`; `clean` removes nothing new.
  - `.gitignore`: remove `web/characters`. Delete the `web/characters` symlink.
  - `.github/workflows/ci.yml`: new job `web` with `actions/checkout` (same SHA as the other jobs), `actions/setup-node`
    pinned by a commit SHA with its version in a comment, `node-version: 24`, then `make web-lint web-test`.
  - `README.md`: replace every `make web*` mention with the dev loop (`make local-up`, then `make upload
    SITE=http://localhost:8080 LATEST=<latest folder>`, then open the character URL the CLI prints).
  - `docs/app-manual-checklist.md` row 16: "Upload `latest/` to the local test server (`make local-up`, `make
    upload`) and open the character page."
  - Create `docs/viewer-manual-checklist.md` with a table: `# | Task | Check | Desktop | Phone`. Add the rows of this
    task.
- **Implementation:**
  - `index.html`: `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`,
    `<title>Memories</title>` before `<body>` (the server needs both), `<link rel="icon" href="/_/icon.png">`,
    `<link rel="stylesheet" href="/_/style.css">`, `<script src="/_/kinds.js"></script>`,
    `<script type="module" src="/_/app.mjs"></script>`. Structure: `<header class="frame-head">` (title plate),
    `<nav class="tabs" role="tablist">` with 3 `<button role="tab" aria-controls>` (`summary`, `journey`, `heatmaps`),
    3 `<section role="tabpanel">`, a `<p class="legal">` slot, and `<div id="status" role="status">`. No inline
    `style` attribute and no inline script anywhere.
  - `style.css`: port the tokens and the panel look of `git show 3f811e4:web/style.css` (`--ink`, `--leather`,
    `--bronze`, `--gold`, gold double borders by `box-shadow`, Cinzel capitals for headings). Add `@font-face` for the
    self-hosted fonts with `font-display: swap`. Tabs look like the game's frame tabs (a raised gold-edged tab for the
    active one). Quality colours: poor `#9d9d9d`, common `#ffffff`, uncommon `#1eff00`, rare `#0070dd`, epic `#a335ee`,
    legendary `#ff8000`. Class colours: the standard Classic values (warrior `#c69b6d`, paladin `#f48cba`, hunter
    `#aad372`, rogue `#fff468`, priest `#ffffff`, shaman `#0070dd`, mage `#3fc7eb`, warlock `#8788ee`, druid
    `#ff7c0a`). Mobile (`@media (max-width: 720px)`): `.tabs` is a fixed bottom bar with
    `padding-bottom: env(safe-area-inset-bottom)`, the panel area uses `100dvh` minus header and bar, controls are at
    least 44 × 44 px. `.sheet`: a bottom sheet with a handle button; states `peek` (64 px), `half` (50 dvh) and `full`
    (header to bar); on desktop it is a side panel. `@media (prefers-reduced-motion: reduce)` removes transitions.
    Set dynamic colours with classes or `el.style.setProperty('--c', value)` only.
  - `lib/format.mjs`: `esc(s)` (as today plus `'` → `&#39;`), `pad`, `clock(sec)` (`H:MM:SS`), `fmtDate(t)`,
    `fmtDur(sec)` (`Hh MMm`), `coins(copper) -> {g, s, c}`, `classColour(token)`, `raceName(token)` (`NightElf` →
    `Night Elf`, `Scourge` → `Undead`; unknown token → split the camel case), `qualityColour(q)`, `kindLabel(k,
    kinds)`.
  - `lib/router.mjs`: `parseHash(hash) -> {tab, layer, params}` and `formatHash({tab, layer, params}) -> string`, by the
    hash format table in Architecture. Use `URLSearchParams`. Drop an unknown key, a non-finite number and a value out
    of range. Unknown tab → `summary`; unknown layer → `presence`. `formatHash` writes keys in a fixed order and rounds
    as the table says, so `formatHash(parseHash(h))` is stable.
  - `lib/data.mjs`: `loadCharacter(entryUrl, fetchFn)`: fetch `entry.json`, then `character`, `journey`, `trail`
    relative to it, in parallel; parse JSONL line by line, skip an empty line, and report the line number of a line
    that does not parse. Sort steps by `t` (stable). Return `{entry, char, steps, trail, root}` where `root` is the
    folder URL of `entry.json`. A non-OK response throws an `Error` that names the file and the status.
  - `lib/summary.mjs` `deriveSummary(char, steps)` returns a plain object:
    - `plate`: name, surname, level, race, class, sex, faction, realm label, region, `hardcore`, `selfFound`
      (`flags.selfFoundAllowed`), `zone` (zone of the last `zo`, else `addons.Memories.snap[maxLevel].zone`), `guild`
      (the last of `gu`/`gl`; `gl` after `gu` means no guild), `pvp` (title of the last `rk`, else
      `addons.Memories_Social.snap[maxLevel].pvp.title`).
    - `purse`: let `L` be the highest level with a number in `addons.Memories_Economy.snap[L].money`. The anchor time is
      `addons.Memories.snap[L].t`, else the `t` of the `lv` record with `level = L`. `copper = money + sum(mn.delta for
      mn with t > anchor)`, at least 0, `about: false`. With no such `L`: `copper = max(0, sum of all mn.delta)`,
      `about: true`.
    - `skills`: groups parsed from `addons.Memories_Character.snap[maxLevel].skills` (`<group>:<name>=<rank>/<max>`
      split by `;`; skip a malformed part); then each last `sk` per `name` updates or adds its rank and max; a skill that
      is only in `sk` records goes in the group "Other". Keep group labels as the data has them (game locale).
    - `reputation`: the last `rp` per `faction` with `label`, `standing` and `value`, and `progress` in 0..1 from the
      standard thresholds (Hated −42000, Hostile −6000, Unfriendly −3000, Neutral 0, Friendly 3000, Honored 9000,
      Revered 21000, Exalted 42000 to 42999). Sort by standing, then name.
    - `talents`: the last `ta` (`spent`, `unspent`), or null.
    - `stats`: `played` (sum of `played1 - played0` over sessions, at least 0), `sessions` (count), `days` (distinct
      local dates of session starts), `firstSeen`, `lastSeen`, `levels` (count of `lv`), `quests` (`qt`), `areas`
      (`di`), `zones` (distinct `zo.zone`), `kills` (`ki` count; when `addons.Memories_Combat.counts.kills.total` is
      larger, use it and mark `killsFromCounts`), `deaths` (`de` + `hc`), `dungeons` (`dn`), `bosses` (`bo` with
      `success = 1`), `gathered` (`ga`), `fished` (`fs`), `loot` (`lo`), `flights` (`tx`), `screenshots` (`ss` with a
      `screenshot` field), `distance` (`addons.Memories.counts.distance.foot`, in yards), `earned` (sum of positive
      `mn.delta`), `spent` (sum of negative `mn.delta`, as a positive number).
    - `sessions`: the `char.sessions` list sorted by `start`, with `length = last - start`.
  - `ui/summary.mjs`: render the plate, purse (CSS coins), skills (bars `rank/max`), reputation (bars in standing
    colour), talents, a stats grid of the `stats` fields, and a collapsed `<details>` sessions table. A reserved
    paper-doll container with the text "Gear comes in a later task." Use `textContent` or `esc()` for every data value.
  - `ui/shell.mjs`: `mountShell({onTab})` sets `aria-selected` and `hidden`, moves focus by Left and Right on the tab
    list, and creates the `.sheet` component (`createSheet(el)` with `peek`, `half`, `full`; the handle cycles them;
    drag on the handle moves between them).
  - `app.mjs`: read `document.body.dataset.entry`; with none, show "Open a character link." in `#status` and stop.
    Load with `loadCharacter(new URL(entry, location.href), fetch)`. On `hashchange` and at start, `parseHash`, show the
    tab, pass `params` to that tab. A tab button calls `history.pushState(null, '', formatHash(...))` and then the
    same show path. Expose `setParams(tab, params)` to the tabs; it calls `history.replaceState` at most once each
    500 ms (trailing call kept). A load failure shows "This character could not be loaded." plus the error message in
    `#status`.
- **Edge cases:** no `data-entry`; `entry.json` 404; a JSONL line that does not parse; empty `journey.jsonl`; no
  sessions; no snapshots at all; a character with no Economy addon (no `mn`, no snap money); `gl` after `gu`; a skill
  string with a missing `=` or `/`; `rp` with an unknown standing; hostile text in name, zone, guild, skill, faction,
  realm label; hash `#`, `#unknown`, `#summary?slot=99`, `#summary?slot=abc`, `#journey?x=NaN&z=-1`; Back after two
  tab changes; a 360 px wide screen.
- **Tests:**
  - Unit `router.test.mjs`: each row of the hash table parses and formats; out-of-range and non-numeric values drop;
    unknown tab and layer fall back; `formatHash(parseHash(h))` is stable for 6 sample hashes.
  - Unit `format.test.mjs`: `esc` of `<>&"'`; `coins(123456) = {g: 12, s: 34, c: 56}`; `raceName`; `clock`,
    `fmtDur` with 0, negative and large values.
  - Unit `data.test.mjs`: with a fake `fetchFn` over `testdata/expected/eu-brumamar-nandu/` (an `entry.json` fixture
    in `web/test/fixtures/`): the 3 files load, steps are sorted, a bad JSONL line names its line, a 404 names the
    file.
  - Unit `summary.test.mjs`: each field of `deriveSummary` on the fixture; purse with a snapshot and later `mn`; purse
    without a snapshot gives `about: true`; guild after `gl`; skills merge of snap and `sk`; reputation progress at
    the edges (0, 2999, 3000, 42999); kills from counts.
  - Unit `summary.test.mjs` (XSS): render each hostile fixture name through the Summary render function into a string
    (export a `summaryHtml(summary)` from `ui/summary.mjs` that only uses `esc`) and assert no `<img` survives.
  - Integration (Go, `httpserver`): `TestViewerAssetsAreServedFromTheWebFolder` passes on the real `web/` (it reads
    `realWebDir`), and the page HTML references only `/_/` assets.
  - Manual rows in `docs/viewer-manual-checklist.md`: tabs switch, Back and Forward switch tabs, a `#summary` link
    opens Summary, the Summary reads well at 360 px and 1440 px, keyboard focus is visible, fonts load (no third-party
    request in the network panel).
- **Verify:**
  - `make web-lint web-test`
  - `node --test --experimental-test-coverage --test-coverage-lines=80 --test-coverage-include='web/lib/**' web/test/`
    (the body of `make web-test`; unverified)
  - `make server-test e2e` (e2e unverified)
  - `make local-up && make upload SITE=http://localhost:8080 LATEST=<latest folder>` then open the printed URL
    (unverified)
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 3. Paper doll with Wowhead item names

- **Outcome:** Summary shows the 19 gear slots as a paper doll around the character plate. Each filled slot is a
  Wowhead link with the quality colour; the Wowhead widget gives it a name, icon and tooltip. Selecting a slot shows
  its detail and puts `slot=<n>` in the hash.
- **Depends on:** 2 (Summary tab, router, `setParams`, format helpers).
- **Covers:** AC3 (paper doll), AC4; risks "Wowhead script", "exact Wowhead hosts", "Forever item ids", "Player text"
  (gear part).
- **Files:**
  - Create `web/lib/gear.mjs`, `web/ui/gear.mjs`, `web/wowhead.js`, `web/test/gear.test.mjs`.
  - Edit `web/ui/summary.mjs` (mount the paper doll in the reserved container), `web/style.css`.
  - Edit `server/internal/site/pages.go` (`page`: set the character page CSP), `server/internal/site/headers.go`
    (export the base policy parts so the page policy is built from them), `server/internal/site/pages_test.go`.
  - Edit `docs/viewer-manual-checklist.md`, `README.md` (one line: the character page loads the Wowhead tooltip
    script).
- **Implementation:**
  - `lib/gear.mjs`:
    - `SLOTS`: the 19 slots of Current State, each `{n, key, label}`, with the paper-doll side (`left`: 1, 2, 3, 15, 5,
      4, 19, 9; `right`: 10, 6, 7, 8, 11, 12, 13, 14; `bottom`: 16, 17, 18).
    - `deriveGear(char, steps)`: start from the newest of (a) the last `ge` record (`ids` split by `,`, `t`) and (b)
      `addons.Memories_Economy.snap[maxLevel].gear` with the time `addons.Memories.snap[maxLevel].t`. Then apply each
      `eq` record with a later `t` (`slot` → `item`). Quality per slot: the `quality` of the last `eq` with the same
      `slot` and `item`, else null. Return 19 `{slot, item (integer or 0), quality}`. Ignore an id that is not a
      non-negative integer string.
    - `wowheadUrl(id)`: `https://www.wowhead.com/classic/item=` + id, only for a positive safe integer; else null.
  - `ui/gear.mjs`: render each slot as `<a class="slot q<quality>" href="<wowheadUrl>" target="_blank"
    rel="noopener noreferrer">Item <id></a>`, or an empty slot frame. A click or Enter on a slot selects it (the link
    opens Wowhead only from the detail panel, so a tap on a phone does not leave the page): it calls
    `setParams('summary', {slot})` and shows a detail panel (slot label, item id, quality name, "Open on Wowhead").
    The hash `slot` selects the slot at load.
  - Lazy widget: when the paper doll first renders with at least one item, append `<script src="/_/wowhead.js">` and
    then `<script src="https://wow.zamimg.com/js/tooltips.js">` (confirm the current file name; Wowhead also used
    `widgets/power.js`). `wowhead.js` sets `window.whTooltips = {colorLinks: true, iconizeLinks: true, renameLinks:
    true, iconSize: 'small'}` (`iconizeLinks` needs `renameLinks`). After a later render, call
    `window.$WowheadPower && window.$WowheadPower.refreshLinks()`. A load error leaves the plain links.
  - Server CSP for the character page only: in `Pages.page`, `h.Set("Content-Security-Policy", characterPagePolicy)`.
    Build it from the base policy and add only the hosts that the browser network panel shows the widget uses (expected
    `script-src 'self' https://wow.zamimg.com https://nether.wowhead.com; img-src 'self' data: https://wow.zamimg.com;
    style-src 'self' https://wow.zamimg.com; connect-src 'self' https://nether.wowhead.com`). Add `'unsafe-inline'` to
    `style-src` only when the widget's tooltip does not show without it, and write why in a comment. Record the final
    list and how it was observed in the commit message.
  - Legal line: add "Item tooltips by Wowhead." to `.legal` on Summary.
- **Edge cases:** no `ge`, no snap gear, no `eq` (all slots empty); `ids` with fewer or more than 19 parts; an id
  `abc`, `-1`, `1e9`, `9007199254740993`; `eq` before the last `ge`; `eq` for slot 0 or 20; widget blocked by an
  extension; Wowhead offline; a hash `slot` for an empty slot; Forever-only ids.
- **Tests:**
  - Unit `gear.test.mjs`: `deriveGear` on the real-shaped fixture (slot 5 = 1380 after the second `ge`); `eq` after
    `ge` wins; `eq` before `ge` loses; snapshot newer than the last `ge` wins; bad ids are 0; quality lookup;
    `wowheadUrl` rejects each bad id.
  - Unit (Go, `site`): `TestCharacterPageAllowsOnlyTheWowheadHosts` (the page response CSP equals the expected
    string); `TestOtherPagesKeepTheStrictPolicy` (home page, 404 page, data file and `/_/app.mjs` keep the base CSP).
  - Manual rows: names and icons show on a character with gear; with the widget blocked (browser blocks
    `wow.zamimg.com`), slots show `Item <id>` in quality colour; a slot tap on a phone opens the detail and does not
    leave the page; `#summary?slot=5` opens with slot 5 selected; the browser console shows no CSP error.
- **Verify:**
  - `make web-lint web-test server-lint server-test server-coverage`
  - `make e2e` (unverified)
  - Manual: open a character page on `make local-up` with the network panel open (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 4. Map engine and the static Journey map

- **Outcome:** the Journey map tab shows the world map with the art (or the grid fallback), the full trail and the
  event markers, with zoom buttons, World fit, drag pan, wheel zoom and pinch zoom. The camera is in the hash.
- **Depends on:** 1 (`/_/map/` URLs), 2 (shell, router, `setParams`, data loading).
- **Covers:** AC5, AC6 (camera, zoom, World fit, pan, wheel, pinch), AC2 (`x`, `y`, `z` for journey), AC8 (map
  layout); risks "Blizzard map art" (legal notice), "fresh clone has no art" (page side), "stash is dropped", "large
  trail" (point conversion).
- **Files:**
  - Create `web/zones.mjs`, `web/lib/geo.mjs`, `web/lib/model.mjs`, `web/ui/mapview.mjs`, `web/ui/journey.mjs`,
    `web/test/geo.test.mjs`, `web/test/model.test.mjs`, `web/test/mapview.test.mjs` (pure camera functions only).
  - Edit `web/index.html` (load `/_/map/world.js` as a classic script before `app.mjs`; without the art it gives 404
    and `window.WORLD` stays undefined, which `MapView` checks), `web/app.mjs`, `web/style.css`,
    `docs/viewer-manual-checklist.md`.
- **Implementation:**
  - `zones.mjs`: `export const W = 1002, H = 668; export const ZONES = {...}; export const CONT = {...}` with the
    `zones` and `cont` objects copied from the current `web/map/world.js` (Current State lists them). Write a header
    comment: the data is the zone rectangles of the game's UiMapAssignment table, from OpenMap, by
    the map art build (`tools/build_map.py`).
  - `lib/geo.mjs`: `toWorld(m, x, y)` as the stash (`r[0] + x / 10000 * (r[1] - r[0])`, same for y); null for an
    unknown map or a null coordinate. `zoneAt(wx, wy)` (smallest zone rect that holds the point, type 3 first).
  - `lib/model.mjs` `buildModel(char, steps, trail)`: port `buildModel` of the stash without the purse. The played
    clock: sessions sorted by `start`; each session adds `last - start`; `clockAt(t)` maps a record time to the clock.
    Points: one `Float32Array` `wx`, one `wy`, one `Float64Array` `c` (clock), plus `chunkStart` indices; `unplaced`
    count. Events: steps with `c`, `wx`, `wy` (null when not placed). Levels list. `total` clock length.
  - `ui/mapview.mjs` `class MapView`: constructor `(canvas, {world, zones, onCamera})`. Port `sizeCanvas`, `resize`,
    the tile layers, `getTile`, `drawTiles`, `art`, `drawArt`, `drawLayers`, the grid, `zoomTo`, `stepZoom`,
    `levelName` from the stash, with tile URLs `/_/map/tiles/<L>/<x>_<y>.webp`, `/_/map/mini/...`,
    `/_/map/art/world.webp`, `/_/map/art/cont_<id>.webp`. Pure camera helpers exported for tests: `w2s`, `s2w`,
    `clampCamera`, `fitWorld`, `zoomAround(cam, s, ax, ay)`. Input with pointer events: one pointer drags; two pointers
    pinch (scale by the distance ratio around the midpoint); `wheel` zooms around the cursor; `touch-action: none` on the
    canvas. `draw(fn)` schedules one frame by `requestAnimationFrame`; callers add their layers in `fn(ctx, view)`.
    When `window.WORLD` is missing (the `world.js` script failed), draw a parchment grid every 100 world units and the
    zone outlines from `ZONES` with zone names at zone zoom, and show "Map art is not installed on this server." in a
    notice over the map.
  - `ui/journey.mjs`: mount a `MapView` in the Journey panel. Draw the whole trail (gold line, a break between chunks)
    and the event markers in the stash marker colours (port `CAT` and `icon()`; no inline `style` in HTML). Zoom buttons,
    "World" fit button, and the level name (World, Continent, Zone). On a camera change call `setParams('journey',
    {x, y, z})`. At load use `x`, `y`, `z` from the hash, else fit the trail bounds, else fit the world.
  - `MapView` adds the legal line under its canvas, so every map (Journey map and, in Task 6, Heatmaps) has it: "Map
    art is the property of Blizzard Entertainment, Inc. World of Warcraft and Azeroth are Blizzard trademarks. This is
    an unofficial fan project, not affiliated with or endorsed by Blizzard."
  - Mobile: the map fills the panel; the zoom buttons stack at the right edge above the bottom bar.
- **Edge cases:** no trail; all points in instances (`m` null); a map id not in `ZONES`; a single point; window resize
  and phone rotation; `devicePixelRatio` 1, 2 and 3; a tile 404; art present but `world.js` missing; a hash camera
  out of the world (clamped); 1,000,000 points.
- **Tests:**
  - Unit `geo.test.mjs`: `toWorld` corners of Teldrassil (1438) and Elwynn (1429); unknown map and null give null;
    `zoneAt` picks the zone over the continent.
  - Unit `model.test.mjs`: clock over 2 sessions with a gap (the gap is not counted); `clockAt` before the first and
    after the last session; `unplaced` count; 1,000,000 synthetic points build in under 2 s (a guard against a
    quadratic loop, not a benchmark).
  - Unit `mapview.test.mjs`: `w2s(s2w(p)) = p`; `zoomAround` keeps the anchor point fixed; `clampCamera` keeps the
    world in view; `fitWorld` for a phone and a desktop size.
  - Manual rows: art loads and sharpens on zoom; drag, wheel and pinch on a phone; rotation keeps the centre; a
    `#journey?x=..&y=..&z=..` link opens at that camera; with `web/map/` renamed, the grid and the notice show and the
    trail is still in the right place.
- **Verify:**
  - `make web-lint web-test`
  - `make server-test e2e` (e2e unverified)
  - Manual with and without `web/map/` on `make local-up` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 5. Journey playback

- **Outcome:** the Journey map tab plays the journey: transport, speeds, timeline with lanes and the purse curve,
  follow camera, marker filters, tooltips and details, the synced journal log in the side panel or bottom sheet,
  the screenshot lightbox, the zone banner and the toasts. The playhead and the selected event are in the hash.
- **Depends on:** 4 (MapView, `buildModel`, Journey tab), 2 (`deriveSummary` purse rule, sheet, router).
- **Covers:** AC6 (all the rest), AC2 (`at`, `ev`), AC8 (journal log in the sheet, compact transport); risks "Player
  text" (tooltips, log, toasts), "stash is dropped".
- **Files:**
  - Create `web/lib/playback.mjs`, `web/test/playback.test.mjs`.
  - Edit `web/lib/model.mjs` (purse curve), `web/ui/journey.mjs`, `web/index.html` (transport, timeline canvas,
    markers fieldset, log list, lightbox, banner, toasts), `web/style.css`, `docs/viewer-manual-checklist.md`.
- **Implementation:**
  - `lib/model.mjs`: add `gold: [{c, v}]` with the purse rule of `deriveSummary` (Task 2) applied over time: start at
    the anchor money at the anchor clock, add each `mn.delta`, at least 0. Before the anchor, walk back from the anchor
    by subtracting deltas. Without a snapshot, start at 0 and mark `goldAbout`.
  - `lib/playback.mjs` (port from the stash): `advance(state, dtSec)` (`c += dt * BASE_RATE * speed`, `BASE_RATE =
    40`, stop at `total`), `goldAt`, `posAt` (interpolate between two points of the same chunk; hold at a chunk end),
    `levelAt`, `lastBefore`, `eventId(e) = e.t + '.' + e.k`, `findEvent(model, id)`, `crossed(model, from, to)` (events
    between two clock values for toasts), `zoneChange(model, from, to)`.
  - `ui/journey.mjs`: port `drawTrail` (played part bright, rest dim), `drawMarks`, `drawPlayer`, `updateCamera` (follow
    with ease; no ease under reduced motion), `setFollow`, `drawTimeline` (lanes Levels, Danger, Dungeons, Quests,
    Finds, World, Shots; session ticks; purse curve with "peak"; playhead), `tipHtml` (all data values through `esc`),
    `showTip`, `pickEvent`, detail panel, `toast`, the zone banner, `updateHud` (clock, purse, zone, level),
    `notifyCrossed`, `openShot` / `closeShot` (screenshot URL `root + entry.path + '/' + screenshot` as today; a 404 shows
    "Screenshot not uploaded"), `seek`, `setPlaying`, keyboard (Space toggles, Left and Right seek `15 * speed`
    seconds; ignore keys when focus is in an input, or when another tab is active), timeline scrub with pointer
    events, the `frame(now)` loop (run only while the Journey tab is visible and the document is not hidden).
  - Marker filters: checkboxes per category; on a phone they are in the bottom sheet with the log.
  - Journal log: the events up to the playhead, newest first, at most 200 items in the DOM; a click seeks to the event
    and selects it.
  - Hash: `setParams('journey', {x, y, z, at, ev})` on pause, seek and select (not on every frame during play). At
    load, `at` sets the playhead and `ev` selects the event and centres the camera on it.
  - Phone: the transport is one compact row (back, play, speed as a cycling button, clock) above the bottom bar;
    the timeline is under it at 64 px height; the log and the markers are in the sheet.
- **Edge cases:** one session; zero-length sessions; no events; events with no position (log only, no marker);
  `ev` that matches nothing; `at` larger than `total`; speed change while playing; tab change while playing (pause);
  tab hidden by the browser; 2,000 events in one second of clock (toasts are rate-limited to 3 at a time); hostile
  text in a kill name, a zone, a note.
- **Tests:**
  - Unit `playback.test.mjs`: `advance` at each speed and at the end; `posAt` inside a chunk, at a chunk edge and in a
    gap; `goldAt` before and after a snapshot anchor; `levelAt`; `crossed` includes the start and excludes the end;
    `findEvent` for a duplicate `t.k` returns the first; `zoneChange`.
  - Unit `playback.test.mjs` (XSS): `tipHtml` of each hostile fixture event has no `<img`.
  - Manual rows: play, pause, back to start, each speed; Space and arrows; scrub; follow on and off; each marker filter;
    tooltip and detail; log click seeks; lightbox opens and closes; banner on a zone change; toasts; a
    `#journey?at=..&ev=..` link opens paused at that point with the event selected; the phone layout with the sheet.
- **Verify:**
  - `make web-lint web-test`
  - Manual on `make local-up` with a real character (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 6. Heatmaps tab

- **Outcome:** the Heatmaps tab shows one heat layer over the map, chosen in a layer picker, with the Gathering
  profession filters and a legend. The layer, the filter and the camera are in the hash.
- **Depends on:** 4 (MapView, `buildModel` points and events), 2 (router, sheet).
- **Covers:** AC7, AC5 (art, grid fallback and legal line on the Heatmaps map, through `MapView`), AC2 (`layer`,
  `prof`, `x`, `y`, `z` for heatmaps), AC8 (layer picker in the sheet); risk "large trail" (binning).
- **Files:**
  - Create `web/lib/heat.mjs`, `web/ui/heatmaps.mjs`, `web/test/heat.test.mjs`.
  - Edit `web/index.html` (layer picker, filters, legend), `web/style.css`, `web/app.mjs` (mount),
    `docs/viewer-manual-checklist.md`.
- **Implementation:**
  - `lib/heat.mjs`:
    - `LAYERS`: `presence` (trail points), `kills` (`ki`), `deaths` (`de`, `hc`), `gathering` (`ga`), `fishing`
      (`fs`), `quests` (`qt`), `loot` (`lo`, `op`), each with a label and a colour ramp (transparent to the layer
      colour to a light tip; one hue per layer).
    - `layerPoints(model, layer, {prof})` → `{wx: Float32Array, wy: Float32Array, w: Float32Array, unplaced}`.
      Presence weight: seconds to the next point of the same chunk, capped at 30; the last point of a chunk weighs 2
      (the default trail rate). Other layers weigh 1 per record. `prof` filter on `ga.prof`: `mining` → `Mining`,
      `herbalism` → `Herbalism`, `skinning` → `Skinning`, `other` → any other value or none.
    - `binGrid(points, view, cell)` → `{cols, rows, data: Float32Array, max}`: add each point weight into a screen
      grid of `cell` CSS px (default 6) over the visible world rectangle; skip points outside it. One pass, O(n).
    - `blur(grid, radius)`: 3 passes of a box blur on rows and columns (an approximation of a Gaussian).
    - `colourise(grid, ramp)` → `Uint8ClampedArray` RGBA with `log1p(v) / log1p(max)` as the ramp index.
  - `ui/heatmaps.mjs`: a second `MapView` in the Heatmaps panel. On each camera change or layer change, bin, blur and
    colourise into an offscreen canvas of `cols × rows`, then draw it scaled with smoothing over the map at 0.85
    alpha. Recompute at most once per animation frame. Layer picker: radio buttons (desktop side panel, phone bottom
    sheet). Gathering shows the profession radios. Legend: the ramp, "N on the map", "M with no map position
    (instances)", and "No records for this layer." for an empty layer. Tap or hover on the map shows the weight of the
    cell under the pointer (for Presence as a duration with `fmtDur`).
  - Hash: `#heatmaps/<layer>?prof=..&x=..&y=..&z=..` through `setParams` and the layer in the path; at load use them,
    else fit the layer bounds, else fit the world.
- **Edge cases:** an empty layer; all points in instances; one point; all points in one cell (`max` > 0, no division by
  zero); a layer change during a pan; 1,000,000 presence points; `prof` on a layer that is not gathering (ignored);
  resize and rotation.
- **Tests:**
  - Unit `heat.test.mjs`: `layerPoints` per layer on the fixture (counts of `ki`, `de`, `fs`, `ga` by prof);
    presence weights with the 30 s cap and the chunk end; `unplaced` count; `binGrid` puts a point in the right cell and
    skips points outside the view; the sum of weights is kept by `binGrid`; `blur` keeps the sum within 1 %;
    `colourise` gives alpha 0 for 0 and the ramp tip for `max`; 1,000,000 points bin in under 2 s (guard).
  - Manual rows: each layer and each gathering filter; the legend counts match the Summary numbers; pan and zoom
    stay smooth on a phone; a `#heatmaps/fishing?x=..&y=..&z=..` link opens that view; the layer picker in the sheet.
- **Verify:**
  - `make web-lint web-test`
  - Manual on `make local-up` with a real character (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

## Validation

1. `make lint test coverage` passes (includes `web-lint`, `web-test`, Go and the other suites).
2. `make e2e` passes.
3. In a clean clone with no art, `docker build -f server/Dockerfile .` passes, and the character page shows the grid
   fallback and the notice.
4. `make web-assets MAP_SRC=~/Code/map-art`, `make local-up`, `make upload SITE=http://localhost:8080
   LATEST=<latest folder>`. Open the character page and run every row of `docs/viewer-manual-checklist.md` on a desktop
   browser (Firefox) and on a phone (or responsive mode at 360 × 740, written in the row).
5. In the browser network panel, the only third-party requests go to the Wowhead hosts of Task 3, and only after
   Summary shows gear. The console shows no CSP error.
6. Run 700 requests to `/_/map/tiles/...` from one IP in one minute: none gives 429. Run 700 to the character page:
   some give 429.
7. Open a link with each hash form of the Architecture table; each opens the stated view.
8. `git status` shows no file under `web/map/`.

## References

- Stash viewer: `git show 3f811e4:web/app.js`, `git show 3f811e4:web/style.css`, `git show 3f811e4:web/index.html`.
  Second source: `~/Code/map-art/site/app.js`.
- Map art build: `~/Code/map-art/README.md` ("Build the map art"), `tools/build_map.py`, `tools/build_layers.py`.
- Earlier spec of the character pages: `specs/done/2026-11-08-upload-backend.md` (AC2, Task 7, the headers section).
- Wowhead tooltips: https://classic.wowhead.com/forums&topic=3464.28/powered-tooltips-guide ;
  https://www.wowhead.com/forums/topic/powered-tooltips-guide-3464?page=30 ; a userscript that sets `whTooltips` and
  loads the widget from `wow.zamimg.com`: https://greasyfork.org/fr/scripts/498631-wowhead-tooltips-on-reddit-optimized/code
- A Wowhead tooltips WordPress plugin was closed for a security issue (April 2025):
  https://de-at.wordpress.org/plugins/wowhead-tooltips/
- Go `http.FileServerFS`: https://pkg.go.dev/net/http#FileServerFS
- Node test runner and coverage flags: https://nodejs.org/api/test.html , https://nodejs.org/api/cli.html#--test-coverage-linesthreshold
- CSP and CSSOM writes (allowed under `style-src 'self'`): https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/style-src
- Pointer events for pinch: https://developer.mozilla.org/en-US/docs/Web/API/Pointer_events/Pinch_zoom_gestures
- Fonts: https://github.com/google/fonts/tree/main/ofl/cinzel , https://github.com/google/fonts/tree/main/ofl/alegreyasans
  (SIL Open Font License 1.1).

## Open Decisions

None. Wowhead shows English names (Out of Scope); a later spec can add a locale choice.

## Completion

When every task is checked and Validation passes, move this file to `specs/done/` with `git mv` (plain `mv` when the
file is untracked). Create `specs/done/` if it does not exist. Commit the move.
