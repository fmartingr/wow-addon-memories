# Memories — map icon pack (75 event kinds)

Designed from the documented journal kind codes in `docs/kinds.md` checked November 12, 2026.

Each of the 75 event kinds has a distinct visual, with shared bronze/gold map medallion framing and category color accents. Transparent surroundings and a dark glyph backing help visibility on parchment maps.

## Contents
- `svg/<event_name>.svg`: scalable vector master for browser maps
- `png64/`, `png32/`, `png24/`, `png20/`, `png16/`: descriptive snake_case-named transparent PNGs for web maps and UI
- `tga64/`, `tga32/`: 32-bit RGBA TGA for WoW client textures
- `manifest.json`: event IDs, category, human label, palette and all file names
- `event_icons.lua`: example map lookup table for `SetTexture`
- `overview.png`: contact sheet of all events

## In-game usage
Copy `tga64/*.tga` to `addons/Memories/Media/MapIcons/`. To use per-event icons in `addons/Memories/UI/Map/Overlay.lua`, load the mapping (or merge the mapping table into Overlay.lua) and change:

`pin.icon:SetTexture(Overlay.GROUP_ICON[data.group] or DEFAULT_ICON)`

to:

`pin.icon:SetTexture(EVENT_ICONS[data.kind] or Overlay.GROUP_ICON[data.group] or DEFAULT_ICON)`

**IMPORTANT:** The existing code uses `pin.icon:SetTexCoord(0.08,0.92,0.08,0.92)` to crop Blizzard's icon borders. For this pack, use `pin.icon:SetTexCoord(0,1,0,1)` and hide the solid group-color rectangular backdrop (`pin.border:Hide()`), or the circular rim will be clipped.

The current default pin size in source is 12 px (`Overlay.PIN_SIZE = 12`). These distinct event icons are best at **20–24 px**, with `lv` and `de` remaining larger at 28–32 px. Rendering at 12 px severely reduces distinction between 75 icons.

If using the Lua file as a separate module, register it in the addon's `.toc` and expose `EVENT_ICONS` to the overlay. The provided Lua file returns a table and will not automatically alter the addon.

## Design choices
- Gold circular ring, dark face, light glyph silhouette, category colored accents.
- Related events are variants: enter/leave, flight start/land, learned/used, etc.
- First mount-up (`mo`) is the only mount-up event recorded for each mount.
- Session and generic addon events are included in case they have map coordinates.

## Icon source and credit
This pack embeds pictogram outlines from Font Awesome Free 6 (Free Solid SVG icons) by Fonticons, Inc., reused with attribution under **CC BY 4.0**. The icon compositions, colors, badges and ring layouts are new; credit is mandatory when distributing the pack. See `ATTRIBUTION.txt`.

Additional files: `gallery.html` is a searchable offline visual catalog; `sprite_sheet.png` and `sprite_sheet.json` provide a 9-column 64px atlas for mapping libraries.

## Descriptive filenames (updated pack)
Every icon now uses a readable snake_case event name instead of a two-letter code, for example:
- `svg/quest_accepted.svg` — event `qa` (updated to a gold exclamation mark)
- `png32/quest_turned_in.png` — event `qt`
- `tga64/entered_a_zone.tga` — event `zo`

`event_names.csv`, `manifest.json` and `event_icons.lua` translate from the original addon event kind codes to these filenames. The TGA mapping is ready for use after copying the texture assets into the addon and loading the Lua map.
