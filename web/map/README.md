# Map art

Map art © Blizzard Entertainment, Inc. All rights reserved. World of Warcraft and Azeroth are trademarks of Blizzard
Entertainment, Inc.

These files are not covered by the GPL-3.0 license of this project. They are used without a license from Blizzard, as
the OpenMap addon does. They will be removed on request of the owner.

## Source

- The textures of the OpenMap addon: `Media/Textures/MapZones`, `Media/Textures/MapMiniLand` and `Data/Minimap.lua`.
- The game art from wago.tools, Classic Era build `1.15.9.70576`.
- `muddyboots-web/tools/build_map.py` and `build_layers.py` build the files from these sources.

## Layout

- `art/`: the zone art.
- `mini/`: the mini map art.
- `tiles/`: the map tiles, one folder for each zoom level.
- `world.js`: the map data. The viewer reads it as `globalThis.WORLD`.
