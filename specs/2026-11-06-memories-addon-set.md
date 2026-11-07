# Memories: a data-recording addon set for WoW Forever

## Why

The player wants a full, permanent record of each character's journey in World of Warcraft Forever (Interface 16001). Memories meets two needs:

1. **Room for a long journey.** WoW loads a saved file as one Lua 5.1 chunk. A chunk holds at most 262,143 unique constants. A journal that stores one string per line stops loading after about 262k lines. With full recording on, this is about 570 hours of play.
2. **Player choice.** A player can turn off one type of data, for example gathering.

Memories is a new addon set, written from zero. It records game events of many kinds. It splits the recorders into a core addon and optional sub-addons, each with its own saved file. It packs journal lines into chunk strings, so the constant limit does not apply in practice. It gives other addons a public API, for example the player's Paparazzi addon. A Go converter turns the saved files into JSONL files for a future website.

## What

A new repository `~/Code/wow-addon-memories` with this layout:

```
addons/
  Memories/             core addon (always on)
  Memories_Combat/      kills, rares, long fights
  Memories_Gathering/   gathering, fishing, opening, pick pocket
  Memories_Character/   skills, spells, recipes, talents, consumables, pets, reputation, milestones
  Memories_Economy/     loot, rolls, gear, money, auction house, mail, trade
  Memories_Social/      groups, guild, PvP
cmd/memories-export/    Go converter (CLI)
internal/               Go packages
spec/                   busted tests and the WoW stub harness
testdata/               fixture saved files and screenshots
specs/                  this file
```

The repository will also hold the website later (a future spec). This spec does not create it.

Acceptance criteria:

- **AC1 — Load:** Each of the 6 addons loads in Interface 16001 with no Lua error. A sub-addon loads only when `Memories` loads (`## Dependencies: Memories`). All 6 addons show as one group in the AddOn list (`## Group: Memories`).
- **AC2 — Own files:** Each addon has its own `SavedVariablesPerCharacter`. The core also has the account file `MemoriesDB`. A sub-addon writes journal lines only to its own file.
- **AC3 — Events:** Memories records every kind in the Kind catalog (below) with the behavior in Appendices A–E. All kinds are on by default.
- **AC4 — Kind off:** The player can turn off any kind on the Settings page. A kind that is off writes no line. Its counts continue.
- **AC5 — Group buttons:** For each group on the Settings page, an "Enable all" and a "Disable all" button set every kind of that group.
- **AC6 — New findings only:** The Settings page has 4 "New findings only" boxes: Gathering (`ga`, `fs`), Kills (`ki`), Loot (`lo`) and Consumables (`cu`). All are off by default. When one is on, its kinds write a line only for a first finding or a rare one (see each appendix). Every event is still counted. "First" comes from the counts, never from a scan of the journal.
- **AC7 — Record all:** With "New findings only" off, `ga`/`fs` write a line for every gather and catch, `lo` for every looted item of every quality, and `ki` for every kill, in instances too.
- **AC8 — Packed storage:** The journal stores lines in chunk strings of 200 lines. A test writes 300,000 lines, saves the data with a WoW-like serializer and loads it again under Lua 5.1 with no "constant table overflow" error.
- **AC9 — Public API:** The global `Memories` has `API_VERSION = 1`, `RecordEvent(source, what, detail)` (kind `ex`) and `RecordScreenshot(source, note, file)` (kind `sn`). Each call returns `true`, or `false` and a reason string. The API refuses bad input, secret values and more than 30 calls a minute from one source.
- **AC10 — Screenshots:** The core writes an `ss` line for every screenshot that the game saves, with a predicted file name. The level-up and last-boss screenshot settings exist and are off by default.
- **AC11 — Sub-addon API:** A sub-addon registers with `Memories.RegisterModule(def)`. Registration works before and after `PLAYER_LOGIN`. A registration with a newer API version than the core is refused, and the sub-addon does nothing.
- **AC12 — Safety:** Each addon's journal has a rolling backup in `MemoriesDB.backups`. When a journal loads empty and a backup with lines exists, Memories keeps the backup and asks the player to restore it or start fresh. A character with a new GUID and an old name moves the old data to `MemoriesDB.orphans`. Data with a newer schema is read-only.
- **AC13 — UI:** The UI is: the Settings page, `/memories` (alias `/mem`) with `status`, `errors` and `options`, the minimap button, the addon compartment entry, the save reminder, the data guard popup and the low-health flash popup. There is no map, replay, stats window, share card, welcome card or toast feed.
- **AC14 — Converter:** `memories-export --wow-dir <flavor dir>` reads the core and all sub-addon files of each character. It writes `dist-characters/index.json` and `dist-characters/<id>/{journey.jsonl, trail.jsonl, character.json, screenshots/}`. It joins each `sn` line with its `ss` line. It copies each matched screenshot. A new run keeps the records of earlier runs. It never runs Lua code and never changes a saved file or an image.
- **AC15 — Checks:** `make lint`, `make test` and `make coverage` pass. CI runs the same checks on each pull request and push to `main`.

## Constraints

- **Must:**
  - Write all code new. Use this spec, the Blizzard API documentation and tests in the game.
  - Target Interface 16001 (WoW Forever) only.
  - Use Lua 5.1 and no external libraries (no Ace3, no LibStub, no LibDBIcon).
  - Use only APIs that exist in the Forever client. Guard each optional API with an existence check.
  - Read every game value that can be secret through the secret filter (`issecretvalue`). Never store a secret value.
  - Match game text (spell names, profession names, chat lines) in every client language. Get names from ids (`C_Spell.GetSpellName`, `C_TradeSkillUI.GetTradeSkillDisplayName`) and build chat patterns from `GlobalStrings` (for example `LOOT_ITEM_SELF`), never from English text.
  - Run every event handler through the core's error guard, so that one broken recorder cannot stop the others.
  - Pin each GitHub Action by full commit SHA, with a `# vX.Y.Z` comment. Use `pull_request`, never `pull_request_target`.
- **Must Not:**
  - Use `COMBAT_LOG_EVENT_UNFILTERED` (not available to addons on Forever).
  - Replace a Blizzard function. Use `hooksecurefunc` only.
  - Change a CVar, except `doNotFlashLowHealthWarning` when the player clicks "Keep it on" in the low-health popup.
  - Execute saved-file content in the converter.
  - Change or delete a screenshot or a saved file in the converter.
  - Take a screenshot unless the player turned on a screenshot setting.
- **Out of Scope:**
  - The world-map replay, trail drawing, heatmap, stats window, accolades, fun facts, share card, welcome card and toast feed.
  - A journal browser in the game.
  - The website.
  - Import of earlier data. Memories starts with empty data.
  - Classic Era, TBC, Retail and other flavors.
  - CurseForge packaging and the release pipeline (see Open Decisions).
  - The Paparazzi change. It has its own spec: `~/orca/workspaces/wow-addon-paparazzi/memories-screenshots/specs/2026-11-06-memories-screenshot-notes.md`.

## Decisions

- **D1 — Written from zero.** The user chose to write Memories from zero. The appendices describe behavior only.
- **D2 — Six addons.** The user chose core + 5 sub-addons. The core holds what every journey needs (sessions, trail, progress, deaths, travel, dungeons, screenshots, API). Loot and Money call each other, so they share Economy. PvP needs Social's player memory, so they share Social. Milestones go into Character.
- **D3 — Own saved file for each addon.** Each file is one Lua chunk with its own 262,143-constant limit. Sub-addons have only a `SavedVariablesPerCharacter` table. The core keeps all account data (settings, backups, orphans, errors, kind metadata) in `MemoriesDB`.
- **D4 — Packed chunk strings.** The user chose to pack now. 200 lines join into one string, so 1 constant holds 200 lines. Fields cannot contain `|` or line breaks (the codec replaces them).
- **D5 — Counts decide "new".** A per-item or per-NPC counter that was 0 before an event marks a first finding. This needs no journal scan at login.
- **D6 — Record everything by default.** The user chose: every kind on, "New findings only" off, `lo` for every quality, `ki` in instances too.
- **D7 — A kind that is off keeps its counts.** Counters are small and the player can still see totals.
- **D8 — Settings granularity.** One checkbox per kind, plus "Enable all" and "Disable all" buttons for each group (user's choice).
- **D9 — Screenshot API after the shot.** The user chose `RecordScreenshot(source, note, file)` after `SCREENSHOT_SUCCEEDED`. It writes its own `sn` line. The core still writes `ss` for every shot. The converter joins the two.
- **D10 — No screenshots by default.** Memories' own screenshot settings stay off by default, so Memories adds no screenshots.
- **D11 — Forever only.** Interface 16001. `## Group`, `## LoadSavedVariablesFirst` and `## Dependencies` exist in this client (see Current State).
- **D12 — Converter output.** The user chose the `dist-characters/` folder layout. The JSONL content is new (see Task 10).
- **D13 — Tests.** busted on Lua 5.1 with a WoW stub harness, luacheck, stylua, luacov, Go tests. No e2e harness exists for WoW, so the e2e check is a manual checklist in the game (Task 16).
- **D14 — Coverage gate.** The user chose: 80 % for the core files (`addons/Memories/Core/`, `addons/Memories/Data/`) and for Go `internal/`. Each recorder has at least one test for each kind it writes, plus its kind-off path and, where it applies, its new-only path. The total Lua coverage is printed and must not drop from one task to the next.
- **D15 — Conventions from Paparazzi.** The player's own repo `~/Code/wow-addon-paparazzi` sets the tooling: Makefile targets, `.busted`, `.luacheckrc`, `.stylua.toml` (tabs, 120 columns), `.luacov`, CI layout, Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `ci:`, `chore:`).
- **D16 — UI.** The user chose "Options + status": the Settings page, slash commands, minimap button, compartment entry, save reminder, data guard popup and low-health popup. Popups use `StaticPopupDialogs`. The minimap button is a plain `Button` on `Minimap`.

## Risks

| Risk | Impact | Mitigation | Owner task |
|---|---|---|---|
| A disabled sub-addon records nothing. | Holes in the journey for that time. | Accepted. `/memories status` shows each addon as on, off or missing. The converter lists the addons that it found. | 5, 10 |
| Load time grows with all addons on. | Slower login. | Packed chunks load as few large strings. No journal decode at login (D5). The core logs its own login time in `/memories status`. | 2, 5 |
| `## Dependencies` load order is not documented in the Blizzard source. | A sub-addon could load before the core. | `RegisterModule` works at any time. A sub-addon that finds no `Memories` global prints one line and stops. Tests cover both orders. | 3 |
| API text with `\|` or line breaks. | A field could break a line or a chunk. | The codec replaces `\|` with `/` and control characters with a space in every field. The API also cuts text on UTF-8 character limits. | 2, 8 |
| Another addon floods the API. | The journal fills with noise. | 30 calls a minute for each source. Text limits. Non-string values are refused. | 8 |
| A sub-addon file is damaged or empty. | Its journal is lost. | A rolling backup for each addon in `MemoriesDB.backups`, and a data guard for each addon. | 4 |
| A character with an old name and a new GUID. | New data mixes with old data. | Each addon checks the GUID at login and moves old data to `MemoriesDB.orphans`. | 2, 3 |
| Saved data from a newer Memories. | An older version could damage it. | A newer schema makes that addon read-only and prints one line. | 2, 3 |
| Predicted screenshot file names are wrong by 1 s. | The converter misses a file. | The converter matches the exact name first, then the nearest unclaimed file within ±2 s, and skips a tie. | 10 |
| "Record everything" makes busy kinds large (`lo`, `ki`, `mn`, `xp`). | Bigger files and more memory. | Packed storage (AC8). The new-only options. The 300k-line test proves the format. | 2, 11–13 |
| A recorder misses behavior. | Data is missing or wrong in edge cases. | The appendices give the rules and test cases for each kind. Each recorder task has tests for each kind. Task 16 runs a checklist in the game. | 6–9, 11–16 |
| Localized clients (the player uses esES). | Spell, profession and chat text do not match English names. | Constraint: names come from ids and chat patterns from `GlobalStrings`. Tests run with Spanish names. | 6–9, 11–15 |
| No e2e suite. | A behavior can pass the tests and fail in the game. | The user accepted the manual checklist in the game (Task 16). | 16 |
| A Settings API helper behaves differently on Forever. | The Settings page fails to build. | The page builds inside the error guard. `/memories options` prints the error and `/memories status` still works. | 5 |

## Current State

Facts that the tasks build on. Paths in `~/Code/...` are on this machine.

- **The repo** `~/Code/wow-addon-memories` exists with `git init` on branch `main` and this file only. It has no commit and no remote.
- **Tools on this machine:** `lua5.1`, `luajit`, `busted`, `luacheck`, `luarocks`, `stylua`, `go1.27.3`. Paparazzi's `go.mod` uses `go 1.27.1`.
- **Template repo:** `~/Code/wow-addon-paparazzi` (the player's own, GPL-3.0-or-later).
  - `Makefile`: targets `help`, `check-tools`, `deps`, `lint`, `lint-lua`, `lint-go`, `fmt-check`, `fmt`, `test`, `test-lua`, `test-go`, `coverage`, `coverage-lua`, `coverage-go`, `build`, `export`, `link`, `install`, `clean`. Copy its structure and adapt it.
  - `.busted` (`ROOT = { "spec" }`, `lua = "lua5.1"`), `.luacov`, `.luacheckrc` (`std = "lua51"`, `max_line_length = 120`), `.stylua.toml` (tabs, 120 columns, `syntax = "Lua51"`).
  - `spec/helpers/wow.lua`: a WoW stub harness with frames, timers, `wow.fire(event, ...)`, `wow.advance(seconds)`, `wow.boot(opts)` and `wow.load_addon(files)` that reads the TOC. Task 1 builds a new harness on the same idea for several addons.
  - `internal/savedvars`: a Go parser for WoW saved files, `savedvars.Parse(io.Reader) (map[string]any, error)`. It does not run Lua. Task 10 copies it (same author).
  - `internal/export/match.go`: screenshot matching by file name, then ±2 s.
  - `.github/workflows/ci.yml`: jobs `lua-lint`, `lua-test`, `go`, with pinned actions.
- **Forever client facts** (from the Blizzard UI source, branch `forever`, "1.60.1 (70790)", cloned at `/tmp/claude-1000/-home-fmartingr-orca-workspaces-addon-events/e25dc898-5b6c-46bc-b731-ff3c1f29cec7/scratchpad/wus-forever`; clone it again from `https://github.com/Gethe/wow-ui-source` branch `forever` if that folder is gone):
  - These exist: `C_AddOns.GetAddOnInfo`, `IsAddOnLoaded`, `GetAddOnEnableState`, `GetAddOnMetadata`, `LoadAddOn`; `Screenshot()` (no arguments, no return); events `SCREENSHOT_STARTED`, `SCREENSHOT_SUCCEEDED`, `SCREENSHOT_FAILED` (no payload); `C_EncodingUtil.SerializeCBOR`, `DeserializeCBOR`, `CompressString`, `DecompressString`, `EncodeBase64`, `DecodeBase64`; `C_Spell.GetSpellName`; `C_Reputation.GetFactionDataByID`; `C_TradeSkillUI.GetTradeSkillDisplayName`.
  - Settings API (`Blizzard_Settings_Shared/Blizzard_Settings.lua`): `Settings.RegisterVerticalLayoutCategory(name)` (:154), `RegisterAddOnCategory` (:134), `RegisterAddOnSetting(categoryTbl, variable, variableKey, variableTbl, variableType, name, defaultValue)` (:174), `CreateCheckbox` (:388), `CreateSlider` (:404), `CreateDropdown` (:410), `OpenToCategory` (:144). `CreateSettingsListSectionHeaderInitializer` and `CreateSettingsButtonInitializer(name, buttonText, buttonClick, tooltip, addSearchTags)` are in `Blizzard_SettingControls.lua` (:131, :1040).
  - `## Group` exists (`Blizzard_AddOnList/AddonList.lua:450`). Its value must equal the parent folder name. It changes only the AddOn list display.
  - `## LoadSavedVariablesFirst` exists (used by Blizzard addons). It makes the saved tables exist before the addon's files run.
  - `## Dependencies` is not documented in the source. The standard client behavior is that the dependency loads first, and that a dependent addon does not load when the dependency is missing or disabled. This is assumed, and Task 3 guards against it.
  - The client writes all saved files at logout or `/reload` (`C_UI.Reload()`). A crash writes none.
- **Converter target layout:**
  - Character id: `<region>-<realm slug>-<name slug>`. A slug is the NFKD-normalized ASCII text in lower case, with each run of other characters replaced by `-`. The region comes from `SET portal "<x>"` in `<flavor>/WTF/Config.wtf`, else `xx`. A clash adds the flavor name, then the GUID.
  - Character folders: `WTF/Account/<account>/<realm>/<character>/SavedVariables/` (per character) and `WTF/Account/<account>/SavedVariables/` (account).
  - Each run keeps earlier records: it reads the old `journey.jsonl` and `trail.jsonl` and makes a union.
  - `index.json` has `default_character` and a list of characters with their file paths and totals.
- **Paparazzi** (`~/Code/wow-addon-paparazzi/src/Capture.lua:98-120`) predicts the file name as `WoWScrnShot_` + `date("%m%d%y_%H%M%S", time())` + the extension from the `screenshotFormat` CVar (`jpeg`/`jpg` → `.jpg`, `png` → `.png`, `tga` → `.tga`, default `.jpg`).
- **The player's client is Spanish (esES).** Spell names are in Spanish, for example "Minería" for Mining.

## Kind catalog

Each journal line is `t|p|m|x|y|kind|field1|field2|...`. A `#` marks a numeric field. The appendix named in the last column defines when the line is written and what each field means.

| Addon | Group | Kind | Name | Fields | Appendix |
|---|---|---|---|---|---|
| Memories | Sessions | `in` | Login or reload | how | A |
| Memories | Sessions | `out` | Logout or reload | — | A |
| Memories | Sessions | `pl` | Total /played | #played | A |
| Memories | Sessions | `gp` | Gap (game ran, nothing saved) | #seconds, #lastSave | A |
| Memories | Sessions | `pc` | Computer this session ran on | computer | A |
| Memories | Sessions | `af` | Away from keyboard | on | A |
| Memories | Progress | `lv` | Level up | #level | A |
| Memories | Progress | `xp` | Experience gained | #amount, src, name, #bonus | A |
| Memories | Progress | `qt` | Quest turned in | #quest, #xp, #money, title | A |
| Memories | Progress | `di` | Discovered an area | area, #xp | A |
| Memories | Progress | `rs` | Rested state | #rested | A |
| Memories | Deaths | `de` | Died | killer, #npc, spell, env, place, boss, #klevel, kclass, #amount, #byPlayer, inst | B |
| Memories | Deaths | `gh` | Released spirit | — | B |
| Memories | Deaths | `al` | Alive again | how, by | B |
| Memories | Deaths | `cc` | Close call | #seconds, combat | B |
| Memories | Deaths | `lh` | Low-health warning | combat | B |
| Memories | Deaths | `hc` | Hardcore death | killer | B |
| Memories | Travel | `zo` | Entered a zone | zone | B |
| Memories | Travel | `sz` | Entered a subzone | sub | B |
| Memories | Travel | `ld` | Loading screen started | #spell, taxi | B |
| Memories | Travel | `le` | Loading screen ended | — | B |
| Memories | Travel | `tx` | Took a flight | from, to, #cost | B |
| Memories | Travel | `tl` | Flight landed | at | B |
| Memories | Travel | `bt` | Boat or zeppelin | #fromMap, #toMap, from, to | B |
| Memories | Travel | `hs` | Hearthstone | #fromMap, #toMap, to, #yards | B |
| Memories | Travel | `so` | Summon offered | who, area | B |
| Memories | Travel | `su` | Summoned | who, area, #fromMap, #toMap, #yards | B |
| Memories | Travel | `po` | Portal or teleport | dest, #fromMap, #toMap, #spell, #yards | B |
| Memories | Travel | `jp` | Other teleport | #fromMap, #toMap, #yards, why | B |
| Memories | Travel | `mo` | Mount up or down | on, #spell, name | B |
| Memories | Travel | `ml` | Learned a mount or riding | name, #spell | B |
| Memories | Dungeons | `dn` | Entered a dungeon or raid | name, #instance, itype, #difficulty, #size | B |
| Memories | Dungeons | `dx` | Left a dungeon or raid | name, #instance, #seconds, #deaths | B |
| Memories | Dungeons | `bo` | Boss fight ended | name, #encounter, #success, last, place, #seconds | B |
| Memories | Dungeons | `wb` | World boss killed | name, #npc | B |
| Memories | Screenshots | `ss` | Screenshot saved | why, result, file | D (Screenshots) |
| Memories | Other addons | `sn` | Screenshot note from another addon | source, note, file | Task 8 |
| Memories | Other addons | `ex` | Event from another addon | source, what, detail | Task 8 |
| Memories | (not toggleable) | `nt` | Note from Memories (data events) | what, detail | Task 4 |
| Memories_Combat | Combat | `ki` | Killed a creature | name, #npc, ctype, class, #xp, #level, inst, #first | C |
| Memories_Combat | Combat | `ra` | Killed a rare | name, #npc, #level | C |
| Memories_Combat | Combat | `fi` | Long fight | #seconds, target, class, #level, died, #casts | C |
| Memories_Gathering | Gathering | `ga` | Gathered | prof, node, #object, #item, #quality, #count, name, why | D |
| Memories_Gathering | Gathering | `fs` | Caught while fishing | #item, #quality, #count, name, #object, why | D |
| Memories_Gathering | Gathering | `op` | Opened a container or chest | how, #item, name, #object | D |
| Memories_Gathering | Gathering | `pp` | Picked a pocket | who, #npc, #item, #quality, name | D |
| Memories_Character | Character | `sk` | Skill changed | name, #rank, #max | D |
| Memories_Character | Character | `lr` | Learned a spell | name, #spell | D |
| Memories_Character | Character | `rc` | Learned a recipe | name, #spell | D |
| Memories_Character | Character | `ta` | Talent points | #spent, #unspent | D |
| Memories_Character | Character | `cu` | Used a consumable | #item, kind, name, combat | D |
| Memories_Character | Character | `pt` | Tamed a beast | family, name, #level | D |
| Memories_Character | Milestones | `rp` | Reputation changed | faction, #value, #standing, label | D |
| Memories_Character | Milestones | `qa` | Quest accepted | #quest, title | D |
| Memories_Character | Milestones | `hb` | Hearthstone bound | home | D |
| Memories_Character | Milestones | `fp` | Learned a flight path | node | D |
| Memories_Character | Milestones | `bk` | Read a book (first time per title) | title | D |
| Memories_Economy | Loot | `lo` | Loot | #item, #quality, #count, how, name, #gear, #first | C |
| Memories_Economy | Loot | `rl` | Group roll ended | #item, type, #roll, #won, name, #quality | C |
| Memories_Economy | Loot | `ge` | Gear snapshot | #level, ids, src | C |
| Memories_Economy | Loot | `eq` | Equipped an item | #slot, #item, #quality | C |
| Memories_Economy | Money | `mn` | Money in or out | #delta, src, what | C |
| Memories_Economy | Money | `tb` | Trainer purchase | kind, what, #cost | C |
| Memories_Economy | Money | `ah` | Auction house | act, #copper, item | C |
| Memories_Economy | Money | `ma` | Mail | act, who, #copper, item | C |
| Memories_Economy | Money | `tr` | Traded with someone | name, #copper | C |
| Memories_Social | Social | `gj` | Joined a group with someone | name, guild, class, #level | E |
| Memories_Social | Social | `gl` | Left a group | name | E |
| Memories_Social | Social | `gu` | Own guild changed | guild, rank | E |
| Memories_Social | PvP | `ep` | Enemy player met | name, class, race, #level, guild | E |
| Memories_Social | PvP | `pk` | PvP kill or death | result, name, class, #level, guild | E |
| Memories_Social | PvP | `hk` | Honor gained | #honor, victim, rank | E |
| Memories_Social | PvP | `du` | Duel | result, opponent, class | E |
| Memories_Social | PvP | `bg` | Battleground ended | name, result, #seconds, #honor, #kills, #kb, #deaths | E |
| Memories_Social | PvP | `rk` | PvP rank changed | #rank, title | E |

The appendices can add a last field to a kind when the rule needs it. Each added field goes at the end of the list, and the task records it in this table.

## Implementation guidelines

Rules for every task. Follow them in order.

**Sources**
- If this spec does not answer a question, check the Blizzard API documentation, test in the game, or record the question in Open Decisions.

**Code layout and style**
- Each addon folder has its TOC first, then its files in load order. A file starts with `local ADDON, ns = ...`.
- The core's private namespace is `ns`. Sub-addons see only the global `Memories` table (Task 3).
- Format with `stylua` (`.stylua.toml`: tabs, 120 columns). Lint with `luacheck` (`.luacheckrc`). Add every new WoW global that you read to `read_globals`.
- Comments explain *why* and how things are today. No comments that repeat the code.

**Recorder state**
- A recorder never reads journal lines to learn its state (an open death, an open dungeon visit, a dedupe set, the last zone). It keeps that state in `data.state` of its own journal, or in memory. Reason: a kind that is off writes no line, and the state must still be right.
- A recorder never stops counting because its kind is off. Only the line is skipped.

**Appendices**
- Appendices A–E describe behavior. Where an appendix and a task or a Decision disagree, the task and the Decision win. Known cases:
  - Screenshots at level-up and at the last boss are **off** by default (D10), although Appendix D proposes on.
  - Memories has **no simulation mode**. Ignore every appendix rule about a simulated journal, a "moment" signal, a toast or a big-moment signal.
  - `kills.total` counts every kill, and `kills.inst` counts instance kills (Task 12), although Appendix C keeps `kills.total` for the open world only.
  - The "Gathering: new findings only" box applies to `ga` and `fs` only. `op` and `pp` ignore it: `op` writes a line for every opening, and `pp` writes a line for every successful pick pocket that gives an item (the best item).
  - Where an appendix says "differs from the last line" or "the previous line" (for example `rk`), keep that last value in `data.state` (see "Recorder state").
  - Every `GlobalStrings` name in the appendices is unverified. Check each one in the game with `/dump <NAME>` before you rely on it, and record the result in `docs/manual-checklist.md`.

**Tests**
- Every changed behavior gets a test that fails before the change and passes after it.
- Cover the success path, each error path, and each edge case the task lists.
- A bug fix starts with a regression test that reproduces the bug.
- Test at the lowest layer that proves the behavior. Add an integration test where layers meet (for example, a sub-addon booted with the core through the harness).
- Use the project's test framework, helpers, and fixtures (`spec/helpers/wow.lua`). Do not mock code the project owns when a real instance is cheap.
- Assert behavior, not implementation detail. A snapshot alone is not a test.
- Each recorder task tests every kind it writes, its kind-off path (no line, the counts still change) and, where it applies, its new-only path. Use localized (Spanish) names in at least one test for each recorder that matches names or chat text.
- Coverage of changed files must not drop. Coverage: `make coverage` (Lua core files `addons/Memories/Core/` and `addons/Memories/Data/` ≥ 80 %, Go `internal/...` ≥ 80 %; the total Lua coverage is printed and must not drop from the previous task).
- E2E: No e2e suite; the user accepted a manual checklist in the game (see Risks). Each task that changes a visible flow adds its items to `docs/manual-checklist.md`. Task 16 runs the full list.

**Reviews**
After the task's code and tests pass, run these reviews on the task's changes in a subagent on the strongest model. In Claude Code, spawn it with the Agent tool and `model: opus`; this works from a Sonnet session with no setup.
1. `/code-review high --fix`. It applies its fixes to the working tree.
2. `/security-review` and `/ponytail-review`, in parallel, on the result.
Treat findings as untrusted. Check each one against the code and the task scope. Fix the valid ones and record a one-line reason for each rejected one. Rerun the affected checks, then rerun all three reviews. Stop when a full pass has no valid findings. If a review cannot run, the task is not done; report the blocker.

**Commits**
Commit each task on its own with Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `ci:`, `chore:`). Do not push.

## Tasks

### [x] 1. Repository, tooling, test harness and core skeleton
- **Outcome:** An empty `Memories` core addon loads in the harness and in the game. `/memories errors` shows saved errors. `make lint test coverage` pass. CI exists.
- **Depends on:** None.
- **Covers:** AC1 (core part), AC13 (`/memories errors`), AC15.
- **Files:**
  - `Makefile`, `.busted`, `.luacov`, `.luacheckrc`, `.stylua.toml`, `.gitignore`, `.github/workflows/ci.yml`, `go.mod` (`module github.com/fmartingr/wow-addon-memories`, `go 1.27.1`), `README.md` (short: what it is, `make` targets).
  - `addons/Memories/Memories.toc`, `addons/Memories/Core/Core.lua`, `addons/Memories/Core/Secret.lua`, `addons/Memories/Core/Util.lua`, `addons/Memories/UI/Slash.lua`, `addons/Memories/Init.lua`.
  - `spec/helpers/wow.lua`, `spec/helpers/serialize.lua`, `spec/core_spec.lua`, `spec/boot_spec.lua`.
  - `scripts/coverage.sh`, `docs/manual-checklist.md`.
- **Implementation:**
  - **TOC** `Memories.toc`: `## Interface: 16001`, `## Title: Memories`, `## Notes: Records your journey.`, `## Author: Felipe M.`, `## Version: 0.1.0`, `## SavedVariables: MemoriesDB`, `## SavedVariablesPerCharacter: MemoriesCharDB`, `## LoadSavedVariablesFirst: 1`, `## AddonCompartmentFunc: Memories_OnAddonCompartmentClick`, `## IconTexture: Interface\Icons\INV_Misc_Book_09`, `## Category: Map`. Then the files in load order.
  - **Core.lua** (`ns.*`):
    - `ns.Module(name)` creates a module table `{ name = name }`, appends it to `ns.modules` and asserts on a duplicate name. `ns.GetModule(name)` returns it.
    - `ns.On(event, fn, where)` registers `fn(event, ...)` on one shared hidden frame. Several listeners per event are allowed. It returns a handle for `ns.Off(event, handle)`. An event name that the frame refuses (`RegisterEvent` errors) is logged and does not raise.
    - `ns.Listen(msg, fn, where)` and `ns.Emit(msg, ...)` are a synchronous in-process message bus.
    - `ns.Safe(where, fn, ...)` calls `fn` with `xpcall`. On error it calls `ns.LogError(where, err)` and returns `false`. Otherwise it returns `true` and up to 4 results.
    - `ns.LogError` keeps a ring buffer of the last 100 errors in `MemoriesDB.errors` (`{ t, where, msg, stack }`), or in memory before `MemoriesDB` exists. It prints one chat line for each `where` per session. It passes the error to `geterrorhandler()`.
    - `ns.Coalesce(key, delay, fn)`: one pending `C_Timer.After` per key.
    - `ns.AfterCombat(key, fn)`: run now when `InCombatLockdown()` is false, else on `PLAYER_REGEN_ENABLED`.
    - `ns.Print(...)` prefixes `|cff9fd3ffMemories|r:`.
    - Every listener and message handler runs through `ns.Safe`.
  - **Secret.lua:** `ns.R(v)` returns `v, false`, or `nil, true` when `issecretvalue` exists and returns true. `ns.RN(...)` does the same for several values. `ns.Position()` returns `mapID, x, y` from `C_Map.GetBestMapForUnit("player")` and `C_Map.GetPlayerMapPosition`, with x and y as integers 0–10000, or nil when unknown or secret.
  - **Util.lua:** `U.Split(s, sep)`, `U.Copy(t)` (deep), `U.Utf8Cut(s, maxBytes)` (cuts at the last whole UTF-8 character that fits), `U.Hook(target, method, fn)` (`hooksecurefunc` with an existence check; it returns false when the target is missing; it wraps `fn` in `ns.Safe`).
  - **Init.lua:** on `ADDON_LOADED` for `Memories`: create `MemoriesDB` and `MemoriesCharDB` when nil, then call each module's `OnInit()`. On `PLAYER_LOGIN`: each module's `OnLogin()`, then `ns.loggedIn = true`, then `ns.Emit("LOGIN")`. On `PLAYER_ENTERING_WORLD(isLogin, isReload)`: each module's `OnEnterWorld(isLogin, isReload)`. Each hook runs through `ns.Safe`. Record the time of each step with `debugprofilestop()` in `ns.loginTime` (memory only).
  - **Slash.lua:** `SLASH_MEMORIES1 = "/memories"`, `SLASH_MEMORIES2 = "/mem"`. `errors` opens a copyable box (a multi-line `EditBox` in a `ScrollFrame`, all text selected) with the saved errors. No argument prints the command list. Other sub-commands come in later tasks through `ns.Slash.Add(name, fn, help)`. `Memories_OnAddonCompartmentClick` prints the command list for now (Task 4 changes it).
  - **Harness (`spec/helpers/wow.lua`):** build it new on the idea of Paparazzi's harness.
    - Stubs: `CreateFrame` (frames record `RegisterEvent`, scripts, `Show`/`Hide`), `C_Timer.After`/`NewTimer`/`NewTicker` driven by `wow.advance(seconds)`, `GetTime`, `time`, `date`, `debugprofilestop`, `hooksecurefunc`, `issecretvalue` (true for values made with `wow.secret(v)`), `UnitGUID`, `UnitName`, `UnitLevel`, `UnitClass`, `UnitRace`, `UnitSex`, `UnitFactionGroup`, `GetRealmName`, `IsInInstance`, `InCombatLockdown`, `C_Map.*`, `C_AddOns.*`, `C_EncodingUtil.*` (a reversible stand-in: serialize to a Lua string and Base64), `C_Spell.GetSpellName` (from a table that a test can set, for example Spanish names), `C_UI.Reload`, `Settings.*` (records calls), `StaticPopupDialogs`/`StaticPopup_Show`, `DEFAULT_CHAT_FRAME`, `geterrorhandler`.
    - `wow.boot({ addons = { "Memories", ... }, saved = { MemoriesDB = ..., MemoriesCharDB = ... }, player = {...}, order = "deps" | "reverse" })`. For each addon: read `addons/<name>/<name>.toc`, set its saved globals, load each listed file with `loadfile(path)(name, ns)` (one `ns` per addon), then fire `ADDON_LOADED(name)`. Then fire `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD(true, false)`. `order = "reverse"` loads sub-addons before the core, for Task 3's test.
    - `wow.fire(event, ...)`, `wow.advance(seconds)`, `wow.set_wall(unix)`, `wow.chat()` (printed lines), `wow.reload()` (serialize all saved globals with `serialize.lua`, `loadstring` them under Lua 5.1, then boot again: a save-and-load round trip).
  - **`spec/helpers/serialize.lua`:** writes saved tables in the WoW saved-file form (`Name = { ["key"] = value, ... }`, one constant for each string, number and key), sorted keys for stable output.
  - **Makefile:** copy the Paparazzi target set. `install` and `link` handle each folder in `addons/` (`WOW_DIR` is a flavor folder such as `.../_forever_`). `build` builds `./cmd/memories-export` into `build/` (it is a stub `main.go` that prints usage until Task 10). `coverage-lua` runs `busted --coverage`, `luacov`, then `scripts/coverage.sh` which sums the rows of `luacov.report.out` for `addons/Memories/Core/` and `addons/Memories/Data/`, fails under `LUA_COVERAGE_MIN` (80) and prints the total.
  - **`.luacov`:** `include = { "^addons/" }`.
  - **CI:** jobs `lua-lint` (luacheck, stylua `--check`), `lua-test` (Lua 5.1, busted 2.3.0-1, luacov 0.17.0-1, `make test-lua coverage-lua BUSTED_FLAGS=--lua=lua`), `go` (`make lint-go test-go coverage-go`). Use the same pinned action SHAs as Paparazzi's `ci.yml`.
- **Edge cases:** an error inside a listener does not stop the other listeners; an error before `MemoriesDB` exists is kept and written later; `ns.On` with an unknown event logs once; `U.Utf8Cut` never splits a 2-, 3- or 4-byte character; `U.Hook` on a missing function returns false and logs nothing.
- **Tests:**
  - `spec/core_spec.lua` (unit): `On`/`Off`/`Emit`/`Listen` order and isolation; `Safe` return values and the error ring buffer (101 errors keep the last 100); `Coalesce` runs once; `AfterCombat` waits for `PLAYER_REGEN_ENABLED`; `R` and `RN` with secret values; `Utf8Cut` with "Minería" and 4-byte characters; `Hook` present and missing.
  - `spec/boot_spec.lua` (integration): boot the core; `ADDON_LOADED`, `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD` call each module hook once in load order; `/memories errors` shows a logged error; `wow.reload()` keeps `MemoriesDB.errors`.
- **Verify:** `make check-tools`, `make lint`, `make test`, `make coverage` (unverified: the targets do not exist yet). In the game: `make install WOW_DIR=".../_forever_"`, log in, `/mem`, `/mem errors`.
- **Definition of done:**
  - [x] Each Covers item is observably met, including one observation that failed before the task.
  - [x] Tests listed above exist and follow the Tests guidelines.
  - [x] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [x] E2E tests pass, or the accepted alternative from Risks is done.
  - [x] All three reviews pass with no valid open findings.
  - [x] Docs and config that describe the changed behavior are updated.
  - [x] Task heading checkbox ticked; changes committed.

### [x] 2. Journal storage: kinds, line codec, packed log, counts, snapshots
- **Outcome:** The core has a journal object that writes packed lines, counts and snapshots into `MemoriesCharDB`. 300,000 lines save and load under Lua 5.1.
- **Depends on:** 1 (module system, harness, serializer).
- **Covers:** AC8; risks "API text with | or line breaks" (codec part), "A character with an old name and a new GUID" (core part), "Saved data from a newer Memories" (core part).
- **Files:** `addons/Memories/Data/Kinds.lua`, `Data/Codec.lua`, `Data/Journal.lua`, `Data/Store.lua`; `spec/codec_spec.lua`, `spec/journal_spec.lua`, `spec/store_spec.lua`, `spec/limit_spec.lua`.
- **Implementation:**
  - **Kinds** (`ns.Kinds`): `Register(kind, spec)` with `spec = { addon, group, name, fields = { "name", "#npc", ... } }`. A `#` marks a numeric field. A duplicate kind asserts. `Get(kind)`, `All()`. `Describe()` returns `{ [kind] = "addon;group;field1,#field2,..." }` for `MemoriesDB.kinds`. Register the core kinds of the Kind catalog here, with the group names of the catalog.
  - **Codec:**
    - `Codec.Field(v)`: nil → `""`, `true` → `"1"`, `false` → `"0"`, other → `tostring(v)` with every `|` replaced by `/` and every control character (bytes 0–31 and 127) replaced by one space.
    - `Codec.EncodeLine(t, p, m, x, y, kind, ...)` joins the 6 columns and the fields with `|`. It drops trailing empty fields.
    - `Codec.DecodeLine(line)` returns `{ t, p, m, x, y, k, <named fields>, raw = { ... } }`, with numbers for the fixed columns and for `#` fields.
  - **Journal** (`ns.Journal.New(data, opts)`): `data` is one addon's character table. `opts = { addon, readOnly }`.
    - Data shape: `{ schema = 1, addon = "<addon>", writtenBy = "<version>", char = { guid, name, realm }, log = { chunks = {}, open = {} }, counts = {}, snap = {}, state = {} }`.
    - `j:Write(kind, ...)`: when `readOnly`, return nil, "read only". Assert that the kind is registered. Ask the kind gate `ns.KindOn(kind)` (a function that returns true until Task 5 replaces it); when off, return nil, "off". Stamp `t = ns.Journal.Now()` (`time()`), `p = ns.Store.PlayedNow()` (nil until Task 6 sets the played base), `m, x, y = ns.Position()` unless `IsInInstance()` is true. Append the line to `log.open`. When `#log.open` reaches 200, append `table.concat(log.open, "\n")` to `log.chunks` and start a new empty `open`. Emit `LINE_WRITTEN(addon, kind, line)`. Return the line.
    - `j:WriteAt(at, kind, ...)`: the same with `at = { t, p, m, x, y }` (any part may be nil; a missing `t` is now).
    - `j:Lines()`: an iterator over all lines in write order (chunks, then open). It splits one chunk at a time.
    - `j:LineCount()`: `#chunks * 200 + #open`, kept as `data.lines` and checked against the real count at load.
    - `j:Count(module, key, n)` adds `n` (default 1) to `data.counts[module][key]` and returns the value before the add. `j:Counts(module)` returns the live table. `j:IsFirst(module, key)` returns true when that count is 0 or nil.
    - `j:Snap(level, key, value)`: with a value it sets `data.snap[level][key]`; without one it returns it.
    - `j:CanWrite()`.
  - **Store** (core character data):
    - `ns.Store.Init()` runs on `PLAYER_LOGIN` before the modules' `OnLogin`. It opens `MemoriesCharDB` as the core journal `ns.Store.Core()`.
    - **Schema:** `ns.SCHEMA = 1`. Data with `schema > ns.SCHEMA` opens read-only and prints "Memories: saved data from a newer version; this addon will not write". `MemoriesDB.schema > ns.SCHEMA` makes all of Memories read-only.
    - **New GUID:** when `data.char.guid` exists and differs from `UnitGUID("player")`, move a copy of the old data to `MemoriesDB.orphans[#+1] = { t, guid, name, addon, data }`, then start a new empty data table. Write `nt|new character|<old guid>` in the new journal.
    - Core-only parts of `MemoriesCharDB`: `char` also has `surname, class, race, sex, faction, level, first = { t, level, played, m, x, y }` (set once); `sessions = {}`; `trail = { v = 1, chunks = {}, open = nil }`; `flags = {}`.
    - `ns.Store.SetPlayed(seconds)` and `ns.Store.PlayedNow()` (`floor(base + GetTime() - at)`).
    - At login, write `MemoriesDB.kinds = ns.Kinds.Describe()`.
- **Edge cases:** a field with `|`, `\n`, `\r` or `\0`; nil fields between set fields (kept as empty); trailing nil fields (dropped); a write while read-only; exactly 200, 201 and 400 lines (chunk edges); a load with a data table from an older empty install (`log` missing: create it); `data.lines` that does not match (recount); a write with an unregistered kind (assert, caught by `ns.Safe` in callers).
- **Tests:**
  - `spec/codec_spec.lua` (unit): encode and decode round trip for each field type; escaping of `|` and control characters; trailing empty fields dropped; numeric fields decoded as numbers.
  - `spec/journal_spec.lua` (unit): chunking at 200; `Lines()` order across chunks and `open`; `Count` returns the old value; `IsFirst`; `Snap`; read-only refuses writes; the kind gate refuses a write and leaves the counts; `LINE_WRITTEN` is emitted.
  - `spec/store_spec.lua` (integration with the harness): new GUID moves old data to orphans and writes `nt`; newer schema is read-only and prints one line; `MemoriesDB.kinds` holds the core kinds after login; `wow.reload()` keeps all lines.
  - `spec/limit_spec.lua` (integration): write 300,000 lines (short fields that differ in each line), serialize `MemoriesCharDB`, `loadstring` under Lua 5.1 succeeds and `Lines()` returns 300,000 lines in order. A control case: a table of 300,000 distinct plain strings fails `loadstring` with "constant table overflow" (this proves the test can detect the limit). Mark the spec with a busted tag `slow` if it takes more than 10 s.
- **Verify:** `make test-lua`, `busted spec/limit_spec.lua`, `make coverage-lua`, `make lint` (unverified).
- **Definition of done:**
  - [x] Each Covers item is observably met, including one observation that failed before the task.
  - [x] Tests listed above exist and follow the Tests guidelines.
  - [x] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [x] E2E tests pass, or the accepted alternative from Risks is done.
  - [x] All three reviews pass with no valid open findings.
  - [x] Docs and config that describe the changed behavior are updated.
  - [x] Task heading checkbox ticked; changes committed.

### [x] 3. Sub-addon registry and the public `Memories` global
- **Outcome:** A sub-addon can register, get its own journal in its own saved file and use core services. A test sub-addon works in both load orders.
- **Depends on:** 2 (journal, store, kinds).
- **Covers:** AC2, AC11; AC1 (sub-addon TOC rules); risks "`## Dependencies` load order", "A character with an old name and a new GUID" and "Saved data from a newer Memories" (sub-addon part).
- **Files:** `addons/Memories/Api/Registry.lua`, `addons/Memories/Api/Services.lua`; `spec/fixtures/addons/Memories_Test/Memories_Test.toc`, `spec/fixtures/addons/Memories_Test/Test.lua`; `spec/registry_spec.lua`; `docs/sub-addon-api.md`.
- **Implementation:**
  - **Global:** `Memories = { API_VERSION = 1, VERSION = "<toc version>" }`, created in the first core file so that it exists as early as possible.
  - **`Memories.RegisterModule(def)`** returns a handle, or `nil, reason`.
    - `def = { addon = "Memories_Combat", api = 1, saved = "MemoriesCombatCharDB", kinds = { { kind, group, name, fields } ... }, newOnly = { { key = "kills", label = "Kills: new findings only", kinds = { "ki" } } }, OnLogin = function(h) end, OnEnterWorld = function(h, isLogin, isReload) end }`.
    - Reasons: `"bad def"` (a missing `addon`, `saved` or `api`), `"newer api"` (`def.api > Memories.API_VERSION`; the core prints "Memories_X needs a newer Memories" once), `"twice"` (same addon again), `"kind taken"` (a kind already registered by another addon).
    - The core registers the kinds, then opens `_G[def.saved]` (it creates `{}` when nil and stores it back in `_G[def.saved]`) as the addon's journal with the same schema and new-GUID rules as Task 2.
    - Before `PLAYER_LOGIN`: the core keeps the def and opens it at login, after its own modules. After `PLAYER_LOGIN`: it opens it at once and calls `OnLogin` and `OnEnterWorld(false, false)`.
  - **Handle** (`h`), the only way a sub-addon reaches the core:
    - `h:On(event, fn)`, `h:Off(event, handle)`, `h:Listen(msg, fn)`; `fn` runs through the core's error guard, with `where = "<addon>:<event>"`.
    - `h:Hook(target, method, fn)` (`U.Hook`).
    - `h:Write(kind, ...)`, `h:WriteAt(at, kind, ...)` — only kinds that this addon registered, else assert.
    - `h:Count(module, key, n)`, `h:Counts(module)`, `h:IsFirst(module, key)`, `h:Snap(level, key, value)`.
    - `h:NewOnly(key)` returns the "New findings only" setting (false until Task 5).
    - `h:Here()` returns `{ t, p, m, x, y }` for now (Task 6 makes it use the trail's last point).
    - `h:Level()`, `h:InFight()` (true from `PLAYER_REGEN_DISABLED` until `PLAYER_REGEN_ENABLED`; the core owns this state), `h:InInstance()`.
    - `h:Fight()` returns the current or last fight `{ start, stop, casts, target }`: `casts` counts the player's `UNIT_SPELLCAST_SUCCEEDED` events between `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`, and `target` is the name of the first hostile target in that fight.
    - `h:Safe(where, fn, ...)`, `h:Print(...)`, `h:R(v)`, `h:RN(...)`, `h:Coalesce(key, delay, fn)`, `h:AfterCombat(key, fn)`, `h:SpellName(id)`, `h:Utf8Cut(s, n)`.
  - **Public messages** that a handle can `Listen` to: `LOGIN`, `LINE_WRITTEN(addon, kind, line)` (a decoded event table is given as a 4th argument, decoded once and shared), `FIGHT_START()`, `FIGHT_END(fight)`, and the messages that later tasks emit: `LEVEL_UP(level)`, `AWAY_CHANGED(isAway)`, `TRAIL_LIVE(m, x, y)` (Task 6), `DIED(info)`, `ALIVE(how)`, `LOW_HEALTH(inCombat)` (Task 7). A recorder that reacts to another recorder uses these messages, never `LINE_WRITTEN`, because a message fires even when the matching kind is off.
  - `Memories.Addons()` returns `{ { addon, state = "on" | "off" | "missing" | "failed" | "newer api", lines, readOnly } }`. It uses the registered defs and `C_AddOns.GetAddOnInfo` / `GetAddOnEnableState(name, UnitName("player"))` for the 5 known sub-addon names.
  - **Sub-addon TOC rule** (document it in `docs/sub-addon-api.md` and use it in the fixture): `## Interface: 16001`, `## Title: Memories - <Part>`, `## Dependencies: Memories`, `## Group: Memories`, `## SavedVariablesPerCharacter: Memories<Part>CharDB`, `## LoadSavedVariablesFirst: 1`, `## X-Memories-API: 1`, `## Version`.
  - **Missing core:** a sub-addon's first file checks `if not Memories or not Memories.RegisterModule then print("Memories_X: Memories is not loaded."); return end`. Put this pattern in the doc.
- **Edge cases:** registration before and after login; the sub-addon loads before the core (`order = "reverse"` in the harness: the global does not exist yet, so the guard prints and stops — the test asserts this message); a newer `api`; the same kind from two addons; the saved global is nil on first run; a sub-addon with a new-GUID data table; a sub-addon with newer schema data (read-only only for that addon).
- **Tests:** `spec/registry_spec.lua` (integration): boot core + `Memories_Test`; the test addon registers the test kinds `zz` and `zy` and writes them into its own saved global and none into `MemoriesCharDB`; `wow.reload()` keeps both; `LINE_WRITTEN` carries the addon name; the `InFight` state follows `PLAYER_REGEN_*`; each refusal reason; late registration after login calls `OnLogin`; `MemoriesDB.kinds` includes the test addon's kinds; `Memories.Addons()` states.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified).
- **Definition of done:**
  - [x] Each Covers item is observably met, including one observation that failed before the task.
  - [x] Tests listed above exist and follow the Tests guidelines.
  - [x] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [x] E2E tests pass, or the accepted alternative from Risks is done.
  - [x] All three reviews pass with no valid open findings.
  - [x] Docs and config that describe the changed behavior are updated.
  - [x] Task heading checkbox ticked; changes committed.

### [x] 4. Backups, data guard, save reminder, minimap button and compartment
- **Outcome:** Each addon's journal has a rolling backup. An empty journal with a backup triggers the data guard. The player gets a save reminder and a minimap button.
- **Depends on:** 3 (all journals known to the core).
- **Covers:** AC12 (backups, data guard), AC13 (minimap, compartment, save reminder, data guard popup); risk "A sub-addon file is damaged or empty".
- **Files:** `addons/Memories/Data/Backup.lua`, `addons/Memories/UI/Guard.lua`, `addons/Memories/UI/Save.lua`, `addons/Memories/UI/Minimap.lua`, `addons/Memories/UI/Slash.lua`; `spec/backup_spec.lua`, `spec/guard_spec.lua`, `spec/save_spec.lua`.
- **Implementation:**
  - **Backup** (`ns.Backup`):
    - `Write(addon)`: skip when the journal is read-only, held, or has 0 lines. Encode the data table with `C_EncodingUtil.SerializeCBOR`, then `CompressString(s, Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSpeed)` (the level only when the enum exists), then `EncodeBase64`. Store `MemoriesDB.backups[guid][addon] = { t, level, lines, blob }`. When `C_EncodingUtil` is missing or fails, store `data = U.Copy(data)` instead.
    - `Read(guid, addon)` reverses it. `Restore(addon)`: move the current data to `MemoriesDB.orphans` with `why = "restored backup"`, put the decoded data in the saved global, reopen the journal, write `nt|restored backup|<lines>`.
    - Schedule: every 15 minutes (`C_Timer.NewTicker`), on `LEVEL_UP`, and 5 s after login. Each run writes one addon per frame (`C_Timer.After(0, ...)`) to spread the cost, and never in combat (`ns.AfterCombat`).
  - **Data guard** (`UI/Guard.lua`): at login, for each journal with 0 lines while `MemoriesDB.backups[guid][addon].lines > 0`: set the hold for that addon (no backup write), and show a `StaticPopup` "Memories: <addon> came back empty. A backup from <date> has <n> lines." with buttons "Restore" (calls `Restore`, then asks for `/reload`) and "Start fresh" (clears the hold). While a hold is on, `PLAYER_LOGOUT` leaves the backup as it is.
  - **Save reminder** (`UI/Save.lua`): WoW writes saved files only at logout or reload. After 60 minutes without a save in this session, print "Memories: 1 hour since the last save. Click the minimap button to save (reloads the UI)." once, and make the minimap button pulse. Setting `saveReminder` (default true; Task 5 shows it). Reset on login.
  - **Minimap button** (`UI/Minimap.lua`): a 31×31 `Button` on `Minimap` with an icon and a border, dragged around the minimap edge, angle in `MemoriesDB.minimap.angle`. Left click: `C_UI.Reload()` (save) — never in combat (print "Memories: cannot save in combat."). Right click: open the Settings page (Task 5; until then, print the slash help). Tooltip: "Memories", the minutes since the last save, "Left click: save (reload)", "Right click: settings". Hidden when `minimapButton` is false.
  - **Compartment:** `Memories_OnAddonCompartmentClick(_, button)`: the same left and right click actions.
  - **`nt` kind:** write `nt|<what>|<detail>` for restored backup, new character and started fresh.
- **Edge cases:** no `C_EncodingUtil`; a blob that does not decode (log the error, keep the current data); a backup for a sub-addon that is now disabled (left as it is); restore while read-only (refused); a click in combat; a hold that is still on at logout.
- **Tests:** `spec/backup_spec.lua` (unit with the reversible encoder stub): write, read, restore round trip; skip rules; one addon per frame; `AfterCombat`. `spec/guard_spec.lua` (integration): empty core journal with a backup → popup shown, no new backup written, restore brings the lines back and writes `nt`; "Start fresh" clears the hold. `spec/save_spec.lua` (unit): reminder after 60 min, once; button click calls `C_UI.Reload` out of combat only; angle saved.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). Manual: add the data guard, minimap and save items to `docs/manual-checklist.md`.
- **Definition of done:**
  - [x] Each Covers item is observably met, including one observation that failed before the task.
  - [x] Tests listed above exist and follow the Tests guidelines.
  - [x] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [x] E2E tests pass, or the accepted alternative from Risks is done.
  - [x] All three reviews pass with no valid open findings.
  - [x] Docs and config that describe the changed behavior are updated.
  - [x] Task heading checkbox ticked; changes committed.

### [x] 5. Settings: kind toggles, new findings only, the Settings page and `/memories status`
- **Outcome:** The player turns any kind on or off, uses the group buttons and the new-only boxes, and sees the state of each addon.
- **Depends on:** 3 (registered kinds and new-only keys from all addons), 4 (settings shown for the save reminder and minimap).
- **Covers:** AC4, AC5, AC6 (settings part), AC13 (Settings page, `status`, `options`); risks "A disabled sub-addon records nothing" (status part), "Load time grows" (status part), "A Settings API helper behaves differently".
- **Files:** `addons/Memories/Data/Settings.lua`, `addons/Memories/UI/Options.lua`, `addons/Memories/UI/Status.lua`, `addons/Memories/UI/Slash.lua`; `spec/settings_spec.lua`, `spec/options_spec.lua`, `spec/status_spec.lua`.
- **Implementation:**
  - **Settings** (`ns.Settings`, account-wide in `MemoriesDB.settings`):
    - Keys and defaults: `kinds = {}` (a kind is off only when `kinds[kind] == false`), `newOnly = {}` (a key is on only when `true`), `recordRate = 2` (seconds; choices 1, 2, 5, 10; Task 6 reads it), `shots = { level = false, lastBoss = false }`, `saveReminder = true`, `minimapButton = true`, `lowHealthFlash = true` (Task 7 reads it).
    - `Get(path)`, `Set(path, value)` (emits `SETTING_CHANGED(path, value)`), `KindOn(kind)`, `SetKind(kind, on)`, `SetGroup(addon, group, on)`, `NewOnly(key)`.
    - Replace the Task 2 gate: `ns.KindOn = ns.Settings.KindOn`. The handle's `NewOnly(key)` reads `newOnly[key]`.
    - The `nt` kind is never gated.
  - **Settings page** (`UI/Options.lua`), built on `PLAYER_LOGIN` after all registrations (and again when a late sub-addon registers, by adding its section):
    - `Settings.RegisterVerticalLayoutCategory("Memories")`, then `Settings.RegisterAddOnCategory`.
    - Section "General": recording rate (dropdown 1/2/5/10 s), screenshot at level-up, screenshot at a dungeon's last boss, save reminder, minimap button, low-health flash.
    - For each addon in load order, and each group in catalog order: a section header `<Addon> — <Group>`, a button row "Enable all" / "Disable all" (`CreateSettingsButtonInitializer`) and one checkbox per kind (`Settings.RegisterAddOnSetting` with the variable table `MemoriesDB.settings.kinds`, key `<kind>`, type boolean, default true; label = the kind's name). Place each new-only box under its group: Gathering → `gathering`, Combat → `kills`, Loot → `loot`, Character → `consumables`.
    - Wrap the whole build in `ns.Safe`. On failure, `/memories options` prints "Memories: the settings page failed; see /memories errors".
    - `ns.Options.Open()` calls `Settings.OpenToCategory(category:GetID())`. The minimap right click and the compartment right click call it.
  - **Status** (`/memories status`): for each of the 6 addons, one chat line: `<addon>: on|off|missing|failed|newer api, <lines> lines, <n> kinds off, backup <age>`. Then a line with the login time from `ns.loginTime`.
  - **Slash:** `options` (alias `settings`), `status`.
- **Edge cases:** a setting key that is missing in old data (default used); a kind of an addon that is not loaded (no checkbox; its saved setting is kept); "Disable all" then "Enable all" leaves no `false` entries; the Settings API missing (the build fails safely).
- **Tests:** `spec/settings_spec.lua` (unit): defaults, `Set` emits, `KindOn`, `SetGroup`, the gate stops lines and keeps counts (with the test sub-addon from Task 3). `spec/options_spec.lua` (integration with the Settings stubs): one checkbox per registered kind, one button pair per group, the 4 new-only boxes under the correct groups, a late registration adds a section, a Settings stub that errors leaves `/memories options` with the error message. `spec/status_spec.lua`: the 6 lines with each state.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). Manual: add Settings page items to `docs/manual-checklist.md`.
- **Definition of done:**
  - [x] Each Covers item is observably met, including one observation that failed before the task.
  - [x] Tests listed above exist and follow the Tests guidelines.
  - [x] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [x] E2E tests pass, or the accepted alternative from Risks is done.
  - [x] All three reviews pass with no valid open findings.
  - [x] Docs and config that describe the changed behavior are updated.
  - [x] Task heading checkbox ticked; changes committed.

### [x] 6. Core recorders: Sessions, Trail, Progress
- **Outcome:** The core records sessions, /played, away state, the position trail, levels, experience, quests, discoveries and rested state.
- **Depends on:** 3 (handle services and messages), 5 (kind gate, `recordRate`).
- **Covers:** AC3 for `in`, `out`, `pl`, `gp`, `pc`, `af`, `lv`, `xp`, `qt`, `di`, `rs`; AC4 for these kinds; risk "Localized clients" (Progress chat patterns).
- **Files:** `addons/Memories/Record/Sessions.lua`, `Record/Trail.lua`, `Record/Progress.lua`, `Data/TrailCodec.lua`; `spec/sessions_spec.lua`, `spec/trail_spec.lua`, `spec/progress_spec.lua`.
- **Implementation:**
  - Follow Appendix A for every event, rule, count, snapshot, saved state and test case.
  - Trail data goes in `MemoriesCharDB.trail` with the chunk format in Appendix A ("Trail data format").
  - Sessions call `ns.Store.SetPlayed` when `TIME_PLAYED_MSG` arrives.
  - Each session entry also stores `tz`: the UTC offset of the client clock in seconds at login (local `date("*t", t)` against `date("!*t", t)`). The converter needs it to match screenshot file names, because these use local time.
  - Replace the Task 3 `h:Here()` with the trail's current point (Appendix A, "Interfaces offered").
  - Emit the public messages `LEVEL_UP(level)` (on `PLAYER_LEVEL_UP`, also when `lv` is off), `AWAY_CHANGED(isAway)` and `TRAIL_LIVE(m, x, y)`.
  - The `pc` line uses `MemoriesDB.computer`, a random id that the core makes once per install.
- **Edge cases:** all edge cases in Appendix A; `lv` off still emits `LEVEL_UP` and still takes the snapshot; a `/reload` writes `out` then `in|reload`; Spanish `GlobalStrings` values in the quest XP pattern.
- **Tests:** the test cases of Appendix A for Sessions, Trail and Progress, as unit tests with the harness; plus one kind-off test for each kind; plus a `wow.reload()` round trip of a trail with 3 chunks.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). In the game: `/dump LOOT_ITEM_SELF`-style checks for each `GlobalStrings` name that Progress uses (record each result in `docs/manual-checklist.md`).
- **Definition of done:**
  - [x] Each Covers item is observably met, including one observation that failed before the task.
  - [x] Tests listed above exist and follow the Tests guidelines.
  - [x] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [x] E2E tests pass, or the accepted alternative from Risks is done.
  - [x] All three reviews pass with no valid open findings.
  - [x] Docs and config that describe the changed behavior are updated.
  - [x] Task heading checkbox ticked; changes committed.

### [x] 7. Core recorders: Deaths and the low-health popup
- **Outcome:** The core records deaths, ghost runs, revivals, close calls, low-health warnings and hardcore deaths. The low-health popup keeps the game's low-health flash on.
- **Depends on:** 6 (trail last point, current level, `LEVEL_UP`).
- **Covers:** AC3 for `de`, `gh`, `al`, `cc`, `lh`, `hc`; AC4 for these kinds; AC13 (low-health popup).
- **Files:** `addons/Memories/Record/Deaths.lua`, `addons/Memories/UI/LowHealth.lua`; `spec/deaths_spec.lua`, `spec/lowhealth_spec.lua`.
- **Implementation:**
  - Follow Appendix B, sections "Deaths" and "Low-health popup".
  - Keep the open death, the death count of the current dungeon visit and the last recap in `data.state`, never in journal lines (see the guideline "Recorder state").
  - Emit the public messages `DIED(info)` (`info` has the fields of `de`), `ALIVE(how)` and `LOW_HEALTH(inCombat)`. Emit each message even when its kind is off.
  - The popup reads and writes the setting `lowHealthFlash` and the CVar `doNotFlashLowHealthWarning` (the only CVar Memories changes, and only on the player's click).
- **Edge cases:** all edge cases in Appendix B for these sections; `de` off still emits `DIED` and still counts.
- **Tests:** the test cases of Appendix B for Deaths and the low-health popup; one kind-off test for each kind; a test that `LOW_HEALTH` fires with `lh` off.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). Manual: add the death and popup items to `docs/manual-checklist.md`.
- **Definition of done:**
  - [x] Each Covers item is observably met, including one observation that failed before the task.
  - [x] Tests listed above exist and follow the Tests guidelines.
  - [x] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [x] E2E tests pass, or the accepted alternative from Risks is done.
  - [x] All three reviews pass with no valid open findings.
  - [x] Docs and config that describe the changed behavior are updated.
  - [x] Task heading checkbox ticked; changes committed.

### [x] 8. Screenshot service and the public API (`ex`, `sn`)
- **Outcome:** Every saved screenshot gets an `ss` line. Other addons record events and screenshot notes through the `Memories` global.
- **Depends on:** 5 (settings `shots.*`, kind gate), 6 (`LEVEL_UP`).
- **Covers:** AC9, AC10; risks "API text with | or line breaks" (API part), "Another addon floods the API".
- **Files:** `addons/Memories/Record/Screenshots.lua`, `addons/Memories/Api/Public.lua`; `spec/screenshots_spec.lua`, `spec/api_spec.lua`; `docs/public-api.md`.
- **Implementation:**
  - **Screenshots:** follow Appendix D, section "Screenshots (core)". The settings `shots.level` and `shots.lastBoss` are **off** by default (D10). The service offers `ns.Screenshots.Take(why, setting)` for Task 9 (last boss, `"shots.lastBoss"`) and the level-up shot; it takes no shot unless that setting is on. Ignore the appendix's rules about a simulated journal: Memories has no simulation mode.
  - **`Memories.RecordEvent(source, what, detail)`** → kind `ex` with fields `source, what, detail`.
  - **`Memories.RecordScreenshot(source, note, file)`** → kind `sn` with fields `source, note, file`. Call it after `SCREENSHOT_SUCCEEDED`. `file` is the caller's predicted file name.
  - **Input rules** (both calls):
    - A number becomes text with `tostring`. Any other type that is not a string is refused. A secret value is refused.
    - Limits in bytes, cut with `U.Utf8Cut`: `source` 40, `what` 100, `detail` 200, `note` 200, `file` 80.
    - `source`, `what` and `note` are required (not empty after a trim). `detail` and `file` are optional.
    - `file`, when given, must match `^WoWScrnShot_%d%d%d%d%d%d_%d%d%d%d%d%d%.%a%a%a%a?$`.
    - The codec then replaces `|` and control characters (Task 2).
  - **Rate limit:** 30 accepted calls per source in each 60 s window (`GetTime()` buckets). Drop buckets older than 2 minutes, so that the table does not grow.
  - **Return values:** `true`, or `false, reason` with reason one of `"not ready"` (before `PLAYER_LOGIN`), `"read only"`, `"off"` (the kind is turned off), `"bad source"`, `"bad what"`, `"bad detail"`, `"bad note"`, `"bad file"`, `"rate limit"`, `"error"` (an error inside the call, logged).
  - Every public function runs through the error guard and never raises into the caller.
  - `docs/public-api.md`: the calls, the rules, the reasons, and this example:
    ```lua
    if Memories and Memories.RecordScreenshot then
        Memories.RecordScreenshot("Paparazzi", "Level up, Boss kill", "WoWScrnShot_110626_140309.jpg")
    end
    ```
- **Edge cases:** a call before login; a call from inside an error handler; `nil`, a table, a function, a boolean and a secret as each argument; a 4-byte UTF-8 character at the cut; `|` and `\n` inside a note; 31 calls in one minute and a new call in the next minute; two sources at the limit at the same time; a screenshot taken by hand (`why` = "by hand"); `SCREENSHOT_FAILED`.
- **Tests:** `spec/api_spec.lua` (unit and integration): each reason; each limit; UTF-8 cut; escaping in the stored line; the rate limit and its reset; the bucket cleanup; `"off"` when `ex` or `sn` is off. `spec/screenshots_spec.lua`: the test cases of Appendix D "Screenshots (core)" with the settings off by default; the level-up shot only when `shots.level` is on.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). In the game: `/run print(Memories.RecordEvent("Test", "hello", "world"))` prints `true`; a PrintScreen key press makes an `ss` line (see `/memories status` line count).
- **Definition of done:**
  - [x] Each Covers item is observably met, including one observation that failed before the task.
  - [x] Tests listed above exist and follow the Tests guidelines.
  - [x] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [x] E2E tests pass, or the accepted alternative from Risks is done.
  - [x] All three reviews pass with no valid open findings.
  - [x] Docs and config that describe the changed behavior are updated.
  - [x] Task heading checkbox ticked; changes committed.

### [x] 9. Core recorders: Travel and Dungeons
- **Outcome:** The core records zones, loading screens, flights, boats, hearthstones, summons, portals, other teleports, mounts, dungeon and raid visits, boss fights and world bosses.
- **Depends on:** 6 (`TRAIL_LIVE`, trail last point), 7 (`ALIVE` for death teleports, the death count of a visit), 8 (`ns.Screenshots.Take(why, "shots.lastBoss")` for the last-boss shot).
- **Covers:** AC3 for `zo`, `sz`, `ld`, `le`, `tx`, `tl`, `bt`, `hs`, `so`, `su`, `po`, `jp`, `mo`, `ml`, `dn`, `dx`, `bo`, `wb`; AC4 for these kinds.
- **Files:** `addons/Memories/Record/Travel.lua`, `addons/Memories/Record/Dungeons.lua`, `addons/Memories/Data/Bosses.lua`; `spec/travel_spec.lua`, `spec/dungeons_spec.lua`.
- **Implementation:**
  - Follow Appendix B, sections "Travel" and "Dungeons", including the last-boss list in "Last-boss data (Bosses)".
  - The hook helper of Appendix B ("Hook utility (core)") is `U.Hook` from Task 1. Extend it only if the appendix needs more.
  - Keep the open dungeon visit, the world-boss dedupe, the learned-mount dedupe and the last zone in `data.state`, never in journal lines.
  - Replace the two English-only rules that Appendix B names (the tram zone name and the word "Riding") with id checks (map id and spell ids).
  - Ignore the Statistics-pane source of last bosses that works only in English. Use the built-in list.
- **Edge cases:** all edge cases in Appendix B for these sections; a teleport while `jp` is off; a boss kill with `shots.lastBoss` off (no shot).
- **Tests:** the test cases of Appendix B for Travel and Dungeons; one kind-off test for each kind; a Spanish zone name test.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). Manual: add flight, hearthstone, boat and dungeon items to `docs/manual-checklist.md`.
- **Definition of done:**
  - [x] Each Covers item is observably met, including one observation that failed before the task.
  - [x] Tests listed above exist and follow the Tests guidelines.
  - [x] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [x] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [x] Docs and config that describe the changed behavior are updated.
  - [x] Task heading checkbox ticked; changes committed.

### [ ] 10. Go converter `memories-export`
- **Outcome:** One command turns the saved files of every character into the `dist-characters/` folder layout, with screenshots and notes joined.
- **Depends on:** 2 (packed log format, `MemoriesDB.kinds`), 3 (one saved file for each addon), 6 (session `tz`), 8 (`ss` and `sn`).
- **Covers:** AC14; risks "Predicted screenshot file names are wrong by 1 s", "A disabled sub-addon records nothing" (converter part).
- **Files:** `cmd/memories-export/main.go`, `cmd/memories-export/main_test.go`; `internal/savedvars/` (copy of Paparazzi's `lexer.go`, `parser.go`, `parser_test.go`, package path changed); `internal/journal/` (unpack and decode), `internal/export/` (merge, screenshots, write); `testdata/wow/...`.
- **Implementation:**
  - **CLI:** `memories-export --wow-dir <flavor dir> [--dist DIR] [--backup DIR] [--default ID]`. Defaults: `--dist ./dist-characters`, `--backup ./backups`. Exit code 2 for a usage error, 1 for a run error.
  - **Find files:** for each `WTF/Account/<account>/` (skip the folder named `SavedVariables`), read `SavedVariables/Memories.lua` (`MemoriesDB`). For each character folder `<realm>/<character>/SavedVariables/`, read `Memories.lua` (`MemoriesCharDB`) and each `Memories_*.lua` (global `Memories<Part>CharDB`). A character without `MemoriesCharDB.char.guid` is skipped with a message.
  - **Backup first:** copy every file it reads to `<backup>/<UTC stamp>/savedvariables/<flavor>/<path under WTF/Account>`.
  - **Decode:** `log.chunks` split on `\n`, then `log.open`. Split each line on `|`. Fields come from `MemoriesDB.kinds[kind]` (`"addon;group;f1,#f2"`): a `#` field becomes a number; empty fields are left out; values past the known fields go into `extra` (`{"<index>": "<text>"}`). An unknown kind keeps all values in `extra`.
  - **Record shape (`journey.jsonl`, one JSON object per line):** `t`, `p`, `m`, `x`, `y`, `k`, `addon`, the named fields at the top level, `session` (1-based index of the session that contains `t`, else null), `screenshot` (`"screenshots/<file>"` when a file was matched), `notes` (`[{"source", "note"}]`, only on `ss` records). Sort by `t`, stable: the core first, then the sub-addons in name order, each in log order.
  - **Join `sn` with `ss`:** for each `sn`, take the `ss` with the same `file`; else the nearest `ss` with `|Δt| <= 2` that no other `sn` took. On a match, add the note to that `ss` and drop the `sn` record. A tie or no match keeps the `sn` record as it is.
  - **Match screenshot files** in `<flavor>/Screenshots/`: the exact `file` name first; else the nearest unclaimed `WoWScrnShot_*` file whose name time is within ±2 s of `t`. The name time is local time: convert with the session's `tz`. Skip a tie. Copy a matched file to `<dist>/<id>/screenshots/` and to `<backup>/<stamp>/screenshots/` when it is not there yet.
  - **`trail.jsonl`:** one record per trail chunk, `{s, t, m, n, pts: [[time, x, y, flags], ...]}` with absolute times.
  - **`character.json`:** the core `char` table, `region`, `realm`, `realmLabel`, `flavor`, `sessions`, `flags`, and `addons: { "<addon>": { counts, snap, schema, writtenBy } }`.
  - **`index.json`:** `default_character` (the `--default` value, else the earlier choice, else the character played last) and `characters: [{ id, guid, name, region, realm, flavor, class, race, sex, faction, level, path, journey, trail, character, steps, sessions, trailPoints, screenshots, addons, start, end }]`.
  - **Character id:** the same rule as `sync_journeys.py` (see Current State).
  - **Keep earlier runs:** read the old `journey.jsonl` and `trail.jsonl`. Make a multiset union: a record is the same when its JSON without `session`, `screenshot` and `notes` is the same.
  - **Never** run Lua, write into `WTF/` or `Screenshots/`, or change a source file.
- **Edge cases:** a missing sub-addon file (its addon is absent from `addons`); a damaged saved file (report the file and line, skip that file, continue); a line with fewer than 6 columns (skipped and counted in the summary); a field that is not a number in a `#` field (kept as text in `extra`); two `sn` for one `ss`; an `sn` with no `ss`; a screenshot tie; two characters with the same name on two realms; a second run with no new data (output unchanged).
- **Tests:** Go unit tests for each package (≥ 80 % for `internal/...`): the parser (copied tests); chunk unpack; decode with kinds; the `sn`/`ss` join cases; file matching with time zones and ties; the union merge; the id rule with accents ("Neral-Brumamar", "Ñandú"). `cmd/memories-export/main_test.go`: run on `testdata/wow` (a fixture with a core file, two sub-addon files, an account file and 3 screenshot files); compare the output with expected files; check that the SHA-256 of every input file is the same after the run.
- **Verify:** `make lint-go`, `make test-go`, `make coverage-go`, `make build`, `make export WOW_DIR=testdata/wow` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 11. Sub-addon `Memories_Gathering`
- **Outcome:** Gathering, fishing, opening and pick pocket are recorded in their own saved file.
- **Depends on:** 3 (registry), 5 (kind gate, `newOnly`).
- **Covers:** AC3 for `ga`, `fs`, `op`, `pp`; AC6 and AC7 for `ga` and `fs`; risk "Localized clients".
- **Files:** `addons/Memories_Gathering/Memories_Gathering.toc`, `addons/Memories_Gathering/Gathering.lua`; `spec/gathering_spec.lua`.
- **Implementation:**
  - TOC per the sub-addon rule (Task 3), saved global `MemoriesGatheringCharDB`.
  - Register the kinds `ga`, `fs`, `op`, `pp` in group "Gathering", and the new-only key `gathering` for `ga` and `fs`.
  - Follow Appendix D, section "Gathering", for every rule. With `h:NewOnly("gathering")` off, write a line for every gather and catch. With it on, write a line only when `h:Count(...)` returned 0 for that item (first) or when the item is rare.
  - Memories_Gathering owns all gathering counts (Appendix D, "Count ownership").
  - Spell names come from spell ids with `h:SpellName(id)`; nothing matches English names.
- **Edge cases:** all edge cases in Appendix D for Gathering; the same item twice with new-only on (one line, count 2); new-only turned on after 10 gathers (no line for those items, because their counts are above 0).
- **Tests:** the test cases of Appendix D for Gathering, with Spanish spell names in at least one; kind-off tests; new-only on and off tests.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). Manual: mine a vein, fish, pick a pocket on the esES client.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 12. Sub-addon `Memories_Combat`
- **Outcome:** Kills, rare kills and long fights are recorded in their own saved file, in instances too.
- **Depends on:** 3 (registry, `InFight`), 5 (kind gate, `newOnly`), 7 (`LOW_HEALTH`, `DIED`).
- **Covers:** AC3 for `ki`, `ra`, `fi`; AC6 and AC7 for `ki`.
- **Files:** `addons/Memories_Combat/Memories_Combat.toc`, `addons/Memories_Combat/Combat.lua`; `spec/combat_spec.lua`.
- **Implementation:**
  - TOC per the sub-addon rule, saved global `MemoriesCombatCharDB`.
  - Register `ki`, `ra`, `fi` in group "Combat", and the new-only key `kills` for `ki`.
  - Follow Appendix C, section "Combat". `ki` has the added last fields `inst` and `first` (see the Kind catalog).
  - The fight's cast count comes from the core fight state (`h:Fight()`, Task 3).
  - Count every kill in `kills.total`. Count instance kills also in `kills.inst`. (This replaces the appendix's "open world only" idea.)
- **Edge cases:** all edge cases in Appendix C for Combat; a kill while `ki` is off (no line, counts change, `ra` still written for a rare).
- **Tests:** the test cases of Appendix C for Combat; kind-off tests; new-only tests (first kill per NPC id, elite, rare).
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). Manual: kill in the open world and in a dungeon.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 13. Sub-addon `Memories_Economy`
- **Outcome:** Loot, group rolls, gear, money, trainers, auction house, mail and trade are recorded in their own saved file.
- **Depends on:** 3 (registry, `Hook`), 5 (kind gate, `newOnly`).
- **Covers:** AC3 for `lo`, `rl`, `ge`, `eq`, `mn`, `tb`, `ah`, `ma`, `tr`; AC6 and AC7 for `lo`; risk "Localized clients".
- **Files:** `addons/Memories_Economy/Memories_Economy.toc`, `addons/Memories_Economy/Loot.lua`, `addons/Memories_Economy/Money.lua`; `spec/loot_spec.lua`, `spec/money_spec.lua`.
- **Implementation:**
  - TOC per the sub-addon rule, saved global `MemoriesEconomyCharDB`.
  - Register `lo`, `rl`, `ge`, `eq` in group "Loot" and `mn`, `tb`, `ah`, `ma`, `tr` in group "Money". New-only key `loot` for `lo`.
  - Follow Appendix C, sections "Loot" and "Money". `lo` has the added last field `first`. Loot and Money call each other through their interfaces inside this addon (Appendix C, "Interfaces").
  - Apply the 2 s dedupe of Appendix C for an item seen both as a loot chat line and as mail or trade.
- **Edge cases:** all edge cases in Appendix C for Loot and Money; money change while `mn` is off (counts change).
- **Tests:** the test cases of Appendix C for Loot and Money; Spanish `GlobalStrings` loot lines; kind-off tests; new-only tests for `lo`.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). In the game: `/dump` each `GlobalStrings` name that Loot and Money use, and record the result in `docs/manual-checklist.md`.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 14. Sub-addon `Memories_Character`
- **Outcome:** Skills, spells, recipes, talents, consumables, tamed pets, reputation, accepted quests, home changes, flight paths and books are recorded in their own saved file.
- **Depends on:** 3 (registry, `InFight`), 5 (kind gate, `newOnly`).
- **Covers:** AC3 for `sk`, `lr`, `rc`, `ta`, `cu`, `pt`, `rp`, `qa`, `hb`, `fp`, `bk`; AC6 for `cu`; risk "Localized clients".
- **Files:** `addons/Memories_Character/Memories_Character.toc`, `addons/Memories_Character/Character.lua`, `addons/Memories_Character/Milestones.lua`; `spec/character_spec.lua`, `spec/milestones_spec.lua`.
- **Implementation:**
  - TOC per the sub-addon rule, saved global `MemoriesCharacterCharDB`.
  - Register `sk`, `lr`, `rc`, `ta`, `cu`, `pt` in group "Character" and `rp`, `qa`, `hb`, `fp`, `bk` in group "Milestones". New-only key `consumables` for `cu`.
  - Follow Appendix D, sections "Character" and "Milestones". Screenshots are not part of this addon (Task 8 owns them).
  - Profession names come from skill-line ids (`C_TradeSkillUI.GetTradeSkillDisplayName`) and spell names from spell ids (Appendix D tables).
  - `rp` writes a line for each change of the reputation value, with the standing (1 Hated … 8 Exalted) and its label in separate fields (Appendix D).
- **Edge cases:** all edge cases in Appendix D for these sections; a Spanish profession name ("Minería", "Primeros auxilios").
- **Tests:** the test cases of Appendix D for Character and Milestones; kind-off tests; new-only tests for `cu`.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). Manual: learn a spell, raise a profession, gain reputation on the esES client.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 15. Sub-addon `Memories_Social`
- **Outcome:** Group members, the own guild, enemy players, PvP kills and deaths, honor, duels, battlegrounds and PvP rank are recorded in their own saved file.
- **Depends on:** 3 (registry), 5 (kind gate), 7 (`DIED` message).
- **Covers:** AC3 for `gj`, `gl`, `gu`, `ep`, `pk`, `hk`, `du`, `bg`, `rk`; risk "Localized clients".
- **Files:** `addons/Memories_Social/Memories_Social.toc`, `addons/Memories_Social/Social.lua`, `addons/Memories_Social/PvP.lua`; `spec/social_spec.lua`, `spec/pvp_spec.lua`.
- **Implementation:**
  - TOC per the sub-addon rule, saved global `MemoriesSocialCharDB`.
  - Register `gj`, `gl`, `gu` in group "Social" and `ep`, `pk`, `hk`, `du`, `bg`, `rk` in group "PvP".
  - Follow Appendix E. PvP reacts to the core's `DIED` message, not to journal lines. The player memory of Social is an interface inside this addon.
  - Build the honor and duel patterns from `GlobalStrings` (Appendix E names them; they are not verified, so check each one in the game and record it in `docs/manual-checklist.md`).
- **Edge cases:** all edge cases in Appendix E; `de` off in the core (PvP still gets `DIED`).
- **Tests:** the test cases of Appendix E; kind-off tests; a Spanish duel line.
- **Verify:** `make test-lua`, `make coverage-lua`, `make lint` (unverified). Manual: join a group, duel a player.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 16. Documentation and the manual checklist in the game
- **Outcome:** The README explains install, settings, the API and the converter. The full manual checklist passes in the game.
- **Depends on:** 1–15.
- **Covers:** AC1 (in the game), AC13 (in the game); risk "No e2e suite".
- **Files:** `README.md`, `docs/manual-checklist.md`, `docs/kinds.md` (generated from `MemoriesDB.kinds` or written from the Kind catalog), `docs/sub-addon-api.md`, `docs/public-api.md`.
- **Implementation:**
  - README: what Memories is; the 6 addons and what each records; install (`make install WOW_DIR=...`); settings; the public API (link); the converter (`make build`, `memories-export --wow-dir ...`); the `make` targets.
  - Run every item in `docs/manual-checklist.md` on the Forever client (esES), with all 6 addons on, then with `Memories_Combat` off. Record the date, the client build and pass or fail for each item. Fix each failure in the task that owns it before you close this task.
  - The checklist includes at least: the AddOn list shows the 6 addons as one group; a sub-addon does not load when `Memories` is disabled; each kind in the Kind catalog appears in the saved files after the matching action; a kind turned off writes no line; the group buttons; each new-only box; the data guard (empty a file by hand while the game is closed); the minimap button and compartment; the save reminder; the low-health popup; `/memories status` and `/memories errors`; a `/run Memories.RecordEvent(...)` call; the converter on the real install.
- **Edge cases:** a failure that needs a change in a closed task: reopen that task's checkbox, fix it there with its tests, then return here.
- **Tests:** none new. All suites pass.
- **Verify:** `make lint test coverage build`; the filled checklist.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

## Validation

Run after the last task.

1. `make check-tools && make lint && make test && make coverage && make build` pass.
2. `busted spec/limit_spec.lua` passes (300,000 lines load).
3. In the game (Forever, esES), with all 6 addons enabled, play 30 minutes: kill creatures in the open world and in a dungeon, loot, mine, fish, take a flight, use a hearthstone, level up, die once, take a screenshot by hand, and run `/run Memories.RecordEvent("Test", "validation", "ok")`. Then `/reload`.
4. `/memories status` shows 6 addons on, with lines in each.
5. Each saved file holds only its own kinds: `grep -c '|ki|' .../SavedVariables/Memories_Combat.lua` is above 0, and `grep -c '|ki|' .../SavedVariables/Memories.lua` is 0.
6. Turn off `ki` and kill a creature: no new `ki` line, and `kills.total` goes up.
7. Turn on "Kills: new findings only" and kill the same creature twice: one line at most.
8. Disable `Memories` in the AddOn list: no sub-addon loads.
9. `build/memories-export --wow-dir ".../_forever_"` writes `dist-characters/` with the character, its screenshots, and an `ex` record with `source = "Test"`. A second run changes nothing.
10. With Paparazzi changed by its own spec: a Paparazzi screenshot shows as one `ss` record with a `notes` entry from source `Paparazzi`.

## References

- Blizzard UI source, branch `forever` (Interface 16001): https://github.com/Gethe/wow-ui-source/tree/forever
  - `Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua`, `ClientDocumentation.lua` (`Screenshot`), `VideoDocumentation.lua` (`SCREENSHOT_*`), `EncodingUtilDocumentation.lua`, `SpellDocumentation.lua`, `ReputationInfoDocumentation.lua`, `TradeSkillUIDocumentation.lua`.
  - `Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua`, `Blizzard_SettingControls.lua`.
  - `Interface/AddOns/Blizzard_AddOnList/AddonList.lua:450` (`## Group`).
- Lua 5.1 constant limit (`MAXARG_Bx` = 262,143 constants per function): https://www.lua.org/source/5.1/lopcodes.h.html
- Template repo: `~/Code/wow-addon-paparazzi` (Makefile, CI, harness, `internal/savedvars`, `internal/export/match.go`).
- busted 2.3.0: https://lunarmodules.github.io/busted/ ; luacov 0.17.0; luacheck 1.2.0; StyLua 2.6.0.
- Paparazzi follow-up spec: `~/orca/workspaces/wow-addon-paparazzi/memories-screenshots/specs/2026-11-06-memories-screenshot-notes.md`.

## Open Decisions

- **OD1 — License of Memories.** Not chosen. Impact: Task 10 copies `internal/savedvars` from Paparazzi (GPL-3.0-or-later), so a GPL-compatible license is needed before the repo is published. Until a choice exists, add no `LICENSE` file and do not publish.
- **OD2 — Release and CurseForge packaging.** Not chosen. Impact: no `.pkgmeta`, release workflow or `release-*` targets in this spec. A multi-folder package needs `move-folders` for the 6 addons.
- **OD3 — Website reader.** The website (a future spec in this repo) must read the new JSONL shape of Task 10.

## Appendix A — Core recorders: Sessions, Trail, Progress

Behavior description. The Appendices rules in the Implementation guidelines apply.
Journal lines are `t|p|m|x|y|kind|field1|...`:

- `p` is empty until the game has answered /played once this load.
- `m`, `x`, `y` (y grows downward) are empty inside instances and on map types 0-2 (cosmic, world, continent).
- `|` in field text becomes `/`. Booleans are `1`/`0`. Trailing empty fields are dropped.

Shared rules for all three recorders:

- **Secret values** (`issecretvalue`) count as "not known". Never compare, store or key on them.
- **Kind switched off**: no line, but counts, snapshots and saved state still update.
- **Read-only data** (saved data failed to load): record nothing.
- **/played estimate**: last answer plus `GetTime()` seconds since it, rounded down.

---

### Sessions

Logins, reloads, logouts, /played, crash gaps, AFK/idle, computer id, realm rules.

#### Events and hooks

- `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)`: first one of a load only.
- `PLAYER_LOGOUT`: logout and reload, just before the save.
- `RequestTimePlayed()` → `TIME_PLAYED_MSG(total, levelSeconds)`; `CHAT_FRAMES` to mute the chat print.
- `PLAYER_FLAGS_CHANGED(unit)` + `UnitIsAFK("player")`.
- `UNIT_SPELLCAST_SUCCEEDED` (unit `player`), `PLAYER_REGEN_DISABLED`: activity.
- `C_GameRules.IsHardcoreActive()`, `C_GameRules.IsSelfFoundAllowed()`: read once at login.

#### Kinds written

| kind | when | fields |
|---|---|---|
| `in` | first entering-world event of a load | `how`: `login` or `reload` |
| `pc` | right after `in`, only when `how` is `login` | `computer`: the account's computer id |
| `out` | `PLAYER_LOGOUT` | none |
| `pl` | a /played answer that the addon asked for at login or after a level-up | `played`: total /played seconds |
| `gp` | first /played answer of a load, when time is missing | `seconds`: missing /played seconds; `lastSave`: unix time of the previous session's last known moment |
| `af` | the AFK flag changes | `on`: `1` flagged AFK, `0` back |

#### Counts

None. Trail counts AFK and idle time.

#### Snapshots per level

None. Each /played answer goes to Progress (`played` snapshot).

#### Saved state outside the journal

- **Computer id** (account): 6 random lowercase hex digits, made once.
- **Sessions list** (character), one entry per load: `start` and `last` (unix times), `how`, `computer`,
  `played0` (/played at load start, set once, rounded down), `played1` (latest /played).
- **Character flags**: `hardcore`, `selfFoundAllowed` (true/false).

#### Rules and edge cases

1. A load is a login when `isInitialLogin` is true. It is a reload when `isReloadingUi` is true and
   `isInitialLogin` is not. Later entering-world events (zone changes, instances) are ignored.
2. Ask /played 3 s after login.
3. Quiet ask: unregister `TIME_PLAYED_MSG` on each `CHAT_FRAMES` frame that has it. Re-register 0.5 s after the
   answer, or 10 s after the ask if no answer comes. Do not mute again while frames are muted.
4. Each ask has a reason (`login`, `ding`, `dev`) used by the next answer only. `login`/`ding` write `pl`. `dev` only
   sets the estimate. An answer with no reason (typed /played) writes no `pl`.
5. Every answer: set the estimate and `played1`, set `played0` if unset, pass total and level seconds to Progress.
6. Gap check, first answer of a load only. "/played at login" = total minus seconds since load start. First ask
   Progress to catch up levels. Then, if the previous entry has `played1` and the difference is **over 120 s**,
   write `gp`. Both are placed at the session `start` with `p` = /played at login. Clean reloads lose 3-6 s.
7. Every 60 s, the running entry's `last` becomes now and `played1` becomes the current estimate.
8. On logout: write `out`, set the running entry's `last` to now and `played1` to the current estimate.
9. AFK flag change (not secret): write `af`, re-check away state. Clearing AFK counts as activity.
10. Away state: `afk` (flag on), `idle` (no activity for **120 s**), or none. Activity = moving, casting, combat
    start, jumping, flying on a taxi. Notify listeners on each change.
11. If saved data is restored from a backup mid-play, add the running entry to the new list if missing.
12. Rule flags are set only when the API exists and the answer is not secret.

#### Interfaces offered

- **Current session**: the running entry.
- **Request played(reason)**: the quiet ask (Progress uses `ding`).
- **Mark active** / **Away state** (`afk`, `idle`, none) / **Check away** (notify on change; Trail calls it each tick).
- **Played now**: the /played estimate, stamped into every line's `p`.

Needs from others: **Trail "here"** (current time, /played and position); **Progress catch-up levels**;
**Progress note played**.

#### Test cases

1. Given a fresh login (`isInitialLogin` true), when the first entering-world fires, then `in|login` and
   `pc|<id>` are written and a new session entry with `how=login` exists.
2. Given a reload (`isInitialLogin` false, `isReloadingUi` true), then `in|reload` is written and no `pc`.
3. Given a second `PLAYER_ENTERING_WORLD` in the same load, then nothing is written.
4. Given the previous entry has `played1=1000` and the first answer is 1500 with 20 s since load start, then
   `gp|480|<prev.last>` is written at the session start time with `p=1480`.
5. Given the same but answer 1105 with 2 s elapsed (gap 103 s), then no `gp` is written.
6. Given an ask with reason `login`, when the answer comes, then `pl|<total>` is written and muted chat frames are
   re-registered 0.5 s later.
7. Given `UnitIsAFK` returns a secret, then no `af` line and the away state is unchanged.
8. Given `PLAYER_LOGOUT`, then `out` is written and the entry's `last` and `played1` are updated.

---

### Trail

Outdoor position sampler: route chunks, time by activity and mode, distance, jump presses.

#### Events and hooks

- A repeating timer every `recordRate` seconds (the sample tick).
- `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition`: map position (x, y × 10000, rounded).
- `C_Map.GetMapInfo(map).mapType`: types 0-2 are skipped (stale for ~20 s after loading). Cache per map.
- `UnitPosition("player")`: world yards and instance id.
- Flag reads: `UnitOnTaxi`, `IsFlying`, `IsMounted`, `UnitIsGhost`, `UnitIsDead`, `IsSwimming`,
  `InCombatLockdown`, `IsInInstance`, `IsPlayerMoving`.
- `LOADING_SCREEN_ENABLED`, `LOADING_SCREEN_DISABLED`, `PLAYER_LOGOUT`, `PLAYER_ENTERING_WORLD`.
- `hooksecurefunc("JumpOrAscendStart", ...)`: jump presses. Install once per load (never remember it in saved data).

#### Kinds written

None. Trail writes chunks and counts.

#### Counts (module: key = value)

- `activity`: `<act>` and `<act>:<level>` = seconds. Acts: `afk`, `dead`, `dungeon`, `combat`, `travel`, `town`.
- `move`: `sec` = all sampled seconds; `moving` = seconds moving; `<mode>` and `<mode>:<level>` = seconds moving
  in that mode. Modes: `foot`, `ride`, `swim`, `ghost`, `fly`, `boat`.
- `distance`: `<mode>` and `<mode>:<level>` = yards, whole numbers.
- `travel`: `jumps` and `jumps:<level>` = jump presses; `ascend` = the same key pressed while swimming or flying.

`<level>` is the current level from Progress.

#### Snapshots per level

None (see `:<level>` count keys).

#### Saved state outside the journal

- **Trail chunks list** (per character): finished stretches.
- **Open copy** (per character): a copy of the open stretch, refreshed at most once a minute, marked as a copy.

#### Trail data format

A chunk is a record:

| field | meaning |
|---|---|
| `s` | start time (unix) of the session it belongs to (the latest session entry's `start`) |
| `t` | unix time of the first point |
| `m` | uiMapID of every point in the chunk |
| `n` | number of points |
| `d` | the points as text |
| `o` | `1` only on a chunk filed from the open copy (the logout step did not run) |

Points text: points are joined by `;`. Each point is `sec,x,y` or `sec,x,y,flags`.

- `sec`: whole seconds since the chunk's first point (rounded).
- `x`, `y`: map position, integers 0..10000.
- `flags`: written on the first point and whenever the flags change. A point without flags keeps the last flags.

Flag letters, always in this order, `-` when none:

| letter | meaning |
|---|---|
| `t` | on a taxi (flight path) |
| `f` | flying |
| `m` | mounted |
| `g` | ghost (spirit run) |
| `d` | dead at the corpse (only when not a ghost) |
| `w` | swimming |
| `c` | in combat (combat lockdown) |
| `i` | in an instance |

Example: `0,4512,6120,m;2,4530,6101;4,4560,6080,mc`.

Sample rate setting `recordRate`: seconds between ticks. Allowed values **1, 2, 5, 10**. Default **2**. Any other
value (not a number, or below 1) falls back to 2. Changing it restarts the timer at once.

#### Rules and edge cases

1. Tick seconds = time since last tick, rounded. Over `rate × 3 + 1` counts as 0 (stall).
2. Skip ticks during a loading screen.
3. Distance: straight yards between this and the last tick's world position, same instance id, seconds > 0.
   Rounded.
4. Teleport: if distance per second is **over 100 yd/s**, distance counts as 0 and the next point starts a new chunk.
5. Moving is true when `IsPlayerMoving` says so, or the distance is **over 0.5 yd**.
6. Moving, combat or taxi mark the player active for Sessions.
7. Activity per tick, first match wins: away (`afk`, from Sessions, both AFK and idle) → `dead` (ghost or dead) →
   `dungeon` (in instance) → `combat` → `travel` (moving or taxi) → `town`.
8. Mode when moving, first match wins: `fly` (taxi or flying) → `ride` (mounted) → `ghost` → `swim` → `boat`
   (over **15 yd/s**) → `foot`. Distance is added only when above 0.
9. A point is fed only outside instances and only with a known map position on a non-skipped map.
10. A chunk closes and a new one opens when: a teleport happened, the map changed, more than **60 s** passed since
    the last position, or the chunk holds **2,000** points.
11. Thinning: keep a point only if it is **3+ yards** (world position) from the last kept point. When yards are
    unknown, use **4 map units** instead. The first point is always kept. A point is also kept when the flags differ
    from the last kept flags.
12. On each kept point, refresh the open copy if 60+ s old, and notify listeners (map, x, y).
13. `LOADING_SCREEN_ENABLED`: close the open chunk, forget the last world position (no teleport across loads), pause.
    `LOADING_SCREEN_DISABLED`: resume, reset the tick clock. `PLAYER_ENTERING_WORLD`: forget the last world position
    and reset the tick clock.
14. `PLAYER_LOGOUT`: close the open chunk and clear the open copy. Closing an empty chunk adds nothing.
15. At login, a leftover open copy (logout step failed) is filed as a chunk if it has points, then cleared. Same
    for a restored backup's copy; the running stretch then writes its own copy into the new data.
16. Jump hook: mark active. If swimming or flying, count `travel.ascend`. Else count `travel.jumps` and
    `travel.jumps:<level>`.
17. Each tick ends by asking Sessions to check the away state, so idle is noticed within one tick.

#### Interfaces offered

- **Here**: `{t, p, m, x, y}` for now; position empty in instances and on skipped maps.
- **Is skipped map(m)**: true for map types 0-2.
- **Flags**: the flag letters right now.
- **Open stretch**: the open chunk as a finished record, or none.
- **Last point**: map, x, y and time of the last outdoor position fed (used for death spots).
- **Feed / Close**: add one position, or close the open chunk (for tests).

Needs from others: **level** from Progress (falls back to `UnitLevel`, then 1); **away state** and **mark active**
from Sessions; latest session `start` for chunk `s`.

#### Test cases

1. Given 2 s ticks with positions 1 yd apart and same flags, then only the first point is kept.
2. Given a mount-up with no movement, then a new point is kept with flag `m`.
3. Given 1,500 yards between ticks 2 s apart, then distance counts 0 and the next point starts a new chunk.
4. Given a map change, then the old chunk is filed and the new chunk has the new `m`.
5. Given a tick 30 s after the last at rate 2, then 0 seconds are counted.
6. Given mounted and moving 22 yd in 2 s, then `move.ride`, `move.ride:<lvl>`, `distance.ride` += 22.
7. Given in an instance, then activity `dungeon` is counted and no point is fed.
8. Given the jump hook fires while swimming, then `travel.ascend` += 1 and `travel.jumps` is unchanged.
9. Given an open copy in saved data at login, then it is filed as a chunk with `o=1` and cleared.

---

### Progress

Level-ups, XP gains by source, quest turn-ins, discoveries, the rested pool.

#### Events and hooks

- `PLAYER_LEVEL_UP(newLevel)`: use the argument. `UnitLevel` still reports the old level at this moment.
- `CHAT_MSG_COMBAT_XP_GAIN(text)`: XP text, never secret.
- `QUEST_TURNED_IN(questID, xp, money)` with `C_QuestLog.GetTitleForQuestID(questID)`.
- `CHAT_MSG_SYSTEM(text)`: "Discovered X: N experience gained".
- `UI_INFO_MESSAGE(type, message)`: "Discovered: X" without XP.
- `PLAYER_XP_UPDATE`, `UPDATE_EXHAUSTION` with `GetXPExhaustion()`: the rested pool.
- `GetRealZoneText()`, `IsInInstance()`, `GetInstanceInfo()`: level snapshots.
- Localized clients: build patterns from GlobalStrings `COMBATLOG_XPGAIN_FIRSTPERSON`,
  `COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED`, `ERR_ZONE_EXPLORED_XP`, `ERR_ZONE_EXPLORED` (drop the final period),
  then try English fallbacks. Group bonus: "(+N group bonus)". Strip thousands commas.

#### Kinds written

| kind | when | fields |
|---|---|---|
| `lv` | level-up, or a catch-up level | `level`: the new level |
| `xp` | each XP gain | `amount`; `src`: `kill`, `quest`, `discover` or `other`; `name`: creature name, quest title or area; `bonus`: group bonus XP |
| `qt` | quest turned in | `quest`: id; `xp`; `money`: copper; `title` |
| `di` | area discovered | `area`; `xp` (empty when none) |
| `rs` | at each login/reload, and when the pool drops to 0 | `rested`: rested pool in XP |

#### Counts

- `xp`: `all`, `<src>` = XP; `dungeon` = XP gained in an instance; `<cat>:<level>` where cat is `dungeon` inside an
  instance, else the source; `rested` = XP drawn from the rested pool.
- `progress`: `levels`, `quests`, `discoveries` = how many.

#### Snapshots per level (keyed by level number)

- `t`: unix time the level was reached.
- `zone`: real zone name at the ding. `inst`: instance name if inside one. `rested`: rested pool at the ding.
- `played`: /played seconds when this level began (= answer total − level seconds, rounded). Set only if missing.
- `gap`: `1` when the level was reached while nothing was recorded.

#### Saved state outside the journal

- Character record `level` (highest seen) and flag `dinged60` (set on reaching level 60 or more).

#### Rules and edge cases

1. Level-up: the level is the event's argument (or current + 1 if secret). Write `lv`, raise the character level,
   write snapshots, count `progress.levels`, then ask Sessions for /played with reason `ding`.
2. A big moment is every level divisible by 10.
3. Kill XP (named): write `xp` with `kill` at once.
4. Nameless XP: if a quest turn-in with the same XP happened within **2 s** and was not used yet, write `xp|quest`
   with its title. Else wait **1.5 s**. If a matching turn-in arrives in that time, it becomes `quest`. If not,
   write `other`. The `xp` line keeps the time of the chat text.
5. Quest turn-in: read the title. If missing, ask again after **2 s**, then write `qt` with or without it.
6. Discovery with XP: write `di`, count, then an `xp|discover` line named after the area. Remember the area and time.
7. Discovery without XP: wait **1.5 s**. Write `di` only if the same area was not recorded within **3 s**.
8. Rested: keep the last pool. When it drops, count `xp.rested` by the drop. When it drops to 0, write `rs|0`.
   A secret pool is ignored. At each load, write `rs` with the current pool.
9. Catch-up levels: the highest known level is the larger of the character's first-seen level and any snapshot level
   with `t`. If the game's level is higher (and the known level is above 0), write `lv` for each missing level, with
   snapshots `t` and `gap=1`. Run on the first /played answer (before the gap check) and after a backup restore.
10. XP amounts of 0 or less are ignored. Lines that do not parse are ignored.

#### Interfaces offered

- **Level**: the current level (from the last level-up event, else `UnitLevel`, else 1).
- **Note played(total, levelSeconds)**: sets the `played` snapshot for the current level.
- **Catch up levels(level, at)**: returns how many levels were added.
- **Known level**: highest level the journal has seen.
- **Parse XP(text)** → amount, name, bonus. **Parse discovery(text)** → area, xp.

Needs from others: **Trail "here"**; **Sessions request played**.

#### Test cases

1. Given "Kobold Vermin dies, you gain 45 experience. (+9 group bonus)", then `xp|45|kill|Kobold Vermin|9`.
2. Given "You gain 1,250 experience." then `QUEST_TURNED_IN(783, 1250, 0)` 0.1 s later, then one `xp|1250|quest|<title>`.
3. Given `QUEST_TURNED_IN(783, 1250, 0)` then the chat text 0.5 s later, then one `xp|quest` line.
4. Given the quest title is missing, then `qt` is written 2 s later with the title read again.
5. Given "Discovered Goldshire: 100 experience gained", then `di|Goldshire|100` and `xp|100|discover|Goldshire`.
6. Given "Discovered: Goldshire" within 3 s of a `di` for Goldshire, then nothing new is written.
7. Given `PLAYER_LEVEL_UP(12)` while `UnitLevel` returns 11, then `lv|12`, snapshot `t` for 12, and a `ding` /played ask.
8. Given known level 10 and `UnitLevel` 13 at the first /played answer, then `lv|11`, `lv|12`, `lv|13` with `gap=1`.
9. Given the rested pool goes 4000 → 3800 → 0, then `xp.rested` = 4000 and one `rs|0`.

## Appendix B — Core recorders: Deaths, Low-health popup, Travel, Dungeons

Behavior description. The Appendices rules in the Implementation guidelines apply.
Shared conventions for all four recorders:

- **Line**: `t|p|m|x|y|kind|fields...`. Position is the player's "here": uiMapID plus x,y 0..10000. Position is **empty** inside instances and when the best map is a world or continent map (type 0..2; the game reports these for about 20 s after a loading screen).
- **Secret values**: every game value is checked with `issecretvalue`. A secret value is never compared or saved. Where a name is required and it is secret, write `?`.
- **Gate**: a recorder writes only while the active journal accepts writes. Each line also goes through the kind setting. Kind off: no line, but counts still change.
- **Moment broadcast**: some writes announce "a moment happened" (journal, decoded line, flags) for UI and other recorders. Listed per recorder.
- **Debounce**: "debounce N s under key K" means each new call restarts one N-second timer; only the last call runs.
- **Kind off and line-based state**: in the source, some rules read earlier lines back (open dungeon visit, open death, dedupes). Memories must keep that state in its own saved fields, so the rules still work when a kind is off. Each case is flagged below.

---

### Deaths

#### Events and hooks

- `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST`.
- `C_DeathRecap.HasRecapEvents` / `C_DeathRecap.GetRecapEvents` (read 1 s after death).
- `CONFIRM_XP_LOSS` (spirit healer dialog), `RESURRECT_REQUEST` (payload: inviter name).
- Post-hooks: `AcceptResurrect`, `RetrieveCorpse`, `C_DeathInfo.UseSelfResurrectOption`.
- `ENCOUNTER_START` / `ENCOUNTER_END` (boss fight on or off), `LOADING_SCREEN_ENABLED` (clears the fight).
- `PLAYER_REGEN_ENABLED` (close-call settle), `CVAR_UPDATE` for `doNotFlashLowHealthWarning`.
- Name learning: `PLAYER_TARGET_CHANGED` (unit `target`), `UPDATE_MOUSEOVER_UNIT` (`mouseover`), `NAME_PLATE_UNIT_ADDED` (unit from payload).
- `LowHealthFrame` script hooks `OnShow` and `OnHide`.
- `UnitIsDeadOrGhost`, `UnitIsGhost`, `IsInInstance`, `GetInstanceInfo`, `UnitPosition` (world yards), `InCombatLockdown`, `UnitAffectingCombat`, `GetUIPanel("fullscreen")`, `C_CVar.GetCVar`.

#### Kinds written

| kind | when | fields |
|---|---|---|
| de | death confirmed 1 s after `PLAYER_DEAD`, or at login when dead and no death is open | killer (name; `?` if secret), npc (creature ID from GUID), spell (killing spell name), env (environmental type, lower case: falling, drowning, fatigue, fire, lava, slime), place (`world` or instance name), boss (1 if a boss fight was on or killer is a world boss), klevel, kclass (classification for creatures, class token for players), amount (killing blow damage), byPlayer (1 if recap GUID was another player), inst (`pvp` in battleground or arena) |
| hc | right after `de`, only on a Hardcore character | killer |
| gh | released spirit (became a ghost) | none |
| al | alive again | how (`corpse`, `spirit`, `res`, `soulstone`), by (res offerer name, only when how is `res`) |
| lh | low-health flash shown | combat (1 or 0) |
| cc | close call: the flash ended and the character lived | seconds (total flash time, rounded, min 1), combat (1 if any show was in combat) |

#### Counts (module `deaths`)

- `total`; one of `world`, `battleground` (inst is pvp), `dungeon` (any other instance).
- `player` (byPlayer), `env.<type>`, `boss`.
- `hardest`: highest killing-blow amount ever (max, not sum).
- `revive.<how>`, `lowHealth`, `closeCalls`.

#### Snapshots per level

None.

#### Saved state outside the journal

- Per character: **deathOpen** (true from `de` to `al`; set false at every login while alive).
- Per character: **lastRecap** (recap timestamp of the last recorded death; dedupes the same death across reloads).
- Journal flag **lowHealthFlash**: mirrors the CVar (true when the CVar is not `"1"`). Refreshed at login and on `CVAR_UPDATE` for that CVar.
- Memory only: creature name cache, player cache, close-call episode, revive marks, current boss fight.

#### Rules and edge cases

1. **Death start**. On `PLAYER_DEAD`: ignore if already in the dead state (double fire, or release). If `UnitIsDeadOrGhost` is false: wait 1 s; if not already dead and the game now says dead, start a death and write it at once. Else start a death.
2. **Starting a death** stores: position now (if outdoors with no map position, use the last trail point), place and inst, whether a boss fight is on, world position and instance ID, and clears all revive marks.
3. **Recap read, 1 s after**. Skip if this death was already written or a newer death replaced it. If the character is alive again with no revive seen: drop silently. Else write `de`.
4. **Killer from recap**: pick the entry with the highest `timestamp` (ties: later entry). Creature or Vehicle GUID: npc = 6th dash field. If the name cache knows that npc, use its plain name, level and classification. Player GUID that is not the player's own: byPlayer = 1, level and class from the player cache if seen. The player's own GUID is never a player killer.
5. **Dedupe**: recap timestamp > 0 and equal to saved lastRecap: no line. Otherwise save the new timestamp. No recap at all: write a bare `de` (place, boss, inst only).
6. **Boss** = a fight was on (between `ENCOUNTER_START` and `ENCOUNTER_END`, cleared by `LOADING_SCREEN_ENABLED`) or killer classification is `worldboss`.
7. **Release**. `PLAYER_ALIVE` while dead and `UnitIsGhost` true, first time: write `gh`. If the death line is still waiting for its 1 s read, flag it; `gh` is written right after `de`.
8. **Not a revive**: `PLAYER_ALIVE` while still dead and not a ghost. This fires after most loading screens and reloads.
9. **Revive** on `PLAYER_ALIVE` (not ghost, not dead) or `PLAYER_UNGHOST`. If the death line is still pending, write `de` first. Then `al`. Clear marks and dead state.
10. **How** (first match, times since the mark): soulstone (self-res hook) within 15 s; `res` if accept hook within 15 s, or offer within 90 s, or `PLAYER_ALIVE` without a ghost step; `spirit` if `CONFIRM_XP_LOSS` within 120 s; `corpse` if `RetrieveCorpse` within 30 s; `spirit` if more than 60 yd from the death spot in the same world instance; else `corpse`.
11. **by**: the `RESURRECT_REQUEST` inviter name, if not secret and not empty. Only written for `res`.
12. **Hardcore**: when the core says the character is Hardcore (`C_GameRules.IsHardcoreActive`), write `hc` with the killer after `de`.
13. **Login recovery** (after all recorders' login handlers). Real journal and character dead. Death is open if deathOpen is true. (Old saves without the flag: last `de` after last `al`.) If not open: write `de` from the recap if present, else bare. Position: empty inside an instance, else the last trail point (this session, else saved trail). Boss unknown. Then set deathOpen. Ghost with no `gh` since that death: write `gh`. A crash itself cannot be recovered.
14. **Name learning**: outdoors only (names are hidden inside instances). Creatures: per npc keep the **shortest** name seen, plus level and classification. Forever adds a stranger's surname in the recap; the shortest name is the plain one. Cap 1500 IDs (new IDs ignored after that). Players: GUID to name, level, class token. Cap 200, then clear all. `UnitGUID` can error on PvP-restricted units: count silently, no error popup. All memory only, so a death after a relog keeps the recap name.
15. **lh**: on flash show. Skip if dead or a fullscreen UI panel is open (the game flashes the edge in combat with such a window, for any health). combat = `InCombatLockdown` or `UnitAffectingCombat`.
16. **Close-call episode**: begins at the first show and keeps the start position and start journal. Each hide adds the shown time. Hide and `PLAYER_REGEN_ENABLED` both debounce 3 s into settle.
17. **Settle**: nothing if no episode or the flash is still shown. Wait (keep the episode) while `InCombatLockdown`. Drop if a `PLAYER_DEAD` came at or after the episode start, or the character is dead. Else write `cc` at the start position, into the start journal if it still accepts writes.
18. **Hook**: hook `LowHealthFrame` at login. If it is missing, retry once after 3 s. The "hooked" flag lives in memory only.
19. **Kind off**: deathOpen, lastRecap and "gh since this death" must come from saved state, not from lines.

#### Interfaces offered

- Moment broadcast for `de` (not big), `hc` (big, hardcore), `gh`, `al`, `cc`. Travel needs the `al` broadcast.
- State query: `{ dead, ghost }`.
- Needs from others: trail "here" and last trail point (live and saved); is-Hardcore flag; world position.

#### Test cases

1. Given alive, outdoors, recap entries ts 10 (wolf) and ts 12 (`Creature-0-1-2-3-4-525-x`, name "Mangy Wolf Smith"), cache knows 525 = "Mangy Wolf"; when `PLAYER_DEAD` and 1 s passes; then `de|Mangy Wolf|525|...|world|...`, counts total=1, world=1.
2. Given a death written with recap ts 50; when `PLAYER_DEAD` fires again with the same recap; then no second `de`.
3. Given dead; when `PLAYER_ALIVE` with `UnitIsGhost` false and still dead; then nothing.
4. Given dead, `RESURRECT_REQUEST("Anna")`; when `PLAYER_ALIVE` and alive; then `al|res|Anna`, count revive.res.
5. Given ghost, death spot 200 yd away in the same instance, no marks; when `PLAYER_UNGHOST`; then `al|spirit`.
6. Given dead 0.5 s ago, line pending; when `PLAYER_ALIVE` as ghost then 1 s timer; then `de` then `gh`, in that order.
7. Given flash shown 2.4 s out of combat; when hidden and 3 s pass alive; then `lh|0` earlier and `cc|2|0`.
8. Given flash shown then hidden; when `PLAYER_DEAD` within 3 s; then no `cc`.
9. Given flash hidden while `InCombatLockdown`; when 3 s pass; then no `cc`; when `PLAYER_REGEN_ENABLED` and 3 s pass; then `cc`.
10. Given login, dead ghost, deathOpen false, no recap; then bare `de` at last trail point, then `gh`, deathOpen true.
11. Given Hardcore; when a death is written; then `de` then `hc|<killer>`.
12. Given kind `de` off; when a death happens; then no line, counts total+1, deathOpen true.

---

### Low-health popup

Close calls rely on the game's low-health flash (player health is always secret). The flash is the account CVar `doNotFlashLowHealthWarning`: `"0"` = flash on (game default), `"1"` = off.

#### Events and hooks

- `CVAR_UPDATE` (name, value).
- First `PLAYER_ENTERING_WORLD` of the session.
- `C_CVar.GetCVar` / `C_CVar.SetCVar` (fall back to `GetCVar`/`SetCVar`).
- Calls from the addon's options and welcome page.

#### Kinds written

None.

#### Counts

None.

#### Snapshots per level

None.

#### Saved state outside the journal

- Addon setting **lowHealthFlash** (default on), mirrors the CVar.

#### Rules and edge cases

1. **Is on**: CVar value is not `"1"`. If the CVar cannot be read (error or secret), use the addon setting.
2. **Set(on)**: write CVar `"0"` (on) or `"1"` (off), ignoring the `CVAR_UPDATE` this causes. A failed write is logged, not shown. Then save the setting and hide the popup.
3. **Popup**: about 400 x 150 px, centered, 80 px above the middle, above other dialogs, takes the mouse. Gold title: "Memories needs this setting on". Body: Memories needs the low-health flash to record close calls; with it off, close calls are not counted. Buttons: "Keep it on" = Set(true); "Turn it off" = Set(false). Strings are localized.
4. **Shown when**: (a) the player unticks the option in the addon (nothing changes until a button is pressed); (b) `CVAR_UPDATE` turns the CVar off, not by us; (c) once per session at the first world entry, if the flash is off. Case (c) also saves the setting as off and waits until combat ends before showing.
5. `CVAR_UPDATE` that turns it on: save the setting as on, no popup.

#### Interfaces offered

- `IsOn()`, `Set(on)`, `RequestOff()`, `Ask()`, `Hide()`, `Shown()`.

#### Test cases

1. Given CVar `"1"` at the first world entry out of combat; then the popup shows and the setting is off.
2. Given the same in combat; then the popup shows only after `PLAYER_REGEN_ENABLED`.
3. Given popup shown; when "Keep it on"; then CVar `"0"`, setting on, popup hidden, no popup from the echo `CVAR_UPDATE`.
4. Given flash on; when `CVAR_UPDATE("doNotFlashLowHealthWarning","1")` from the game; then the popup shows.
5. Given `GetCVar` errors and setting off; then `IsOn()` is false.

---

### Travel

#### Events and hooks

- Zones: `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `PLAYER_ENTERING_WORLD`; `GetRealZoneText` (fallback `GetZoneText`), `GetSubZoneText`, `C_Map.GetMapInfo`.
- Loading: `LOADING_SCREEN_ENABLED`, `LOADING_SCREEN_DISABLED`.
- Casts: `UNIT_SPELLCAST_SUCCEEDED` (unit `player`), `GetBindLocation`.
- Summons: `CONFIRM_SUMMON`, `CANCEL_SUMMON`, `C_SummonInfo.GetSummonConfirmSummoner`, `GetSummonConfirmAreaName`, post-hook `C_SummonInfo.ConfirmSummon`.
- Flights: `TAXIMAP_OPENED`, `NumTaxiNodes`, `TaxiNodeGetType` (`"CURRENT"`), `TaxiNodeName`, `TaxiNodeCost`, fallback `C_TaxiMap.GetAllTaxiNodes` with `Enum.FlightPathState.Current`; post-hook `TakeTaxiNode(slot)`; `PLAYER_CONTROL_GAINED`; `UnitOnTaxi`.
- Mounts: `PLAYER_MOUNT_DISPLAY_CHANGED`, `IsMounted`, `C_MountJournal.GetMountFromSpell`, `GetMountInfoByID`, `GetMountIDs`, `C_Spell.GetSpellName`; `NEW_MOUNT_ADDED`; `CHAT_MSG_SKILL`, `CHAT_MSG_SYSTEM` with GlobalString `ERR_SKILL_GAINED_S`.
- Positions: the trail sampler's "live position" message; `UnitPosition` world yards and instance ID; `UnitIsDead`, `UnitIsGhost`.
- The core moment broadcast for `al`.

#### Kinds written

| kind | when | fields |
|---|---|---|
| zo | zone name changed | zone |
| sz | subzone changed, outside instances | sub |
| ld | loading screen start | spell (own cast in last 15 s), taxi (1 if on a taxi) |
| le | loading screen end, after an `ld` | none |
| tx | flight taken | from node, to node (`?` if unknown), cost (copper) |
| tl | flight landed | at (destination node name; empty after a mid-flight reload) |
| bt | boat or zeppelin | fromMap, toMap, from, to (subzone, else zone) |
| hs | Hearthstone arrival | fromMap, toMap, to (bind location, else place after), yards |
| so | summon offered | who, area |
| su | summon arrived | who, area, fromMap, toMap, yards |
| po | mage teleport or portal | dest (zone after), fromMap, toMap, spell (empty for a portal from another mage), yards |
| jp | other jump | fromMap, toMap, yards, why (`death`, `spirit`, `tram`, `other`) |
| mo | first use of each mount | on (always 1), spell, name |
| ml | mount or Riding learned | name, spell |

Yards: straight line in world yards, rounded down. Only when both ends have world positions in the same world instance.

#### Counts

- `travel`: `flights`, `boats`, `hearths`, `offers`, `summons`, `portals`, `teleports` (jp), `mountUps` (every mount-up), `mount:<spellID or name>` (per mount).
- `distance`: `hearth` (hs yards summed), `portal` (su and po yards summed).

#### Snapshots per level

None.

#### Saved state outside the journal

- None required. The last written zone is seeded from the last `zo` line at login. **Kind off**: keep the last zone in saved state instead.

#### Rules and edge cases

1. **Zone**: write `zo` only if the name differs from the last zone. A new zone clears the last subzone. At login the last zone comes from the journal, so a reload does not repeat it.
2. **Inn as zone**: at `PLAYER_ENTERING_WORLD` the zone text can be an inn or building. Write it (if new) and start a "load check". On each `ZONE_CHANGED`/`ZONE_CHANGED_INDOORS` (outside instances): if the current map's name equals the load name, end the check. Else if the zone text differs from the load name and equals the map's name, end the check and write that zone. `ZONE_CHANGED_NEW_AREA` ends the check. A zone text the map name does not confirm is never written.
3. **Subzone**: after the zone check, write `sz` if outside an instance, not empty, and different from the last.
4. **Trip detector** keeps the last 8 own casts. Hearthstone spells **8690, 556** start a Hearthstone trip. Teleport spells **3561, 3562, 3563, 3565, 3566, 3567** and Portal spells **10059, 11416, 11417, 11418, 11419, 11420** start a teleport trip.
5. **Summon**: `CONFIRM_SUMMON` writes `so` and keeps who and area (they read nil after Accept). `CANCEL_SUMMON` marks the offer cancelled, no line. The `ConfirmSummon` hook starts a summon trip with the kept who and area.
6. **Watch**: while a trip waits (not on a loading screen), read the position every 0.25 s. A trip not loading and older than 15 s is dropped. Hard stop after 180 reads.
7. **Arrival**: a move of 5+ yd from the trip start, or a world instance change.
8. **Loading start**: if no map position, use the last fed position. Write `ld`. A trip started within 15 s is marked "loading". Else open a "loading" trip with: fast (fast movement within 6 s before), no-feed (no positions yet this session), other-cast (any own cast within 15 s). Forget the last position, so no jump is measured across the screen.
9. **Loading end**: write `le` if an `ld` is open. 2 s later, if the same trip still waits, arrive with a full position read (with zone names).
10. **Fast**: speed between samples (time floor 0.1 s) over **12 yd/s** unmounted or **18 yd/s** mounted, under 60, not on taxi, not dead or ghost.
11. **Jump outside loading**: no trip, move of **150+ yd** at over **60 yd/s**, not on taxi.
12. **Revive**: an `al` within 10 s before the trip start, up to now, marks the trip as a revive.
13. **Classify** in order: summon → `su`; hearth → `hs`; teleport → `po`. Revive with loading or jump → nothing. Instance type before or after not "none" → nothing (Dungeons and PvP own it). On taxi before → nothing. Jump: became ghost → `death`; ghost before → `spirit`; else `other`. Loading and fast: world instance changed, or fast again within 30 s → `bt`; else wait up to **30 s** (no fast move → treat as not fast). Became ghost or dead before → `jp death`; ghost before → `jp spirit`; zone "Deeprun Tram" before or after → `jp tram`; no-feed, other-cast, or missing map on either side → `jp other`; else `po` with no spell (portal from another mage; unproven).
14. **Localized clients**: the tram rule compares an English zone name. Use a map ID check instead. The Riding rule builds a pattern from `ERR_SKILL_GAINED_S` but looks for the English word "Riding"; prefer a skill-line ID.
15. **Flights**: `TAXIMAP_OPENED` keeps the current node name. `TakeTaxiNode` hook writes `tx` and opens a flight. Landing: `PLAYER_CONTROL_GAINED` not on a taxi, 5+ s after take-off → `tl`. Fallback: a position sample says not on a taxi, 5+ s after take-off → `tl` at the current spot.
16. **Mid-flight reload**: at login and each `PLAYER_ENTERING_WORLD`, if on a taxi with no open flight, open one with unknown nodes, started 10 s ago.
17. **Mount up**: mounted now, not before, not on a taxi or open flight. Mount: a cast within 5 s that maps to a mount; else the active mount in the journal; else the cast's spell name. Count every mount-up. First use of that key (from counts, so it works with the kind off) writes `mo`. The moment is "big" if the journal has no earlier `mo` or `ml`.
18. **Learned**: `NEW_MOUNT_ADDED` (mount ID → name, spell) or a skill-gained chat line naming Riding. Skip if the same name was written within **120 s**. **Kind off**: keep that dedupe in memory.
19. **Distance unit**: explicit setting `yards` or `meters` wins. Else `GetCurrentRegion` 1..5 decides (1 = yards, others meters). Else `GetLocale` `enUS` or unknown = yards, others meters.

#### Hook utility (core)

- Input: a table (or none for globals), a function name, a label, a handler.
- If the target is not a function, return false and do nothing.
- Install a **post-hook** with `hooksecurefunc` (never replace the function; no taint).
- The handler gets the original call's arguments. It runs inside an error guard; errors are logged with the label and never reach the caller.
- If installing fails, log with the label and return false. Return true on success.

#### Interfaces offered

- Last outdoor point `{m, x, y, t}` (Dungeons uses it as entrance fallback).
- Current flight `{from, to, cost, t}` (Money labels the fare).
- Distance unit, yards between two positions.
- Pure classifier and a tracker with an injectable clock and no timers, for tests and simulations.
- Needs: the trail's live position message; the `al` moment broadcast.

#### Test cases

1. Given last zone "Elwynn Forest"; when `ZONE_CHANGED_NEW_AREA` reads "Elwynn Forest"; then nothing.
2. Given `PLAYER_ENTERING_WORLD` reads "Lakeshire Inn"; when `ZONE_CHANGED` reads "Redridge Mountains" and the map is "Redridge Mountains"; then `zo|Lakeshire Inn` then `zo|Redridge Mountains`.
3. Given cast 8690, bind "Goldshire"; when loading start, end, and 2 s later; then `ld|8690|`, `le`, `hs|<from>|<to>|Goldshire|<yards or empty>`, hearths+1.
4. Given `CONFIRM_SUMMON` ("Zed", "Duskwood"), Accept; when a sample 40 yd away within 15 s; then `so|Zed|Duskwood` and `su|Zed|Duskwood|...|40`.
5. Given Accept and no move; when 16 s pass; then no `su`.
6. Given samples at 26 yd/s up to 3 s before a loading screen and a world instance change after; then `bt`.
7. Given fast before loading, same instance after, no fast move in 30 s; then `po` (or `jp other` if a cast was in the 15 s).
8. Given `al` at t=100; when a loading screen at t=102 with no cast; then no travel line (only `ld`/`le`).
9. Given ghost; when a 300 yd move at 500 yd/s; then `jp|..|spirit`.
10. Given `TakeTaxiNode` at t=0, `PLAYER_CONTROL_GAINED` at t=3 off taxi; then no `tl`; at t=60 off taxi; then `tl|<to>`.
11. Given a mount used twice; then one `mo`, mountUps=2, `mount:<id>`=2.
12. Given region 110 and locale deDE, no setting; then meters.

---

### Dungeons

#### Events and hooks

- `PLAYER_ENTERING_WORLD` (isLogin, isReload), `ZONE_CHANGED_NEW_AREA`: debounce 1 s, then check.
- `IsInInstance` (type `party` or `raid`), `GetInstanceInfo` (name, difficultyID, maxPlayers, instanceID).
- `ENCOUNTER_START` (encounterID), `ENCOUNTER_END` (encounterID, encounterName, difficultyID, groupSize, success).
- `PLAYER_REGEN_ENABLED` plus target reads: `UnitExists`, `UnitIsDead`, `UnitName`, `UnitClassification`, `UnitIsPlayer`, `UnitGUID`.
- Statistics pane: `GetStatisticsCategoryList`, `GetCategoryNumAchievements`, `GetAchievementInfo`.

#### Kinds written

| kind | when | fields |
|---|---|---|
| dn | entered a dungeon or raid | name, instance (instance ID), itype (`party`/`raid`), difficulty, size (max players). Position = entrance (last outdoor point) |
| dx | left it | name, instance, seconds (visit length), deaths (deaths during visit) |
| bo | boss fight ended inside | name, encounter ID, success (1/0), last (1 if a last boss), place (instance name), seconds (pull to end) |
| wb | world boss killed outdoors | name, npc |

#### Counts (module `dungeons`)

- `visits` / `raidVisits`; `seconds` / `raidSeconds` (sum of visit lengths).
- On success: `bosses` / `raidBosses`, `kills:<name>`, `clears` / `raidClears` (last boss), `longest:<name>` / `raidLongest:<name>` (max fight seconds).
- On failure: `wipes` / `raidWipes`.
- `worldBosses`.

#### Snapshots per level

None.

#### Saved state outside the journal

- None in the source. The open visit is read from lines (last `dn` with no later `dx`; same second: log order). **Kind off**: Memories must save the open visit `{name, instance, itype, t}` and its death count itself.
- Memory only: pull times per encounter, "seen inside this session", login time, last-boss list.

#### Rules and edge cases

1. **Check**: open visit and inside the same instance ID → nothing (reload or zone change inside).
2. Open visit, not there now → write `dx`. Leave time: if outside now and not seen inside this session (logged out inside, logged in outside), use the logout line after the visit, else the last line before this login (not a login line). Else now.
3. Inside now (new instance) → `dn` at the entrance: the last outdoor trail point, else Travel's last outdoor point. Mark seen inside. Instance to instance writes `dx` then `dn`.
4. At login or reload inside an instance, "seen inside" is set: the open visit goes on.
5. `dx` seconds = leave time minus `dn` time, min 0. deaths = deaths from `dn` to leave. **Kind off**: count deaths in visit state, not from `de` lines.
6. **Boss**: `ENCOUNTER_START` stores the pull time. `ENCOUNTER_END` inside a party or raid instance writes `bo`. Pull time is memory only; after a reload mid-fight, seconds is empty.
7. Success = 1 (or true). Name secret → `?`.
8. **Last boss**: the name is in the last-boss list. Success and last → ask the core screenshot service for `"last boss <name>"`, 1 s later, only if the same journal is still active. The service checks its own setting.
9. **World boss, path A**: `ENCOUNTER_END` success while not in any instance (so battleground generals do not count).
10. **World boss, path B**: `PLAYER_REGEN_ENABLED` outside a party or raid instance. The target exists, is dead, is not a player, and has classification `worldboss` or a name in: Azuregos, Lord Kazzak, Ysondre, Lethon, Emeriss, Taerar. npc from the GUID.
11. **World boss dedupe**: same name within **600 s**, checked against the last 6 `wb`. **Kind off**: keep that in memory.
12. Raids use the same path with type `raid`; unproven in game.

#### Last-boss data (Bosses)

- **Source 1**: built-in list, boss name → place.
- **Source 2**: 10 s after login, a background job (yield about every 50 entries) reads all Statistics categories. It keeps names shaped "`<Boss> kills (<Place>)`" ("kills" any case). It skips places containing "most kills" and the boss "Dungeon". Pane entries override the built-in list. The pattern is English only; localized clients get only the built-in list.
- **Place match**: lower case, drop everything from the first ":", trim, drop a leading "the ". "The Deadmines" = "Deadmines".
- **Built-in list** (43):
  - Aku'mai: Blackfathom Deeps. Amnennar the Coldbringer: Razorfen Downs. Archaedas: Uldaman. Archmage Arugal: Shadowfang Keep.
  - Baron Rivendare, Balnazzar: Stratholme. Bazil Thredd: Stormwind Stockade. Bazzalan: Ragefire Chasm.
  - Blazeroar: Alcaz Prison. Charlga Razorflank: Razorfen Kraul. Chief Ukorz Sandscalp: Zul'Farrak.
  - Darkmaster Gandling: Scholomance. Durgen Dirgehammer: Hall of Thanes. Edwin VanCleef: Deadmines.
  - Emperor Dagran Thaurissan: Blackrock Depths. General Drakkisath: Upper Blackrock Spire. Overlord Wyrmthalak: Lower Blackrock Spire.
  - Scarlet Monastery: High Inquisitor Whitemane, Scarlet Commander Mograine, Herod, Arcanist Doan, Bloodmage Thalnos.
  - Dire Maul: King Gordok, Prince Tortheldrin, Alzzin the Wildshaper.
  - City of Dalaran: Lyn the Ignored, Shade of the Archmage.
  - Mekgineer Thermaplugg: Gnomeregan. Mutanus the Devourer: Wailing Caverns. Nanaya: Shaper's Terrace.
  - Princess Theradras: Maraudon. Rath'mael: Ruins of Lordaeron. Shade of Eranikus: Sunken Temple.
  - Sonya Darkhallow: Barrow Deeps. The Wild King: Hyjal Summit. Relic Guardian: Excavation Site: Wetlands.
  - Raids: Onyxia: Onyxia's Lair. Ragnaros: Molten Core. Nefarian: Blackwing Lair. Hakkar: Zul'Gurub. Ossirian the Unscarred: Ruins of Ahn'Qiraj. C'Thun: Ahn'Qiraj Temple. Kel'Thuzad: Naxxramas.

#### Interfaces offered

- Open visit query; "is last boss" (name → place); full last-boss list; "known place" (the list has a last boss for this instance name). Stats re-reads the list for old journals.
- Screenshot request to the core service: reason `"last boss <name>"`.
- Needs: last outdoor trail point, Travel's last outdoor point, death count during a visit, logout and login moments, journal clock.

#### Test cases

1. Given outdoors at (1415, 4000, 6000), no open visit; when PEW inside "Deadmines" (party, ID 36) and 1 s passes; then `dn|Deadmines|36|party|1|5` at that position, visits+1.
2. Given an open visit to ID 36; when `/reload` inside ID 36; then nothing.
3. Given `dn` at t=1000 and one `de` at t=1500; when zone change outdoors at t=2800 (seen inside); then `dx|Deadmines|36|1800|1`, seconds+=1800.
4. Given an open visit, a logout line at t=5000, then login outside; then `dx` with t=5000.
5. Given an open visit to ID 36; when PEW inside ID 48; then `dx` then `dn`.
6. Given `ENCOUNTER_START(1)` at 10 s, `ENCOUNTER_END(1,"Edwin VanCleef",…,1)` at 95 s inside; then `bo|Edwin VanCleef|1|1|1|Deadmines|85`, clears+1, and a screenshot request 1 s later.
7. Given `ENCOUNTER_END` with success 0; then `bo|..|0||..`, wipes+1, no screenshot.
8. Given outdoors, dead target "Azuregos", classification `worldboss`; when `PLAYER_REGEN_ENABLED`; then `wb|Azuregos|6109`; again 5 min later → nothing.
9. Given `ENCOUNTER_END` success inside a battleground; then no `wb`, no `bo`.
10. Given pane entry "Hogger kills (Elwynn Forest)"; when the pane job runs; then Hogger is a last boss.

## Appendix C — Memories_Economy and Memories_Combat: Loot, Money, Combat

Behavior description. The Appendices rules in the Implementation guidelines apply.
### Shared rules (all three recorders)

- **Journal line:** `t|p|m|x|y|kind|fields`. Fields are listed in order. An empty field means "not known".
- **Position:** every line uses the core's **current position** (empty inside instances).
- **Hidden values:** every game read can return a **secret value**. A secret value counts as "not known". Where a name was hidden, write `?`.
- **Writable journal:** when the core says no journal can be written: **no line and no count**.
- **Kind switch (Memories):** every kind is **on by default**. When a kind is off, its line is not written, but **counts and snapshots still run**. A "moment" (toast or big-moment signal) belongs to its line, so it is skipped too. *(Source: no per-kind switch.)*
- **New fields:** fields added for Memories go **after** the source's fields, so an old reader still works.
- **Failed game calls:** logged, treated as "not known".
- **Localized clients:** the source matches **English** chat text. Memories should build each pattern from the client's GlobalStrings (names given below; check each against the client). Where no GlobalString exists, the English pattern is the fallback.

---

### Loot

#### Events and hooks

- `CHAT_MSG_LOOT` (arg 1 = text): every loot, roll and receive line.
- `PLAYER_LEVEL_UP` (arg 1 = new level): gear snapshot **2 s** later.
- Login: gear snapshot **4 s** after the sub-addon starts.
- `PLAYER_EQUIPMENT_CHANGED`: rescan the worn gear, **coalesced to 0.5 s** (many events in 0.5 s = one rescan).
- Reads: `GetInventoryItemID` / `GetInventoryItemQuality` for slots **1-19**, `C_Item.GetItemInfoInstant`.

#### Reading a loot line

1. If the text starts with a loot-history link (`|HlootHistory:N|h[Loot]|h:`), keep **N** as the roll key and drop the prefix. Without it, the roll key is `item:<itemID>`.
2. Item id comes from the first `|Hitem:<id>` link. Name comes from the link's bracket text. Count comes from a trailing `x<N>` after the link (default **1**).
3. Quality: ask `C_Item.GetItemQualityByID`. If unknown, read the link color: `|cnIQ<n>` gives n; otherwise the hex color maps `9d9d9d`=0, `ffffff`=1, `1eff00`=2, `0070dd`=3, `a335ee`=4, `ff8000`=5.
4. Line types (source English prefixes; Memories GlobalStrings in brackets):

| Type | Source text | GlobalStrings for Memories |
|---|---|---|
| own | "You receive loot" | `LOOT_ITEM_SELF`, `LOOT_ITEM_SELF_MULTIPLE` |
| pushed | "You receive item" | `LOOT_ITEM_PUSHED_SELF`, `LOOT_ITEM_PUSHED_SELF_MULTIPLE` |
| made | "You create" | `LOOT_ITEM_CREATED_SELF`, `LOOT_ITEM_CREATED_SELF_MULTIPLE` |
| select (mine) | "You have selected <Type> for" | `LOOT_ROLL_NEED_SELF`, `LOOT_ROLL_GREED_SELF` |
| select (other) | "<who> has selected <Type> for" | `LOOT_ROLL_NEED`, `LOOT_ROLL_GREED` |
| roll | "<Type> Roll - <N> for <item> by <who>" | `LOOT_ROLL_ROLLED_NEED`, `LOOT_ROLL_ROLLED_GREED` |
| won (mine) | "You won" | `LOOT_ROLL_YOU_WON` |
| won (other) | "<who> won: " | `LOOT_ROLL_WON` |
| allpassed | "Everyone passed on" | `LOOT_ROLL_ALL_PASSED` |
| passed | "You passed on" / "<who> passed on" | `LOOT_ROLL_PASSED_SELF`, `LOOT_ROLL_PASSED` |
| other | contains " receive(s) loot" | `LOOT_ITEM` (ignored) |

5. **"Is me":** the name equals the player's name, **or** starts with the player's name plus a space (Forever names carry a surname).

#### Kinds written

| kind | when | fields |
|---|---|---|
| `lo` | an item reaches the bags | `item` (id), `quality` (0-5), `count` (empty when 1), `how` (loot, quest, made, roll, bought, trade, mail, other), `name`, `gear` (1 = wearable, else empty), **`first`** (Memories: 1 when this is the first of this item id for the character, else empty) |
| `rl` | a group roll of Need or Greed ends, or expires | `item`, `type` (need, greed), `roll` (1-100 or empty), `won` (1 won, 0 lost, empty = no result seen), `name`, `quality` |
| `ge` | gear snapshot | `level`, `ids` (19 item ids, comma separated; `0` empty slot, `?` hidden), `src` (login, ding) |
| `eq` | a worn slot changed | `slot` (1-19), `item` (0 = slot emptied), `quality` |

`how` for a pushed line comes from Money's open window: vendor -> `bought`; auction -> `bought`; quest -> `quest`; mail -> `mail`; trade -> `trade`; anything else or none -> `other`.

**Wearable** (`gear`): class id 2 (weapon) or 4 (armor) is wearable unless its equip location is `INVTYPE_NON_EQUIP_IGNORE`. Any other class is wearable only if it has a non-empty equip location other than that value. If both class id and equip location are unknown, treat it as **wearable**.

#### Counts

- `loot.items` += count, for **every** item.
- `loot.q<n>` += count, when quality n is known.
- **Memories adds** `loot.item:<itemID>` += count (needed for the first-finding rule).
- Rolls: `loot.needRolls` / `loot.greedRolls` += 1; `loot.needWon` / `loot.greedWon` += 1 on a win; `loot.perfect` += 1 and `loot.perfect:<need|greed>:<itemID>` += 1 when the roll is **100**.

#### Snapshots per level

- `snap[level].gear` = the same `ids` string as the `ge` line.

#### Rules and edge cases

1. **Memories:** write `lo` for **every** item of every quality. *(Source: only wearable items or quality >= 2; the rest is only counted.)*
2. Quality >= **4** (epic) raises a **big moment** for the `lo` line.
3. **Rolls repeat:** Forever prints each roll line **3-4 times**. One history key = one roll. After a "won" line marks a roll done, further "won" lines for that key are ignored.
4. Only **Need** and **Greed** rolls count. Other roll types are ignored.
5. Roll state starts at my "selected" line or my "Roll - N" line. The first roll number seen is kept.
6. A "won" line by me: write `rl` won=1 (if I had a roll type), then write `lo` with how=`roll`, **unless** the same item was received in the last **5 s** or already won in the last **10 s**. Remember the win time.
7. A "You receive loot" line for an item I won in the last **10 s** is the same item: skip it once.
8. A "won" line by someone else for a roll I joined: `rl` won=0.
9. "Everyone passed" closes the roll with no line.
10. A roll with no result after **300 s** is closed: if it has a type, write `rl` with `won` empty. This check runs on every new loot line.
11. **Gear at login:** 4 s after start, read slots 1-19. If `snap[level].gear` already exists, write nothing (a ding's snapshot wins over a login or reload). Else write `ge` src=login.
12. **Gear at ding:** 2 s after `PLAYER_LEVEL_UP`, using the event's level, write `ge` src=ding (always).
13. **Equipment:** the first scan (or the first snapshot) is the **baseline**, not a change. Later scans compare each slot. A slot that is hidden (`?`) in either scan is never a change. Each change writes `eq`.
14. **Reload:** roll, win and receive memory is lost. A roll in progress during a reload is never closed.
15. **Possible double:** a pushed line while the mail or trade window is open, plus Money's attachment or trade record, could write the item twice. Memories should drop a pushed `lo` when Money recorded the same item id within **2 s**.

#### New-findings-only rule (Memories, default OFF)

- **Decision:** write `lo` only when the item is **new** or **rare**.
  - **New:** the counter `loot.item:<itemID>` was **0 before** this event.
  - **Rare:** quality >= **3** (blue or better). This is the source's own "rare find" bar for gathered items.
- `first` = 1 only for a new item.
- **Counts always run.** The counter is raised after the decision.
- An item with no id is always written.
- When the option is OFF, every item is written (rule 1).

#### Interfaces

- **Needs from core:** event registration; delayed and coalesced timers; current position; current level; write line; add to count; read count; read and write per-level snapshot; "is the journal writable"; big-moment signal; player name.
- **Offers (inside Economy):** `recordItem({item, quality, count, how, name})` — used by Money for mail attachments and trade items.
- **Uses (inside Economy):** Money's `currentWindow()`.

#### Test cases

1. **Given** option off, **when** "You receive loot: [Linen Cloth]x2" (quality 1), **then** `lo` item, 1, 2, loot, Linen Cloth, empty gear; `loot.items` +2, `loot.q1` +2.
2. **Given** "new findings" on and `loot.item:2589` = 0, **when** Linen Cloth is looted, **then** `lo` with first=1; a second loot of it writes no line, counts still +.
3. **Given** the vendor window open, **when** "You receive item: [Flask]", **then** `lo` how=bought.
4. **Given** I selected Need (history key 7) and rolled 100, **when** "You won: [Sword]" appears 3 times, **then** one `rl` need, 100, won=1; one `lo` how=roll; `perfect` +1; `needWon` +1.
5. **Given** that win, **when** "You receive loot: [Sword]" arrives 2 s later, **then** no second `lo`.
6. **Given** I rolled Greed 45, **when** "Bob Stone won: [Ring]", **then** `rl` greed, 45, won=0.
7. **Given** `snap[12].gear` exists, **when** the player reloads at level 12, **then** no `ge` line.
8. **When** `PLAYER_LEVEL_UP` 13, **then** 2 s later `ge` 13, ids, ding and `snap[13].gear` set.
9. **Given** a baseline, **when** the chest slot is emptied, **then** `eq` 5, 0, empty.
10. **Given** `lo` turned off, **when** an epic drops, **then** no line, no big moment, counts +1.

---

### Money

#### Events and hooks

**Gold:** `PLAYER_MONEY` -> read `GetMoney()`; delta = now minus last known. At start, read `GetMoney()` as the baseline.

**Windows** (one label slot; opening any window replaces the label):

| Opens on | Label | Closes on | Close delay |
|---|---|---|---|
| `MERCHANT_SHOW` | vendor | `MERCHANT_CLOSED` | 0 |
| `TRAINER_SHOW` | trainer | `TRAINER_CLOSED` | 0 |
| `MAIL_SHOW` | mail | `MAIL_CLOSED` | 0 |
| `AUCTION_HOUSE_SHOW` | auction | `AUCTION_HOUSE_CLOSED` | **3 s** |
| `BANKFRAME_OPENED` | bank | `BANKFRAME_CLOSED` | 0 |
| `TRADE_SHOW` | trade | `TRADE_CLOSED` | **2 s** |
| `GOSSIP_SHOW` | gossip | `GOSSIP_CLOSED` | 0 |
| `QUEST_COMPLETE` | quest | `QUEST_FINISHED` | **1 s** |
| `TAXIMAP_OPENED` | flight | `TAXIMAP_CLOSED` | **2 s** |

A close event clears the label **only if that label is the current one** (a gossip window often closes after the vendor it opened). With a delay, the label stays until the delay passes; it is checked when someone asks.

**Secure hooks** (run after the game function):

- `RepairAllItems` -> repair time.
- `ConfirmTalentWipe` -> talent reset time.
- `BuyMerchantItem(index)` -> bought item name (`GetMerchantItemInfo`, else name of `GetMerchantItemID`).
- `C_Container.UseContainerItem(bag, slot)` and global `UseContainerItem` -> only while the label is vendor: sold item name and stack count (`C_Container.GetContainerItemInfo`).
- `BuyTrainerService(index)` -> a trainer click (name, rank text, skill line, cost).
- `C_AuctionHouse.PlaceBid(auctionID, amount)`, `C_AuctionHouse.PostItem`, `C_AuctionHouse.PostCommodity`, `C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)`, legacy `PlaceAuctionBid(listType, index, amount)`, `PostAuction`, `StartAuction`.
- `SendMail(recipient)` with `GetSendMailMoney()` and `GetSendMailItem(1)`.
- `TakeInboxMoney(i)`, `TakeInboxItem(i, slot)`, `AutoLootMailItem(i)`.

**Other events:** `QUEST_TURNED_IN` (quest id -> `C_QuestLog.GetTitleForQuestID`); `TRAINER_SHOW` (read now and **1 s** later); `TRAINER_UPDATE` (read, coalesced **0.3 s**); `AUCTION_HOUSE_PURCHASE_COMPLETED`, `COMMODITY_PURCHASE_SUCCEEDED`, `COMMODITY_PURCHASE_FAILED`; `MAIL_SHOW`, `MAIL_SEND_SUCCESS`, `MAIL_FAILED`, `MAIL_CLOSED`; `TRADE_SHOW` (partner = `UnitName("NPC")`), `TRADE_TARGET_ITEM_CHANGED`, `TRADE_MONEY_CHANGED`, `TRADE_ACCEPT_UPDATE`; `UI_INFO_MESSAGE` (arg 2) and `CHAT_MSG_SYSTEM` (arg 1) compared with `ERR_TRADE_COMPLETE`; `PLAYER_LEVEL_UP`.

#### Kinds written

| kind | when | fields |
|---|---|---|
| `mn` | every gold change | `delta` (copper, signed), `src` (see table), `what` (item, quest, person, place or empty) |
| `tb` | a trainer purchase was paid | `kind` (class, profession, weapon, pet, riding), `what` (service, plus " (Rank N)" when a real rank), `cost` |
| `ah` | auction house action | `act` (buyout, bid, post, sold, expired), `copper` (paid; deposit for post; sale money for sold), `item` |
| `ma` | mail sent or taken | `act` (send, take, invoice), `who` (`?` when hidden), `copper` (empty when 0), `item` (first attachment or invoice item) |
| `tr` | a trade completed | `name` (partner, `?` when hidden), `copper` (received minus given; empty when 0) |

#### Source attribution (`mn.src`)

Checked **in this order**; the first match wins.

| # | Condition | src | what |
|---|---|---|---|
| 1 | loss, within **2 s** of `RepairAllItems` | repair | empty |
| 2 | loss, within **3 s** of `ConfirmTalentWipe` | respec | empty |
| 3 | loss, trainer clicks pending, and the first k clicks (oldest first, clicks older than **3 s** dropped) add up **exactly** to the loss | trainer | service names joined by ", " |
| 4 | label auction, loss within **3 s** of a post | auction | posted item (also writes `ah` post, copper = loss) |
| 5 | label auction, loss matches a pending bid's amount exactly, else the oldest pending bid with no amount | auction | that item (also writes `ah` buyout/bid, copper = loss) |
| 6 | label auction, loss, an auction purchase confirmed in the last **10 s** | auction | that item (no new `ah`) |
| 7 | label auction, anything else | auction | empty |
| 8 | label mail, loss, a send in the last **15 s** not yet paid, money sent > 0 and loss >= money sent | **two lines:** mail (−sent) and, if more was lost, postage (the rest) | recipient on both |
| 9 | label mail, loss, a fresh unpaid send (no money or loss < money) | postage | recipient |
| 10 | label mail, loss, no fresh send | mail (cash on delivery) | empty |
| 11 | label mail, gain, a mail take in the last **15 s** | the take's src (below) | the take's what |
| 12 | label mail, gain, no fresh take | mail | empty |
| 13 | label trade | trade | partner (current, else last) |
| 14 | label vendor, loss | vendor | item bought in the last **3 s** |
| 15 | label vendor, gain | vendor | item sold in the last **3 s**, as "20 Wool Cloth" when the stack is > 1 |
| 16 | label quest | quest | title if `QUEST_TURNED_IN` came in the last **5 s** |
| 17 | label flight | flight | destination from the flight tracker |
| 18 | label bank, gossip or trainer | that label | empty |
| 19 | no label, gain | loot | empty |
| 20 | no label, loss | other | empty |

**Mail take src:** seller invoice -> `auction` (what = sold item); "Outbid on %s" subject -> `auction` (what = item); a player mail (can reply and not GM) -> `mail` (what = sender); anything else -> `other` (what = sender).

#### Counts

- `money.<src>+` / `money.<src>-` += size of change; `money.earned` / `money.spent` += size.
- `money.held` += delta (gold on hand). At start and after a journal restore, `held` is set to the real gold (no `mn` line for the gap).
- `money.peak` = highest `held` ever. When peak rises from a change, `money.peakLevel` = level at that time.
- `trainers.<kind>` += cost.
- `auction.<act>` += 1; `auction.<act>Copper` += copper when known.
- `mail.<act>` += 1. `trade.trades` += 1.

#### Snapshots per level

- `snap[level].money` = `GetMoney()` read **2 s** after `PLAYER_LEVEL_UP` (level from the event).

#### Rules and edge cases

1. A zero change writes nothing.
2. **Trainer list:** empty at `TRAINER_SHOW`, so it is read again 1 s later and on updates. A read with fewer services for the **same** NPC never replaces a fuller one.
3. **Trainer kind** per service: no NPC unit (the hunter's own pet window) -> training points, **never recorded**; `IsTradeskillTrainer` -> profession; skill line contains "Riding" -> riding; skill line is a weapon skill (Axes, Two-Handed Axes, Bows, Crossbows, Daggers, Fist Weapons, Guns, Maces, Two-Handed Maces, Polearms, Staves, Swords, Two-Handed Swords, Thrown, Wands) -> weapon; "Beast Training" -> pet; else class. These names are **English**: on other clients everything falls back to class. Memories should compare against localized skill names.
4. A click with cost 0 or unknown cost is ignored. Clicks count only when the gold actually drops (the button can be clicked without paying). After a match, all other pending clicks are dropped.
5. Rank text: the second value of `GetTrainerServiceInfo` is an availability word on Forever (available, unavailable, used, header); those are **never** a rank. Header rows are skipped.
6. Buying riding also tells the travel recorder "Riding learned" (it writes its own line).
7. **Auction clicks:** a bid is "buyout" when amount >= the listing's buyout (buyout > 0 for legacy). Commodity purchases have no amount; item text is "Name xQ" when quantity > 1. Pending clicks expire after **30 s**.
8. A purchase event (`AUCTION_HOUSE_PURCHASE_COMPLETED` / `COMMODITY_PURCHASE_SUCCEEDED`) writes `ah` for the **oldest** pending click (its amount may be empty) and remembers it for 10 s. `COMMODITY_PURCHASE_FAILED` drops the **newest** click. Whichever comes first, the gold drop or the event, consumes the click.
9. **Mail visit:** each mail is handled once per mailbox visit (key = sender, subject, days left).
   - Seller invoice (`GetInboxInvoiceInfo` type seller): `ah` sold (copper = money, item) and `ma` invoice (who = buyer).
   - Buyer invoice: `ma` invoice (who = seller, item = invoice item or first attachment).
   - Other mail: if subject matches `AUCTION_EXPIRED_MAIL_SUBJECT` -> `ah` expired (item from subject). Always `ma` take (who = sender, item = first attachment).
10. **Mail attachments:** each asked attachment (`TakeInboxItem` = one slot, default 1; `AutoLootMailItem` = all) waits until it has **left** its mail. Checks run every **1 s** while any wait. Left = not in its mail any more (slot, id and name compared) or the mail is gone. Then `lo` is written via Loot with how: buyer invoice -> bought; expired-auction subject -> other; else mail.
11. An attachment still there after **10 s** is forgotten (full bags). A failed inbox read (call error, no count, a header with no sender or subject) proves nothing: keep waiting. At `MAIL_CLOSED`: one last check only if the inbox reads non-empty; then **drop** every wait. Taking only the gold writes no `lo`.
12. **Send:** `ma` send is written once on `MAIL_SEND_SUCCESS`; `MAIL_FAILED` forgets it.
13. **Trade:** items and gold re-read on each trade update (6 target slots: `GetTradeTargetItemLink`, `GetTradeTargetItemInfo`; `GetTargetTradeMoney`, `GetPlayerTradeMoney`). Done when the message equals `ERR_TRADE_COMPLETE`, **once** (it shows in two events). Writes `tr` and one `lo` how=trade per item received. Items given away are not recorded.
14. **Reload:** labels, pending clicks and mail waits are lost; gold is re-read, so no false `mn`.
15. If `GetMoney()` is hidden, the last known value is kept and no line is written.

#### New-findings-only rule

- Not applicable. Money kinds are never filtered.

#### Interfaces

- **Needs from core:** event registration; secure-hook helper; timers (delay, coalesce); current position; current level; write line; counts (add, read, set by difference); snapshots; "is the journal writable"; message "journal reset/restored" (to re-sync `held`).
- **Needs from other recorders (optional):** flight destination of the current flight; "record Riding learned". When missing, `what` is empty and nothing more is written.
- **Offers (inside Economy):** `currentWindow()` -> vendor, trainer, mail, auction, bank, trade, gossip, quest, flight or none (after close delays). Uses Loot's `recordItem`.

#### Test cases

1. **Given** no window, **when** gold rises 35c, **then** `mn` 35, loot.
2. **Given** vendor open and Wool Cloth x20 sold 1 s ago, **when** gold +400, **then** `mn` 400, vendor, "20 Wool Cloth".
3. **Given** vendor open, **when** `RepairAllItems` then gold −1200 within 2 s, **then** `mn` −1200, repair.
4. **Given** trainer open, clicks A (100) and B (250) within 3 s, **when** gold −350, **then** two `tb` lines and `mn` −350, trainer, "A, B".
5. **Given** trainer open, one click of 100, **when** gold −90, **then** `mn` −90, trainer, empty what, no `tb`.
6. **Given** `QUEST_FINISHED` 0.8 s ago, **when** gold +500, **then** `mn` src quest (label still alive).
7. **Given** mail open, a send of 1000 to Ann 2 s ago, **when** gold −1030, **then** `mn` −1000 mail Ann and `mn` −30 postage Ann; `ma` send on success.
8. **Given** mail open, a seller invoice for Copper Bar taken, **when** gold +950, **then** `ah` sold, `ma` invoice, `mn` 950 auction "Copper Bar".
9. **Given** an attachment asked, **when** next check shows it gone, **then** `lo` how=mail once; asked twice -> still once.
10. **Given** a trade with Bob, he gives 2 items and 50s, I give 10s, **when** "Trade complete." shows in both events, **then** one `tr` Bob 4000, two `lo` how=trade.
11. **Given** auction open, `PostItem` 1 s ago, **when** gold −60, **then** `ah` post 60 and `mn` −60 auction.
12. **When** `PLAYER_LEVEL_UP` 20, **then** 2 s later `snap[20].money` = gold.

---

### Combat

No combat log (forbidden on Forever). Kills come from **XP chat lines** and **name plates**, paired by name.

#### Events and hooks

- `CHAT_MSG_COMBAT_XP_GAIN` (arg 1): "<Name> dies, you gain <N> experience" (commas removed from N). Memories: build from `COMBATLOG_XPGAIN_FIRSTPERSON` and its variants.
- `PLAYER_TARGET_CHANGED`: learn the target (open world, not a player, not player-controlled).
- `NAME_PLATE_UNIT_REMOVED` (arg 1 = unit): a plate gone while its creature is dead and engaged = a death.
- Fight start / end: **core-owned in Memories** (`PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED`).
- Plate scan ticker every **0.5 s** while `InCombatLockdown()` or for **5 s** after a fight ends: `nameplate1`..`nameplate40`, plus `target`.
- `PLAYER_LEVEL_UP` (arg 1 = new level): kills snapshot.
- Core message "low-health warning shown".

#### Kinds written

| kind | when | fields |
|---|---|---|
| `ki` | a kill is settled | `name` (`?` hidden), `npc` (creature id from GUID), `ctype` (creature type), `class` (normal, elite, rare, rareelite, ...), `xp` (empty when none), `level`, **`inst`** (Memories: `party` or `raid` for an instance kill, empty in the open world), **`first`** (Memories: 1 when first kill of this NPC) |
| `ra` | the kill was a rare | `name`, `npc`, `level` |
| `fi` | a fight ended that was long, deadly or close | `seconds`, `target`, `class`, `level`, `died` (1 or empty), `casts` |

#### Kill detection

1. **Engaged:** a plate or target unit (not a player, not player-controlled, alive) is engaged when the player has threat on it (`UnitThreatSituation("player", unit)` not empty), else the pet has threat, else it is **not** tap-denied and is in combat ("tapped" by my group). A unit tapped by someone else is never mine. On first engage, read name, npc id, type, classification and level.
2. Unit key = GUID; if hidden, `name:<name>:<unit>`.
3. **Death:** an engaged unit seen dead in a scan, or its plate removed while dead. Each key dies **once**.
4. Engaged entries untouched for **120 s** are dropped (evaded or left behind). Dead keys are kept **600 s**.
5. **Pairing:** a plate death and an XP line with the **same name** within **2.5 s** (either order) are one kill. Each kill takes one plate and one XP line at most.
6. A kill settles **2.6 s** after it was first seen (timer), or when a settle pass finds it older than 2.5 s. Zone (`GetRealZoneText`) is taken when first seen (open world only).
7. **Missing details** come from a learned-creature table, by name: plate first, then learned. When an XP line arrives in the open world for a name not learned and the current target has that name, read the target first.
8. **Learned table:** up to **400** names; never a player's pet; new non-empty values overwrite old ones. Lost on reload.
9. **Instances** (`IsInInstance` type `party` or `raid`): no scanning, no learning (plates and names are secret). Only XP lines count. Battlegrounds and arenas count as **open world**.
10. Kills with no XP line (grey, or every kill at level 60) are seen **only** from plates, so in instances they are not seen at all.

#### Counts (per kill)

- **Open world:** `kills.total`, `kills.xp` or `kills.noxp`, `kills.t:<ctype or ?>`, `kills.critter` (type Critter), `kills.n:<name>`, `kills.nz:<name>@<zone>`, `kills.elite` and `kills.e:<name>` (elite or rareelite).
- **Instance:** `kills.dungeon` (source: this only).
- **Memories adds:** `kills.npc:<id>` for every kill with a known id; for instance kills also `kills.n:<name>` when the XP line named it. `kills.total` stays **open world only** so snapshots keep their meaning.
- **Rare** (classification rare or rareelite): `kills.rare`.
- **Fights:** `fights.n` += 1, `fights.sec` += seconds, `fights.longest` = max, `fights.died` += 1.

#### Snapshots per level

- At `PLAYER_LEVEL_UP` (no delay), `snap[newLevel].kills` = `{ total, xp, dungeon }`.

#### Rules and edge cases

1. **Memories:** write `ki` for **every** kill, **including instance kills** (name from the XP line, `inst` = party/raid, other fields empty). *(Source: instance kills are counted only, never written.)*
2. A rare also writes `ra` and shows a toast "Rare killed: <name>".
3. **Fight target:** **1 s** after the fight starts (the game's restrictions switch after the event), read the target if it exists, is not a player and can be attacked: name (`?` if hidden), classification, level. If a new fight started meanwhile, skip.
4. **Fight end:** seconds rounded to whole; died = player dead or ghost.
5. `fi` is written when seconds >= **20**, or the player died, or the low-health warning showed during the fight.
6. **Casts:** spells cast during the fight; the count comes from the core (Memories) or the character recorder (source).
7. **Reload or login inside combat:** no fight object, so no `fi` and no fight counts for that fight. Pending kill pairs are lost.
8. Secret unit values: name `?`, other fields empty. A key with no GUID and no name is skipped.

#### New-findings-only rule (Memories, default OFF)

- Write `ki` only when:
  - the counter `kills.npc:<id>` was **0 before** this kill (`first` = 1); or, with no id, `kills.n:<name>` was 0; or
  - classification is **elite** or **rareelite**; or
  - the kill is a **rare** (rare or rareelite).
- Instance kills have no id or class: only the name rule applies. A kill with no id and a hidden name is always written.
- `ra` is never filtered. **Counts always run**, raised after the decision.

#### Interfaces

- **Needs from core:** event registration; timers and a repeating ticker; current position; level; write line; counts (add, read); snapshots; "is the journal writable"; toast signal.
- **Fight service (core-owned):** "is the player in a fight", fight-start and fight-end messages, the fight's start time and **cast count**.
- **Core message `LOW_HEALTH`** (from Deaths): sent each time the low-health warning shows, with `combat` (1/0). It must fire **even when the `lh` kind is off**. Combat sets "low" on the current fight.

#### Test cases

1. **Given** open world, a Defias Pillager engaged by threat, **when** its plate shows dead and 1 s later "Defias Pillager dies, you gain 45 experience", **then** one `ki` Defias Pillager, id, Humanoid, normal, 45, level; `total` +1, `xp` +1.
2. **Given** level 60, **when** an engaged plate dies with no XP line, **then** after 2.6 s `ki` with xp empty; `noxp` +1.
3. **Given** a creature tapped by another player, **when** it dies, **then** nothing.
4. **Given** in a dungeon, **when** "Van Cleef dies, you gain 300 experience", **then** `ki` Van Cleef, empty npc/type/class, 300, empty level, inst=party; `kills.dungeon` +1; `total` unchanged.
5. **Given** I targeted a rareelite before its kill, **when** its XP line comes, **then** `ki` and `ra`; `rare` +1, `elite` +1; toast.
6. **Given** "new findings" on and `kills.npc:116` = 3, **when** a normal 116 dies, **then** no `ki`; counts +.
7. **Given** a fight of 25 s, **when** it ends, **then** `fi` 25, target, class, level, empty died, casts; `fights.n` +1.
8. **Given** a 6 s fight with `LOW_HEALTH` during it, **when** it ends, **then** `fi` 6.
9. **Given** `kills.total` = 120, **when** `PLAYER_LEVEL_UP` 15, **then** `snap[15].kills.total` = 120.
10. **Given** `ki` turned off, **when** a kill settles, **then** no line, counts +1.

## Appendix D — Memories_Character, Memories_Gathering and core Screenshots

Behavior description. The Appendices rules in the Implementation guidelines apply.
Description of what Memories records. Target: **Memories_Character** (Character + Milestones), **Memories_Gathering** (Gathering), and the **core screenshot service**.

**Words used here**

- **Journal**: the saved, append-only list of lines for one character. A line = time + position + kind + fields in a fixed order.
- **Counts**: saved number buckets per namespace (`spells`, `items`, `character`, `prof`, `gather`, `milestones`). "+n" means add n.
- **Snapshot**: a saved value keyed by (character level, name). Writing the same key again overwrites it.
- **"?"**: the stored stand-in for a value the game hid.
- **Clean read**: every value from the game passes a secret check first (`issecretvalue`). A secret value becomes "missing". Never compare, index or save a secret.
- **Coalesce(key, s)**: run once, s seconds after the last request with that key. A new request restarts the timer.
- **Writable target**: lines and counts go only to the current journal, and only when it accepts writes (not read-only). A simulated journal is marked as such.

**Memories rules that apply to every part (differ from source)**

- **All recording is on by default.** Each kind has an on/off switch.
- **Kind off** = no line is written. Counts and snapshots still run.
- **"New findings only"** is an option per area (gathering, consumables). Default **off**.

---

### Shared facts

**Professions (skill line id, base spell id)** — used to recognise professions in any client language:

| English key | Skill line | Spell |
|---|---|---|
| Mining | 186 | 2575 |
| Herbalism | 182 | 2366 |
| Skinning | 393 | 8613 |
| Blacksmithing | 164 | 2018 |
| Engineering | 202 | 4036 |
| Leatherworking | 165 | 2108 |
| Tailoring | 197 | 3908 |
| Enchanting | 333 | 7411 |
| Alchemy | 171 | 2259 |
| First Aid | 129 | 3273 |
| Cooking | 185 | 2550 |
| Fishing | 356 | 7620 |

**Profession key lookup** (a shared helper, the core should offer it):

1. Input: a profession name as the client shows it. Output: the English key, or nothing.
2. The English keys always map to themselves.
3. Also map `C_TradeSkillUI.GetTradeSkillDisplayName(skillLine)` and `C_Spell.GetSpellName(spell)` for every row. A Spanish client then maps "Minería" to Mining.
4. Build the map lazily on first use. If no game name could be read yet (too early after login), answer from English keys only and **try again next call**. Once any game name was read, keep the map for the session.
5. Every game call is protected; an error or empty string counts as "no name".

**Other spell ids (facts)**

| Spell | Id | Use |
|---|---|---|
| Auto Shot | 75 | never counted as a cast |
| Shoot | 5019 | never counted as a cast |
| Attack | 6603 | never counted as a cast |
| Tame Beast | 1515 | marks a tame |
| Herb Gathering / "Herbalism" | 2366 | gathering cast (Forever's client names it "Herbalism") |
| Mining | 2575 | gathering cast |
| Skinning | 8613 | gathering cast |
| Fishing | 7620 | fishing cast |
| Disenchant | 13262 | counted with Enchanting |
| Pick Pocket | 921 | pick pocket cast |
| Opening | 3365 | chest cast |
| "Opening - No Text" | (match by literal name) | chest cast; the name is not translated in any client |

**Matching casts by name, not id.** Higher ranks of a profession use other spell ids but the same name. So match the cast's `C_Spell.GetSpellName(spellID)` against a set of names. At login, add `C_Spell.GetSpellName(id)` for each base id above to the English names. Keep English names too.

---

### Character

#### Events and hooks

- `SKILL_LINES_CHANGED` → Coalesce 3 s → skill check.
- `LEARNED_SPELL_IN_SKILL_LINE(spellID)` → learned spell.
- `CHAT_MSG_SYSTEM`, `CHAT_MSG_SKILL` → learned spell / recipe lines.
- `NEW_RECIPE_LEARNED(recipeID)` → recipe.
- `TRAIT_NODE_CHANGED`, `TRAIT_CONFIG_UPDATED`, `PLAYER_TALENT_UPDATE` → Coalesce 1 s → talent read.
- `UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)` → remember the target name of a gathering cast. `target` can be secret.
- `UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)` → cast counts, consumables, tames.
- `UNIT_SPELLCAST_START` / `STOP` / `FAILED` / `INTERRUPTED`, `UNIT_SPELLCAST_CHANNEL_START` / `CHANNEL_STOP` → cast time.
- `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` → fight cast window. (In Memories: subscribe to the core's fight start/end instead; see Interfaces.)
- `TRADE_SKILL_SHOW` → read `C_TradeSkillUI.GetBaseProfessionInfo().professionName`. `TRADE_SKILL_CLOSE` → forget it.
- `CHAT_MSG_LOOT` → "You create" lines.
- `BAG_UPDATE`, `BAG_UPDATE_DELAYED` → Coalesce 0.2 s → bag check.
- `UNIT_AURA("player")` → Coalesce 1 s → buff scan.
- `UPDATE_SHAPESHIFT_FORM` → form check. `PLAYER_TOTEM_UPDATE(slot)` → totem. `UNIT_PET("player")` → Coalesce 0.5 s → pet check.
- `PLAYER_LEVEL_UP(newLevel)` → ding work (see Snapshots).
- Login timers: +3 s buffs, pet, bag baseline, form baseline. +4 s talents. +8 s Statistics pane. +10 s skills.

#### Kinds written

| Kind | When | Fields (in order) |
|---|---|---|
| `sk` | Skill new, cap changed, profession rank changed, or skill dropped | name; rank (number); max (number). Rank 0 and max 0 = dropped |
| `lr` | Spell, ability or recipe learned | name; spell id (number, may be empty) |
| `rc` | Recipe learned (written **in addition** to `lr`) | name; spell id |
| `ta` | Talent spent or unspent changed | spent (number); unspent (number, may be empty) |
| `cu` | Consumable used | item id (number); kind (`food` `drink` `potion` `elixir` `flask` `bandage` `scroll` `other`); item name; combat (`1` when used in combat, else empty) |
| `pt` | A beast was tamed | family; pet name (as the pet bar first shows it); pet level (number) |

`ss` is no longer written by Character. See **Screenshots (core)**.

#### Counts

Namespace `spells`:
- `total` +1 per counted cast. `combat` or `calm` +1 (combat = `InCombatLockdown()`).
- `c:<spell name>` or `o:<spell name>` +1 (in / out of combat). The name has no rank, so ranks merge.
- `castTime` + seconds from cast start to stop/fail/interrupt, or channel start to channel stop, rounded to 0.1 s.
- `combatSec` + whole seconds of each fight (rounded).

Namespace `items` (consumables):
- `total` +n, `k:<kind>` +n, `c:<itemID>` or `o:<itemID>` +n.

Namespace `character`:
- `learned` +1 per `lr`. `recipes` +1 per `rc`. `respecs` +1 when spent talent points went down.
- `buffs` +1 per newly gained buff. `buffsFromOthers` +1 when another player cast it. `special:<name>` +1 for Self-Found, String of Ears, Soul of Iron.
- `form:<form spell name>` +1 per form entered (fallback name `form <index>`).
- `totem:<totem name>` +1 per totem placed.
- `petn:<family>|<pet name>` set to 1 the first time a pet is seen. `pet:<family>` +1 at the same moment. `tames` +1 when that pet was just tamed.

Namespace `prof` (crafting; gathering part is moved, see rules 36–37):
- `<verb>|<item name>|<profession>` +n per "You create" line. Verb by profession key: Mining → `smelted`, Cooking → `cooked`, Enchanting → `applied`, anything else → `made`. Profession unknown → "?".

#### Snapshots per level

"Current level" = `UnitLevel("player")` at write time.

| Name | Value | Written |
|---|---|---|
| `skills` | All skills, sorted by name, as `<header>:<name>=<rank>/<max>` joined with `;` ("?" for a missing number, empty header allowed) | After every full (not partial) skill check; always the latest |
| `talents` | spent points | With every `ta` line |
| `casts` | `spells.total` at the moment of the ding | On `PLAYER_LEVEL_UP`, keyed by the new level |
| `bestFight` | { n casts, sec, t = epoch time, place } | At fight end, when n > the stored n for this level |
| `buffs` | Special buffs held now, sorted, joined with `,` | Each full buff scan, when the list is non-empty **or** a value already exists (so it can go back to empty) |
| `stats` | Statistics pane list | At the ding read, or the first read in a level |
| `statsNow` | Statistics pane list | Every read; the latest in this level |

#### Rules and edge cases

**Skills**

1. Read the skill list with `C_SkillInfo.GetNumSkillLines` / `GetSkillLineInfo(i)` (name, isHeader, isCollapsed, rank, maxRank). Fall back to the legacy global functions when that table is missing.
2. A header row sets the category for the rows below it. A **collapsed** header makes the read **partial**.
3. A name seen twice in one read: keep the first.
4. An empty read writes nothing.
5. Known state comes from the journal's own `sk` lines: the last line per name wins; rank 0 means "not known". Build it once per journal per session.
6. For each skill (sorted by name) write `sk` when: not known, or max differs, or it is a profession (Profession key lookup finds it) and rank differs. So non-profession skills (weapon skills, languages) only write on new / trained / dropped.
7. Partial read: no drop check, no snapshot.
8. Full read: each known name missing from the list gets `sk name 0 0`, sorted. Then the `skills` snapshot.

**Learned spells and recipes**

9. Chat lines: match the client's GlobalStrings `ERR_LEARN_SPELL_S`, `ERR_LEARN_ABILITY_S` and `ERR_LEARN_RECIPE_S` (the recipe one marks a recipe). **Memories differs:** the source matches English text only; build patterns from GlobalStrings so localized clients work.
10. From the matched text: spell id from the `|Hspell:<id>` link, name from the bracketed link text, else the plain text without a trailing period.
11. `LEARNED_SPELL_IN_SKILL_LINE`: name = `C_Spell.GetSpellName(spellID)`.
12. The event and the chat line name the same spell: ignore a name already recorded less than **10 s** ago.
13. Recipes: `NEW_RECIPE_LEARNED` (name from `C_Spell.GetSpellName(recipeID)`) or the recipe chat line. Same 10 s name dedupe, its own list. Either source may be missing.

**Talents**

14. Read: `C_ClassTalents.GetActiveConfigID()`. Candidate specs: the current spec (`C_SpecializationInfo.GetSpecialization` → `GetSpecializationInfo`), then the class's other specs (`GetSpecializationInfoForClassID`). For each spec, tree = `C_ClassTalents.GetTraitTreeForSpec`; spent = sum of `ranksPurchased` from `C_Traits.GetNodeInfo(config, node)` over `C_Traits.GetTreeNodes(tree)`. Keep the tree with the highest spent among trees with at least 1 readable node. Unspent = `quantity` of the first entry of `C_Traits.GetTreeCurrencyInfo(config, tree, false)`.
15. The legacy talent calls return nothing on Forever; use the traits path only.
16. Write `ta` only when spent or unspent differs from the last `ta` line. If spent is lower than the last line's spent, `respecs` +1.

**Casts**

17. Only unit `"player"`. Skip ids 75, 5019, 6603 entirely.
18. Mount casts (`C_MountJournal.GetMountFromSpell(id)` returns something; cache per id) are left out of every count, but still count as "the last cast" for consumables and still trigger gathering logic.
19. A cast with no readable name is not counted.
20. During a fight (core-owned), each counted cast adds 1 to this fight's cast count and to the core's current fight record (`casts`), which long-fight lines carry.
21. Fight end: `combatSec` += seconds. If casts > 0 and casts beat this level's `bestFight`, store it. Place = `GetRealZoneText()`, or the instance name (`GetInstanceInfo()`) when `IsInInstance()`.

**Consumables**

22. Bag scan: bags 0–4 via `C_Container`, only items whose item class (`C_Item.GetItemInfoInstant`) is 0 (consumable). Sum stack counts per item id. The first scan is only a baseline.
23. A drop of **1 to 3** units of one item id is a candidate. Bigger drops are ignored (sold, banked, mailed).
24. Pair a drop with the player's last successful cast within **1.5 s**, in either order: drop after cast → credit now; drop first → hold it; the next cast within 1.5 s credits it. Held drops older than **2.0 s** are discarded (destroyed, traded, sold).
25. Kind: class 0 subclass 5 → `drink` when the paired cast's name is the Drink spell's name, else `food`. Subclass 1 `potion`, 2 `elixir`, 3 `flask`, 4 `scroll`, 7 `bandage`, else `other`. **Memories differs:** the source checks the English word "Drink"; compare with the localized name of a Drink spell instead (for example `C_Spell.GetSpellName(430)`; verify the id in game).
26. Combat flag = `InCombatLockdown()` at credit time.
27. Lines: one `cu` line per unit used, **at most 3** per credit.

**Buffs**

28. If `C_Secrets.ShouldAurasBeSecret()` is true, skip the scan: add 1 to a session-only "skipped" counter, keep the first reason text, and schedule a rescan in **5 s** (Coalesce). The game sends no `UNIT_AURA` when auras become readable again.
29. Read `C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")` for i = 1..40 in a protected call; stop at the first empty slot. If any read fails with an error containing "cannot be accessed when secret", treat it like rule 28 and **drop the whole half-read scan** (no counts, known buffs stay). Other errors are real errors.
30. The first scan after login only notes what is on. Later, a buff name not in the previous scan is "gained". "From other" = source unit exists, is not `"player"`, `UnitIsPlayer` is true and `UnitIsUnit(source, "player")` is false. Special buffs: name contains "Self-Found", "String of Ears" or "Soul of Iron". **Memories:** prefer matching these by aura `spellId` once the ids are known; the English substring match fails on localized clients.

**Forms, totems, pets**

31. Form: `GetShapeshiftForm()`. First read (login +3 s) is a baseline. Index 0 (no form) is never counted. A change to a non-zero index counts `form:<C_Spell.GetSpellName of GetShapeshiftFormInfo's spell id>`.
32. Totem: `GetTotemInfo(slot)`; count only when it reports a totem with a non-empty name.
33. Pet: if `UnitExists("pet")`, family = `UnitCreatureFamily("pet")` or `UnitCreatureType("pet")`. "Tamed" = a Tame Beast (1515) success less than **30 s** ago; then write `pt` and forget the tame. A pet with no family records nothing. A pet already counted (same family and name) is not counted again (summons, reloads).

**Crafting**

34. Match `CHAT_MSG_LOOT` against `LOOT_ITEM_CREATED_SELF` and `LOOT_ITEM_CREATED_SELF_MULTIPLE` (GlobalStrings). Item = the link's bracket text; n = the multiplier, default 1. **Memories differs:** the source matches English "You create:" only.
35. The profession is the open trade window's name (set on show, cleared on close); else "?".

**Gathering-cast counts — ownership (recommendation)**

36. The source counts one `prof` entry per gathering cast in Character: `<verb>|<node>|<profession>` with verbs Mining `mined`, Herbalism `picked`, Skinning `skinned`, Fishing `caught`, Disenchant `disenchanted` (profession Enchanting). It fires on cast success, even with an empty loot window or a missed fish.
37. **Recommendation:** Memories_Gathering owns every gathering count (node casts and items). Character keeps crafting counts and the Disenchant cast count (Disenchant is crafting-side, not a world node). Character must not match gathering casts at all. Any stats view that read the old `prof` gathering keys reads Gathering's `gather` namespace instead.

**Statistics pane**

38. Read with `GetStatisticsCategoryList`, `GetCategoryNumAchievements(cat)`, `GetAchievementInfo(cat, i)` (stat id), `GetStatistic(id)`. Skip if any of these is missing.
39. Clean each value: gold/silver/copper coin textures become `g`/`s`/`c`, other textures are removed, the characters `|`, `;`, `=` are removed, then trim. Skip empty, `--` and `0`.
40. List = `<id>=<value>` joined with `;`. An empty list writes nothing (the pane can be empty right after login).

**Level-up**

41. On `PLAYER_LEVEL_UP(newLevel)`: `casts` snapshot now. Ask the core for a level-up screenshot after **1.5 s** (if the core setting is on), why = `level <N>`. Statistics read at **+4 s** (as a ding read). Skills and talents at **+6 s** (the new talent point shows late).

#### New-findings-only rule

- Applies to `cu` only in this part.
- **Off (default):** a `cu` line for every unit used (max 3 per credit). **Differs from source:** none; the source also writes every use.
- **On:** write `cu` only when the item's counters `c:<id>` + `o:<id>` were **0 before** this credit. Decide from counts, never by scanning the journal. Write one line even if 3 units were used.
- Counts run in both modes.

#### Interfaces needed / offered

Needed from core:
- `On(event, fn)` event bus; `Coalesce(key, seconds, fn)`; timers.
- `Write(kind, fields…, at?)` → line to the writable target; honors the kind switch.
- `Count(namespace, key, n)` and `Counts(namespace)` (read).
- `Snap(level, name[, value])`; `Lines(kind)` to rebuild known skills from `sk` lines.
- `Clean(value)` secret check; `HIDDEN` = "?".
- `ProfessionKey(name)`.
- Fight state: `InFight()` → current fight record or nothing; fight start / fight end callbacks.
- `TakeScreenshot(why)` and the `shots.level` setting (core).
- `IsKindOn(kind)`, `Option(key)` for "new findings only".

Offered: none required. Optional: `secretAuras` status (skipped count, first reason) for a debug view.

#### Test cases

1. **Given** known `sk` "Mining 50/75". **When** the skill list shows Mining 51/75. **Then** one `sk Mining 51 75` line and the `skills` snapshot updates.
2. **Given** the "Secondary Skills" header is collapsed and First Aid is known. **When** a check runs. **Then** First Aid is not dropped and no snapshot is written.
3. **Given** a Spanish client. **When** the skill list shows "Minería" rank change. **Then** it is treated as a profession and writes `sk`.
4. **Given** `LEARNED_SPELL_IN_SKILL_LINE` for Fishing at t=0. **When** the chat line for Fishing arrives at t=0.3. **Then** exactly one `lr` and `learned` +1.
5. **Given** last `ta` spent 10. **When** a read gives spent 0, unspent 10. **Then** `ta 0 10` and `respecs` +1.
6. **Given** out of combat. **When** the player casts Attack (6603) and a mount spell. **Then** `spells.total` is unchanged.
7. **Given** 5 Conjured Water in bag 0. **When** a Drink cast succeeds at t=0 and bags show 4 at t=0.3. **Then** `cu <id> drink <name>` with empty combat, `items.k:drink` +1.
8. **Given** a drop of 1 bandage at t=0 and no cast. **When** a cast lands at t=1.0. **Then** credited. **When** instead the cast lands at t=2.5. **Then** not credited.
9. **Given** new-only ON and `c:`/`o:` for item 159 are 0. **When** item 159 is used twice. **Then** one `cu` line; `items.total` +2.
10. **Given** auras are secret. **When** `UNIT_AURA` fires. **Then** no counts; a rescan is scheduled 5 s later.
11. **Given** Tame Beast succeeds at t=0. **When** a new wolf pet appears at t=12. **Then** `pt Wolf <name> <level>`, `tames` +1, `pet:Wolf` +1. **When** it is resummoned later. **Then** no new counts.
12. **Given** level 9. **When** `PLAYER_LEVEL_UP(10)`. **Then** snapshot `casts` at 10 now; screenshot request at +1.5 s (if on); stats at +4 s; skills and talents at +6 s.

---

### Milestones

#### Events and hooks

- `FACTION_STANDING_CHANGED(factionID, updatedStanding)` → reputation. The second value is the **reputation value** (Friendly starts at 3000), not the standing tier.
- `QUEST_ACCEPTED` → quest. Forever gives `(questId)`; older Classic clients give `(questLogIndex, questId)`. Use the last value present.
- `HEARTHSTONE_BOUND` → `GetBindLocation()`.
- `CHAT_MSG_SYSTEM` → home line (pattern from `ERR_DEATHBIND_SUCCESS_S`) and the new flight path line (`ERR_NEWTAXIPATH`).
- `UI_INFO_MESSAGE(type, message)` → message equal to `ERR_NEWTAXIPATH`.
- `TAXIMAP_OPENED` → the current flight node: loop `NumTaxiNodes()`, the node whose `TaxiNodeGetType(i)` is `"CURRENT"`, name = `TaxiNodeName(i)`.
- `ITEM_TEXT_BEGIN` → `ItemTextGetItem()`.

#### Kinds written

All Milestones lines carry the player's position at the moment (from core), unless a captured position is given.

| Kind | When | Fields |
|---|---|---|
| `rp` | Reputation value changed | faction name; value (number); standing (1 Hated … 8 Exalted, from `reaction`); label (`FACTION_STANDING_LABEL<standing>`) |
| `qa` | Quest accepted | quest id (number); title (may be empty) |
| `hb` | Hearthstone bound to a new home | home name |
| `fp` | New flight path learned | node name ("?" if none) |
| `bk` | First read of a book, letter or plaque title | title |

#### Counts

Namespace `milestones`: `questsAccepted` +1 per `qa`; `flightPaths` +1 per `fp`; `booksRead` +1 per read (**every** read, also repeats).

#### Snapshots per level

None.

#### Rules and edge cases

1. Reputation: name and reaction from `C_Reputation.GetFactionDataByID(id)`. No name → nothing. Value = the event's value, else `currentStanding` from the data.
2. Reputation dedupe: skip when the value equals the last value written for that faction **this session**. Session memory only; after a reload the first change always writes.
3. Quest: title from `C_QuestLog.GetTitleForQuestID(id)`. If missing, wait **2 s** and try once more; write anyway (title may be empty). Use the position captured at accept time.
4. Home: the chat pattern is built from the localized `ERR_DEATHBIND_SUCCESS_S` (its `%s` becomes the captured name; other pattern characters escaped). English fallback: "<name> is now your home.".
5. Home dedupe A: chat line and `HEARTHSTONE_BOUND` tell the same moment; skip the same home within **10 s**.
6. Home dedupe B: skip when the last `hb` line in the journal names the same home (bound again at the same inn).
7. Flight path: both sources fire; ignore a second "new path" within **10 s**.
8. Flight path node: if the flight map opened up to **6 s** before, use its current node. Else wait: a map opening within **6 s** after names it. Else after 6 s use `GetSubZoneText()`, then `GetZoneText()`. Position = where the message came.
9. Book: empty or missing title → nothing. Known titles are rebuilt from the journal's `bk` lines once per session.
10. Every game call is protected; a failure is logged and treated as "no value".

#### New-findings-only rule

Does not apply. `bk` is already first-per-title by design (same as source).

#### Interfaces needed / offered

Needed: event bus, timers, `Write` (with position), `Count`, `Lines(kind)` for `hb` and `bk`, `Position()` ("here"), `Clean`, `IsKindOn`.
Offered: none.

#### Test cases

1. **Given** Stormwind at 3000. **When** `FACTION_STANDING_CHANGED(72, 3250)`. **Then** `rp Stormwind 3250 5 Friendly`.
2. **Given** that line written. **When** the same event repeats with 3250. **Then** nothing.
3. **Given** a quest whose title is not yet cached. **When** accepted. **Then** after 2 s a `qa <id> <title or empty>` line with the accept-time position.
4. **Given** last `hb` is Goldshire. **When** the player binds in Goldshire again. **Then** nothing.
5. **Given** a Spanish client. **When** the localized "<inn> es ahora tu hogar" line arrives and `HEARTHSTONE_BOUND` 0.2 s later. **Then** one `hb` line.
6. **Given** the flight map opened at t=0 with current node "Sentinel Hill". **When** `ERR_NEWTAXIPATH` arrives at t=2. **Then** `fp Sentinel Hill`, `flightPaths` +1.
7. **Given** `ERR_NEWTAXIPATH` at t=0 via `UI_INFO_MESSAGE` and chat at t=0.1. **When** no map opens. **Then** one `fp <subzone>` at t=6.
8. **Given** a plaque "In Memory of" already has a `bk` line. **When** read again. **Then** no line, `booksRead` +1.

---

### Gathering

#### Events and hooks

- `UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)` → for a known cast, remember { castGUID, target name }. Empty or secret target → no name.
- `UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)` → for a known cast, remember { what, profession, node name (only if the sent castGUID matches), time }.
- Secure post-hook on `C_Container.UseContainerItem(bag, slot)` → if `C_Container.GetContainerItemInfo(bag, slot).hasLoot`, remember { item id, name (`C_Item.GetItemNameByID`), time }. Items without loot (a potion) are ignored.
- `LOOT_OPENED(autoLoot, isFromItem)` → classify and record.
- `UI_ERROR_MESSAGE(type, message)` → `ERR_FISH_ESCAPED` / `ERR_FISH_NOT_HOOKED`.

**Known casts (by localized name, see Shared facts):** Mining, Herb Gathering, Herbalism, Skinning → `gather` with that profession (Herb Gathering → Herbalism). Pick Pocket → `pick`. Opening, "Opening - No Text" → `chest`. Fishing is not a known cast here; fish are found by `IsFishingLoot()`.

#### Kinds written

| Kind | When | Fields |
|---|---|---|
| `ga` | Item from a gathering loot window (see new-only rule) | prof (Mining, Herbalism, Skinning); node (vein/herb/creature name, "?" if hidden); object id (number); item id; quality; count (only when > 1); item name; why (`rare`, `first`, or empty) |
| `fs` | Item from a fishing loot window | item id; quality; count (only when > 1); item name; object id (the pool's, if any); why |
| `op` | A container item or a chest opened | how (`item` or `chest`); item id (for `item`); name (item name or chest name, "?" if hidden); object id (for `chest`) |
| `pp` | A pick pocket | who (target name, "?" if hidden); npc id; item id; quality; item name |

#### Counts

Namespace `gather`:
- `<prof>` +count and `item:<prof>|<itemID>` +count per gathered item.
- `Fishing` +count and `item:Fishing|<itemID>` +count per fished item.
- `fish:escaped` +1, `fish:missed` +1.
- `open:item` +1, `open:chest` +1.
- `pickpockets` +1 per pick pocket loot window (even money only).
- **Moved from Character (recommended):** `cast:<verb>|<node>|<profession>` +1 per successful gathering cast (verbs `mined`, `picked`, `skinned`, `caught`). Counted at cast success, independent of the loot window.

#### Snapshots per level

None.

#### Rules and edge cases

1. **Classification on `LOOT_OPENED`**, in this order:
   1. `IsFishingLoot()` true → **fish**.
   2. `isFromItem` true, or a loot-bearing item used within **2 s** and no known cast within **3 s** → **item**.
   3. A known cast within **3 s** → its what (`gather`, `pick`, `chest`).
   4. Else nothing (a corpse; another part reads loot from chat).
2. After every `LOOT_OPENED`, forget the remembered cast and item use (one window each).
3. **Reading the window:** for each slot `1..GetNumLootItems()`: `GetLootSlotType` money → "has money"; item → `GetLootSlotInfo` (name, count, quality, isQuestItem) and the item id from `GetLootSlotLink`. A slot without an item id is skipped. Count defaults to 1.
4. **Source ids:** from the first slot whose `GetLootSourceInfo(slot)` returns a GUID. GUID form `Type-0-server-instance-zone-ID-spawn`; the 6th dash field is the id. `GameObject` → object id; `Creature` or `Vehicle` → npc id.
5. **Rare:** for `ga`, quality ≥ **3** (blue) or item id in {13468 Black Lotus, 12363 Arcane Crystal}. For `fs`, quality ≥ **2** (green). `why` = `rare` beats `first`.
6. **Gather:** one record per item slot, with the cast's profession and node name.
7. **Fish:** one record per item slot.
8. **Item open:** one `op` per window with the used item's id and name (both empty when only `isFromItem` was known; name then "?").
9. **Chest:** write `op` only if the window has money or at least one **non-quest** item. Quest crates opened with the same cast hold only their quest item and are skipped. Name = the cast's target name.
10. **Pick pocket:** the "best" item is the highest quality, first one wins on ties. Money-only window → count only.
11. **Fish escape:** `UI_ERROR_MESSAGE` with `ERR_FISH_ESCAPED` → `fish:escaped`; `ERR_FISH_NOT_HOOKED` → `fish:missed`. GlobalStrings are localized, so this works on any client.
12. Every game call is protected. No source GUID → no object id. Hidden target name → node "?".
13. Unproven on Forever: `IsFishingLoot`, `GetLootSourceInfo`, and the sent-target name. Each falls back as above; never error.

#### New-findings-only rule

Option "new findings only", default **off**.

| Kind | Off (default) | On | Source |
|---|---|---|---|
| `ga` | **Every** gathered item writes a line. `why` = `rare`, `first`, or empty | Only when rare, or the per-item counter `item:<prof>|<id>` was **0 before** this find | Source writes only first-of-item or rare, decided by scanning `ga` lines. **Differs** |
| `fs` | **Every** fished item writes a line | Rare (green+) or counter `item:Fishing|<id>` was 0 before | Same difference as `ga` |
| `op` | Every opening (chest rule 9 still applies) | Same as off | Same as source |
| `pp` | **Recommended:** every successful pick pocket with **any** item (best item) | Best item green or better (quality ≥ 2) | Source: green or better only. **Differs** when off |

- "First" is decided from counts only, never by scanning the journal. Note: the source's "first" is per item across all gathering professions; the counter is per profession + item. Accept that small difference.
- Counts run in both modes and even when a kind is off.

#### Interfaces needed / offered

Needed: event bus; **secure post-hook helper** (`HookAfter(table, "UseContainerItem", fn)`); `Write` with position (core "here"); `Count` / `Counts`; `Clean`; `IsKindOn`; `Option("gathering.newOnly")`.
Offered: optional `LastGatherCast()` for any part that needs node names. Character no longer matches gathering casts.

#### Test cases

1. **Given** new-only off, Copper Ore counter 5. **When** a Mining window gives 2 Copper Ore. **Then** `ga Mining "Copper Vein" <obj> 2770 1 2 "Copper Ore" ""`; `gather.Mining` +2.
2. **Given** new-only on, Copper Ore counter 5. **When** the same window. **Then** no line; counts +2.
3. **Given** new-only on, Silverleaf counter 0. **When** a Herbalism window gives Silverleaf. **Then** `ga … why first`.
4. **Given** new-only on, Black Lotus counter 3. **When** gathered. **Then** `ga … why rare`.
5. **Given** a Spanish client (cast name "Minería"). **When** the cast succeeds and the window opens 1 s later. **Then** classified as gather, prof Mining.
6. **Given** `IsFishingLoot()` true. **When** the window holds a green fish (counter 9), new-only on. **Then** `fs … why rare`.
7. **Given** `UI_ERROR_MESSAGE` with `ERR_FISH_NOT_HOOKED`. **Then** `fish:missed` +1, no line.
8. **Given** an Opening cast on a quest crate holding only a quest item. **When** the window opens. **Then** nothing.
9. **Given** an Opening cast on a chest with money. **Then** `op chest "<chest name>" <object>`; `open:chest` +1.
10. **Given** a Heavy Junkbox (hasLoot) used at t=0. **When** the window opens at t=1 with `isFromItem` true. **Then** `op item <id> "Heavy Junkbox"`.
11. **Given** new-only off. **When** a pick pocket yields only a grey item. **Then** `pp <who> <npc> <id> 0 <name>`; `pickpockets` +1. **Given** new-only on. **Then** count only.
12. **Given** a pick pocket with money only. **Then** `pickpockets` +1, no line.

---

### Screenshots (core)

Moves from Character to the core. Every screenshot the game saves gets an `ss` line, **except** silent ones (the Share card's picture).

#### Events and hooks

- `SCREENSHOT_SUCCEEDED` → answer "ok".
- `SCREENSHOT_FAILED` → answer "failed".
- `SCREENSHOT_STARTED` exists in the API docs but is unproven on Forever (see rule 9).
- `Screenshot()` is the game call that takes the picture.
- `PLAYER_LEVEL_UP` (via Character) → level-up shot.

#### Kinds written

| Kind | When | Fields |
|---|---|---|
| `ss` | The game answers a screenshot the addon asked for (non-silent), or saves one taken by hand | why (`level N`, `last boss <name>`, `by hand`, or any caller text); result (`ok` or `failed`); file (predicted file name; empty when failed) |

#### Counts

Namespace `character` (or a core namespace; pick one): `shots` +1 per ok line, `shotsFailed` +1 per failed line.

#### Snapshots per level

None.

#### Rules and edge cases

1. **Waiting list.** Before calling `Screenshot()`, the caller adds an entry { why, time } to a list, oldest first. `why` empty = silent.
2. **Each answer goes to the oldest entry.** First drop entries older than **10 s**. Then take the oldest:
   - entry with why → write `ss why result file`.
   - silent entry → write nothing.
   - no entry, answer ok → write `ss "by hand" ok file`.
   - no entry, answer failed → nothing (no file was made).
3. **Simulated journal:** a by-hand shot is not written into a simulation.
4. **Take(why):** add the entry, call `Screenshot()` in a protected call. If the call errors: remove the entry and write `ss why failed` at once.
5. **Expect(why) / Cancel(entry):** for callers that call `Screenshot()` themselves (the Share card). Expect right before the call, Cancel when the call fails. A Print Screen pressed just before Expect keeps its own by-hand line.
6. **Predicted file name** (built when the answer comes):
   - Stem = `WoWScrnShot_` + local date/time as `MMDDYY_HHMMSS` (two-digit month, day, year, hour 00–23, minute, second), from the clock at the answer.
   - Extension from `C_CVar.GetCVar("screenshotFormat")`: `jpeg` or `jpg` → `.jpg`, `png` → `.png`, `tga` → `.tga`. Missing or unknown → no extension (stem only).
   - **Memories differs:** the source stores only the stem; Memories stores stem + extension.
   - The answer can come about **1 s** after the file's real time, so the name can be one second late. A viewer looking for the file should also try the previous second.
7. **Level-up shot:** setting `shots.level`. On `PLAYER_LEVEL_UP`, wait **1.5 s** (the level-up art shows), then Take(`level <N>`). **Memories default: on** (all recording on); source default was off. Flag for the core owner: this writes files to disk, so confirm the default.
8. **Last-boss shot:** setting `shots.lastBoss`, same default question. The dungeon part asks 1 s after the kill, and only if the current journal is still the one the boss was written in. In a simulation it writes `ss <why> ok` at once without a real shot.
9. **Known race:** a Print Screen whose answer is still pending when a silent shot is expected (within about 1 s) swaps the two: the silent picture is saved as "by hand". Fix later with `SCREENSHOT_STARTED` if it is proven on Forever.
10. Kind `ss` off → no line, counts still run.

#### New-findings-only rule

Does not apply.

#### Interfaces needed / offered

Offered (public core API):
- `TakeScreenshot(why)` → asks and records.
- `ExpectScreenshot(why or empty)` → returns a handle; `CancelScreenshot(handle)`.
- Setting reads `shots.level`, `shots.lastBoss`.

Needed: the game's `Screenshot()`, `C_CVar.GetCVar`, `date`/`time`, the event bus, `Write`, `Count`, the target journal's simulation flag.

#### Test cases

1. **Given** `screenshotFormat` = `jpeg`, local time 2026-11-06 14:03:09. **When** a by-hand shot succeeds. **Then** `ss "by hand" ok WoWScrnShot_110626_140309.jpg`, `shots` +1.
2. **Given** `screenshotFormat` = `png`. **When** Take(`level 10`) succeeds. **Then** `ss "level 10" ok WoWScrnShot_….png`.
3. **Given** Expect(silent). **When** `SCREENSHOT_SUCCEEDED`. **Then** no line.
4. **Given** Take(`level 10`) at t=0 and no answer. **When** a by-hand shot succeeds at t=15. **Then** the old entry is dropped; `ss "by hand" ok …`.
5. **Given** Take(`last boss Van Cleef`). **When** `SCREENSHOT_FAILED`. **Then** `ss "last boss Van Cleef" failed` with empty file, `shotsFailed` +1.
6. **Given** `Screenshot()` throws. **When** Take(`level 5`). **Then** `ss "level 5" failed` at once; no entry is left waiting.
7. **Given** `shots.level` on. **When** `PLAYER_LEVEL_UP(20)`. **Then** `Screenshot()` is called 1.5 s later with why `level 20`.
8. **Given** kind `ss` turned off. **When** a by-hand shot succeeds. **Then** no line; `shots` +1.

## Appendix E — Memories_Social: Social, PvP

Behavior description. The Appendices rules in the Implementation guidelines apply.
Sub-addon **Memories_Social**, using only the public core API. All kinds record by default; a kind turned off writes **no line**, but **counts still run**. A secret value is treated as unknown and never stored. `?` marks a hidden name.

### Social

#### Events and hooks

- `GROUP_ROSTER_UPDATE`: scan the group, merged into one run **1 s** after the last event.
- Login: scan the group **5 s** after login, and read your own guild **7 s** after login. If `IsInGuild()`, ask for the roster once with `C_GuildInfo.GuildRoster()`.
- `PLAYER_GUILD_UPDATE`, `GUILD_ROSTER_UPDATE`, `GUILDTABARD_UPDATE`: read your own guild, merged into one run **2 s** after the last event.
- Core message "journal restored from a backup" (current, real, writable journal): forget the remembered group and scan again.

#### Kinds written

| kind | when | fields |
|---|---|---|
| `gj` | A player is in your party/raid now and was not in the remembered group | name (full), guild (or empty), class token, level |
| `gl` | A remembered member is no longer in the group (you left, or they left) | name |
| `gu` | Your own guild name or rank changed, or you left a guild | guild (empty after leaving), rank name |

#### Counts (group "social")

- `joins` +1 per `gj`.
- `guildmateJoins` +1 when the joiner's guild equals your guild from the last `gu` line.
- `guildChanges` +1 per `gu`.

#### Snapshots per level

- `guild` at your current level: guild name, rank name, rank index, tabard. Written with every `gu` that has a guild. Also filled in when the guild is unchanged but this level has no guild snapshot yet, or it has no tabard.
- Tabard: background, border and emblem colors (`{r, g, b}`, 0-1, 3 decimals), emblem file ID, emblem style.

#### Saved state outside the journal

- Per character: **tabards by guild name**. Every guild you were in keeps its last tabard. Used by the guilds window.
- The player memory and the remembered group are session only.

#### Rules and edge cases

1. **Full name**: "First Surname" when a surname exists, else the first name. No name means unknown, and the unit is skipped.
2. **Name from text** (duel requests, chat): the first `-` becomes a space ("First-Surname" becomes "First Surname").
3. **Reading a player unit**: the unit must exist, be a player, and not be you. The read collects name, first name, class token, race token, level, guild, enemy (true when both factions are known and differ), the time, and the source (target, mouseover, nameplate, group, scan).
4. **Guild read failures**: `GetGuildInfo` on another unit can throw on PvP-restricted tokens. Catch it and treat the guild as unknown. Log only the **first** failure per session; count the rest.
5. **Player memory**: keyed by full name, plus a first-name index that points to the latest full name seen. A new read merges into the old record: known values overwrite, unknown values never erase. A "seen" count goes up by 1 per read.
6. **Memory caps**: **400** enemy players and **100** others per session. Over the cap, the record is still returned for use now but is not kept.
7. **Late guild**: a read reports "guild just learned" when the player was already in memory without a guild and now has one.
8. **Find**: look up by full name first, then by first name (the given string's first word).
9. **Group units**: in a raid, `raid1` to `raidN` (N = `GetNumGroupMembers()`, max **40**); otherwise `party1` to `party4`. Skip yourself.
10. **Remembered group after a load**: when no group is remembered for this journal (login, reload), rebuild it from the journal: every `gj` name with no later `gl`. So a reload never writes duplicate joins, and people who left during a crash get a `gl` on the next scan.
11. **Scan order**: write all joins first, then leaves sorted by name.
12. **Own guild read**:
    - In a guild but the name is not known yet: wait, write nothing.
    - No guild now and no `gu` line ever: write nothing.
    - Same guild and rank as the last `gu`: only fill the level snapshot and the saved tabard (rule above).
    - Otherwise write `gu`. Read the tabard only when in a guild.
13. **Tabard read**: prefer `C_GuildInfo.GetGuildTabardInfo("player")` (log if it throws). Fall back to `GetGuildLogoInfo()`: returns 1-3 background, 4-6 border, 7-9 emblem color (0-255, divide by 255), 10 emblem file, 11 style; only when the 1st and 10th exist.
14. **Script of a name** (for fonts): look at UTF-8 lead bytes; the first match wins. `0xD0`/`0xD1` = Cyrillic, `0xEA`-`0xED` = Korean, `0xE4`-`0xE9` = Chinese, `0xE3` = Japanese, else Latin.
15. **Font for a name**: Korean uses `Fonts\2002.TTF`; Chinese and Japanese use `Fonts\ARKai_T.ttf`. No special font for Latin or Cyrillic. No special font when the client already draws that script (`koKR` for Korean, `zhCN`/`zhTW` for Chinese).

#### Interfaces

- **Needs from core**: events, timers, coalesce (key + delay), current writable journal, write line, add count, level snapshot, journal lines (all, and by kind), per-character saved table, error log, secret-value reader, "journal restored" message, kind on/off switch.
- **Offers (to PvP and UI)**: full name of a unit, name from text, read a player unit (record + "guild just learned"), find by name, remember a record (tests), my guild, open members, script and font for a text.

#### Test cases

1. **Given** no group, **when** Ann and Bob join a party and the roster fires 3 times in 0.5 s, **then** one scan runs 1 s later and writes `gj` Ann and `gj` Bob, and `joins` = 2.
2. **Given** your last `gu` is "Oak Guard" and Bob's guild is "Oak Guard", **when** Bob joins, **then** `guildmateJoins` +1.
3. **Given** lines `gj` Ann, `gj` Bob, `gl` Bob, **when** you reload in a group with Ann and Cid, **then** the scan writes only `gj` Cid.
4. **Given** no `gu` line ever and no guild, **when** the login read runs at 7 s, **then** nothing is written.
5. **Given** you are in a guild but `GetGuildInfo` has no name yet, **when** the read runs, **then** nothing is written; a later roster event writes `gu`.
6. **Given** last `gu` "Oak Guard"/"Member", **when** the rank becomes "Officer", **then** `gu` "Oak Guard","Officer" is written, `guildChanges` +1, the level snapshot is updated, and the tabard is saved under "Oak Guard".
7. **Given** you were in a guild, **when** you leave, **then** `gu` with an empty guild is written and no snapshot is made.
8. **Given** 100 non-enemy players are in memory, **when** a 101st is read, **then** the record is returned but `Find` cannot find it later.
9. **Given** "Ivan Petrov" is in memory, **when** you `Find("Ivan")`, **then** you get his record.

### PvP

#### Events and hooks

- `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`, `NAME_PLATE_UNIT_ADDED` (not in a party/raid instance): read the unit into Social's memory; track enemies.
- `PLAYER_REGEN_DISABLED`: start the combat scan. `PLAYER_REGEN_ENABLED`: keep scanning **5 s** more.
- `CHAT_MSG_COMBAT_HONOR_GAIN`: honor.
- `PLAYER_PVP_KILLS_CHANGED`: lifetime kills (merged, **1 s**) and rank read (merged, **2 s**).
- `PLAYER_DEAD`: fallback loss.
- Core message "a line of kind `de` was written" on the current journal: judge the death.
- `DUEL_REQUESTED(playerName)`, `DUEL_TO_THE_DEATH_REQUESTED(playerName)`, `CHAT_MSG_SYSTEM`: duels.
- `ZONE_CHANGED_NEW_AREA`, `UPDATE_BATTLEFIELD_STATUS`, and **2 s** after each `PLAYER_ENTERING_WORLD`: battleground start or end. `UPDATE_BATTLEFIELD_STATUS` also tracks queues.
- `UPDATE_BATTLEFIELD_SCORE`, `PVP_MATCH_COMPLETE(winner)`: battleground winner.
- `UPDATE_FACTION`, `MAJOR_FACTION_RENOWN_LEVEL_CHANGED`: rank read, merged **2 s**. Also at login + **5 s**.
- At login, store the baseline from `GetPVPLifetimeStats()` (1st return = lifetime honorable kills).

#### Kinds written

| kind | when | fields |
|---|---|---|
| `ep` | An enemy player is met (rules 2-3) | name, class token, race token, level, guild |
| `pk` | A fight with an enemy player is won or lost | result `won`/`lost`, name (or `?`), class, level, guild |
| `hk` | Honor gained in the open world | honor, victim name (if known), victim rank name (classic line only) |
| `du` | Your own duel ended | result `won`/`lost`/`fled`, opponent (or `?`), opponent class token |
| `bg` | You left a battleground | name (or `?`), result `won`/`lost`/`left`, seconds, honor, your honorable kills, killing blows, deaths |
| `rk` | PvP rank differs from the last `rk` line (or there is none, so rank 0 is written once) | rank number, rank title |

#### Counts (group "pvp")

- `met` +1 per `ep`.
- `won` / `lost` per fight. `bgWon` / `bgLost` too when the fight was in a battleground.
- `honor` += honor always; plus `honorBg` or `honorWorld`.
- `hk` += new lifetime kills; plus `hkBg` or `hkWorld`.
- `duel_<result>` +1; `duel_<result>:<CLASS>` +1 when the class is known; `duelDeath` +1 for a duel to the death.
- `bg_<result>` +1; `bgSec` += seconds; `bgPlayed:<name>` +1; `bgWon:<name>` +1 on a win.
- Maximum-style counts (raised only when the new value is higher): `bgBest:<name>` and `bgBest` (most honorable kills in one game), `highestRank` (from the highest rank ever and the current rank).
- `queueSec` += rounded seconds each queue was in "queued" state.

#### Snapshots per level

- `pvp` at your current level, on every rank read: rank, title, points, threshold, highest rank ever, lifetime honorable kills, total honor.

#### Saved state outside the journal

- None. Enemy tracking, "met" times, win guards, the battleground tally, queue start times and the kill baseline are session only.

#### Rules and edge cases

1. **Enemy tracking**: each enemy seen this session has "targeted" and "fought" times. Targeting sets targeted = now, and fought = now when `UnitAffectingCombat("player")`.
2. **`ep` on target**: write it when the enemy was never met this session, or the last `ep` for them was more than **30 minutes** ago.
3. **`ep` on late guild**: from any source, write a new `ep` when the enemy was met before, their guild was just learned, and it differs from the guild on their last `ep`.
4. **Combat scan**: runs every **0.5 s**, only when at least one enemy was seen this session. It stops when you are not in combat lockdown and the 5 s tail has ended. Each tick checks `target`, and `nameplate1`-`nameplate40` unless you are in a party or raid instance.
5. **Scan of one unit**: unknown players are read first (source scan); non-enemies are skipped. A dead or ghost enemy that was fought within **30 s** is a **fight won**, and its fought time is cleared. A living enemy that is your target, or whose target is you, gets fought = now.
6. **Win guard**: at most one win per enemy name per **60 s**. Class, level and guild come from Social's memory.
7. **Honor parsing** (English text):
   - Classic kill line: "<victim> dies, honorable kill Rank: <rank> (Estimated Honor Points: <n>)" gives honor, victim and rank.
   - Otherwise: the first number (commas allowed) followed by " Honor" or " honor" gives honor only.
   - No match: ignore the line.
8. **Honor victim**: the parsed victim, else the enemy fought **or targeted** most recently within **30 s**.
9. **Honor in a battleground** (`IsInInstance` type `pvp`): counts only, and the honor is added to the game tally. No `hk` line.
10. **Honor in the open world**: write `hk`. Then if the victim is a tracked enemy, it is a fight won (with the 60 s guard).
11. **Lifetime kills**: when the 1st return of `GetPVPLifetimeStats()` grows, count the difference (battleground or world, and add it to the game tally). The baseline always updates to the new value.
12. **Death line judged as a player kill**: the line has no creature ID, AND one of these is true:
    - the killer is an enemy in Social's memory,
    - the killer class is one of the 9 class tokens (WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID),
    - the line's byPlayer field is 1.

    A hidden killer (`?`) is never looked up in memory.
13. **Loss from a death line**: remember "death judged now" (player or not). For a player kill, skip it if a fallback loss was written less than **15 s** ago. Otherwise write `pk lost`. Use memory data first, then the line's killer name, class and level.
14. **`PLAYER_DEAD` fires again on spirit release**: ignore it when a death was judged or a loss written less than **30 s** ago.
15. **Fallback loss**: on `PLAYER_DEAD`, pick the enemy with the latest fought time within **15 s** (targeted-only does not count). Wait **6 s**. If no death line was judged and no loss was written since the death, write `pk lost` for that enemy.
16. **Fight moment**: each written `pk` sends a core "moment" (PvP flag, localized toast "Defeated <first name>" / "Slain by <first name>", `?` when no name).
17. **Duel requests**: remember the challenger's name (rule 2 of Social) and whether it is to the death. The game fires these only when you receive a request.
18. **Duel result line**: "<winner> has defeated <loser> in a duel" or "<loser> has fled from <winner> in a duel". "You" = the 1st return of `UnitName("player")`. A name matches you when it equals that or starts with it plus a space. Winner = you gives `won`; loser = you gives `fled` or `lost`. Other people's duels are ignored.
19. **Duel to the death**: true when the line contains "death" (any case), or the remembered request was to the death with the same opponent. Clear the remembered request after each of your results. Class comes from memory.
20. **Battleground start**: on entering a `pvp` instance, start a tally: name from `GetInstanceInfo()`, start time, honor 0, kills 0. Call `RequestBattlefieldScoreData()`.
21. **Battleground winner**: decide once per game. Use the event's winner, else `GetBattlefieldWinner()`, else `C_PvP.GetActiveMatchWinner()`. Your side: Alliance = 1, Horde = 0. At that moment, take your score from `C_PvP.GetScoreInfoByPlayerGuid(UnitGUID("player"))`: honorableKills, killingBlows, deaths, honorGained. Catch and log errors.
22. **Battleground end** (no longer in a `pvp` instance): write `bg`. Result is `left` when no winner was seen. Seconds are rounded. Score values beat tally values.
23. **Reload inside a battleground**: the tally restarts; earlier seconds and honor are lost. Battlegrounds are unproven in game (level 30+).
24. **Queues**: for each index 1..`GetMaxBattlefieldID()`, `GetBattlefieldStatus(i)` "queued" starts a timer; any other status ends it and adds to `queueSec`.
25. **Rank read**:
    - Source: `C_MajorFactions.GetMajorFactionProgressionInfo(2800)`. rank = renownLevel, points = renownReputationEarned, threshold = renownLevelThreshold. No table or no number: stop.
    - Highest rank: 2nd return of `GetPVPLifetimeStats()`, minus 4 when it is 5 or more, else 0.
    - Total honor: `C_CurrencyInfo.GetCurrencyInfo` quantity for `Constants.CurrencyConsts.CLASSIC_HONOR_CURRENCY_ID` (default 1901), then 1792. Unproven.
26. **Rank title**: rank 0 or less gives `PVP_RANK_0_NAME` (else localized "Civilian"). Otherwise `GetText("PVP_RANK_<base+rank-1>_<1 if Alliance else 0>", sex)`, where base = `Enum.PvPRanks.Rank_1` (default 5). If that fails or returns the token itself, use "Rank <n>".
27. **Localized clients**: honor and duel patterns are English only; elsewhere they silently match nothing. Better: build them from GlobalStrings (`DUEL_WINNER_KNOCKOUT`, `DUEL_WINNER_RETREAT`, `COMBATLOG_HONORGAIN`, `COMBATLOG_HONORAWARD`).

#### Interfaces

- **Needs from core**: the Social needs above, plus read counts, last written line, player level, "in fight" state, "line of kind X written" message, moment message, localization.
- **Needs from Social (same sub-addon)**: read a player unit, full name of a unit, name from text, find by name.
- **Offers**: the current battleground tally (name, start, honor, kills, won), or nothing.

#### Test cases

1. **Given** an enemy "Kor Ash" not yet met, **when** you target him, **then** `ep` is written and `met` +1. Targeting him again 10 minutes later writes nothing; 31 minutes later writes a new `ep`.
2. **Given** an enemy was met with no guild, **when** a name plate later shows his guild "Red Fang", **then** a new `ep` with "Red Fang" is written.
3. **Given** you are in combat and fought "Kor Ash" 12 s ago, **when** the scan sees his name plate dead, **then** `pk won` is written, `won` +1, and a toast "Defeated Kor" is sent. If he is seen dead again 20 s later, nothing more is written.
4. **Given** you targeted an enemy 10 s ago, **when** "You have been awarded 6 Honor." arrives in the open world, **then** `hk` 6 with that victim is written, honor and honorWorld +6, and `pk won` is written.
5. **Given** you are in a battleground, **when** 12 honor arrives, **then** there is no `hk` line, honorBg +12, and the tally honor +12.
6. **Given** a `de` line with killer "Kor Ash", no creature ID, and class ROGUE, **when** it is written, **then** `pk lost` is written and `lost` +1. `PLAYER_DEAD` again at release 20 s later writes nothing.
7. **Given** an enemy fought you 8 s before you died and no `de` line comes, **when** 6 s pass after `PLAYER_DEAD`, **then** `pk lost` is written for that enemy.
8. **Given** a `de` line with a creature ID, **when** it is written, **then** no `pk` line, and the later fallback is cancelled.
9. **Given** "Mookz" received a duel to the death from "Immar-Stone", **when** "Immar Stone has defeated Mookz in a duel" arrives, **then** `du lost`, "Immar Stone" is written, with `duel_lost` +1 and `duelDeath` +1.
10. **Given** a battleground with a winner equal to your side and a score of 7 kills, **when** you leave, **then** `bg` with name, `won`, seconds, honor, 7, kb, deaths is written; `bg_won`, `bgPlayed:<name>`, `bgWon:<name>` +1; `bgBest` is at least 7.
11. **Given** the last `rk` was 2, **when** a rank read returns 2, **then** no line is written but the level `pvp` snapshot updates. A read of 3 writes `rk` 3 with its title.

## Completion

When every task is checked and Validation passes, move this file to `specs/done/` with `git mv` (plain `mv` when the file is untracked). Create `specs/done/` if it does not exist. Commit the move.
