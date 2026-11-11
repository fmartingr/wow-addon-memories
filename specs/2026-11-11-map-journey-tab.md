# Journey tab on the world map: the trail and the events of the character, in the game

## Why

The player sees the journey only on the website or in the local viewer, outside the game. The game already shows a
world map, and every trail point and most journal lines have a map id and a position on it. The player must see the
journey on the game map, while playing, with no upload and no app.

This spec adds a side tab beside the quest log tab of the world map. The tab draws the trail and pins on the map and
shows a panel in the place of the quest log.

## What

- **AC1 — Tab:** the world map has a **Journey** tab in the column of the side tabs, under the last game tab. A click
  shows the Journey panel in the place of the quest log and turns the overlay on. A click on a game tab turns it off.
  The map opens on the tab that the player used last.
- **AC2 — Trail:** the overlay draws the recorded trail of the map that the map shows, as lines. The line color shows
  the way of travel (foot, mounted, taxi, swimming, dead or ghost), as the website does.
- **AC3 — Pins:** the overlay draws one pin for each journal line that has a position on that map. A pin has an icon of
  its kind group and a tooltip with the time, the kind name and the fields. A pin of a death and of a level up is
  larger.
- **AC4 — Panel:** the Journey panel has a check box for each group of kinds (Progress, Deaths, Travel, ...) and a
  check box for Trail, a list of sessions (the date and the length) with one choice for "All", and a count of the
  shown lines and pins.
- **AC5 — Higher maps:** on a continent or the world map, the overlay draws the trail and the pins of the zones
  below it, put on that map through the world position. Without a valid projection for a zone, the overlay skips that
  zone.
- **AC6 — Saved choice:** the shown groups, Trail on or off, and the last tab are saved per account in
  `MemoriesDB.settings.map`. A session choice is not saved.
- **AC7 — Safe:** the overlay never changes a game map function. A failure in the overlay does not break the map: the
  error goes to `/memories errors`, and the game map still works. In combat, the tab works and shows no taint error.
- **AC8 — Language:** all new texts exist in the 6 languages of the addon (`Locales.lua`).
- **AC9 — Docs:** `docs/addons.md`, `docs/settings.md` and `docs/manual-checklist.md` describe the tab.

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
  - A replay (an animation of the journey on the map).
  - Heat maps, the gear card and the stats window.
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
| The panel opens where the quest log sits; with no quest log, it docks beside the map view. | The map has no tab strip of its own. |
| The tab icon is the addon icon `Media\icon`. | The file exists in the addon already. |

## Risks

| Risk | Impact | Mitigation | Owner task |
|---|---|---|---|
| No game client is at hand while we write the code, so the map API may differ from the notes. | The tab or the overlay does not show in the game. | Each frame call goes through a small adapter that tests fake; the manual checklist runs in the game before the release; every call that may be missing is checked first. | 2, 3 |
| A long trail (2000 points per stretch, many stretches) makes the draw slow. | A frame drop when the map opens. | Draw only the shown map; thin the points to one for each screen pixel; draw in slices of 200 segments for each frame. | 1, 2 |
| `Line` textures and pins are many on a continent map. | A frame drop; a high memory use. | A cap of 3000 lines and 500 pins for each draw, and the panel says when a cap cuts the view. | 2 |
| Taint from the tab or the panel in combat. | A blocked action. | No secure frame is changed; the tab and the panel are plain frames; `InCombatLockdown` is not needed. | 3 |
| A zone has no projection on the continent map. | A zone is missing on the higher map. | Skip it and count it; the panel shows "N zones not shown". | 1 |
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
- **Client:** `## Interface: 16001` in every TOC.

## Implementation guidelines

Same rules as `specs/done/2026-11-11-app-local-viewer.md`, section "Implementation guidelines": a test for each
changed behavior, the three reviews in a subagent on the strongest model, one commit for each task on `main`, no push.
Coverage: `make coverage-lua` must not drop.

## Tasks

### [ ] 1. Map data: what to draw for a map

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

### [ ] 2. The overlay: a data provider that draws on the map

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

### [ ] 3. The tab and the panel

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

### [ ] 4. Texts and docs

- **Outcome:** AC8 and AC9.
- **Depends on:** 3.
- **Files:** `addons/Memories/Locales.lua`, `spec/locales_spec.lua` (inspect), `docs/addons.md`, `docs/settings.md`,
  `docs/manual-checklist.md`.
- **Implementation:** each new text in 6 languages; the manual rows: the tab shows on the map; the trail and the pins
  show on a zone map; a continent map shows the zones; the panel filters; a long journey does not drop the frame
  rate; a click on the quest log tab hides the overlay; combat shows no error; another addon with a map tab shows no
  clash.
- **Verify:** `make test-lua lint-lua fmt-check`.

## Validation

1. `make lint test` passes.
2. In the game: open the map, click Journey, and see the trail and the pins of the zone. Change a filter and see the
   change. Open the continent map and see the zones. Close and open the map: the last tab stays.
3. `/memories errors` shows no new error after a play session with the map open.
4. Every manual row that this spec adds is run and marked.

## References

- `docs/kinds.md`, `docs/addons.md`, `docs/settings.md`.
- Earlier specs: `specs/done/2026-11-11-app-local-viewer.md`.

## Open Decisions

- No game client was available while writing this spec. The map API names come from the Blizzard UI code. Run task 3
  in the game before the release.
