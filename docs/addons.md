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


## Other addons

Other addons write events and screenshot notes into the journal with `Memories.RecordEvent` and
`Memories.RecordScreenshot`. See [`docs/public-api.md`](public-api.md). Memories sub-addons use
[`docs/sub-addon-api.md`](sub-addon-api.md).
