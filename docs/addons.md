# The addons

Back to the [documentation index](README.md).

Each addon has its own per-character saved file. A sub-addon loads only when `Memories` loads
(`## Dependencies: Memories`), and the AddOn list shows all 6 as the group "Memories". Turn a sub-addon off in the
AddOn list to stop its recording.

| Addon | Records | Saved table |
|---|---|---|
| `Memories` (core, always on) | sessions, the position trail, progress (levels, XP, quests, discoveries, rest), deaths, close calls, travel (zones, flights, boats, hearthstone, summons, portals, mounts), dungeons and bosses, screenshots, and lines from other addons | `MemoriesCharDB`, plus the account table `MemoriesDB` (settings, backups, orphans, errors, kind metadata) |
| `Memories_Combat` | kills, rare kills and long fights | `MemoriesCombatCharDB` |
| `Memories_Gathering` | gathering, fishing, opening containers and chests, pick pocket | `MemoriesGatheringCharDB` |
| `Memories_Character` | skills, spells, recipes, talents, consumables, tamed pets, reputation, accepted quests, homes, flight paths and books | `MemoriesCharacterCharDB` |
| `Memories_Economy` | loot, group rolls, gear, equipped items, money, trainers, the auction house, mail and trade | `MemoriesEconomyCharDB` |
| `Memories_Social` | group members, your guild, enemy players, PvP kills and deaths, honor, duels, battlegrounds and PvP rank | `MemoriesSocialCharDB` |

## The Journey tab on the world map

The core addon adds a **Journey** tab to the side tabs of the world map, under the last game tab. The tab replays the
recorded journey on the map, with no upload and no app. A click on the tab shows the Journey panel beside the map and a
player bar at the bottom of the map. On a maximized map the panel lies over the right side of the map, as the screen
leaves no room beside it. A click on a game tab hides the Journey view.

- **Player bar:** play and pause, a speed button (1×, 2×, 4×, 8×, 16×), a slider to seek, and the clock of the replay.
  The clock counts played seconds, and a long pause counts as 20 s, so a journey of many sessions plays with no dead
  time. At 1× the replay runs 40 played seconds for each real second, as on the website. Play at the end starts again
  from the start.
- **Replay:** the trail draws as the playhead passes it, with a glowing marker at the head. A pin pops in when the
  playhead passes its event and pulses for 6 played seconds. With no replay running, the whole journey shows.
- **Trail:** lines on the map shown, coloured by the way of travel (foot, mounted, taxi, swimming, dead or ghost).
- **Pins:** one pin for each journal line that has a position on the map, with an icon of its group. The tooltip shows
  the time, the kind name and the fields. The pins of a death and of a level up are larger.
- **Zoom:** pins and lines keep their screen size when the map zooms. On a continent or the world map the pins show
  at half size, as a whole journey packs into a small space there.
- **Continent and world maps:** the trail and the pins of the zones below the map, put on it through the world
  position. A zone with no position on the map is skipped, and the panel counts these zones.
- **Panel:** a check box for the trail and for each group of kinds, the list of sessions (the date and the length,
  with one choice for "All"), and the count of the lines and pins. The panel says when a cap (3000 lines, 500 pins)
  cuts the view.
- **Limits:** the tab only reads the saved data. It records nothing, and it changes no game map function.

Code: `addons/Memories/UI/Map/` (`MapData.lua` reads the data, `Replay.lua` is the timeline, `Overlay.lua` draws and
animates, `Panel.lua` and `Tab.lua` are the panel, the player bar and the tab). Errors go to `/mem errors`.

## Other addons

Other addons write events and screenshot notes into the journal with `Memories.RecordEvent` and
`Memories.RecordScreenshot`. See [`docs/public-api.md`](public-api.md). Memories sub-addons use
[`docs/sub-addon-api.md`](sub-addon-api.md).
