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

The core addon adds a **Journey** tab to the side tabs of the world map, under the last game tab. The tab shows the
recorded trail and the journal pins of the map on the map, with no upload and no app. A click on the tab opens the
Journey panel in the place of the quest log. A click on a game tab hides the Journey view.

- **Trail:** lines on the map shown, coloured by the way of travel (foot, mounted, taxi, swimming, dead or ghost).
- **Pins:** one pin for each journal line that has a position on the map, with an icon of its group. The tooltip shows
  the time, the kind name and the fields. The pins of a death and of a level up are larger.
- **Continent and world maps:** the trail and the pins of the zones below the map, put on it through the world
  position. A zone with no position on the map is skipped, and the panel counts these zones.
- **Panel:** a check box for the trail and for each group of kinds, the list of sessions (the date and the length,
  with one choice for "All"), and the count of the lines and pins shown. The panel says when a cap (3000 lines, 500
  pins) cuts the view.
- **Limits:** the tab only reads the saved data. It records nothing, and it changes no game map function.

Code: `addons/Memories/UI/Map/` (`MapData.lua` reads the data, `Overlay.lua` draws, `Panel.lua` and `Tab.lua` are the
panel and the tab). Errors go to `/mem errors`.

## Other addons

Other addons write events and screenshot notes into the journal with `Memories.RecordEvent` and
`Memories.RecordScreenshot`. See [`docs/public-api.md`](public-api.md). Memories sub-addons use
[`docs/sub-addon-api.md`](sub-addon-api.md).
