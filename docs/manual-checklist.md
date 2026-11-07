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
| 9 | `ERR_SKILL_GAINED_S` | Type `/dump ERR_SKILL_GAINED_S`. | A text with one `%s` (the skill), for example "Has aprendido la habilidad %s.". | not run |
| 9 | Riding names | Type `/dump C_SkillInfo.GetSkillLineInfoByID(762)`, then `/dump C_Spell.GetSpellName(824)` (and 825, 826, 828, 10861, 10906, 10908, 18995). | The skill line 762 has `name` "Equitación" (Riding); each spell is a racial riding skill, for example "Equitación de caballos". Any other name means the id list in `Record/Travel.lua` is wrong. | not run |
| 9 | Tram map id | In the Deeprun Tram, type `/dump select(4, UnitPosition("player"))`. | It prints `369`. | not run |
| 9 | Zone | Walk from one zone into another, then into a new subzone. | One `zo|<zone>` line, then one `sz|<subzone>` line, in Spanish. A `/reload` adds no second `zo`. | not run |
| 9 | Inn at login | Log out inside an inn, log in, walk out. | `zo|<inn>` only when the zone text names the inn, then `zo|<zone>` once the map confirms it; no other zone line. | not run |
| 9 | Flight | Talk to a flight master, fly to another node, land. | `tx|<from node>|<to node>|<copper>` at take-off; `tl|<to node>` at landing; `counts.travel.flights` 1 more. | not run |
| 9 | Flight across a reload | Take a flight and `/reload` in the air, then land. | No new `tx`; `tl` with an empty node at landing. | not run |
| 9 | Hearthstone | Use the Hearthstone in another zone. | `ld|8690`, `le`, then `hs|<from map>|<to map>|<bind location>|<yards>`; `counts.travel.hearths` 1 more and `counts.distance.hearth` grows by the yards. | not run |
| 9 | Boat or zeppelin | Take a boat or a zeppelin to another continent. | `ld`, `le`, then `bt|<from map>|<to map>|<from place>|<to place>` within 30 s; `counts.travel.boats` 1 more. | not run |
| 9 | Portal or teleport | On a mage, cast Teleport: Stormwind (3561). | `ld|3561`, `le`, `po|<zone after>|<from map>|<to map>|3561|<yards or empty>`. | not run |
| 9 | Summon | Accept a warlock summon. | `so|<warlock>|<area>` at the offer, `su|<warlock>|<area>|<from map>|<to map>|<yards>` after the arrival. A declined summon writes only `so`. | not run |
| 9 | Spirit release | Die outdoors and release. | `jp|<from map>|<to map>|<yards>|death`, or no travel line when a loading screen came right after a revive. | not run |
| 9 | Deeprun Tram | Ride the Deeprun Tram from Stormwind to Ironforge. | `ld`, `le`, then `jp|...|tram` on each loading screen into or out of the tram. | not run |
| 9 | Mount | Mount the same mount twice, with a dismount in between. | One `mo|1|<spell>|<name>`; `counts.travel.mountUps` 2 more and `counts.travel["mount:<spell>"]` 2 more. | not run |
| 9 | Learned mount or riding | Learn riding at a trainer, or learn a new mount. | One `ml|<name>|<spell>` (riding: `ml|<skill name>` or with the racial riding spell). | not run |
| 9 | Distance unit | Type `/dump GetCurrentRegion(), GetLocale()`. | Region 1 counts in yards, 2 to 5 in meters; any other region falls back to the client language. | not run |
| 9 | Dungeon visit | Enter the Deadmines (or any dungeon), die once inside, leave. | `dn|<name>|<instance id>|party|<difficulty>|<size>` at the entrance, then `dx|<name>|<instance id>|<seconds>|1`; `counts.dungeons.visits` 1 more. | not run |
| 9 | Reload inside | `/reload` inside a dungeon. | No new `dn` or `dx`. | not run |
| 9 | Logout inside | Log out inside a dungeon, wait, log in outside after the instance reset. | `dx` with the time of the logout. | not run |
| 9 | Boss fight | Kill a dungeon boss, then wipe on another. | `bo|<boss>|<encounter id>|1||<dungeon>|<seconds>` for the kill (`1` in the 4th field for the last boss), `bo|<boss>|<id>|0||<dungeon>|<seconds>` for the wipe. | not run |
| 9 | Last-boss shot off | With "Screenshot at a dungeon's last boss" off (the default), kill the last boss of a dungeon. | No screenshot and no `ss` line. The list of last bosses holds English names, so on the esES client a boss with a translated name is not a last boss (`last` stays empty). | not run |
| 9 | Last-boss shot on | Turn the setting on and kill Edwin VanCleef (the name is the same in Spanish). | About 1 s later a screenshot and `ss|last boss Edwin VanCleef|ok|<file>`. | not run |
| 9 | World boss | Kill a world boss (for example Azuregos) or be there when it dies, with it targeted. | One `wb|<name>|<npc id>`; a second kill within 10 minutes writes nothing. | not run |
| 9 | Click on the current node | Open the flight map and click the node where you stand. | No `tx` line and no flight count. | not run |
| 9 | Ghost run in a dungeon | Die inside a dungeon, release, run back as a ghost and enter again. | No `dx` and no second `dn`; the visit goes on. | not run |
| 10 | Converter | Play a few minutes, take a screenshot by hand, run `/run Memories.RecordEvent("Test", "converter", "ok")`, log out. Run `make export WOW_DIR=".../_forever_"`, then run it again. | `dist-characters/<id>/` holds `journey.jsonl` with an `ss` record whose `screenshot` names a file in `screenshots/`, and an `ex` record with `source` "Test". The second run changes no output file. The saved files and screenshots in the game folder keep their modification times; `backups/<stamp>/` holds a copy of each saved file. | not run |
| 11 | Gathering loads | Install the set, enable "Memories - Gathering", log in, `/mem status`. | `Memories_Gathering` is `on`; the Settings page has "Memories_Gathering — Gathering" with `ga`, `fs`, `op`, `pp` and the "Gathering: new findings only" box. | not run |
| 11 | `ERR_FISH_ESCAPED` | Type `/dump ERR_FISH_ESCAPED`. | The Spanish text that the game shows when a hooked fish gets away. | not run |
| 11 | `ERR_FISH_NOT_HOOKED` | Type `/dump ERR_FISH_NOT_HOOKED`. | The Spanish text that the game shows when the bobber is clicked with no fish. | not run |
| 11 | Gather spell names | Type `/dump C_Spell.GetSpellName(2575), C_Spell.GetSpellName(2366), C_Spell.GetSpellName(8613), C_Spell.GetSpellName(921), C_Spell.GetSpellName(3365), C_Spell.GetSpellName(7620)`. | "Minería", the herb gathering name, "Desollar", the pick pocket name, the opening name and "Pesca". The cast bar shows the same names when you gather. | not run |
| 11 | Loot functions | Open any loot window and type `/dump IsFishingLoot(), GetLootSourceInfo(1), GetLootSlotLink(1)`. | A boolean, a GUID (`GameObject-...` or `Creature-...`) and an item link. | not run |
| 11 | Mine a vein | Mine a copper vein, loot it, `/reload`. | `MemoriesGatheringCharDB` has `ga|Mining|<vein name>|<object id>|2770|1|<count or empty>|Mena de cobre|<first or empty>`; `counts.gather` has `Mining`, `item:Mining|2770` and `cast:mined|<vein name>|Mining`. | not run |
| 11 | New findings only | Turn on "Gathering: new findings only", mine the same ore again, `/reload`. | No new `ga` line; `counts.gather["item:Mining|2770"]` grows. | not run |
| 11 | Fish | Fish until one catch, then let one fish get away and click once with no fish. | One `fs|<item>|<quality>|<count or empty>|<name>|<pool id or empty>|<why>` per caught item; `counts.gather` has `Fishing`, `fish:escaped` and `fish:missed` 1 more each. | not run |
| 11 | Pick pocket | On a rogue, pick the pocket of a humanoid that gives an item, then one that gives only money. | One `pp|<name>|<npc id>|<item>|<quality>|<item name>` for the first; `counts.gather.pickpockets` 2 more. | not run |
| 11 | Open a container and a chest | Open a Heavy Junkbox (or any lockbox), then a chest in the world. | `op|item|<item id>|<item name>`, then `op|chest||<chest name>|<object id>`; a quest crate with only its quest item writes nothing. | not run |
| 12 | Combat loads | Install the set, enable "Memories - Combat", log in, `/mem status`. | `Memories_Combat` is `on`; the Settings page has "Memories_Combat — Combat" with `ki`, `ra`, `fi` and the "Kills: new findings only" box. | not run |
| 12 | `COMBATLOG_XPGAIN_FIRSTPERSON` | Type `/dump COMBATLOG_XPGAIN_FIRSTPERSON`, then kill a creature while rested and in a group. | A text with one `%s` (the creature) and one `%d` (the XP); the rested and group XP lines start with the same text. | not run |
| 12 | Unit functions | Target a hostile creature in a fight and type `/dump UnitThreatSituation("player", "target"), UnitIsTapDenied("target"), UnitCreatureType("target"), UnitPlayerControlled("target")`. | A threat number (0 to 3), `false`, the localized type name and its id (for example "Humanoide", 7), `false`. | not run |
| 12 | Critter type id | Target a rabbit or another critter and type `/dump UnitCreatureType("target")`. | "Alimaña" and `8`. | not run |
| 12 | Kill in the open world | With name plates on, kill a creature that gives XP, then one grey creature, `/reload`. | `MemoriesCombatCharDB` has `ki|<name>|<npc id>|<type>|<classification>|<xp>|<level>||<1 or empty>` and a `ki` with an empty XP for the grey one; `counts.kills` has `total`, `xp`, `noxp`, `npc:<id>` and `n:<name>`. | not run |
| 12 | Tapped by another | Let another player tag a creature, help to kill it. | No `ki` line. | not run |
| 12 | Kill in a dungeon | Kill a creature in a dungeon (for example the Deadmines), `/reload`. | `ki|<name>||||<xp>||party|<1 or empty>`; `counts.kills` has `total` and `inst` 1 more. | not run |
| 12 | Rare | Kill a rare creature. | `ki` with `rare` or `rareelite` and one `ra|<name>|<npc id>|<level>`. | not run |
| 12 | New findings only | Turn on "Kills: new findings only" and kill the same normal creature twice. | No new `ki` line; `counts.kills["npc:<id>"]` grows. | not run |
| 12 | Long fight | Fight one creature for more than 20 s. | `fi|<seconds>|<target>|<classification>|<level>||<casts>`; `counts.fights` has `n`, `sec` and `longest`. | not run |
| 12 | Reload in combat | `/reload` during a fight longer than 20 s. | No `fi` for that fight. | not run |
| 13 | Economy loads | Install the set, enable "Memories - Economy", log in, `/mem status`. | `Memories_Economy` is `on`; the Settings page has "Memories_Economy — Loot" with `lo`, `rl`, `ge`, `eq` and the "Loot: new findings only" box, and "Memories_Economy — Money" with `mn`, `tb`, `ah`, `ma`, `tr`. | not run |
| 13 | `LOOT_ITEM_SELF` | Type `/dump LOOT_ITEM_SELF`. | A text with one `%s` (the item link), for example "Recibes botín: %s.". | not run |
| 13 | `LOOT_ITEM_SELF_MULTIPLE` | Type `/dump LOOT_ITEM_SELF_MULTIPLE`. | A text with one `%s` (the item link) and one `%d` (the count) after it. | not run |
| 13 | `LOOT_ITEM_PUSHED_SELF` | Type `/dump LOOT_ITEM_PUSHED_SELF`. | A text with one `%s` (the item link). | not run |
| 13 | `LOOT_ITEM_PUSHED_SELF_MULTIPLE` | Type `/dump LOOT_ITEM_PUSHED_SELF_MULTIPLE`. | A text with one `%s` (the item link) and one `%d` (the count). | not run |
| 13 | `LOOT_ITEM_CREATED_SELF` | Type `/dump LOOT_ITEM_CREATED_SELF`. | A text with one `%s` (the item link). | not run |
| 13 | `LOOT_ITEM_CREATED_SELF_MULTIPLE` | Type `/dump LOOT_ITEM_CREATED_SELF_MULTIPLE`. | A text with one `%s` (the item link) and one `%d` (the count). | not run |
| 13 | `LOOT_ROLL_NEED_SELF` | Type `/dump LOOT_ROLL_NEED_SELF`. | A text with an optional `|HlootHistory:%d|h[...]|h:` link in front, then one `%s` (the item link). | not run |
| 13 | `LOOT_ROLL_GREED_SELF` | Type `/dump LOOT_ROLL_GREED_SELF`. | A text with an optional loot history link in front, then one `%s` (the item link). | not run |
| 13 | `LOOT_ROLL_ROLLED_NEED` | Type `/dump LOOT_ROLL_ROLLED_NEED`. | A text with an optional loot history link in front, then the roll `%d`, the item `%s` and the player `%s`, in that argument order. | not run |
| 13 | `LOOT_ROLL_ROLLED_GREED` | Type `/dump LOOT_ROLL_ROLLED_GREED`. | A text with the same arguments as `LOOT_ROLL_ROLLED_NEED`. | not run |
| 13 | `LOOT_ROLL_YOU_WON` | Type `/dump LOOT_ROLL_YOU_WON`. | A text with an optional loot history link in front, then one `%s` (the item link). | not run |
| 13 | `LOOT_ROLL_WON` | Type `/dump LOOT_ROLL_WON`. | A text with an optional loot history link in front, then the player `%s` and the item `%s`. | not run |
| 13 | `LOOT_ROLL_ALL_PASSED` | Type `/dump LOOT_ROLL_ALL_PASSED`. | A text with an optional loot history link in front, then one `%s` (the item link). | not run |
| 13 | `ERR_TRADE_COMPLETE` | Type `/dump ERR_TRADE_COMPLETE`. | A text with the text that the game shows when a trade completes, with no `%`. | not run |
| 13 | `AUCTION_EXPIRED_MAIL_SUBJECT` | Type `/dump AUCTION_EXPIRED_MAIL_SUBJECT`. | A text with the subject of an expired auction's mail with one `%s` (the item name). | not run |
| 13 | `AUCTION_OUTBID_MAIL_SUBJECT` | Type `/dump AUCTION_OUTBID_MAIL_SUBJECT`. | A text with the subject of an outbid mail with one `%s` (the item name). | not run |
| 13 | Item functions | Type `/dump C_Item.GetItemQualityByID(2589), C_Item.GetItemInfoInstant(2589), GetInventoryItemID("player", 5)`. | `1`; `2589`, the type texts, `""`, an icon, `7` and a subclass; the chest item id or nil. | not run |
| 13 | Loot | Loot a stack of Linen Cloth from a creature, `/reload`. | `MemoriesEconomyCharDB` has `lo|2589|1|<count or empty>|loot|<Spanish name>||<1 or empty>`; `counts.loot` has `items`, `q1` and `item:2589`. | not run |
| 13 | New findings only | Turn on "Loot: new findings only", loot Linen Cloth again, then a blue item. | No new `lo` for the cloth (`counts.loot["item:2589"]` grows); a `lo` for the blue item. | not run |
| 13 | Made item | Craft an item (for example a bandage). | `lo|<id>|<quality>|<count or empty>|made|<name>|...`. | not run |
| 13 | Group roll | In a group, roll Need on a green item, win it, then roll Greed on another and lose. | One `rl|<id>|need|<roll>|1|<name>|2` and one `lo|...|roll|...` for the win (no second `lo` from the loot line); one `rl|<id>|greed|<roll>|0|<name>|<quality>` for the loss, although the chat shows each roll line several times. | not run |
| 13 | Gear at login | Log in, wait 5 s, `/reload`, wait 5 s. | One `ge|<level>|<19 ids>|login` only; `snap[<level>].gear` holds the same ids. | not run |
| 13 | Gear at level up | Gain a level, wait 3 s. | `ge|<new level>|<19 ids>|ding`; `snap[<level>].gear` and `snap[<level>].money` are set. | not run |
| 13 | Equip | Take off the chest item, then put it on again. | `eq|5|0`, then `eq|5|<item id>|<quality>`. | not run |
| 13 | Vendor | Sell a stack of 20 Wool Cloth, buy a Refreshing Spring Water, repair all. | `mn|<copper>|vendor|20 <name>`, `mn|-<copper>|vendor|<water name>`, `mn|-<copper>|repair`; a bought item writes `lo|...|bought|...`. | not run |
| 13 | Trainer functions | At a trainer, type `/dump GetTrainerServiceInfo(2), GetTrainerServiceCost(2), GetTrainerServiceSkillLine(2), IsTradeskillTrainer()`. | The service name, an availability word (`available`, `unavailable` or `used`), a texture, a level and the rank text; the cost; the skill line name; a boolean. | not run |
| 13 | Trainer | Learn two spells at a class trainer, then a profession rank. | `tb|class|<spell> (<rank>)|<cost>` per spell and one `mn|-<sum>|trainer|<names>`; `tb|profession|...` for the profession; `counts.trainers` grows. | not run |
| 13 | Quest money | Turn in a quest that gives gold. | `mn|<copper>|quest|<title>`. | not run |
| 13 | Flight fare | Take a flight. | `mn|-<cost>|flight|<destination>`. | not run |
| 13 | Auction house | Post an item, buy one with buyout, let one expire and take its mail. | `ah|post|<deposit>|<item>` with `mn|-<deposit>|auction|<item>`; `ah|buyout|<copper>|<item>` with `mn|-<copper>|auction|<item>`; `ah|expired||<item>` and `ma|take|...` when the mail is taken. | not run |
| 13 | Auction sold | Sell an item in the auction house, take the money from the invoice mail. | `ah|sold|<copper>|<item>`, `ma|invoice|<buyer>|<copper>|<item>`, `mn|<copper>|auction|<item>`. | not run |
| 13 | Mail functions | Open a mail with an attachment and type `/dump GetInboxHeaderInfo(1)`, then `/dump GetInboxItem(1, 1), GetInboxInvoiceInfo(1)`. | Sender, subject, money, COD, days left, item count, ... `canReply`, `isGM`; the item name, id, texture, count and quality; nil for a player mail. | not run |
| 13 | Mail send | Send 1 gold and an item to another character. | `mn|-10000|mail|<name>` and `mn|-30|postage|<name>`, then `ma|send|<name>|10000|<item>`. | not run |
| 13 | Mail take | Take an item and gold from a player's mail, then take all from another. | `ma|take|<sender>|<copper or empty>|<item>`, `mn|<copper>|mail|<sender>`, and one `lo|...|mail|...` per item, never two for one item. | not run |
| 13 | Trade | Trade with another player: receive 2 items and 50 silver, give 10 silver. | One `tr|<name>|4000`, `mn|4000|trade|<name>` and one `lo|...|trade|...` per item received. | not run |
| 14 | Character loads | Install the set, enable "Memories - Character", log in, `/mem status`. | `Memories_Character` is `on`; the Settings page has "Memories_Character — Character" with `sk`, `lr`, `rc`, `ta`, `cu`, `pt` and the "Consumables: new findings only" box, and "Memories_Character — Milestones" with `rp`, `qa`, `hb`, `fp`, `bk`. | not run |
| 14 | `ERR_LEARN_SPELL_S` | Type `/dump ERR_LEARN_SPELL_S`. | A text with one `%s` (the spell link), for example "Has aprendido un nuevo hechizo: %s.". | not run |
| 14 | `ERR_LEARN_ABILITY_S` | Type `/dump ERR_LEARN_ABILITY_S`. | A text with one `%s` (the ability link). | not run |
| 14 | `ERR_LEARN_RECIPE_S` | Type `/dump ERR_LEARN_RECIPE_S`. | A text with one `%s` (the recipe link). | not run |
| 14 | `ERR_DEATHBIND_SUCCESS_S` | Type `/dump ERR_DEATHBIND_SUCCESS_S`. | A text with one `%s` (the inn's place), for example "%s es ahora tu hogar.". | not run |
| 14 | `ERR_NEWTAXIPATH` | Type `/dump ERR_NEWTAXIPATH`. | The text that the game shows for a new flight path, with no `%`. | not run |
| 14 | `FACTION_STANDING_LABEL1` to `8` | Type `/dump FACTION_STANDING_LABEL1, FACTION_STANDING_LABEL5, FACTION_STANDING_LABEL8, GetText("FACTION_STANDING_LABEL5", 3)`. | "Odiado", "Amistoso", "Exaltado" and the female form of Friendly (or the same text). | not run |
| 14 | Profession names | Type `/dump C_TradeSkillUI.GetTradeSkillDisplayName(186), C_TradeSkillUI.GetTradeSkillDisplayName(129), C_Spell.GetSpellName(3273)`. | "Minería", "Primeros auxilios" and the First Aid spell name. | not run |
| 14 | Skill functions | Open the skills pane and type `/dump C_SkillInfo.GetNumSkillLines(), C_SkillInfo.GetSkillLineInfo(2)`. | A count and a table with `name`, `isHeader`, `isCollapsed`, `rank`, `maxRank` and `skillID`. | not run |
| 14 | Drink spell id | Type `/dump C_Spell.GetSpellName(430)`, then drink a water and check the cast bar. | The same name ("Beber") for the id and the cast. | not run |
| 14 | Special buff ids | On a Self-Found or Hardcore character, type `/dump C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")` for each buff until you find Self-Found Adventurer, Soul of Iron and String of Ears. | The `spellId` of Self-Found is 431567 and of Soul of Iron 364001; note the id of String of Ears (not matched yet). | not run |
| 14 | Talent functions | Type `/dump C_ClassTalents.GetActiveConfigID(), C_SpecializationInfo.GetSpecialization()`. | A config id and a spec index (or nil before level 10). | not run |
| 14 | Statistics functions | Type `/dump GetStatisticsCategoryList()`. | A list of category ids, or an error when the client has no Statistics pane (then `stats` stays empty). | not run |
| 14 | Learn a spell | Learn a spell at a class trainer, `/reload`. | `MemoriesCharacterCharDB` has one `lr|<Spanish name>|<spell id>` for it, although the event and the chat line both fire; `counts.character.learned` 1 more. | not run |
| 14 | Learn a recipe | Learn a First Aid recipe at the trainer. | `lr|<name>|<id>` and `rc|<name>|<id>`, one each. | not run |
| 14 | Raise a profession | Mine until Minería rises one rank, wait 3 s, `/reload`. | `sk|Minería|<rank>|<max>`; `snap[<level>].skills` lists every skill as `<header>:<name>=<rank>/<max>`. A weapon skill rank-up writes nothing. | not run |
| 14 | Talents | At level 10 or more, spend a talent point, wait 1 s. | `ta|<spent>|<unspent>`; `snap[<level>].talents` is the spent points. | not run |
| 14 | Consumable | Drink a water out of combat, then use a bandage in combat. | `cu|<id>|drink|<name>` and `cu|<id>|bandage|<name>|1`; `counts.items` has `k:drink`, `k:bandage`, `o:<id>` and `c:<id>`. | not run |
| 14 | Consumables: new findings only | Turn on "Consumables: new findings only" and drink the same water again. | No new `cu` line; `counts.items["o:<id>"]` grows. | not run |
| 14 | Channel functions | On a hunter, start Tame Beast and type `/dump UnitChannelInfo("player")` during the channel, then cancel a second try by moving. | The channel name, its start and end in ms; the cancelled try writes no `pt` when you call a pet within 30 s. | not run |
| 14 | Tame | On a hunter, tame a beast. | `pt|<family>|<pet name>|<level>`; `counts.character` has `tames`, `pet:<family>` and `petn:<family>|<name>`; dismissing and calling the pet adds nothing. | not run |
| 14 | Crafting | Open Cooking and cook 2 items at once. | `counts.prof["cooked|<item>|Cooking"]` 2 more. | not run |
| 14 | Gain reputation | Turn in a quest that gives Stormwind reputation. | `rp|Ventormenta|<value>|<standing>|<Spanish label>`; the same value again in the session writes nothing. | not run |
| 14 | Accept a quest | Accept a quest. | `qa|<quest id>|<Spanish title>` at the place where you accepted it; `counts.milestones.questsAccepted` 1 more. | not run |
| 14 | Bind the hearthstone | Bind at a new inn, then at the same inn again. | One `hb|<place>`; the second bind writes nothing. | not run |
| 14 | Learn a flight path | Talk to a new flight master. | One `fp|<node name>`; `counts.milestones.flightPaths` 1 more. | not run |
| 14 | Read a book | Read a plaque or book twice. | One `bk|<title>`; `counts.milestones.booksRead` 2 more. | not run |
