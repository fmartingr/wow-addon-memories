# Journey tab on the world map: a replay of the journey of the character, in the game

## Why

The player sees the journey only on the website or in the local viewer, outside the game. The game already shows a
world map, and every trail point and most journal lines have a map id and a position on it. The player must see the
journey on the game map, while playing, with no upload and no app.

This spec adds a side tab beside the quest log tab of the world map. The tab is a replay player like the one on the
website: a play button, a speed button, a slider and a clock, a trail that draws as time runs, and pins that pop in for
the events of the journey (level up, death and others).

**Revision 4 (icons).** The player added an icon pack for every kind (`assets/icons`). The pins, the bursts of the
events with no pin and the feed use these coins, from `Media/MapIcons` (TGA 64), and the arrow of the player draws over
every mark. The glyphs come from Font Awesome Free (CC BY 4.0), credited in `Media/MapIcons/ATTRIBUTION.txt`. This
replaces the badge and the skull of revision 3.

**Revision 3 (own window).** The player uses OpenMap, a world map addon that draws its own stitched layout of the
zones with no API for other addons. An overlay on the world map cannot follow that layout, so the trail vanished when
the replay moved to another zone. The replay now runs in a Journey window of this addon that draws its own map from
the game's map data, and the world map only has a button that opens it. The player also asked for fewer icons: only
level ups (a badge with the level) and deaths (a skull) leave a pin. AC18 and task 10 record this, and they replace
AC1, AC3, AC6 and AC13 where these differ.

**Revision 2 (look and feel).** The player wants the replay to look and feel like the best replay players for the
game: a trail with a readable colour scheme, a marker that points along the route, arcs for the trips that skip the
trail, a list of chapters to jump to, a feed of highlights, and an animation for each big moment. AC14 to AC16 and tasks
7 and 8 record this. All code, text and art are our own, written from the public game API (see the Must Not rules).

**Revision (after the first build).** The first build drew a static overlay and listed the replay as out of scope. That
did not match the goal. The player also found two bugs in the game: icons that "bug out" and cover the map when
zoomed out, and a wrong tab and panel layout. AC10 to AC13 and the decisions below record the fixes.

## What

- **AC1 — Tab:** the world map has a **Journey** tab in the column of the side tabs, under the last game tab. A click
  shows the Journey panel and the player bar and turns the overlay on. A click on a game tab turns it off. The map
  opens on the tab that the player used last.
- **AC2 — Trail:** the overlay draws the recorded trail of the map that the map shows, as lines. The line color shows
  the way of travel (foot, mounted, taxi, swimming, dead or ghost), as the website does.
- **AC3 — Pins:** the overlay draws one pin for each journal line that has a position on that map. A pin has an icon of
  its kind group and a tooltip with the time, the kind name and the fields. A pin of a death and of a level up is
  larger.
- **AC4 — Panel:** the Journey panel has a check box for each group of kinds (Progress, Deaths, Travel, ...) and a
  check box for Trail, a list of sessions (the date and the length) with one choice for "All", and a count of the
  lines and pins.
- **AC5 — Higher maps:** on a continent or the world map, the overlay draws the trail and the pins of the zones
  below it, put on that map through the world position. Without a valid projection for a zone, the overlay skips that
  zone.
- **AC6 — Saved choice:** the shown groups, Trail on or off, and the last tab are saved per account in
  `MemoriesDB.settings.map`. A session choice is not saved.
- **AC7 — Safe:** the overlay never changes a game map function. A failure in the overlay does not break the map: the
  error goes to `/memories errors`, and the game map still works. In combat, the tab works and shows no taint error.
- **AC8 — Language:** all new texts exist in the 6 languages of the addon (`Locales.lua`).
- **AC9 — Docs:** `docs/addons.md`, `docs/settings.md` and `docs/manual-checklist.md` describe the tab.
- **AC10 — Player bar:** a bar at the bottom of the map has a play and pause button, a speed button (1x, 2x, 4x, 8x,
  16x), a slider to seek, and the clock of the replay (`m:ss / m:ss`). The clock counts played seconds, and a pause
  longer than 20 s counts as 20 s. At 1x the replay runs 40 played seconds for each real second, as the website. Play
  at the end starts again from the start. With nothing to play, the controls are off.
- **AC11 — Replay:** the trail draws as the playhead passes it, with a glowing marker at the head that moves along the
  trail. A pin pops in with a short grow animation when the playhead passes its event, then pulses for 6 played
  seconds. A seek back hides the lines and pins after the playhead. With no replay running, the whole journey shows.
- **AC12 — Zoom and size:** pins, lines and the head marker keep their screen size at each canvas scale and each map
  size. On a continent or world map the pins are half size. No icon covers the map, and no texture stretches.
- **AC13 — Layout:** the panel stays on screen and never lies over a game frame that it does not own. On the
  windowed map it docks beside the map. On a maximized map it lies over the right side of the map. It follows the map
  when the map is maximized or made small while open. The tab, the panel and the player bar lie above the map pins and
  take their clicks.

- **AC14 — Trail look:** the trail has three colour modes, saved as `map.color`: `way` (the way of travel, the default),
  `level` (the level of the character at that time) and `age` (older steps are cooler and dimmer than newer ones). A
  check box `map.colorblind` swaps the palette for one that stays readable with the common colour blindness types. The
  marker at the head is an arrow in silver that points along the route and turns with it. A trip that skips the trail
  (a hearthstone, a portal, a summon, a boat or a flight with no recorded points) draws as a curved arc from the last
  point before to the first point after, and it draws in the replay in the time of the trip.
- **AC15 — Chapters and highlights:** the panel lists the journey in chapters (the start, then one chapter for each
  level) and a click on a chapter jumps the replay to that moment. The same list area switches to the list of sessions
  (AC4). A Highlights feed shows the last six events that the playhead passed, newest first, each with its icon, its
  kind name and its main field. The feed empties on a seek back and on a new draw that does not keep the playhead.
- **AC16 — Highlight animations:** when the playhead passes a level up, a death, a flight, a boat or zeppelin, a
  hearthstone, a portal or teleport, a summon, a dungeon, or a boss, a burst plays at its pin: a ring grows and fades
  and a short label rises and fades (about 1.2 s). The colour and the label follow the kind. At most 4 bursts play at
  once, and none plays on a seek or a jump over many events.

- **AC17 — Follow:** with the check box **Follow** on the player bar (saved as `map.follow`, on by default), the replay
  moves through the maps by itself. The clock then spans the whole journey on all maps. When the playhead enters a
  stretch of the trail on another map, the world map shows that map, the replay waits 0.6 s, and it goes on from the
  same moment. A continent or world map that shows the zone of the playhead stays as it is. A map change that the
  player makes during a replay turns following off until the next Play, seek or change of the box. A map that cannot be
  shown turns following off in the same way. With Follow off, the replay plays the map shown only.

- **AC18 — Journey window:** a button under the side tabs of the world map (or on its right edge) opens and closes a
  Journey window of this addon, and is lit while it is open. The window draws its own map: the art tiles of the map,
  scaled to its map area, and the explored areas over them. It opens on the map of the player, or on the first map of
  the trail when that one has no art. A left click on a zone opens the zone, and a right click or the Up button goes
  to the map that holds it. The panel sits at the right of the map and the player bar under it. Escape closes the
  window and the title bar moves it. Memories draws nothing on the world map, so the window works the same with
  OpenMap or another world map addon. Only level ups and deaths leave a pin: a level up is a badge with its level and
  a gold rim, a death is a skull with a red rim. The other kinds of the replay play their burst and go to the feed
  with no pin. The panel boxes are Level ups, Deaths, Travel and Dungeons. The saved setting of the last tab is gone.

## Constraints

- **Must:**
  - Put the code in the core addon `Memories`, in new files under `addons/Memories/UI/Map/`, listed in
    `Memories.toc`. No new addon folder.
  - Use only public game APIs and mixins: `WorldMapFrame`, `AddDataProvider`, `MapCanvasDataProviderMixin`, the
    canvas, `C_Map`, `EventRegistry`, `hooksecurefunc`.
  - Read the journey from the saved data: `MemoriesCharDB.trail` (the chunks and the open stretch) and
    `Journal:Lines()`. Never write to the saved data.
  - Keep the memory low: decode a chunk when the overlay needs it, keep one list for the map shown, and reuse the
    line and pin frames from a pool.
  - Write texts through `ns.L`, and add each text to the 5 other languages.
  - Commit on `main`, one commit per task.
- **Must Not:**
  - Copy code, text or art from another addon. Write all code from the public game API.
  - Replace or hide a game map function or frame. Hide only the overlay of this addon.
  - Hide the pins or drawings of other addons.
  - Record any new data. This is a viewer only.
- **Out of Scope:**
  - Heat maps, the gear card and the stats window.
  - Camera follow, the purse and level read-outs of the website player, and the events list.
  - Other characters of the account.
  - Skins for ElvUI, GW2 UI and other UI suites (the tab uses the look of the game tabs).
  - The Retail client. The target is the client of `## Interface: 16001`.

## Decisions

| Decision | Reason |
|---|---|
| A side tab that is a frame of this addon, not a member of the `TabButtons` array of the quest log. | The game owns that array, and a change to it can cause taint. |
| One data provider, added with `WorldMapFrame:AddDataProvider`, draws the overlay on a canvas layer. | The provider gets `OnMapChanged` and `RemoveAllData` from the game, so the overlay follows the zoom and the map change with no hook. |
| The pure data code (what to draw for a map) is separate from the frame code. | The busted suite tests the data code with no game frames. The frame code is thin. |
| Trail lines come from `Line` textures on a pool, in the canvas coordinates of the shown map. | `Line` is the game's own way to draw a segment, with no art file. |
| The panel docks beside the windowed map and lies over the right side of a maximized map. It never lies over the quest log. | The Era client has no `QuestMapFrame`. A panel over a game frame was fragile, and a 16:9 screen has only about 170 px beside a maximized map. |
| The pure timeline (`Replay.lua`) is separate from the frame code (`Overlay.lua`). | The busted suite tests the clock, the counts and the head position with no frames. |
| The replay uses played seconds with each pause capped at 20 s, 40 played seconds for each real second at 1x. | A journey of many sessions plays with no dead time, and the rate matches the website. |
| One `OnUpdate` on the overlay frame runs only while the replay plays or an animation runs, and shows at most `SLICE` new lines for each frame. | No cost at rest, and a long trail never stops a frame. |
| Pin, line and head sizes are in screen units and divide by the canvas scale (`GetCanvasScale`). The provider callbacks `OnCanvasSizeChanged` and `OnCanvasScaleChanged` place them again. | This is how the game sizes its own pins. A size in canvas units grew with the map and covered it. |
| Pins on a continent or world map (`ns.IsSkippedMap`) are half size. | Up to 500 pins at full size are too dense on those maps. |
| The player bar and the panel take their frame level from `PIN_FRAME_LEVEL_TOPMOST` of the map's pin manager, plus 10, with a fixed level as fallback. | The game's pins sit at levels from 2000 up, and they drew over the bar and took its clicks. |
| The colour of a step by level or by age is worked out when the timeline is built, not for each frame. | The colour modes cost nothing while the replay plays. |
| The head marker is the game's own arrow texture (`Interface\Minimap\ROTATING-MINIMAPARROW`), set to grey and rotated with `SetRotation`. | An arrow that follows the route needs no art of our own. |
| A trip arc comes from a jump in the trail: two points of consecutive chunks that are less than 120 s apart and far apart on the map. The arc is a quadratic curve cut in 10 steps that are edges of the timeline. | Every kind of trip (hearthstone, portal, summon, boat, flight) leaves such a jump, so one rule covers them all. |
| A burst is one pooled frame with a ring texture and a label, driven by the same `OnUpdate` as the pins. | No new update loop, and no per-burst garbage. |
| Chapters come from the `lv` lines of the journal. | Levels are the natural chapters of the journey of a character. |
| The panel changes a text or a value only when it changed. | No garbage while the replay plays. |
| Follow uses one clock for the whole journey, built from the time range of each trail chunk: real time inside a chunk and at most 20 s for each gap between chunks. | The chunk records give the range with no full decode, so the clock costs two numbers for each chunk, and it is the same on each map. |
| Follow switches the map with `WorldMapFrame:SetMapID`, a public call, and keeps the playhead through the redraw. | The provider redraws the map by itself, so no game function is changed. |
| A map change that the overlay did not ask for during a replay turns following off, not the saved setting. | The replay never fights the player for the map. |
| The replay runs in a window of this addon, not on the world map. | A world map addon such as OpenMap draws its own layout and changes maps on its own, with no API. Only a map of our own gives Follow and the trail a fixed place. |
| The window draws the map art from `C_Map.GetMapArtLayers`, `C_Map.GetMapArtLayerTextures` and `C_MapExplorationInfo.GetExploredMapTextures`. | These are the public calls the game's own map uses, so the art matches the projection of the trail. |
| The overlay draws into a host (the window), which gives the map id, the canvas and `SetMapID`. | The overlay, the replay and Follow stay as they are; only the host changed. |
| Only level ups and deaths leave a pin; the death pin is the game's skull texture, and the level pin is text in a badge. | The map stays readable, and no art of our own is needed. |
| Every texture has its own size and one anchor. A pin takes no clicks, only the tooltip. | A texture with `SetAllPoints` in a frame of size 0 can fill the canvas. |
| The tab icon is the addon icon `Media\icon`. | The file exists in the addon already. |

## Risks

| Risk | Impact | Mitigation | Owner task |
|---|---|---|---|
| No game client is at hand while we write the code, so the map API may differ from the notes. | The tab or the overlay does not show in the game. | Each frame call goes through a small adapter that tests fake; the manual checklist runs in the game before the release; every call that may be missing is checked first. | 2, 3 |
| A long trail (2000 points per stretch, many stretches) makes the draw slow. | A frame drop when the map opens. | Draw only the shown map; thin the points to one for each screen pixel; draw in slices of 200 segments for each frame. | 1, 2 |
| `Line` textures and pins are many on a continent map. | A frame drop; a high memory use. | A cap of 3000 lines and 500 pins for each draw, and the panel says when a cap cuts the view. | 2 |
| Taint from the tab or the panel in combat. | A blocked action. | No secure frame is changed; the tab and the panel are plain frames; `InCombatLockdown` is not needed. | 3 |
| A zone has no projection on the continent map. | A zone is missing on the higher map. | Skip it and count it; the panel shows "N zones not shown". | 1 |
| The animation costs frame time on a long journey at 16x. | A frame drop while the replay plays. | One `OnUpdate`, a slice of lines for each frame, at most 8 pops for each frame, and it stops at rest. | 2, 3 |
| A texture path of the replay is wrong on the client (the head glow `Interface\Cooldown\star4`). | A square block shows instead of a glow. | Manual rows U19 and U21; change the path if the row fails. | 2 |
| The tab or the panel lies outside the map frame, which the map draws through a frame buffer. | The tab or the panel is clipped. | Manual row U14 on the windowed and the maximized map. | 3 |
| Another addon adds a tab or an overlay to the map. | Two tabs and two overlays. | Each addon owns its frames; the tab column puts ours under the last tab that exists. | 3 |

## Current State

- **Recorded data:** the trail is `MemoriesCharDB.trail = { v, chunks }`. A chunk is `{ s, t, m, n, d, o }` (session
  start, unix time of the first point, map id, point count, point text). `TrailCodec.Decode(rec)` returns points
  `{ t, x, y, flags }` with `x`, `y` in 0..10000 of map `m` and `y` down. The open stretch is `Trail.Open()`.
  Flags are `t` taxi, `f` flying, `m` mounted, `g` ghost, `d` dead, `w` swimming, `c` combat, `i` instance
  (`addons/Memories/Data/TrailCodec.lua`).
- **Journal:** `Journal:Lines()` yields the lines `t|p|m|x|y|kind|fields...` (`docs/kinds.md`). `m`, `x`, `y` are empty
  inside an instance and on a world or continent map (`ns.IsSkippedMap`). `ns.Kinds` holds the kinds with their
  addon, group and fields.
- **Sessions:** `in` and `out` lines mark a session; the trail chunks have the session start `s`.
- **Settings:** account-wide in `MemoriesDB.settings` with defaults and a `clean` pass in `Data/Settings.lua`. The
  Settings page is `UI/Options.lua`. Texts are in `Locales.lua` for deDE, frFR, esES, esMX, itIT and ptBR.
- **UI files:** `UI/Minimap.lua`, `UI/Status.lua`, `UI/Options.lua`. No file touches `WorldMapFrame` yet.
- **Test harness:** `spec/helpers/wow.lua` has a `C_Map` stub (`GetBestMapForUnit`, `GetPlayerMapPosition`,
  `GetMapInfo`) and a `CreateFrame` stub. `make test-lua` runs busted; `make lint-lua` runs luacheck; `make fmt-check`
  runs stylua.
- **Client:** `## Interface: 16001` in every TOC. The Era map has no quest log frame and no mouse-wheel zoom, so a
  zoom out means a change to the continent or world map.
- **Segments:** `MapData.Segments` returns `{ way, pts, ts }`, with one time for each point, so the replay can order
  the steps in time.

## Implementation guidelines

Same rules as `specs/done/2026-11-11-app-local-viewer.md`, section "Implementation guidelines": a test for each
changed behavior, the three reviews in a subagent on the strongest model, one commit for each task on `main`, no push.
Coverage: `make coverage-lua` must not drop.

## Tasks

### [x] 1. Map data: what to draw for a map

- **Outcome:** `ns.MapData` returns, for a map id and a filter, the trail segments and the pins, in map coordinates.
- **Covers:** AC2 (data), AC3 (data), AC5 (projection), AC6 (settings keys); risk "long trail", "no projection".
- **Files:** `addons/Memories/UI/Map/MapData.lua` (new), `addons/Memories/Memories.toc`,
  `addons/Memories/Data/Settings.lua` (`map = { groups = {}, trail = true, tab = "quest" }`),
  `spec/mapdata_spec.lua` (new), `spec/settings_spec.lua`.
- **Implementation:**
  - `MapData.Segments(mapID, filter)`: decode the chunks of that map (and of its child zones when `mapID` is a
    continent or the world, through `MapData.Project`), join the points into segments, break a segment at a gap of
    more than `Trail.PAUSE` seconds, a teleport and a map change, and thin the points.
  - `MapData.Pins(mapID, filter)`: the journal lines with a position on that map, by group, each `{ t, kind, x, y,
    fields }`.
  - `MapData.Project(zoneMap, x, y, targetMap)`: through `C_Map.GetWorldPosFromMapPos` and
    `C_Map.GetMapPosFromWorldPos`; nil when a call is missing or gives nil.
  - `MapData.Sessions()`: the list `{ start, stop }` from the `in` and `out` lines.
  - `filter = { trail, groups = { [group] = true }, session }`.
- **Edge cases:** an empty journal; a malformed chunk (skipped); a chunk with the flag `i` (instance, not drawn); a
  point outside 0..10000; a read-only journal.
- **Tests:** `spec/mapdata_spec.lua` for each function and edge case, with the `C_Map` stub extended in
  `spec/helpers/wow.lua`.
- **Verify:** `make test-lua lint-lua fmt-check coverage-lua`.

### [x] 2. The overlay: a data provider that draws on the map

- **Outcome:** with the overlay on, the map shows the lines and the pins of task 1 and their tooltips.
- **Depends on:** 1.
- **Covers:** AC2, AC3, AC5, AC7; risk "long trail", "many lines", "no game client".
- **Files:** `addons/Memories/UI/Map/Overlay.lua` (new), `addons/Memories/Memories.toc`, `spec/overlay_spec.lua`.
- **Implementation:** a provider that mixes in `MapCanvasDataProviderMixin`; `OnMapChanged` asks for a draw; a pool of
  `Line` textures and of pin frames; the draw runs in slices; a failure goes through `ns.Safe`; `Overlay.Show(on)`.
  Colors for each way of travel as in `web/` (`web/kinds.js`, `web/style.css`; read, not changed).
- **Tests:** a fake canvas and fake provider mixin in the harness: a draw puts N lines and M pins; a cap cuts the
  count; a change of map clears the pools; an error in a draw leaves the map working.
- **Verify:** `make test-lua lint-lua fmt-check`; in the game, the manual rows of task 3.

### [x] 3. The tab and the panel

- **Outcome:** the Journey tab and panel of AC1, AC4 and AC6.
- **Depends on:** 2.
- **Covers:** AC1, AC4, AC6, AC7; risk "taint", "another map addon".
- **Files:** `addons/Memories/UI/Map/Tab.lua` (new), `addons/Memories/UI/Map/Panel.lua` (new),
  `addons/Memories/Memories.toc`, `spec/maptab_spec.lua`.
- **Implementation:** the tab is a frame of ours, placed under the last visible tab of the map's side column; a click
  calls `Overlay.Show(true)` and shows the panel where the quest log sits; `EventRegistry` callback
  `QuestLog.SetDisplayMode` and a click on a game tab call `Overlay.Show(false)`; the panel has the check boxes, the
  session choice and the count; the choices go to `MemoriesDB.settings.map`.
- **Tests:** the tab shows and hides the overlay; a game tab hides it; the choices save and load; a read-only
  `MemoriesDB` keeps the choices for the session only.
- **Verify:** `make test-lua lint-lua fmt-check`.

### [x] 4. Texts and docs

- **Outcome:** AC8 and AC9.
- **Depends on:** 3.
- **Files:** `addons/Memories/Locales.lua`, `spec/locales_spec.lua` (inspect), `docs/addons.md`, `docs/settings.md`,
  `docs/manual-checklist.md`.
- **Implementation:** each new text in 6 languages; the manual rows: the tab shows on the map; the trail and the pins
  show on a zone map; a continent map shows the zones; the panel filters; a long journey does not drop the frame
  rate; a click on the quest log tab hides the overlay; combat shows no error; another addon with a map tab shows no
  clash.
- **Verify:** `make test-lua lint-lua fmt-check`.

### [x] 5. Replay: the timeline, the player bar and animated pins

- **Outcome:** AC10, AC11 and the zoom part of AC12.
- **Depends on:** 3.
- **Covers:** AC10, AC11, AC12; risk "animation cost".
- **Files:** `addons/Memories/UI/Map/Replay.lua` (new), `Overlay.lua`, `Panel.lua`, `MapData.lua` (`ts`),
  `Memories.toc`, `Locales.lua` ("Play", "Pause"), `spec/replay_spec.lua` (new), `spec/overlay_spec.lua`,
  `spec/maptab_spec.lua`, `spec/mapdata_spec.lua`, `spec/helpers/wow.lua`.
- **Implementation:** `Replay.Build` makes the sorted steps and pins with a clock; `Replay.Advance`, `Counts`, `Head` and
  `ClockText` are pure. The overlay keeps the playhead, the speed and the shown counts, and runs one `OnUpdate`. The
  bar has a play button, a speed button, a slider and a clock, set from the events `MAP_REPLAY_CHANGED` and
  `MAP_REPLAY_TICK`.
- **Tests:** the clock caps a pause; counts and head position at a clock; play, pause, restart at the end, speed, seek
  back and forward; pop and pulse end by themselves; at most 8 pops for each frame; the bar controls and the slider;
  a failure in a frame clears the drawing and stops the update.
- **Verify:** `make test-lua lint-lua fmt-check`.

### [x] 6. Fix the zoom, the icons and the layout

- **Outcome:** AC12 and AC13.
- **Depends on:** 5.
- **Covers:** AC12, AC13; risk "texture path", "frame buffer".
- **Files:** `Overlay.lua`, `Panel.lua`, `Tab.lua`, `docs/addons.md`, `docs/manual-checklist.md` (U14, U18 to U21),
  `spec/overlay_spec.lua`, `spec/maptab_spec.lua`.
- **Implementation:** sizes divide by the canvas scale and follow `OnCanvasSizeChanged` and `OnCanvasScaleChanged`;
  pins are half size on a continent or world map; every texture has its own size and one anchor; the panel docks beside
  the windowed map and over the right side of a maximized map, follows `SynchronizeDisplayState`, and is clamped to the
  screen; the tab is clamped and lies above the panel; the bar and panel take the level of `PIN_FRAME_LEVEL_TOPMOST`
  plus 10; the slider takes the mouse and has a thumb of its own size.
- **Tests:** sizes at several scales and a scale out of range; a canvas of size 0; the dock on a windowed and a
  maximized map; the bar level; the slider drag.
- **Verify:** `make test-lua lint-lua fmt-check`; in the game, rows U14, U18, U19 and U21.

### [x] 7. Trail look: colour modes, the arrow marker and trip arcs

- **Outcome:** AC14.
- **Depends on:** 6.
- **Covers:** AC14, AC6 (`map.color`, `map.colorblind`).
- **Files:** `Data/Settings.lua`, `UI/Map/MapData.lua` (`Levels`, jumps), `Replay.lua`, `Overlay.lua`, `Panel.lua`,
  `Locales.lua`, `spec/settings_spec.lua`, `spec/mapdata_spec.lua`, `spec/replay_spec.lua`, `spec/overlay_spec.lua`,
  `spec/maptab_spec.lua`.
- **Implementation:** `MapData.Levels()` lists `{ t, level }` from the `lv` lines; `MapData.Segments` returns the jumps as a
  third result; `Replay.Build` adds the arc edges, and gives each edge its `level` and `age`; the overlay picks the colour
  of a line from the mode and the palette; the head is an arrow that turns with the direction of the step; the panel has a
  button that cycles the colour mode and a check box for the colourblind palette.
- **Tests:** the level at a time (before the first `lv`, between, after, none); a jump needs less than 120 s and enough
  distance; an arc has 10 edges that join the two points in the time of the trip; the colour of a step in each mode and
  palette; the arrow turns for each direction; the settings save and clean.
- **Verify:** `make test-lua lint-lua fmt-check`.

### [x] 8. Chapters, the Highlights feed and highlight animations

- **Outcome:** AC15 and AC16.
- **Depends on:** 7.
- **Covers:** AC15, AC16; risk "animation cost".
- **Files:** `UI/Map/Replay.lua`, `Overlay.lua`, `Panel.lua`, `Locales.lua`, `docs/addons.md`,
  `docs/manual-checklist.md`, `spec/replay_spec.lua`, `spec/overlay_spec.lua`, `spec/maptab_spec.lua`.
- **Implementation:** the timeline gives the clock of a unix time, so a chapter row seeks to it; the panel list switches
  between chapters and sessions; the overlay sends an event for each pin that the playhead passes while the replay plays,
  and the panel keeps the last six for the feed; a pool of burst frames plays the ring and the label with the same
  `OnUpdate` as the pins, and a kind table sets the colour and the label.
- **Tests:** a chapter click seeks to its clock; the list switch; the feed order, size and reset; a burst plays for the
  kinds in the table and not for others; at most 4 bursts at once; no burst on a seek or a jump over many events; a
  burst ends by itself and returns to the pool.
- **Verify:** `make test-lua lint-lua fmt-check`; in the game, the new manual rows.

### [x] 9. Follow: the replay moves through the maps

- **Outcome:** AC17.
- **Depends on:** 8.
- **Covers:** AC17, AC6 (`map.follow`).
- **Files:** `Data/Settings.lua`, `UI/Map/MapData.lua` (`Route`, `Shows`), `Replay.lua` (`Clock`, `Route`, `MapAt`, a clock for
  `Build`), `Overlay.lua`, `Panel.lua`, `Locales.lua`, `docs/addons.md`, `docs/settings.md`, `docs/manual-checklist.md`,
  `spec/settings_spec.lua`, `spec/mapdata_spec.lua`, `spec/replay_spec.lua`, `spec/overlay_spec.lua`, `spec/maptab_spec.lua`.
- **Implementation:** `MapData.Route` lists one visit `{ m, t0, t1 }` for each trail chunk (not an instance chunk),
  read from the chunk fields with no full decode; `Replay.Clock` builds the clock of the whole journey from the visits and
  `Replay.Build` takes it; the overlay finds the map of the playhead, and when it is not the map shown and the map shown
  does not show it, it keeps the playhead, calls `SetMapID`, and waits `MAP_PAUSE`; a draw during a replay keeps the
  playhead; an unexpected map change or a failed `SetMapID` sets a hold that Play, a seek and the box clear; the bar has the
  Follow box.
- **Tests:** the route and its session filter; the clock; the map at a clock; the switch, the pause and the kept playhead;
  a continent that stays; a change by the player and a failure hold following; Play clears the hold; Follow off plays
  one map; the box saves the setting.
- **Verify:** `make test-lua lint-lua fmt-check`; in the game, rows U28 to U30.

### [x] 10. The Journey window and fewer pins

- **Outcome:** AC18.
- **Depends on:** 9.
- **Covers:** AC18, AC8, AC9; risk "another map addon".
- **Files:** `UI/Map/Window.lua` (new), `Overlay.lua` (host, pins, filter), `Panel.lua` (groups), `Tab.lua` (button),
  `MapData.lua` (`filter.kinds`), `Data/Settings.lua` (no `tab`), `Memories.toc`, `Locales.lua`, `.luacheckrc`, `docs/*`,
  `spec/maptab_spec.lua`, `spec/overlay_spec.lua`, `spec/settings_spec.lua`, `spec/helpers/wow.lua`.
- **Tests:** the button places and toggles the window; the first map; the tiles and the explored pieces with their
  sizes, offsets and texture coordinates; Up, right click and a left click on a zone; a map with no art; Follow switches
  the window map; the pins: badge, skull, no pin for other kinds; the filter reads only the panel groups.
- **Verify:** `make test-lua lint-lua fmt-check`; in the game, rows U1, U2, U4, U7, U8, U12, U14, U18, U19, U21 and U28
  to U31.

## Validation

1. `make lint test` passes.
2. In the game: open the map, click Journey, and see the player bar. Click Play and see the trail draw with the head
   marker and the pins pop in. Change the speed, drag the slider, pause. Change a filter and see the change. Open the
   continent map and see the zones, with smaller pins and no icon over the map. Maximize and shrink the map with
   Journey on. Close and open the map: the last tab stays.
3. `/memories errors` shows no new error after a play session with the map open.
4. Every manual row that this spec adds is run and marked.

## References

- `docs/kinds.md`, `docs/addons.md`, `docs/settings.md`.
- Earlier specs: `specs/done/2026-11-11-app-local-viewer.md`.

## Open Decisions

- No game client was available while writing this spec. The map API names come from the Blizzard UI code (checked
  against the Classic Era 1.15.9 source after the revision). Run the manual rows U1 to U21 in the game before the
  release. Two points stay open: the head glow texture `Interface\Cooldown\star4`, and the clip of the tab and the panel
  by the frame buffer of the map.
