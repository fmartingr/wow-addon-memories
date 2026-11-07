# Kinds

Every journal line is `t|p|m|x|y|kind|field1|field2|...`:

- `t`: `time()` of the line. `p`: /played seconds, empty until the game answered /played once this load.
- `m`, `x`, `y`: map id and position (0..10000, `y` grows downward), empty inside an instance and on a world or
  continent map.
- A `#` before a field name marks a number. Booleans are `1`/`0`. Trailing empty fields are dropped.
- In field text, `|` becomes `/`, and line breaks and other control characters become a space.

This list comes from the kinds that the code registers: `addons/Memories/Data/Kinds.lua` for the core, and the
`kinds` of each `Memories.RegisterModule` call (`Combat.lua`, `Gathering.lua`, `Milestones.lua`, `Money.lua`,
`PvP.lua`). The same data is in the saved file as `MemoriesDB.kinds[kind] = "<addon>;<group>;<fields>"`, which the
converter reads to name the fields. The Settings page shows one checkbox per kind, labelled with its name, under the
header `<addon> — <group>`. Every kind is on by default.

The fields of every kind match the Kind catalog of
[`specs/2026-11-06-memories-addon-set.md`](../specs/2026-11-06-memories-addon-set.md). Three names are shorter than in
the catalog: `nt` ("Note from Memories"), `bk` ("Read a book", a line for the first read of each title) and `gj`
("Joined a group"). `mo` is written only for the first mount-up with each mount, so it always has `on` = `1`.

"New findings only" boxes (all off by default; every event is still counted):

| Box | Kinds | Addon |
|---|---|---|
| Gathering: new findings only | `ga`, `fs` | Memories_Gathering |
| Kills: new findings only | `ki` | Memories_Combat |
| Loot: new findings only | `lo` | Memories_Economy |
| Consumables: new findings only | `cu` | Memories_Character |

## Memories

| Kind | Group | Name | Fields |
|---|---|---|---|
| `in` | Sessions | Login or reload | `how` |
| `out` | Sessions | Logout or reload | — |
| `pl` | Sessions | Total /played | `#played` |
| `gp` | Sessions | Gap (game ran, nothing saved) | `#seconds`, `#lastSave` |
| `pc` | Sessions | Computer this session ran on | `computer` |
| `af` | Sessions | Away from keyboard | `on` |
| `lv` | Progress | Level up | `#level` |
| `xp` | Progress | Experience gained | `#amount`, `src`, `name`, `#bonus` |
| `qt` | Progress | Quest turned in | `#quest`, `#xp`, `#money`, `title` |
| `di` | Progress | Discovered an area | `area`, `#xp` |
| `rs` | Progress | Rested state | `#rested` |
| `de` | Deaths | Died | `killer`, `#npc`, `spell`, `env`, `place`, `boss`, `#klevel`, `kclass`, `#amount`, `#byPlayer`, `inst` |
| `gh` | Deaths | Released spirit | — |
| `al` | Deaths | Alive again | `how`, `by` |
| `cc` | Deaths | Close call | `#seconds`, `combat` |
| `lh` | Deaths | Low-health warning | `combat` |
| `hc` | Deaths | Hardcore death | `killer` |
| `zo` | Travel | Entered a zone | `zone` |
| `sz` | Travel | Entered a subzone | `sub` |
| `ld` | Travel | Loading screen started | `#spell`, `taxi` |
| `le` | Travel | Loading screen ended | — |
| `tx` | Travel | Took a flight | `from`, `to`, `#cost` |
| `tl` | Travel | Flight landed | `at` |
| `bt` | Travel | Boat or zeppelin | `#fromMap`, `#toMap`, `from`, `to` |
| `hs` | Travel | Hearthstone | `#fromMap`, `#toMap`, `to`, `#yards` |
| `so` | Travel | Summon offered | `who`, `area` |
| `su` | Travel | Summoned | `who`, `area`, `#fromMap`, `#toMap`, `#yards` |
| `po` | Travel | Portal or teleport | `dest`, `#fromMap`, `#toMap`, `#spell`, `#yards` |
| `jp` | Travel | Other teleport | `#fromMap`, `#toMap`, `#yards`, `why` |
| `mo` | Travel | Mount up or down | `on`, `#spell`, `name` |
| `ml` | Travel | Learned a mount or riding | `name`, `#spell` |
| `dn` | Dungeons | Entered a dungeon or raid | `name`, `#instance`, `itype`, `#difficulty`, `#size` |
| `dx` | Dungeons | Left a dungeon or raid | `name`, `#instance`, `#seconds`, `#deaths` |
| `bo` | Dungeons | Boss fight ended | `name`, `#encounter`, `#success`, `last`, `place`, `#seconds` |
| `wb` | Dungeons | World boss killed | `name`, `#npc` |
| `ss` | Screenshots | Screenshot saved | `why`, `result`, `file` |
| `sn` | Other addons | Screenshot note from another addon | `source`, `note`, `file` |
| `ex` | Other addons | Event from another addon | `source`, `what`, `detail` |
| `nt` | (not toggleable) | Note from Memories | `what`, `detail` |

## Memories_Combat

| Kind | Group | Name | Fields |
|---|---|---|---|
| `ki` | Combat | Killed a creature | `name`, `#npc`, `ctype`, `class`, `#xp`, `#level`, `inst`, `#first` |
| `ra` | Combat | Killed a rare | `name`, `#npc`, `#level` |
| `fi` | Combat | Long fight | `#seconds`, `target`, `class`, `#level`, `died`, `#casts` |

## Memories_Gathering

| Kind | Group | Name | Fields |
|---|---|---|---|
| `ga` | Gathering | Gathered | `prof`, `node`, `#object`, `#item`, `#quality`, `#count`, `name`, `why` |
| `fs` | Gathering | Caught while fishing | `#item`, `#quality`, `#count`, `name`, `#object`, `why` |
| `op` | Gathering | Opened a container or chest | `how`, `#item`, `name`, `#object` |
| `pp` | Gathering | Picked a pocket | `who`, `#npc`, `#item`, `#quality`, `name` |

## Memories_Character

| Kind | Group | Name | Fields |
|---|---|---|---|
| `sk` | Character | Skill changed | `name`, `#rank`, `#max` |
| `lr` | Character | Learned a spell | `name`, `#spell` |
| `rc` | Character | Learned a recipe | `name`, `#spell` |
| `ta` | Character | Talent points | `#spent`, `#unspent` |
| `cu` | Character | Used a consumable | `#item`, `kind`, `name`, `combat` |
| `pt` | Character | Tamed a beast | `family`, `name`, `#level` |
| `rp` | Milestones | Reputation changed | `faction`, `#value`, `#standing`, `label` |
| `qa` | Milestones | Quest accepted | `#quest`, `title` |
| `hb` | Milestones | Hearthstone bound | `home` |
| `fp` | Milestones | Learned a flight path | `node` |
| `bk` | Milestones | Read a book | `title` |

## Memories_Economy

| Kind | Group | Name | Fields |
|---|---|---|---|
| `lo` | Loot | Loot | `#item`, `#quality`, `#count`, `how`, `name`, `#gear`, `#first` |
| `rl` | Loot | Group roll ended | `#item`, `type`, `#roll`, `#won`, `name`, `#quality` |
| `ge` | Loot | Gear snapshot | `#level`, `ids`, `src` |
| `eq` | Loot | Equipped an item | `#slot`, `#item`, `#quality` |
| `mn` | Money | Money in or out | `#delta`, `src`, `what` |
| `tb` | Money | Trainer purchase | `kind`, `what`, `#cost` |
| `ah` | Money | Auction house | `act`, `#copper`, `item` |
| `ma` | Money | Mail | `act`, `who`, `#copper`, `item` |
| `tr` | Money | Traded with someone | `name`, `#copper` |

## Memories_Social

| Kind | Group | Name | Fields |
|---|---|---|---|
| `gj` | Social | Joined a group | `name`, `guild`, `class`, `#level` |
| `gl` | Social | Left a group | `name` |
| `gu` | Social | Own guild changed | `guild`, `rank` |
| `ep` | PvP | Enemy player met | `name`, `class`, `race`, `#level`, `guild` |
| `pk` | PvP | PvP kill or death | `result`, `name`, `class`, `#level`, `guild` |
| `hk` | PvP | Honor gained | `#honor`, `victim`, `rank` |
| `du` | PvP | Duel | `result`, `opponent`, `class` |
| `bg` | PvP | Battleground ended | `name`, `result`, `#seconds`, `#honor`, `#kills`, `#kb`, `#deaths` |
| `rk` | PvP | PvP rank changed | `#rank`, `title` |
