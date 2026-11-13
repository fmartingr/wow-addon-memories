# Manual checklist in the game

There is no e2e suite for WoW, so these checks run by hand on the Forever client (esES). The rows are in session
order: run them from top to bottom. Run A has all 6 addons on. Run B (section T) turns `Memories_Combat` off.

## Run record

| Run | Date | Client build (`/dump GetBuildInfo()`) | Locale | Addons on | Tester | Result |
|---|---|---|---|---|---|---|
| A | | | esES | all 6 | | not run |
| B | | | esES | all but `Memories_Combat` | | not run |

## How to run

- **Result:** `not run`, `pass`, or `fail: <what happened>`. Fix a fail in the task that owns it (the Source column)
  before Task 16 closes.
- **Source:** the spec task number, or `V<n>` for step `n` of the spec's Validation.
- **Lua errors:** type `/console scriptErrors 1` once, so an error shows a window.
- **Saved files:** per character `WTF/Account/<account>/<realm id>/<Name>-<Realm>/SavedVariables/<addon>.lua`, and the
  account file `WTF/Account/<account>/SavedVariables/Memories.lua`. The client writes them at `/reload` and logout
  only, so `/reload` before you read a file.
- **Journal lines:** 200 lines are packed into one string. Search the file for `|<kind>|`, or run the converter (row
  S1) and count the kinds with `jq -r '.k + " " + .addon' dist-characters/<id>/journey.jsonl | sort | uniq -c`.
- **Line formats:** each Expected line leaves out the `t|p|m|x|y|` prefix. The fields of each kind are in
  [`kinds.md`](kinds.md).
- **Opportunistic rows:** the rows of section P (level up, rare, world boss, Hardcore) happen when they happen. Check
  them whenever the event comes up in the session.

## A. Before the game (game closed)

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| A1 | V1 | Repo checks | In the repo, run `make check-tools && make lint && make test && make coverage`. | Each command passes. | not run |
| A2 | V2 | 300k lines | Run `busted spec/limit_spec.lua`. | It passes (300,000 lines load). | not run |
| A3 | 1 | Install | Run `make install WOW_DIR=".../_forever_"`. | `Interface/AddOns` holds `Memories`, `Memories_Character`, `Memories_Combat`, `Memories_Economy`, `Memories_Gathering` and `Memories_Social`. | not run |

## B. Load and the AddOn list

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| B1 | 3, 16 | Group in the AddOn list | Start the game and open the AddOn list on the character screen. | The 6 addons show as one group "Memories": "Memories", "Memories - Character", "Memories - Combat", "Memories - Economy", "Memories - Gathering" and "Memories - Social". | not run |
| B2 | 1 | All addons load | Enable the 6 addons and log in. | No Lua error. | not run |
| B3 | 5 | Status | Type `/mem status`. | "Memories: status:", then one `on` line for each of the 6 addons with `<n> lines, <n> kinds off, ...`, then `login time: init <n> ms, login <n> ms, world <n> ms`. | not run |
| B4 | 1 | Command list | Type `/mem`, then `/memories`. | Each prints "Memories: commands:" and the `errors`, `options`, `settings`, `note` and `status` lines. | not run |
| B5 | 1 | Errors box, none | On a clean install, type `/mem errors`. | It prints "Memories: no saved errors." | not run |
| B6 | 3 | Public global | Type `/dump Memories.API_VERSION, Memories.VERSION`. | It prints `1` and the TOC version. | not run |

## C. GlobalStrings and client functions

Every `GlobalStrings` name and client function that the recorders read, checked with `/dump` in the city before the
play starts. Deaths and the low-health popup read no `GlobalStrings` name: the killer, spell and environment come from
`C_DeathRecap` (row L1).

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| C1 | 6, 12 | `COMBATLOG_XPGAIN_FIRSTPERSON` | Type `/dump COMBATLOG_XPGAIN_FIRSTPERSON`. | A text with one `%s` (the creature) and one `%d` (the XP), for example "%s muere, ganas %d p. de experiencia.". The rested and group XP lines (rows G4 and N3) start with the same text. | not run |
| C2 | 6 | `COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED` | Type `/dump COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED`. | A text with one `%d` (the XP). | not run |
| C3 | 6 | `COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP` | Type `/dump COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP`. | A text with two `%d`; the group bonus words come after the second one, for example "(+%d group bonus)". | not run |
| C4 | 6 | `ERR_ZONE_EXPLORED_XP` | Type `/dump ERR_ZONE_EXPLORED_XP`. | A text with one `%s` (the area) and one `%d` (the XP). | not run |
| C5 | 6 | `ERR_ZONE_EXPLORED` | Type `/dump ERR_ZONE_EXPLORED`. | A text with one `%s` (the area). | not run |
| C6 | 9 | `ERR_SKILL_GAINED_S` | Type `/dump ERR_SKILL_GAINED_S`. | A text with one `%s` (the skill), for example "Has aprendido la habilidad %s.". | not run |
| C7 | 9 | Riding names | Type `/dump C_SkillInfo.GetSkillLineInfoByID(762)`, then `/dump C_Spell.GetSpellName(824)` (and 825, 826, 828, 10861, 10906, 10908, 18995). | The skill line 762 has `name` "Equitación" (Riding); each spell is a racial riding skill, for example "Equitación de caballos". Any other name means the id list in `Record/Travel.lua` is wrong. | not run |
| C8 | 9 | Distance unit | Type `/dump GetCurrentRegion(), GetLocale()`. | Region 1 counts in yards, 2 to 5 in meters; any other region falls back to the client language. | not run |
| C9 | 11 | `ERR_FISH_ESCAPED` | Type `/dump ERR_FISH_ESCAPED`. | The Spanish text that the game shows when a hooked fish gets away. | not run |
| C10 | 11 | `ERR_FISH_NOT_HOOKED` | Type `/dump ERR_FISH_NOT_HOOKED`. | The Spanish text that the game shows when the bobber is clicked with no fish. | not run |
| C11 | 11 | Gather spell names | Type `/dump C_Spell.GetSpellName(2575), C_Spell.GetSpellName(2366), C_Spell.GetSpellName(8613), C_Spell.GetSpellName(921), C_Spell.GetSpellName(3365), C_Spell.GetSpellName(7620)`. | "Minería", the herb gathering name, "Desollar", the pick pocket name, the opening name and "Pesca". The cast bar shows the same names when you gather. | not run |
| C12 | 13 | `LOOT_ITEM_SELF` | Type `/dump LOOT_ITEM_SELF`. | A text with one `%s` (the item link), for example "Recibes botín: %s.". | not run |
| C13 | 13 | `LOOT_ITEM_SELF_MULTIPLE` | Type `/dump LOOT_ITEM_SELF_MULTIPLE`. | A text with one `%s` (the item link) and one `%d` (the count) after it. | not run |
| C14 | 13 | `LOOT_ITEM_PUSHED_SELF` | Type `/dump LOOT_ITEM_PUSHED_SELF`. | A text with one `%s` (the item link). | not run |
| C15 | 13 | `LOOT_ITEM_PUSHED_SELF_MULTIPLE` | Type `/dump LOOT_ITEM_PUSHED_SELF_MULTIPLE`. | A text with one `%s` (the item link) and one `%d` (the count). | not run |
| C16 | 13 | `LOOT_ITEM_CREATED_SELF` | Type `/dump LOOT_ITEM_CREATED_SELF`. | A text with one `%s` (the item link). | not run |
| C17 | 13 | `LOOT_ITEM_CREATED_SELF_MULTIPLE` | Type `/dump LOOT_ITEM_CREATED_SELF_MULTIPLE`. | A text with one `%s` (the item link) and one `%d` (the count). | not run |
| C18 | 13 | `LOOT_ROLL_NEED_SELF` | Type `/dump LOOT_ROLL_NEED_SELF`. | A text with an optional `\|HlootHistory:%d\|h[...]\|h:` link in front, then one `%s` (the item link). | not run |
| C19 | 13 | `LOOT_ROLL_GREED_SELF` | Type `/dump LOOT_ROLL_GREED_SELF`. | A text with an optional loot history link in front, then one `%s` (the item link). | not run |
| C20 | 13 | `LOOT_ROLL_ROLLED_NEED` | Type `/dump LOOT_ROLL_ROLLED_NEED`. | A text with an optional loot history link in front, then the roll `%d`, the item `%s` and the player `%s`, in that argument order. | not run |
| C21 | 13 | `LOOT_ROLL_ROLLED_GREED` | Type `/dump LOOT_ROLL_ROLLED_GREED`. | A text with the same arguments as `LOOT_ROLL_ROLLED_NEED`. | not run |
| C22 | 13 | `LOOT_ROLL_YOU_WON` | Type `/dump LOOT_ROLL_YOU_WON`. | A text with an optional loot history link in front, then one `%s` (the item link). | not run |
| C23 | 13 | `LOOT_ROLL_WON` | Type `/dump LOOT_ROLL_WON`. | A text with an optional loot history link in front, then the player `%s` and the item `%s`. | not run |
| C24 | 13 | `LOOT_ROLL_ALL_PASSED` | Type `/dump LOOT_ROLL_ALL_PASSED`. | A text with an optional loot history link in front, then one `%s` (the item link). | not run |
| C25 | 13 | `ERR_TRADE_COMPLETE` | Type `/dump ERR_TRADE_COMPLETE`. | The text that the game shows when a trade completes, with no `%`. | not run |
| C26 | 13 | `AUCTION_EXPIRED_MAIL_SUBJECT` | Type `/dump AUCTION_EXPIRED_MAIL_SUBJECT`. | The subject of an expired auction's mail, with one `%s` (the item name). | not run |
| C27 | 13 | `AUCTION_OUTBID_MAIL_SUBJECT` | Type `/dump AUCTION_OUTBID_MAIL_SUBJECT`. | The subject of an outbid mail, with one `%s` (the item name). | not run |
| C28 | 13 | Item functions | Type `/dump C_Item.GetItemQualityByID(2589), C_Item.GetItemInfoInstant(2589), GetInventoryItemID("player", 5)`. | `1`; `2589`, the type texts, `""`, an icon, `7` and a subclass; the chest item id or nil. | not run |
| C29 | 14 | `ERR_LEARN_SPELL_S` | Type `/dump ERR_LEARN_SPELL_S`. | A text with one `%s` (the spell link), for example "Has aprendido un nuevo hechizo: %s.". | not run |
| C30 | 14 | `ERR_LEARN_ABILITY_S` | Type `/dump ERR_LEARN_ABILITY_S`. | A text with one `%s` (the ability link). | not run |
| C31 | 14 | `ERR_LEARN_RECIPE_S` | Type `/dump ERR_LEARN_RECIPE_S`. | A text with one `%s` (the recipe link). | not run |
| C32 | 14 | `ERR_DEATHBIND_SUCCESS_S` | Type `/dump ERR_DEATHBIND_SUCCESS_S`. | A text with one `%s` (the inn's place), for example "%s es ahora tu hogar.". | not run |
| C33 | 14 | `ERR_NEWTAXIPATH` | Type `/dump ERR_NEWTAXIPATH`. | The text that the game shows for a new flight path, with no `%`. | not run |
| C34 | 14 | `FACTION_STANDING_LABEL1` to `8` | Type `/dump FACTION_STANDING_LABEL1, FACTION_STANDING_LABEL5, FACTION_STANDING_LABEL8, GetText("FACTION_STANDING_LABEL5", 3)`. | "Odiado", "Amistoso", "Exaltado" and the female form of Friendly (or the same text). | not run |
| C35 | 14 | Profession names | Type `/dump C_TradeSkillUI.GetTradeSkillDisplayName(186), C_TradeSkillUI.GetTradeSkillDisplayName(129), C_Spell.GetSpellName(3273)`. | "Minería", "Primeros auxilios" and the First Aid spell name. | not run |
| C36 | 14 | Skill functions | Open the skills pane and type `/dump C_SkillInfo.GetNumSkillLines(), C_SkillInfo.GetSkillLineInfo(2)`. | A count and a table with `name`, `isHeader`, `isCollapsed`, `rank`, `maxRank` and `skillID`. | not run |
| C37 | 14 | Drink spell id | Type `/dump C_Spell.GetSpellName(430)`, then drink a water and check the cast bar. | The same name ("Beber") for the id and the cast. | not run |
| C38 | 14 | Special buff ids | On a Self-Found or Hardcore character, type `/dump C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")` for each buff until you find Self-Found Adventurer, Soul of Iron and String of Ears. | The `spellId` of Self-Found is 431567 and of Soul of Iron 364001; note the id of String of Ears (not matched yet). | not run |
| C39 | 14 | Talent functions | Type `/dump C_ClassTalents.GetActiveConfigID(), C_SpecializationInfo.GetSpecialization()`. | A config id and a spec index (or nil before level 10). | not run |
| C40 | 14 | Statistics functions | Type `/dump GetStatisticsCategoryList()`. | A list of category ids, or an error when the client has no Statistics pane (then `stats` stays empty). | not run |
| C41 | 15 | `DUEL_WINNER_KNOCKOUT` | Type `/dump DUEL_WINNER_KNOCKOUT`. | A text with the winner as `%1$s` and the loser as `%2$s`, for example "%1$s ha derrotado a %2$s en un duelo.". Plain `%s` in the order winner, loser also works. | not run |
| C42 | 15 | `DUEL_WINNER_RETREAT` | Type `/dump DUEL_WINNER_RETREAT`. | A text with the winner as `%1$s` and the one who fled as `%2$s`. | not run |
| C43 | 15 | `COMBATLOG_HONORGAIN` | Type `/dump COMBATLOG_HONORGAIN`. | A text with `%s` (the victim), `%s` (the rank name) and `%d` (the honor), in that order. | not run |
| C44 | 15 | `COMBATLOG_HONORGAIN_NO_RANK` | Type `/dump COMBATLOG_HONORGAIN_NO_RANK`. | A text with `%s` (the victim) and `%d` (the honor), in that order, or nil. | not run |
| C45 | 15 | `COMBATLOG_HONORAWARD` | Type `/dump COMBATLOG_HONORAWARD`. | A text with one `%d` (the honor). | not run |
| C46 | 15 | `PVP_RANK_0_NAME` | Type `/dump PVP_RANK_0_NAME`, then `/dump GetText("PVP_RANK_6_1", UnitSex("player"))`. | The Spanish name of "no rank", then a Spanish rank title. | not run |

## D. Settings page

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| D1 | 5 | Settings page | Type `/mem options`, then `/mem settings`. | Each opens Options > AddOns > Memories with no Lua error. | not run |
| D2 | 5 | General section | Open the Settings page. | "General" shows "Recording rate" (1, 2, 5, 10 s; 2 s chosen), "Save reminder", "Minimap button" and "Low-health flash" (all on). | not run |
| D3 | 5, 11–15 | Kind sections | Scroll the Settings page. | One header `<Addon> — <Group>` per group, each with "Enable all", "Disable all" and one checkbox per kind, all checked: `Memories` — Sessions, Progress, Deaths, Travel, Dungeons, Screenshots, Other addons, Notes (`un`); `Memories_Combat — Combat` (`ki`, `ra`, `fi`); `Memories_Gathering — Gathering` (`ga`, `fs`, `op`, `pp`); `Memories_Character — Character` (`sk`, `lr`, `rc`, `ta`, `cu`, `pt`) and `— Milestones` (`rp`, `qa`, `hb`, `fp`, `bk`); `Memories_Economy — Loot` (`lo`, `rl`, `ge`, `eq`) and `— Money` (`mn`, `tb`, `ah`, `ma`, `tr`); `Memories_Social — Social` (`gj`, `gl`, `gu`) and `— PvP` (`ep`, `pk`, `hk`, `du`, `bg`, `rk`). No checkbox for `nt`. | not run |
| D4 | 5 | New findings only boxes | Look under each group. | "Gathering: new findings only" under Gathering, "Kills: new findings only" under Combat, "Loot: new findings only" under Loot and "Consumables: new findings only" under Character, all off. | not run |
| D5 | 5 | Group buttons | Click "Disable all" under "Memories — Travel", then "Enable all". Repeat under "Memories_Economy — Money". | Every checkbox of that group clears at once, then checks again. No other group changes. | not run |
| D6 | 5 | Minimap setting | Uncheck "Minimap button", then check it. | The minimap button hides and shows at once. | not run |
| D7 | 5 | Settings survive | Change a few settings, `/reload`, open the page. Then set them back. | The same choices are shown after the reload. | not run |

## E. Minimap button and addon compartment

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| E1 | 4 | Minimap tooltip | Hover over the book button on the minimap edge. | The tooltip shows "Memories", the minutes since the last save, "Left click: write a note", "Shift + left click: save (reload)" and "Right click: settings". | not run |
| E2 | 4 | Minimap settings | Right click the minimap button. | The Memories Settings page opens. | not run |
| E3 | 4 | Minimap drag | Drag the minimap button around the minimap, then `/reload`. | It follows the minimap edge and stays at the new place after the reload. | not run |
| E4 | 4 | Minimap save | Shift + left click the minimap button out of combat. Later, in a fight (section H), shift + left click it again. | Out of combat the UI reloads. In combat it prints "Memories: cannot save in combat." | not run |
| E5 | 4 | Compartment | Right click the Memories entry in the addon compartment, then left click it. | The right click opens the Memories Settings page. The left click reloads the UI. | not run |
| E6 | 4 | Compartment in combat | In a fight, left click the Memories entry in the addon compartment. | It prints "Memories: cannot save in combat." and does not reload. | not run |
| E7 | 3 | Minimap note | Left click the minimap button. Click it again while the window is open. Then drag the button a little. | The first click opens the Note window. The second click keeps the window and the text. The drag moves the button and does not open the window. | not run |

## F. Sessions, trail and progress

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| F1 | 6 | Session lines | Log out and log in, wait 5 s, `/reload`, wait 5 s, `/reload`. Read `MemoriesCharDB` in the saved file. | The login writes `in\|login`, `pc\|<id>`, `rs\|<n>`, then `pl\|<played>`; each reload adds `out`, `in\|reload`, `rs`, `pl`. `MemoriesCharDB.sessions` has an entry for each with `start`, `last`, `how`, `computer`, `tz`, `played0`, `played1`. No "Total time played" text shows in the chat at login. | not run |
| F2 | 6 | Away | Type `/afk`, then move. | One `af\|1` line, then one `af\|0` line. | not run |
| F3 | 6 | Jumps | Jump 3 times on land and once while swimming, `/reload`. | `MemoriesCharDB.counts.travel` has `jumps` 3 more and `ascend` 1 more. | not run |
| F4 | 6 | Recording rate | Set "Recording rate" to 10 s, walk for a minute, `/reload`. Set it back to 2 s. | The new chunk's points are about 10 s apart. | not run |
| F5 | 6 | Trail | Walk, mount and ride for a minute, take a flight (row K3), then `/reload`. | `MemoriesCharDB.trail.chunks` has chunks with `s`, `t`, `m`, `n` and `d` text such as `0,4512,6120,-;...`, with `m` and `t` flags while mounted and on the flight. | not run |
| F6 | 6 | Discovery | Enter an area not explored yet. | `di\|<area>\|<xp>` and `xp\|<xp>\|discover\|<area>`; with no XP, one `di\|<area>` line. | not run |
| F7 | 6, 13 | Quest, XP and money | Turn in a quest that gives XP and gold. | One `xp\|<n>\|quest\|<title>` and one `qt\|<id>\|<xp>\|<money>\|<title>` line, in Spanish on the esES client. `MemoriesEconomyCharDB` has `mn\|<copper>\|quest\|<title>`. | not run |

## G. In town: trainers, vendors, mail, auction house

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| G1 | 13 | Gear at login | Log in, wait 5 s, `/reload`, wait 5 s. | One `ge\|<level>\|<19 ids>\|login` only; `snap[<level>].gear` holds the same ids. | not run |
| G2 | 13 | Equip | Take off the chest item, then put it on again. | `eq\|5\|0`, then `eq\|5\|<item id>\|<quality>`. | not run |
| G3 | 13 | Trainer functions | At a trainer, type `/dump GetTrainerServiceInfo(2), GetTrainerServiceCost(2), GetTrainerServiceSkillLine(2), IsTradeskillTrainer()`. | The service name, an availability word (`available`, `unavailable` or `used`), a texture, a level and the rank text; the cost; the skill line name; a boolean. | not run |
| G4 | 13, 14 | Trainer and new spells | Learn two spells at a class trainer, `/reload`. | `MemoriesEconomyCharDB` has `tb\|class\|<spell> (<rank>)\|<cost>` per spell and one `mn\|-<sum>\|trainer\|<names>`; `counts.trainers` grows. `MemoriesCharacterCharDB` has one `lr\|<Spanish name>\|<spell id>` per spell, although the event and the chat line both fire; `counts.character.learned` grows by 2. | not run |
| G5 | 13, 14 | Profession trainer and recipe | Learn a profession rank and a First Aid recipe at a trainer. | `tb\|profession\|...` for the rank; `lr\|<name>\|<id>` and `rc\|<name>\|<id>`, one each, for the recipe. | not run |
| G6 | 9 | Learned mount or riding | Learn riding at a trainer, or learn a new mount. | One `ml\|<name>\|<spell>` (riding: `ml\|<skill name>` or with the racial riding spell). | not run |
| G7 | 13 | Vendor | Sell a stack of 20 Wool Cloth, buy a Refreshing Spring Water, repair all. | `mn\|<copper>\|vendor\|20 <name>`, `mn\|-<copper>\|vendor\|<water name>`, `mn\|-<copper>\|repair`; the bought item writes `lo\|...\|bought\|...`. | not run |
| G8 | 14 | Consumable | Drink a water out of combat. Later, in a fight (section H), use a bandage. | `cu\|<id>\|drink\|<name>` and `cu\|<id>\|bandage\|<name>\|1`; `counts.items` has `k:drink`, `k:bandage`, `o:<id>` and `c:<id>`. | not run |
| G9 | 14 | Crafting | Open Cooking and cook 2 items at once. | `counts.prof["cooked\|<item>\|Cooking"]` 2 more. | not run |
| G10 | 13 | Made item | Craft an item (for example a bandage). | `lo\|<id>\|<quality>\|<count or empty>\|made\|<name>\|...`. | not run |
| G11 | 14 | Bind the hearthstone | Bind at a new inn, then at the same inn again. | One `hb\|<place>`; the second bind writes nothing. | not run |
| G12 | 14 | Read a book | Read a plaque or book twice. | One `bk\|<title>`; `counts.milestones.booksRead` 2 more. | not run |
| G13 | 14 | Accept a quest | Accept a quest. | `qa\|<quest id>\|<Spanish title>` at the place where you accepted it; `counts.milestones.questsAccepted` 1 more. | not run |
| G14 | 13 | Mail functions | Open a mail with an attachment and type `/dump GetInboxHeaderInfo(1)`, then `/dump GetInboxItem(1, 1), GetInboxInvoiceInfo(1)`. | Sender, subject, money, COD, days left, item count, ... `canReply`, `isGM`; the item name, id, texture, count and quality; nil for a player mail. | not run |
| G15 | 13 | Mail send | Send 1 gold and an item to another character. | `mn\|-10000\|mail\|<name>` and `mn\|-30\|postage\|<name>`, then `ma\|send\|<name>\|10000\|<item>`. | not run |
| G16 | 13 | Mail take | Take an item and gold from a player's mail, then take all from another. | `ma\|take\|<sender>\|<copper or empty>\|<item>`, `mn\|<copper>\|mail\|<sender>`, and one `lo\|...\|mail\|...` per item, never two for one item. | not run |
| G17 | 13 | Auction house | Post an item, buy one with buyout, let one expire and take its mail. | `ah\|post\|<deposit>\|<item>` with `mn\|-<deposit>\|auction\|<item>`; `ah\|buyout\|<copper>\|<item>` with `mn\|-<copper>\|auction\|<item>`; `ah\|expired\|\|<item>` and `ma\|take\|...` when the mail is taken. | not run |
| G18 | 13 | Auction sold | Sell an item in the auction house, take the money from the invoice mail. | `ah\|sold\|<copper>\|<item>`, `ma\|invoice\|<buyer>\|<copper>\|<item>`, `mn\|<copper>\|auction\|<item>`. | not run |
| G19 | 13 | Trade | Trade with another player: receive 2 items and 50 silver, give 10 silver. | One `tr\|<name>\|4000`, `mn\|4000\|trade\|<name>` and one `lo\|...\|trade\|...` per item received. | not run |

## H. Open world: combat, loot and gathering

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| H1 | 12 | Unit functions | Target a hostile creature in a fight and type `/dump UnitThreatSituation("player", "target"), UnitIsTapDenied("target"), UnitCreatureType("target"), UnitPlayerControlled("target")`. | A threat number (0 to 3), `false`, the localized type name and its id (for example "Humanoide", 7), `false`. | not run |
| H2 | 12 | Critter type id | Target a rabbit or another critter and type `/dump UnitCreatureType("target")`. | "Alimaña" and `8`. | not run |
| H3 | 12 | Kill in the open world | With name plates on, kill a creature that gives XP, then one grey creature, `/reload`. | `MemoriesCombatCharDB` has `ki\|<name>\|<npc id>\|<type>\|<classification>\|<xp>\|<level>\|\|<1 or empty>` and a `ki` with an empty XP for the grey one; `counts.kills` has `total`, `xp`, `noxp`, `npc:<id>` and `n:<name>`. `MemoriesCharDB` has `xp\|<xp>\|kill\|<name>`. | not run |
| H4 | 12 | Tapped by another | Let another player tag a creature, help to kill it. | No `ki` line. | not run |
| H5 | 12 | Long fight | Fight one creature for more than 20 s. | `fi\|<seconds>\|<target>\|<classification>\|<level>\|\|<casts>`; `counts.fights` has `n`, `sec` and `longest`. | not run |
| H6 | 12 | Reload in combat | `/reload` during a fight longer than 20 s. | No `fi` for that fight. | not run |
| H7 | 11 | Loot functions | Open any loot window and type `/dump IsFishingLoot(), GetLootSourceInfo(1), GetLootSlotLink(1)`. | A boolean, a GUID (`GameObject-...` or `Creature-...`) and an item link. | not run |
| H8 | 13 | Loot | Loot a stack of Linen Cloth from a creature, `/reload`. | `MemoriesEconomyCharDB` has `lo\|2589\|1\|<count or empty>\|loot\|<Spanish name>\|\|<1 or empty>`; `counts.loot` has `items`, `q1` and `item:2589`. | not run |
| H9 | 11 | Mine a vein | Mine a copper vein, loot it, `/reload`. | `MemoriesGatheringCharDB` has `ga\|Mining\|<vein name>\|<object id>\|2770\|1\|<count or empty>\|Mena de cobre\|<first or empty>`; `counts.gather` has `Mining`, `item:Mining\|2770` and `cast:mined\|<vein name>\|Mining`. | not run |
| H10 | 14 | Raise a profession | Mine until Minería rises one rank, wait 3 s, `/reload`. | `sk\|Minería\|<rank>\|<max>`; `snap[<level>].skills` lists every skill as `<header>:<name>=<rank>/<max>`. A weapon skill rank-up writes nothing. | not run |
| H11 | 11 | Fish | Fish until one catch, then let one fish get away and click once with no fish. | One `fs\|<item>\|<quality>\|<count or empty>\|<name>\|<pool id or empty>\|<why>` per caught item; `counts.gather` has `Fishing`, `fish:escaped` and `fish:missed` 1 more each. | not run |
| H12 | 11 | Pick pocket | On a rogue, pick the pocket of a humanoid that gives an item, then one that gives only money. | One `pp\|<name>\|<npc id>\|<item>\|<quality>\|<item name>` for the first; `counts.gather.pickpockets` 2 more. | not run |
| H13 | 11 | Open a container and a chest | Open a Heavy Junkbox (or any lockbox), then a chest in the world. | `op\|item\|<item id>\|<item name>`, then `op\|chest\|\|<chest name>\|<object id>`; a quest crate with only its quest item writes nothing. | not run |
| H14 | 14 | Gain reputation | Turn in a quest that gives Stormwind reputation. | `rp\|Ventormenta\|<value>\|<standing>\|<Spanish label>`; the same value again in the session writes nothing. | not run |
| H15 | 14 | Channel functions | On a hunter, start Tame Beast and type `/dump UnitChannelInfo("player")` during the channel, then cancel a second try by moving. | The channel name, its start and end in ms; the cancelled try writes no `pt` when you call a pet within 30 s. | not run |
| H16 | 14 | Tame | On a hunter, tame a beast. | `pt\|<family>\|<pet name>\|<level>`; `counts.character` has `tames`, `pet:<family>` and `petn:<family>\|<name>`; dismissing and calling the pet adds nothing. | not run |

## I. New findings only

Turn each box off again after its row.

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| I1 | 11 | Gathering: new findings only | Turn on "Gathering: new findings only", mine the same ore as in H9 again, `/reload`. | No new `ga` line; `counts.gather["item:Mining\|2770"]` grows. | not run |
| I2 | 12, V7 | Kills: new findings only | Turn on "Kills: new findings only" and kill the same normal creature twice, `/reload`. | One `ki` line at most, none when the creature was killed before; `counts.kills["npc:<id>"]` grows by 2. | not run |
| I3 | 13 | Loot: new findings only | Turn on "Loot: new findings only", loot Linen Cloth again, then a blue item. | No new `lo` for the cloth (`counts.loot["item:2589"]` grows); a `lo` for the blue item. | not run |
| I4 | 14 | Consumables: new findings only | Turn on "Consumables: new findings only" and drink the same water as in G8 again. | No new `cu` line; `counts.items["o:<id>"]` grows. | not run |

## J. Kind turned off

Check every kind again with "Enable all" after its row.

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| J1 | 5 | Core kind off | Uncheck "Entered a subzone", walk into a new subzone, `/reload`, read `MemoriesCharDB`. | No new `sz` line; `MemoriesDB.settings.kinds.sz` is `false`. | not run |
| J2 | 12, V6 | Sub-addon kind off | Note `/dump MemoriesCombatCharDB.counts.kills.total`. Uncheck "Killed a creature", kill a creature, `/reload`. | No new `ki` line in `MemoriesCombatCharDB`; `counts.kills.total` is 1 more. `/mem status` shows `Memories_Combat: on, ..., 1 kinds off`. | not run |

## K. Travel

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| K1 | 9 | Zone | Walk from one zone into another, then into a new subzone. | One `zo\|<zone>` line, then one `sz\|<subzone>` line, in Spanish. A `/reload` adds no second `zo`. | not run |
| K2 | 9 | Inn at login | Log out inside an inn, log in, walk out. | `zo\|<inn>` only when the zone text names the inn, then `zo\|<zone>` once the map confirms it; no other zone line. | not run |
| K3 | 9, 13, 14 | Flight | Talk to a flight master you have not met, fly to another node, land. | `fp\|<node name>` and `counts.milestones.flightPaths` 1 more at the new master; `tx\|<from node>\|<to node>\|<copper>` and `mn\|-<cost>\|flight\|<destination>` at take-off; `tl\|<to node>` at landing; `counts.travel.flights` 1 more. | not run |
| K4 | 9 | Click on the current node | Open the flight map and click the node where you stand. | No `tx` line and no flight count. | not run |
| K5 | 9 | Flight across a reload | Take a flight and `/reload` in the air, then land. | No new `tx`; `tl` with an empty node at landing. | not run |
| K6 | 9 | Hearthstone | Use the Hearthstone in another zone. | `ld\|8690`, `le`, then `hs\|<from map>\|<to map>\|<bind location>\|<yards>`; `counts.travel.hearths` 1 more and `counts.distance.hearth` grows by the yards. | not run |
| K7 | 9 | Boat or zeppelin | Take a boat or a zeppelin to another continent. | `ld`, `le`, then `bt\|<from map>\|<to map>\|<from place>\|<to place>` within 30 s; `counts.travel.boats` 1 more. | not run |
| K8 | 9 | Portal or teleport | On a mage, cast Teleport: Stormwind (3561). | `ld\|3561`, `le`, `po\|<zone after>\|<from map>\|<to map>\|3561\|<yards or empty>`. | not run |
| K9 | 9 | Summon | Accept a warlock summon. | `so\|<warlock>\|<area>` at the offer, `su\|<warlock>\|<area>\|<from map>\|<to map>\|<yards>` after the arrival. A declined summon writes only `so`. | not run |
| K10 | 9 | Tram map id | In the Deeprun Tram, type `/dump select(4, UnitPosition("player"))`. | It prints `369`. | not run |
| K11 | 9 | Deeprun Tram | Ride the Deeprun Tram from Stormwind to Ironforge. | `ld`, `le`, then `jp\|...\|tram` on each loading screen into or out of the tram. | not run |
| K12 | 9 | Mount | Mount a mount never used before twice, with a dismount in between, then a mount used before. | One `mo\|1\|<spell>\|<name>` for the new mount only (a `mo` line marks the first use of each mount; no line for a dismount or a known mount); `counts.travel.mountUps` 2 more and `counts.travel["mount:<spell>"]` 2 more. | not run |

## L. Deaths and the low-health popup

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| L1 | 7 | Recap fields | Die to a creature, then type `/dump C_DeathRecap.GetRecapEvents()` while dead. | Each entry has `timestamp`, `sourceGUID`, `sourceName`, `amount` and, for a spell, `spellName`; a fall has `environmentalType`. | not run |
| L2 | 7 | Death to a creature | Target a creature, let it kill you, wait 2 s. | One `de\|<name>\|<npc id>\|<spell>\|\|world\|\|<level>\|<classification>\|<amount>` line at the death spot; `counts.deaths` has `total` and `world` 1 more and `hardest` at least the amount. | not run |
| L3 | 7, 9 | Release and spirit healer | Release outdoors, accept the spirit healer's resurrection. | `gh`, `jp\|<from map>\|<to map>\|<yards>\|death` (or no travel line when a loading screen came right after a revive), then `al\|spirit`; `counts.deaths["revive.spirit"]` 1 more. | not run |
| L4 | 7 | Corpse run | Release, run back to the body and click "Resurrect". | `gh`, then `al\|corpse`. | not run |
| L5 | 7 | Death across a reload | Die, wait 2 s, `/reload` while dead, then release and `/reload` again. | One `de` and one `gh` only. | not run |
| L6 | 7 | Death at login | Die, type `/run MemoriesCharDB.state.deaths.open = false`, `/reload`. | One new bare `de` line at the last trail point (no killer when the recap is gone). | not run |
| L7 | 7 | Fall | Jump from a high place and die. | `de\|\|\|\|falling\|world\|...`; `counts.deaths["env.falling"]` 1 more. | not run |
| L8 | 7 | Low health and close call | Out of combat, lose health below 35 % (for example a fall), then heal up and wait 3 s. | `lh\|0`, then `cc\|<seconds>\|0`; `counts.deaths` has `lowHealth` and `closeCalls` 1 more. | not run |
| L9 | 7 | Close call in combat | Drop below 35 % in a fight, survive, end the fight, wait 3 s. | `lh\|1` at once; `cc\|<seconds>\|1` only 3 s after the fight ends. | not run |
| L10 | 7 | No close call on death | Drop below 35 % and die. | `lh`, `de`, no `cc`. | not run |
| L11 | 7 | Low-health popup at login | Type `/console doNotFlashLowHealthWarning 1`, `/reload`. | A popup "Memories needs this setting on" with "Keep it on" and "Turn it off"; the "Low-health flash" option is unchecked. | not run |
| L12 | 7 | Keep it on | Click "Keep it on". | `/dump C_CVar.GetCVar("doNotFlashLowHealthWarning")` prints `"0"`; the option is checked; no second popup. | not run |
| L13 | 7 | Turn it off | Repeat L11 and click "Turn it off". | The CVar is `"1"`, the option is unchecked, no second popup until the next login or `/reload`. | not run |
| L14 | 7 | Popup in combat | Turn the flash off, start a fight, `/reload` in combat. | The popup shows only after the fight ends. Click "Keep it on". | not run |
| L15 | 7 | Option untick | Uncheck "Low-health flash" on the Settings page. | The popup shows; the option and the CVar stay on until a button is clicked. Click "Keep it on". | not run |
| L16 | 7 | Game turns it off | With the flash on, untick the game's own low-health flash option (Interface options). | The Memories popup shows. Turning it on again in the game shows no popup and checks the Memories option. | not run |

## M. Dungeons

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| M1 | 9, 7 | Dungeon visit | Enter the Deadmines (or any dungeon), die once inside, leave. | `dn\|<name>\|<instance id>\|party\|<difficulty>\|<size>` at the entrance; the `de` line has no position and the dungeon name as `place`; then `dx\|<name>\|<instance id>\|<seconds>\|1`; `counts.dungeons.visits` and `counts.deaths.dungeon` 1 more. | not run |
| M2 | 9 | Ghost run in a dungeon | Die inside a dungeon, release, run back as a ghost and enter again. | No `dx` and no second `dn`; the visit goes on. | not run |
| M3 | 9 | Reload inside | `/reload` inside a dungeon. | No new `dn` or `dx`. | not run |
| M4 | 12 | Kill in a dungeon | Kill a creature in the dungeon, `/reload`. | `ki\|<name>\|\|\|\|<xp>\|\|party\|<1 or empty>`; `counts.kills` has `total` and `inst` 1 more. | not run |
| M5 | 9 | Boss fight | Kill a dungeon boss, then wipe on another. | `bo\|<boss>\|<encounter id>\|1\|\|<dungeon>\|<seconds>` for the kill (`1` in the 4th field for the last boss), `bo\|<boss>\|<id>\|0\|\|<dungeon>\|<seconds>` for the wipe. | not run |
| M6 | 9 | Last boss, no shot | Kill the last boss of a dungeon. | No screenshot and no `ss` line. The last boss is found by its encounter ID, so on every client language it counts. A WoW Forever custom boss and Scarlet Commander Mograine have no known ID and count on an English client only. | not run |
| M8 | 9 | Logout inside | Log out inside a dungeon, wait, log in outside after the instance reset. | `dx` with the time of the logout. | not run |

## N. Groups, guild and PvP

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| N1 | 15 | Surname | Target another player with a surname, type `/dump UnitName("target")`. | The first name, then the surname as the second value. | not run |
| N2 | 15 | Join a group | Invite a player and let them join, wait 2 s, `/reload`. | One `gj\|<First Surname>\|<guild>\|<CLASS>\|<level>` in `MemoriesSocialCharDB`; `counts.social.joins` 1 more. The reload adds no second `gj`. | not run |
| N3 | 6 | Group bonus | In the group, kill a creature while rested and read the XP chat line. | The `xp` line ends with the group bonus `N`, never the rested bonus. | not run |
| N4 | 13 | Group roll | In a group, roll Need on a green item, win it, then roll Greed on another and lose. | One `rl\|<id>\|need\|<roll>\|1\|<name>\|2` and one `lo\|...\|roll\|...` for the win (no second `lo` from the loot line); one `rl\|<id>\|greed\|<roll>\|0\|<name>\|<quality>` for the loss, although the chat shows each roll line several times. | not run |
| N5 | 7 | Resurrection by a player | Die in the group, accept a resurrection from a priest or a paladin. | `al\|res\|<their name>`. | not run |
| N6 | 15 | Leave a group | Leave the group, wait 2 s. | One `gl\|<name>` for each member. | not run |
| N7 | 15 | Own guild | Join a guild, or get a new rank, wait 3 s. | `gu\|<guild>\|<rank>`; `snap[<level>].guild` has the name, rank and tabard; `state.tabards[<guild>]` has the tabard. Leaving writes `gu` with an empty guild. | not run |
| N8 | 15 | Duel | Accept a duel from a player and lose it, then win one. | `du\|lost\|<First Surname>\|<CLASS>`, then `du\|won\|...`; `counts.pvp` has `duel_lost` and `duel_won`. | not run |
| N9 | 15 | Declined duel to the death | Decline a duel to the death from a player, then challenge the same player to a normal duel and win it. | `du\|won\|...`; `counts.pvp.duelDeath` does not grow (`DUEL_FINISHED` fires on the decline). | not run |
| N10 | 15 | Enemy player | On a PvP realm or in a contested zone, target a player of the other faction. | One `ep\|<name>\|<CLASS>\|<Race>\|<level>\|<guild>`; targeting again within 30 minutes writes nothing. | not run |
| N11 | 15 | PvP kill | Target an enemy player, fight and kill them out of a battleground. | One `pk\|won\|<name>\|<CLASS>\|<level>\|<guild>`; `counts.pvp.won` 1 more. When the kill gives honor, also `hk\|<honor>\|<victim>\|<rank>` and `counts.pvp` `honor` and `honorWorld` grow. | not run |
| N12 | 15 | PvP death | Let an enemy player kill you. | `de\|<name>\|...` in `MemoriesCharDB` and one `pk\|lost\|<name>\|<CLASS>\|<level>\|<guild>`; `counts.pvp.lost` 1 more. | not run |
| N13 | 15 | Battleground | Join a battleground, play to the end, leave. | One `bg\|<name>\|<won or lost>\|<seconds>\|<honor>\|<kills>\|<kb>\|<deaths>` when you leave; no `hk` lines inside; `counts.pvp` has `bg_won` or `bg_lost`, `bgSec` and `bgPlayed:<name>`. Leaving before the end writes `left`. | not run |
| N14 | 15 | PvP rank | Log in and wait 6 s. | One `rk\|<rank>\|<Spanish title>` on the first login; `snap[<level>].pvp` has `rank`, `points` and `threshold`. | not run |

## O. Screenshots and the public API

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| O1 | 8 | By-hand screenshot | Note the line count in `/mem status`, press PrintScreen, then `/mem status` again. | The count is at least 1 more (other recorders can write lines meanwhile). After a `/reload`, the journal ends with `ss\|by hand\|ok\|WoWScrnShot_<MMDDYY_HHMMSS>.<ext>`, and that file (or the one a second earlier) is in `Screenshots/`. `counts.screenshots.shots` is 1 more. | not run |
| O2 | 8 | Screenshot format | Type `/dump C_CVar.GetCVar("screenshotFormat")`, press PrintScreen, `/reload`. | The `ss` file name ends with the matching extension (`jpeg` → `.jpg`, `png` → `.png`, `tga` → `.tga`). | not run |
| O3 | 8 | Screenshot note | Type `/run Screenshot() C_Timer.After(1.5, function() print(Memories.RecordScreenshot("Test", "manual note")) end)`, then `/reload`. | It prints `true`. The journal has `ss\|by hand\|ok\|<file>`, then `sn\|Test\|manual note`. | not run |
| O4 | 8, V3 | Public event | Type `/run print(Memories.RecordEvent("Test", "validation", "ok"))`, then `/reload`. | It prints `true`. The journal in `MemoriesCharDB` has an `ex\|Test\|validation\|ok` line. | not run |
| O5 | 8 | Public refusal | Type `/run print(Memories.RecordEvent("Test"))`. | It prints `false bad what`. | not run |
| O6 | 8 | Rate limit | Type `/run for i = 1, 31 do print(i, Memories.RecordEvent("Spam", "x")) end`. | Lines 1 to 30 print `true`, line 31 prints `false rate limit`. A loop that crosses a minute of `GetTime()` starts the count again: wait a minute and run it once more. | not run |
| O7 | 8 | Kind off for the API | Uncheck "Event from another addon", type `/run print(Memories.RecordEvent("Test", "off"))`, check it again. | It prints `false off`. | not run |

## P. When it happens

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| P1 | 6, 13 | Level up | Gain a level, wait 3 s. | `lv\|<level>`, then `pl\|<played>`; `MemoriesCharDB.snap[<level>]` has `t`, `zone`, `rested` and `played`. `ge\|<new level>\|<19 ids>\|ding`; the Economy `snap[<level>]` has `gear` and `money`. No screenshot and no new `ss` line. | not run |
| P3 | 14 | Talents | At level 10 or more, spend a talent point, wait 1 s. | `ta\|<spent>\|<unspent>`; `snap[<level>].talents` is the spent points. | not run |
| P4 | 12 | Rare | Kill a rare creature. | `ki` with `rare` or `rareelite` and one `ra\|<name>\|<npc id>\|<level>`. | not run |
| P5 | 9 | World boss | Kill a world boss (for example Azuregos) or be there when it dies, with it targeted. | One `wb\|<name>\|<npc id>`; a second kill within 10 minutes writes nothing. | not run |
| P6 | 7 | Hardcore death | On a Hardcore character, die. | `de`, then `hc\|<killer>`. | not run |

## Q. Save reminder

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| Q1 | 4 | Save reminder | Play 60 minutes without a reload or a logout (play the rows that need no `/reload` meanwhile). | One chat line "Memories: 1 hour since the last save. Shift-click the minimap button to save (reloads the UI)." and the minimap button pulses. No second line later. | not run |

## R. End of the session (game closed between steps)

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| R1 | V4 | Lines in each addon | Type `/mem status`. | 6 addons `on`, each with more than 0 lines. | not run |
| R2 | 4 | Backup written | Type `/dump MemoriesDB.backups`. | The character's GUID has an entry for each of the 6 addons with `t`, `level`, `lines` and a `blob` (or `data` when the client cannot encode). | not run |
| R3 | V5 | Own files | Log out. Run `grep -c '\|ki\|' .../SavedVariables/Memories_Combat.lua` and `grep -c '\|ki\|' .../SavedVariables/Memories.lua`. | The first is above 0, the second is 0. | not run |
| R4 | 6 | Gap | Log in, `/reload`, play 3 minutes, then kill the game process (task manager or `kill -9`) so nothing is saved. Start the game and log in. | After the first /played answer, `gp\|<seconds, 180 or more>\|<time of the last save>`. | not run |
| R5 | 4 | Data guard, restore | With a backup in place, close the game. In `WTF/Account/<account>/<realm id>/<Name>-<Realm>/SavedVariables/Memories.lua`, delete the `MemoriesCharDB` table. Start the game and log in. | A popup "Memories: Memories came back empty. A backup from <date> has <n> lines." with "Restore" and "Start fresh". "Restore" asks to reload; after the reload the old lines are back, followed by `nt\|restored backup\|<n>`, then `out` and the reload lines. | not run |
| R6 | 4 | Data guard, start fresh | Repeat R5 and click "Start fresh". | The new journal holds `nt\|started fresh\|<n>` right after the login lines (`in\|login`, `pc`, `rs`). The next backup run (at most 15 minutes later) replaces the old one. | not run |
| R7 | 4 | Data guard, no answer | Repeat R5, but log out without an answer (the popup stays open). Log in again. | The popup shows again and `MemoriesDB.backups` still has the old backup. Click "Restore". | not run |
| R8 | 4 | Data guard, sub-addon | Close the game. In `SavedVariables/Memories_Combat.lua`, delete the `MemoriesCombatCharDB` table. Start the game and log in. Click "Restore". | A popup "Memories: Memories_Combat came back empty. A backup from <date> has <n> lines."; after the reload the `ki` lines are back and the Combat journal ends with `nt\|restored backup\|<n>`. | not run |
| R9 | 1 | Errors box | Close the game. In `WTF/Account/<account>/SavedVariables/Memories.lua`, set `["errors"] = { { ["t"] = 1793560500, ["where"] = "manual", ["msg"] = "test error", ["stack"] = "line 1" } }` inside `MemoriesDB`. Start the game and type `/mem errors`. | A box opens with "manual: test error" and "line 1", all text selected; Ctrl+C copies it; Escape closes it. | not run |
| R10 | 1 | Errors survive a reload | With at least one saved error, `/reload`, then `/mem errors`. | The same errors are listed. | not run |

## S. Converter on the real install

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| S1 | 10, V9 | Converter | Log out. Run `make export WOW_DIR=".../_forever_"`, then run it again. | `dist-characters/` has `index.json` and `<id>/` with `journey.jsonl`, `trail.jsonl`, `character.json` and `screenshots/`. `journey.jsonl` has an `ss` record whose `screenshot` names a file in `screenshots/`, and an `ex` record with `source` "Test". The second run changes no output file. The saved files and screenshots in the game folder keep their modification times; `backups/<stamp>/` holds a copy of each saved file. | not run |
| S2 | 10 | Screenshot note joined | Find the O3 screenshot in `journey.jsonl`. | Its `ss` record has `notes: [{"source": "Test", "note": "manual note"}]`. | not run |
| S3 | 10 | Addons listed | Read `dist-characters/index.json` and `<id>/character.json`. | The character lists the 6 addons, each with its `counts`. | not run |
| S4 | 3, 16 | Every kind seen | Run `jq -r .k dist-characters/<id>/journey.jsonl \| sort -u`. Tick each kind in the coverage table below. | Every kind that the session's actions produced is listed. A kind with no row run stays open. | not run |
| S5 | V10 | Paparazzi note | With Paparazzi changed by its own spec, take a Paparazzi screenshot, log out, run the converter. | The shot is one `ss` record with a `notes` entry from source `Paparazzi`. | not run |

## T. Run B: `Memories_Combat` off, then the core off

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| T1 | 5 | Disabled sub-addon | Disable "Memories - Combat" for this character in the AddOn list, log in, `/mem status`. | Its line says `Memories_Combat: off`; the other 5 are `on`. The Settings page has no `Memories_Combat — Combat` section. | not run |
| T2 | 3, 16 | Run B play | Play 10 minutes: kill creatures, loot, gather, `/reload`. | No Lua error. No new `ki`, `ra` or `fi` line in any file; the core still writes `xp\|<n>\|kill\|<name>`, and Economy and Gathering still write lines. | not run |
| T3 | 3, V8 | Sub-addon without the core | Disable `Memories`, keep the sub-addons enabled, log in. | No sub-addon loads (shown as a missing dependency), with no Lua error. | not run |
| T4 | 3, 5 | Only the core installed | Close the game, move the 5 sub-addon folders out of `Interface/AddOns`, log in. Type `/dump Memories.Addons()`, then `/mem status`. Put the folders back. | The core is `on`; each of the 5 sub-addons is `missing`, in `Addons()` and in the status lines. | not run |

## U. Journey window

Rows U1 to U31 check the spec `specs/2026-11-11-map-journey-tab.md`. No game client was at hand when the code was
written, so run them before the release. The Journey window replaced the overlay on the world map, so each row runs
in the window.

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| U1 | spec AC1 | Button | Open the world map, first the default one, then with OpenMap on. | A Journey button with the Memories icon shows in the side column, under the last game tab, or on the right edge of the map. There is no Lua error. | not run |
| U2 | spec AC18 | Window | Click the Journey button. Drag the window by its title. Press Escape. | The Journey window opens on the map of your character, with the map art and the explored areas, the panel at the right and the player bar under the map. The button is lit. The window moves, and Escape closes it. | not run |
| U3 | spec AC2 | Trail on a zone map | Open the map of a zone where you walked, rode and swam, and took a flight. | Lines follow the recorded trail. The colour changes with the way of travel. | not run |
| U4 | spec AC3 | Pins | Look at a zone where you levelled up and died. Hover over the pins. | Each pin is the coin of its kind: an up arrow for a level up, with the level at its lower right, and a skull for a death. No other event leaves a pin. The tooltip shows the time, the kind name and the fields. | not run |
| U5 | spec AC4 | Panel filters | Clear the "Deaths" box, then the "Trail" box. Choose one session, then "All". | The pins of the group and then the lines go away. One session shows only its own lines and pins. "All" shows everything. The count line follows each change. | not run |
| U6 | spec AC5 | Continent map | Open the map of a continent, then the world map. | The trail and the pins of the zones show on it. The coastal zones show too. A zone with no position is skipped, and the panel says "N zones not shown". | not run |
| U7 | spec AC18 | Map navigation | In the window, left click a zone on a continent map, then right click, then click Up. | A left click opens the zone. A right click and Up go back to the continent. The name of the map at the top left follows. | not run |
| U8 | spec AC6 | Saved choices | Change the boxes, the colour and Follow, close the window, `/reload`, open it again. | The same choices show. | not run |
| U9 | spec AC7 | Combat | In a fight, open the map and switch Journey on and off. | No taint error shows, and `/mem errors` has nothing new. | not run |
| U10 | spec AC7 | Errors | After a play session with the map open, type `/mem errors`. | No new error. | not run |
| U11 | spec risk | Long journey | Open a continent map with a journey of many hours. | The frame rate does not drop when the map opens. If a cap cuts the view, the panel says so. | not run |
| U12 | spec risk | Another map addon | With OpenMap, Questie or another map addon on, open the world map and the window. | The world map and its pins are as the other addon draws them. Memories draws nothing on the world map. The Journey button does not overlap another tab. | not run |
| U13 | spec AC8 | Language | Run on the esES client, then on frFR or deDE. | All texts of the tab and the panel show in the client language. Long labels wrap and do not overlap. | not run |
| U14 | spec risk | Window layout | Open the window on a small screen and with a large UI scale. Scroll a long list of sessions. | The window stays on screen. The session rows move on scroll and the chosen one is marked. The check boxes fit in the panel. | not run |
| U15 | replay | Play | On a zone map with a trail, click Play. | The trail draws from the start, with a glowing marker at its head. The slider and the clock move. At the end the marker goes away and the button shows Play again. | not run |
| U16 | replay | Pins pop | Play a journey that has a level up and a death on the map. | Each pin pops in with a short grow animation when the marker passes its event, then pulses for a moment. | not run |
| U17 | replay | Speed and seek | Click the speed button until 16×. Drag the slider back and forward. Click Pause, then Play. | The replay runs faster at each step. A drag back hides the lines and pins after the playhead. Pause holds the picture and Play goes on from the same place. | not run |
| U18 | replay | Size | Open a zone, a continent and the world map in the window during a replay and after it. | Pins and lines keep a normal size. Continent and world pins are half the size of zone pins. No icon covers the map. | not run |
| U19 | replay | Icons | Look at the pins on a map with many level ups and deaths, then play a journey with flights and hearthstones, at 1x. | The coins are round and sharp, with no square block and no stretched icon. The burst of a flight or a hearthstone shows its coin. The feed lines show the coin of each event. The silver arrow of the player draws over every coin and burst when it passes them. | not run |
| U20 | replay | Frame rate | Play a long journey at 16× on a continent map. | The frame rate stays smooth and `/mem errors` shows nothing new. | not run |
| U21 | replay | Bar and art | Open a zone and play. | The map art fills the map area with no gap and no seam between tiles. The thumb of the slider shows and drags. The head glow is a soft star, not a square. | not run |
| U22 | AC14 | Arrow | Click Play on a zone map. | A silver arrow, not a dot, walks the route. It turns with each bend of the trail. It keeps one size at each map. | not run |
| U23 | AC14 | Trail colours | Click the colour button until "Color: Level", then "Color: Age", then "Color: Way". Turn the colourblind box on and off. | The trail changes colour at each click. By level it moves from cool to warm as the level rises. By age the old steps are dim and cool and the new ones bright. The colourblind palette is readable. | not run |
| U24 | AC14 | Trip arcs | Play a journey that has a hearthstone, a portal, a boat or a flight with no recorded points. | A curved arc draws from the place before the trip to the place after it, in the time of the trip. Walking between zones draws no arc. | not run |
| U25 | AC15 | Chapters | Open the panel with the "Chapters" button on. Click a chapter, then Play. | The list shows the start and each level. A click jumps the replay to that moment. The mark follows the playhead. "Sessions" shows the list of sessions again. | not run |
| U26 | AC15 | Highlights feed | Play a journey with level ups, deaths and flights. Drag the slider back. | The feed shows the last six events, newest first, each with an icon and a main field. A drag back empties it. | not run |
| U27 | AC16 | Highlight animations | Play a journey with a level up, a death, a flight and a hearthstone, at 1x and at 8x. | A ring grows and fades at the pin and a short label rises and fades. The colour fits the kind. At 8x no more than 4 play at once and the frame rate stays smooth. A seek plays none. The ring is a soft star, not a square. | not run |
| U28 | AC17 | Follow | Open a zone, keep Follow on, click Play on a journey that crossed two zones. Run it also with OpenMap on. | When the playhead enters the other zone, the window shows that zone, waits a moment, and goes on from the same moment with the trail of the new zone. Passed pins show with no pop. The feed keeps its events. There is no Lua error. | not run |
| U29 | AC17 | Follow on a continent | Open the map of a continent in the window, keep Follow on, click Play on a journey that crossed zones of that continent, then a flight to another continent. | The map stays on the continent while its zones are on it. It changes to a zone map only when the playhead leaves the continent. | not run |
| U30 | AC17 | The player moves the map | During a replay, open another map in the window yourself. Then click Pause and Play. | The replay keeps playing on your map and does not take the map back. After Pause and Play, or a seek, it follows again. Turn Follow off: the replay stays on the map shown. | not run |
| U31 | spec AC18 | Window edge cases | Maximize the world map and click Journey. Then go into a dungeon and open the window. | The window opens in front of the maximized map and comes to the front on a click. In the dungeon it opens on the first map of the trail (with no trail: on the zone or continent that holds the dungeon), with no Lua error. | not run |

## V. Notes

| ID | Source | Check | Steps | Expected | Result |
|---|---|---|---|---|---|
| V1 | 2 | Open the window | Type `/mem note`. | The Note window opens with an empty box that has the focus, a counter `0 / 400`, and Save off. Escape closes it. | not run |
| V2 | 2 | Write and save | Type `/mem note first note`, then click Save. | The window closes. The chat shows "Memories: note saved." After `/reload`, the file holds `\|un\|first note`. | not run |
| V3 | 2 | Counter and limit | Paste 500 characters in the box. | The box stops at 400 bytes and the counter shows `400 / 400` in red. | not run |
| V4 | 2 | Link by shift-click | With the box focused, shift-click an item in the bags, then a quest in the quest log. | The box holds `{item:<id>:<name>}` and `{quest:<id>:<title>}`. The chat box does not stay open and takes no text. | not run |
| V5 | 2 | Link by drag | Drag an item from the bags onto the box. | The box holds the item token and the item is back in its bag slot (the cursor is empty). | not run |
| V6 | 2 | Pipe character | Type `a|b` in the box and save. | The line holds `a/b`. If the typed `\|` reaches the addon as `\|\|`, the saved text has one `/`. | not run |
| V7 | 2 | In combat | Start a fight, type `/mem note in a fight`, click Save. | The note saves. No taint error shows. | not run |
| V8 | 2 | Kind off | Turn off the kind "Note" in the Settings page, then save a note. | The window stays open and the chat shows "Memories: notes are off in the settings." | not run |

## Validation map

| Validation step | Rows |
|---|---|
| 1 | A1 |
| 2 | A2 |
| 3 (30 minutes of play, then `/reload`) | sections F to P, O4 |
| 4 | R1 |
| 5 | R3 |
| 6 | J2 |
| 7 | I2 |
| 8 | T3 |
| 9 | S1 |
| 10 | S5 |

## Kind coverage

Each kind of [`kinds.md`](kinds.md) and the rows whose action writes it. Tick "Seen" in row S4.

| Kind | Rows | Seen |
|---|---|---|
| `in`, `out`, `pl`, `pc`, `rs` | F1 | |
| `gp` | R4 | |
| `af` | F2 | |
| `lv` | P1 | |
| `xp` | F6, F7, H3, N3 | |
| `qt` | F7 | |
| `di` | F6 | |
| `de` | L2, L6, L7, M1, N12 | |
| `gh` | L3, L4 | |
| `al` | L3, L4, N5 | |
| `cc` | L8, L9 | |
| `lh` | L8, L9 | |
| `hc` | P6 | |
| `zo`, `sz` | K1 | |
| `ld`, `le` | K6, K7, K8, K11 | |
| `tx`, `tl` | K3 | |
| `bt` | K7 | |
| `hs` | K6 | |
| `so`, `su` | K9 | |
| `po` | K8 | |
| `jp` | K11, L3 | |
| `mo` | K12 | |
| `ml` | G6 | |
| `dn`, `dx` | M1 | |
| `bo` | M5 | |
| `wb` | P5 | |
| `ss` | O1, O2, O3 | |
| `sn` | O3 | |
| `ex` | O4 | |
| `nt` | R5, R6, R8 | |
| `ki` | H3, M4, P4 | |
| `ra` | P4 | |
| `fi` | H5 | |
| `ga` | H9 | |
| `fs` | H11 | |
| `op` | H13 | |
| `pp` | H12 | |
| `sk` | H10 | |
| `lr` | G4, G5 | |
| `rc` | G5 | |
| `ta` | P3 | |
| `cu` | G8 | |
| `pt` | H16 | |
| `rp` | H14 | |
| `qa` | G13 | |
| `hb` | G11 | |
| `fp` | K3 | |
| `bk` | G12 | |
| `lo` | G7, G10, G16, G19, H8, N4 | |
| `rl` | N4 | |
| `ge` | G1, P1 | |
| `eq` | G2 | |
| `mn` | F7, G4, G7, G15, G16, G17, G18, G19, K3 | |
| `tb` | G4, G5 | |
| `ah` | G17, G18 | |
| `ma` | G15, G16, G17, G18 | |
| `tr` | G19 | |
| `gj` | N2 | |
| `gl` | N6 | |
| `gu` | N7 | |
| `ep` | N10 | |
| `pk` | N11, N12 | |
| `hk` | N11 | |
| `du` | N8, N9 | |
| `bg` | N13 | |
| `rk` | N14 | |
