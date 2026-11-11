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
- **Replay:** the trail draws as the playhead passes it. A silver arrow at the head points along the route and turns
  with it. A pin pops in when the playhead passes its event and pulses for 6 played seconds. With no replay running,
  the whole journey shows.
- **Highlight animations:** when the playhead passes a level up, a death, a flight, a boat or zeppelin, a hearthstone,
  a portal, a summon, a dungeon or a boss, a ring grows and fades at its pin and a short label rises and fades (about
  1.2 s). At most 4 play at once, and none plays on a seek.
- **Follow:** with the Follow box on the player bar (on by default), the replay moves through the maps by itself. The
  clock then spans the whole journey. When the playhead enters a stretch of the trail on another map, the world map
  shows that map, the replay waits 0.6 s, and it goes on from the same moment. A continent or world map that shows the
  zone of the playhead stays as it is. A map change that you make during a replay turns following off until the next
  Play, seek or change of the box. With Follow off, the replay plays the map shown only.
- **Trail colour:** a button in the panel changes the colour of the trail: the way of travel (foot, mounted, taxi,
  swimming, dead or ghost), the level of the character, or the age (older steps are cooler and dimmer). A check box
  swaps the colours for a palette that is readable with colour blindness.
- **Trip arcs:** a trip that skips the trail (a hearthstone, a portal, a summon, a boat, or a flight with no points)
  draws as a curved arc from the last point before it to the first point after it, in the time of the trip.
- **Pins:** one pin for each journal line that has a position on the map, with an icon of its group. The tooltip shows
  the time, the kind name and the fields. The pins of a death and of a level up are larger.
- **Zoom:** pins and lines keep their screen size when the map zooms. On a continent or the world map the pins show
  at half size, as a whole journey packs into a small space there.
- **Continent and world maps:** the trail and the pins of the zones below the map, put on it through the world
  position. A zone with no position on the map is skipped, and the panel counts these zones.
- **Panel:** a check box for the trail and for each group of kinds, and a list that switches between chapters and
  sessions. A click on a chapter (the start, then one for each level) jumps the replay to it. The sessions show the
  date and the length, with one choice for "All". The panel also has the count of the lines and pins, which says when
  a cap (3000 lines, 500 pins) cuts the view, and the Highlights feed: the last six events that the replay passed,
  newest first.
- **Limits:** the tab only reads the saved data. It records nothing, and it changes no game map function.

Code: `addons/Memories/UI/Map/` (`MapData.lua` reads the data, `Replay.lua` is the timeline, `Overlay.lua` draws and
animates, `Panel.lua` and `Tab.lua` are the panel, the player bar and the tab). Errors go to `/mem errors`.

## Other addons

Other addons write events and screenshot notes into the journal with `Memories.RecordEvent` and
`Memories.RecordScreenshot`. See [`docs/public-api.md`](public-api.md). Memories sub-addons use
[`docs/sub-addon-api.md`](sub-addon-api.md).
