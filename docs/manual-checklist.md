# Manual checklist in the game

There is no e2e suite for WoW, so these checks run by hand on the Forever client (esES). Record the date, the client
build and pass or fail for each item.

| Task | Check | Steps | Expected | Result |
|---|---|---|---|---|
| 1 | The core loads | `make install WOW_DIR=".../_forever_"`, start the game, open the AddOn list, log in. | "Memories" is in the list and loads with no Lua error. | not run |
| 1 | Command list | Type `/mem`, then `/memories`. | Each prints "Memories: commands:" and the `errors` line. | not run |
| 1 | Errors box, none | On a clean install, type `/mem errors`. | It prints "Memories: no saved errors." | not run |
| 1 | Errors box | Close the game. In `WTF/Account/<account>/SavedVariables/Memories.lua`, set `["errors"] = { { ["t"] = 1793560500, ["where"] = "manual", ["msg"] = "test error", ["stack"] = "line 1" } }` inside `MemoriesDB`. Start the game and type `/mem errors`. | A box opens with "manual: test error" and "line 1", all text selected; Ctrl+C copies it; Escape closes it. | not run |
| 1 | Errors survive a reload | With at least one saved error, `/reload`, then `/mem errors`. | The same errors are listed. | not run |
| 3 | Public global | Log in with Memories on. Type `/dump Memories.API_VERSION, Memories.VERSION`. | It prints `1` and the TOC version. | not run |
| 3 | Addon states | Log in with only the core installed. Type `/dump Memories.Addons()`. | The core is `on`; each of the 5 sub-addons is `missing`. | not run |
| 3 | Group in the AddOn list | Install a sub-addon (from Task 11 on) next to the core and open the AddOn list. | The sub-addon shows under the "Memories" group. | not run |
| 3 | Sub-addon without the core | Disable `Memories`, keep a sub-addon enabled, log in. | The sub-addon does not load (shown as a missing dependency), with no Lua error. | not run |
| 4 | Compartment | Right click the Memories entry in the addon compartment, then left click it. | The right click prints the command list. The left click reloads the UI. | not run |
| 4 | Compartment in combat | Start a fight, left click the Memories entry in the addon compartment. | It prints "Memories: cannot save in combat." and does not reload. | not run |
| 4 | Minimap button | Log in. Hover over the book button on the minimap edge. | The tooltip shows "Memories", the minutes since the last save, "Left click: save (reload)" and "Right click: settings". | not run |
| 4 | Minimap save | Left click the minimap button out of combat, then again in combat. | Out of combat the UI reloads. In combat it prints "Memories: cannot save in combat." | not run |
| 4 | Minimap settings | Right click the minimap button. | It prints the command list (the Settings page from Task 5 on). | not run |
| 4 | Minimap drag | Drag the minimap button around the minimap, then `/reload`. | It follows the minimap edge and stays at the new place after the reload. | not run |
| 4 | Save reminder | Play 60 minutes without a reload or logout. | One chat line "Memories: 1 hour since the last save. Click the minimap button to save (reloads the UI)." and the minimap button pulses. No second line later. | not run |
| 4 | Backup written | From Task 6 on (the core writes lines), log in, play a minute, `/reload`. Type `/dump MemoriesDB.backups`. | The character's GUID has a `Memories` entry with `t`, `level`, `lines` and a `blob`. | not run |
| 4 | Data guard, restore | With a backup in place, close the game. In `WTF/Account/<account>/<realm>/<character>/SavedVariables/Memories.lua`, delete the `MemoriesCharDB` table. Start the game and log in. | A popup "Memories: Memories came back empty. A backup from <date> has <n> lines." with "Restore" and "Start fresh". "Restore" asks to reload; after the reload the old lines are back and the journal ends with `nt|restored backup|<n>`. | not run |
| 4 | Data guard, start fresh | Repeat the step above and click "Start fresh". | The journal starts with `nt|started fresh|<n>`. The next backup run (at most 15 minutes later) replaces the old one. | not run |
| 4 | Data guard, no answer | Repeat the step above, but log out without an answer (the popup stays open). Log in again. | The popup shows again and `MemoriesDB.backups` still has the old backup. | not run |
