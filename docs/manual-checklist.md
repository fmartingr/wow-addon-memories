# Manual checklist in the game

There is no e2e suite for WoW, so these checks run by hand on the Forever client (esES). Record the date, the client
build and pass or fail for each item.

| Task | Check | Steps | Expected | Result |
|---|---|---|---|---|
| 1 | The core loads | `make install WOW_DIR=".../_forever_"`, start the game, open the AddOn list, log in. | "Memories" is in the list and loads with no Lua error. | not run |
| 1 | Command list | Type `/mem`, then `/memories`. | Each prints "Memories: commands:" and the `errors`, `options`, `settings` and `status` lines. | not run |
| 1 | Errors box, none | On a clean install, type `/mem errors`. | It prints "Memories: no saved errors." | not run |
| 1 | Errors box | Close the game. In `WTF/Account/<account>/SavedVariables/Memories.lua`, set `["errors"] = { { ["t"] = 1793560500, ["where"] = "manual", ["msg"] = "test error", ["stack"] = "line 1" } }` inside `MemoriesDB`. Start the game and type `/mem errors`. | A box opens with "manual: test error" and "line 1", all text selected; Ctrl+C copies it; Escape closes it. | not run |
| 1 | Errors survive a reload | With at least one saved error, `/reload`, then `/mem errors`. | The same errors are listed. | not run |
| 3 | Public global | Log in with Memories on. Type `/dump Memories.API_VERSION, Memories.VERSION`. | It prints `1` and the TOC version. | not run |
| 3 | Addon states | Log in with only the core installed. Type `/dump Memories.Addons()`. | The core is `on`; each of the 5 sub-addons is `missing`. | not run |
| 3 | Group in the AddOn list | Install a sub-addon (from Task 11 on) next to the core and open the AddOn list. | The sub-addon shows under the "Memories" group. | not run |
| 3 | Sub-addon without the core | Disable `Memories`, keep a sub-addon enabled, log in. | The sub-addon does not load (shown as a missing dependency), with no Lua error. | not run |
| 4 | Compartment | Right click the Memories entry in the addon compartment, then left click it. | The right click opens the Memories Settings page. The left click reloads the UI. | not run |
| 4 | Compartment in combat | Start a fight, left click the Memories entry in the addon compartment. | It prints "Memories: cannot save in combat." and does not reload. | not run |
| 4 | Minimap button | Log in. Hover over the book button on the minimap edge. | The tooltip shows "Memories", the minutes since the last save, "Left click: save (reload)" and "Right click: settings". | not run |
| 4 | Minimap save | Left click the minimap button out of combat, then again in combat. | Out of combat the UI reloads. In combat it prints "Memories: cannot save in combat." | not run |
| 4 | Minimap settings | Right click the minimap button. | The Memories Settings page opens. | not run |
| 4 | Minimap drag | Drag the minimap button around the minimap, then `/reload`. | It follows the minimap edge and stays at the new place after the reload. | not run |
| 4 | Save reminder | Play 60 minutes without a reload or logout. | One chat line "Memories: 1 hour since the last save. Click the minimap button to save (reloads the UI)." and the minimap button pulses. No second line later. | not run |
| 4 | Backup written | From Task 6 on (the core writes lines), log in, play a minute, `/reload`. Type `/dump MemoriesDB.backups`. | The character's GUID has a `Memories` entry with `t`, `level`, `lines` and a `blob`. | not run |
| 4 | Data guard, restore | With a backup in place, close the game. In `WTF/Account/<account>/<realm>/<character>/SavedVariables/Memories.lua`, delete the `MemoriesCharDB` table. Start the game and log in. | A popup "Memories: Memories came back empty. A backup from <date> has <n> lines." with "Restore" and "Start fresh". "Restore" asks to reload; after the reload the old lines are back and the journal ends with `nt|restored backup|<n>`. | not run |
| 4 | Data guard, start fresh | Repeat the step above and click "Start fresh". | The journal starts with `nt|started fresh|<n>`. The next backup run (at most 15 minutes later) replaces the old one. | not run |
| 4 | Data guard, no answer | Repeat the step above, but log out without an answer (the popup stays open). Log in again. | The popup shows again and `MemoriesDB.backups` still has the old backup. | not run |
| 5 | Settings page | Type `/mem options`, then `/mem settings`. | Each opens Options > AddOns > Memories with no Lua error. | not run |
| 5 | General section | Open the Settings page. | "General" shows "Recording rate" (1, 2, 5, 10 s; 2 s chosen), "Screenshot at level-up" and "Screenshot at a dungeon's last boss" (both off), "Save reminder", "Minimap button" and "Low-health flash" (all on). | not run |
| 5 | Kind sections | Open the Settings page with every sub-addon installed. | One header `<Addon> — <Group>` per group, in catalog order, each with "Enable all", "Disable all" and one checkbox per kind, all checked. No checkbox for `nt`. | not run |
| 5 | New findings only | Open the Settings page with every sub-addon installed. | "Gathering", "Kills", "Loot" and "Consumables: new findings only" show under the Gathering, Combat, Loot and Character groups, all off. | not run |
| 5 | Kind off | Uncheck "Entered a subzone", walk into a new subzone (from Task 9 on), `/reload`, read `MemoriesCharDB`. | No new `sz` line; `MemoriesDB.settings.kinds.sz` is `false`. | not run |
| 5 | Group buttons | Click "Disable all" under "Memories — Travel", then "Enable all". | Every Travel checkbox clears at once, then checks again. | not run |
| 5 | Minimap setting | Uncheck "Minimap button", then check it. | The minimap button hides and shows at once. | not run |
| 5 | Settings survive | Change a few settings, `/reload`, open the page. | The same choices are shown. | not run |
| 5 | Status | Type `/mem status` with only the core installed. | "Memories: status:", then `Memories: on, <n> lines, 0 kinds off, ...` and one `missing` line for each of the 5 sub-addons, then `login time: init <n> ms, login <n> ms, world <n> ms`. | not run |
| 5 | Status of a disabled sub-addon | Disable a sub-addon for this character (from Task 11 on), log in, `/mem status`. | Its line says `off`. | not run |
| 6 | `COMBATLOG_XPGAIN_FIRSTPERSON` | Type `/dump COMBATLOG_XPGAIN_FIRSTPERSON`. | A text with one `%s` (the creature) and one `%d` (the XP), for example "%s muere, ganas %d p. de experiencia.". | not run |
| 6 | `COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED` | Type `/dump COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED`. | A text with one `%d` (the XP). | not run |
| 6 | `ERR_ZONE_EXPLORED_XP` | Type `/dump ERR_ZONE_EXPLORED_XP`. | A text with one `%s` (the area) and one `%d` (the XP). | not run |
| 6 | `ERR_ZONE_EXPLORED` | Type `/dump ERR_ZONE_EXPLORED`. | A text with one `%s` (the area). | not run |
| 6 | `COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP` | Type `/dump COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP`. | A text with two `%d`; the group bonus words come after the second one, for example "(+%d group bonus)". | not run |
| 6 | Group bonus | Kill a creature in a group while rested and read the XP chat line. | The `xp` line ends with the group bonus `N`, never the rested bonus. | not run |
| 6 | Session lines | Log in, wait 5 s, `/reload`, wait 5 s, `/reload`. Read `MemoriesCharDB` in the saved file. | The journal starts with `in|login`, `pc|<id>`, `rs|<n>`, then `pl|<played>`; each reload adds `out`, `in|reload`, `rs`, `pl`. `MemoriesCharDB.sessions` has 3 entries with `start`, `last`, `how`, `computer`, `tz`, `played0`, `played1`. No "Total time played" text shows in the chat at login. | not run |
| 6 | Away | Type `/afk`, then move. | One `af|1` line, then one `af|0` line. | not run |
| 6 | Trail | Walk, mount and ride for a minute, take a flight, then `/reload`. | `MemoriesCharDB.trail.chunks` has chunks with `s`, `t`, `m`, `n` and `d` text such as `0,4512,6120,-;...`, with `m` and `t` flags while mounted and on the flight. | not run |
| 6 | Jumps | Jump 3 times on land and once while swimming, `/reload`. | `MemoriesCharDB.counts.travel` has `jumps` 3 more and `ascend` 1 more. | not run |
| 6 | Recording rate | Set "Recording rate" to 10 s, walk for a minute, `/reload`. | The new chunk's points are about 10 s apart. | not run |
| 6 | Level up | Gain a level. | Lines `lv|<level>`, then `pl|<played>`; `MemoriesCharDB.snap[<level>]` has `t`, `zone`, `rested` and `played`. | not run |
| 6 | Quest and XP | Turn in a quest that gives XP. | One `xp|<n>|quest|<title>` and one `qt|<id>|<xp>|<money>|<title>` line, in Spanish on the esES client. | not run |
| 6 | Discovery | Enter an area not explored yet. | `di|<area>|<xp>` and `xp|<xp>|discover|<area>`; with no XP, one `di|<area>` line. | not run |
| 7 | GlobalStrings | Deaths and the low-health popup read no `GlobalStrings` name: the killer, spell and environment come from `C_DeathRecap`. | Nothing to `/dump`. | not run |
| 7 | Recap fields | Die to a creature, then type `/dump C_DeathRecap.GetRecapEvents()` while dead. | Each entry has `timestamp`, `sourceGUID`, `sourceName`, `amount` and, for a spell, `spellName`; a fall has `environmentalType`. | not run |
| 7 | Death to a creature | Target a creature, let it kill you, wait 2 s. | One `de|<name>|<npc id>|<spell>||world||<level>|<classification>|<amount>` line at the death spot; `counts.deaths` has `total` and `world` 1 more and `hardest` at least the amount. | not run |
| 7 | Release and spirit healer | Release, accept the spirit healer's resurrection. | `gh`, then `al|spirit`; `counts.deaths["revive.spirit"]` 1 more. | not run |
| 7 | Corpse run | Release, run back to the body and click "Resurrect". | `gh`, then `al|corpse`. | not run |
| 7 | Resurrection by a player | Die in a group, accept a resurrection from a priest or a paladin. | `al|res|<their name>`. | not run |
| 7 | Death across a reload | Die, wait 2 s, `/reload` while dead, then release and `/reload` again. | One `de` and one `gh` only. | not run |
| 7 | Death at login | Die, type `/run MemoriesCharDB.state.deaths.open = false`, `/reload`. | One new bare `de` line at the last trail point (no killer when the recap is gone). | not run |
| 7 | Dungeon death | Die inside a dungeon. | The `de` line has no position and the dungeon name as `place`; `counts.deaths.dungeon` 1 more. | not run |
| 7 | Fall | Jump from a high place and die. | `de||||falling|world|...`; `counts.deaths["env.falling"]` 1 more. | not run |
| 7 | Hardcore death | On a Hardcore character, die. | `de`, then `hc|<killer>`. | not run |
| 7 | Low health and close call | Out of combat, lose health below 35 % (for example a fall), then heal up and wait 3 s. | `lh|0`, then `cc|<seconds>|0`; `counts.deaths` has `lowHealth` and `closeCalls` 1 more. | not run |
| 7 | Close call in combat | Drop below 35 % in a fight, survive, end the fight, wait 3 s. | `lh|1` at once; `cc|<seconds>|1` only 3 s after the fight ends. | not run |
| 7 | No close call on death | Drop below 35 % and die. | `lh`, `de`, no `cc`. | not run |
| 7 | Popup at login | Type `/console doNotFlashLowHealthWarning 1`, `/reload`. | A popup "Memories needs this setting on" with "Keep it on" and "Turn it off"; the "Low-health flash" option is unchecked. | not run |
| 7 | Keep it on | Click "Keep it on". | `/dump C_CVar.GetCVar("doNotFlashLowHealthWarning")` prints `"0"`; the option is checked; no second popup. | not run |
| 7 | Turn it off | Repeat the popup and click "Turn it off". | The CVar is `"1"`, the option is unchecked, no second popup until the next login. | not run |
| 7 | Popup in combat | Turn the flash off, start a fight, `/reload` in combat. | The popup shows only after the fight ends. | not run |
| 7 | Option untick | Uncheck "Low-health flash" on the Settings page. | The popup shows; the option and the CVar stay on until a button is clicked. | not run |
| 7 | Game turns it off | With the flash on, untick the game's own low-health flash option (Interface options). | The Memories popup shows. Turning it on again in the game shows no popup and checks the Memories option. | not run |
| 8 | Public event | Type `/run print(Memories.RecordEvent("Test", "hello", "world"))`. | It prints `true`. After a `/reload`, the journal in `MemoriesCharDB` ends with an `ex|Test|hello|world` line. | not run |
| 8 | Public refusal | Type `/run print(Memories.RecordEvent("Test"))`. | It prints `false bad what`. | not run |
| 8 | Rate limit | Type `/run for i = 1, 31 do print(i, Memories.RecordEvent("Spam", "x")) end`. | Lines 1 to 30 print `true`, line 31 prints `false rate limit`. A loop that crosses a minute of `GetTime()` starts the count again: wait a minute and run it once more. | not run |
| 8 | By-hand screenshot | Note the line count in `/mem status`, press PrintScreen, then `/mem status` again. | The count is at least 1 more (other recorders can write lines meanwhile). After a `/reload`, the journal ends with `ss|by hand|ok|WoWScrnShot_<MMDDYY_HHMMSS>.<ext>`, and that file (or the one a second earlier) is in `Screenshots/`. `counts.screenshots.shots` is 1 more. | not run |
| 8 | Screenshot format | Type `/dump C_CVar.GetCVar("screenshotFormat")`, press PrintScreen, `/reload`. | The `ss` file name ends with the matching extension (`jpeg` → `.jpg`, `png` → `.png`, `tga` → `.tga`). | not run |
| 8 | Level-up shot off | With "Screenshot at level-up" off (the default), gain a level. | No screenshot and no new `ss` line. | not run |
| 8 | Level-up shot on | Turn "Screenshot at level-up" on and gain a level. | About 1.5 s later a screenshot is saved and the journal has `ss|level <N>|ok|<file>`. | not run |
