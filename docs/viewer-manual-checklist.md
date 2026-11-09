# Viewer manual checklist

Run each row on a desktop browser (Firefox) and on a phone. When no phone is at hand, use the responsive mode of the
browser at 360 × 740 and write "360 px" in the cell. Use a real character on `make local-up` (`make upload SITE=http://localhost:8080 LATEST=<folder>`).

| # | Task | Check | Desktop | Phone |
|---|---|---|---|---|
| 1 | 2 | The tabs Summary, Journey map and Heatmaps switch when you click them. | not run | not run |
| 2 | 2 | Back and Forward switch between the tabs that you opened. | not run | not run |
| 3 | 2 | A link with `#summary` opens Summary. An unknown hash opens Summary. | not run | not run |
| 4 | 2 | Summary reads well at 360 px and 1440 px, and has no horizontal scroll at 360 px. | not run | not run |
| 5 | 2 | The keyboard focus is visible on each tab and button. Left and Right move between the tabs. | not run | not run |
| 6 | 2 | The fonts load. The network panel shows no request to a third-party host. | not run | not run |
| 7 | 2 | On a phone width, the tabs are a bottom bar, and every control is at least 44 × 44 px. | not run | not run |
| 8 | 3 | Item names and icons show on a character with gear, and a tooltip opens on hover. | not run | not run |
| 9 | 3 | With the widget blocked (block `wow.zamimg.com` in the browser), the slots show `Item <id>` in the quality colour. | not run | not run |
| 10 | 3 | A slot tap on a phone opens the slot detail and does not leave the page. "Open on Wowhead" opens a new tab. | not run | not run |
| 11 | 3 | `#summary?slot=5` opens with slot 5 selected. A tap on a slot puts `slot=<n>` in the hash. | not run | not run |
| 12 | 3 | The console shows no CSP error. The network panel shows requests to `wow.zamimg.com` and `nether.wowhead.com` only after Summary shows gear. | not run | not run |
| 13 | 4 | The map art loads and sharpens when you zoom in. | not run | not run |
| 14 | 4 | Drag, wheel (desktop) and pinch (phone) move and zoom the map. The zoom buttons and World work. | not run | not run |
| 15 | 4 | A phone rotation keeps the centre of the map. | not run | not run |
| 16 | 4 | A link `#journey?x=..&y=..&z=..` opens at that camera. The URL follows the camera, and Back does not step through each move. | not run | not run |
| 17 | 4 | With `web/map/` renamed, the grid and the notice "Map art is not installed on this server." show, and the trail is still in the right place. | not run | not run |
| 18 | 4 | The Blizzard legal notice shows under the map. | not run | not run |
