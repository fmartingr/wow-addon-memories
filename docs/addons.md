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

## The Journey window

The core addon replays the recorded journey in a **Journey** window of its own, with no upload and no app. A button
under the side tabs of the world map opens and closes it (the button is lit while the window is open). Escape closes
it, and the title bar moves it.

The window draws its own map from the game's map data: the tiles of the map and the areas that the character
explored. So it works the same with the default world map and with a world map addon such as OpenMap, and it never
draws on the world map. A left click on a zone opens that zone. A right click, or the **Up** button, goes up to the
map that holds it. The map opens on the map of the player, else on the first map of the trail, else on the nearest
map above the player with art (for example in a dungeon).

- **Player bar:** play and pause, a speed button (1×, 2×, 4×, 8×, 16×), a slider to seek, and the clock of the replay.
  The clock counts played seconds, and a long pause counts as 20 s, so a journey of many sessions plays with no dead
  time. At 1× the replay runs 40 played seconds for each real second, as on the website. Play at the end starts again
  from the start.
- **Replay:** the trail draws as the playhead passes it. A silver arrow at the head points along the route and turns
  with it. A pin pops in when the playhead passes its event and pulses in size for 1.5 s, with no frame around the coin. With no replay running,
  the whole journey shows.
- **Pins:** only level ups and deaths leave a pin. Each pin is the coin of its kind (a gold rim and a glyph, from
  `Media/MapIcons`), and a level up shows its level at the lower right of the coin. The tooltip shows the time, the
  kind name and the fields. The other events of the replay (flights, boats, hearthstones, portals, summons, dungeons
  and bosses) play their burst with their coin in it and go to the Highlights feed with their coin, with no pin. The
  arrow of the player draws over every pin and burst.
- **Highlight animations:** when the playhead passes a level up, a death, a flight, a boat or zeppelin, a hearthstone,
  a portal, a summon, a dungeon or a boss, a ring grows and fades at its pin and a short label rises and fades (about
  1.2 s). At most 4 play at once, and none plays on a seek.
- **Follow:** with the Follow box on the player bar (on by default), the replay moves through the maps by itself. The
  clock then spans the whole journey. When the playhead enters a stretch of the trail on another map, the window
  shows that map, the replay waits 0.6 s, and it goes on from the same moment. A continent or world map that shows the
  zone of the playhead stays as it is. A map change that you make during a replay turns following off until the next
  Play, seek or change of the box. With Follow off, the replay plays the map shown only.
- **Trail colour:** a button in the panel changes the colour of the trail: the way of travel (foot, mounted, taxi,
  swimming, dead or ghost), the level of the character, or the age (older steps are cooler and dimmer). A check box
  swaps the colours for a palette that is readable with colour blindness.
- **Trip arcs:** a trip that skips the trail (a hearthstone, a portal, a summon, a boat, or a flight with no points)
  draws as a curved arc from the last point before it to the first point after it, in the time of the trip.
- **Size:** on a continent or the world map the pins show at half size, as a whole journey packs into a small space
  there.
- **Continent and world maps:** the trail and the pins of the zones below the map, put on it through the world
  position. A zone with no position on the map is skipped, and the panel counts these zones.
- **Panel:** a check box for the trail and for Level ups, Deaths, Travel and Dungeons, and a list that switches between chapters and
  sessions. A click on a chapter (the start, then one for each level) jumps the replay to it. The sessions show the
  date and the length, with one choice for "All". The panel also has the count of the lines and pins, which says when
  a cap (3000 lines, 500 pins) cuts the view, and the Highlights feed: the last six events that the replay passed,
  newest first.
- **Limits:** the window only reads the saved data. It records nothing, and it changes no game map function.

Code: `addons/Memories/UI/Map/` (`MapData.lua` reads the data, `Replay.lua` is the timeline, `Overlay.lua` draws and
animates, `Panel.lua` is the panel and the player bar, `Window.lua` is the window and its map, `Tab.lua` is the button
on the world map). Errors go to `/mem errors`.

## Other addons

Other addons write events and screenshot notes into the journal with `Memories.RecordEvent` and
`Memories.RecordScreenshot`. See [`docs/public-api.md`](public-api.md). Memories sub-addons use
[`docs/sub-addon-api.md`](sub-addon-api.md).
