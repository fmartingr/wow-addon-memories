# Sub-addon API

A Memories sub-addon (`Memories_Combat`, `Memories_Gathering`, ...) records its own kinds into its own saved file. It
reaches the core only through the global `Memories` and the handle that `Memories.RegisterModule` returns.

## TOC

```
## Interface: 16001
## Title: Memories - <Part>
## Notes: <what it records>
## Title-deDE: <translated title>
## Notes-deDE: <translated notes>
## Version: 0.1.0
## Dependencies: Memories
## Group: Memories
## SavedVariablesPerCharacter: Memories<Part>CharDB
## LoadSavedVariablesFirst: 1
## X-Memories-API: 1

Locales.lua
<Part>.lua
```

- `## Dependencies: Memories`: the client loads the core first and skips the sub-addon when the core is missing.
- `## Group: Memories`: the AddOn list shows the whole set as one group.
- `## Title-<locale>` and `## Notes-<locale>` follow the plain lines, one pair for each of `deDE`, `frFR`, `esES`,
  `esMX`, `itIT` and `ptBR`. The AddOn list shows them on a client with that language.
- The saved table is per character only. Account data (settings, backups, orphans) lives in the core's `MemoriesDB`.

## Strings

`Locales.lua` is the first file. Each addon carries its own strings, so a sub-addon needs no core API for them. It
keeps one table for each locale in `ns.locales` (`enUS`, `deDE`, `esES`, `frFR`, `itIT`, `ptBR`; `enGB` uses `enUS`
and `esMX` uses `esES`). The keys are `UPPER_SNAKE` constants, and the English text is the `enUS` value. `ns.L` answers
in the language of `GetLocale()`. A missing translation gives the `enUS` text, and a missing key gives the key itself.
Code uses `local L = ns.L` and `L.KEY`. A format string keeps the same placeholders, in the same order, in every
language. Start each translated table with the note "Machine translated. Corrections are welcome."
`spec/locales_spec.lua` checks the keys and the placeholders of each addon.

A kind registers its `name` and its new-only `label` through `L`. The `group` stays an English token: it is saved in
`MemoriesDB.kinds`. The core Settings page translates the group names it knows ("Combat", "Gathering", "Character",
"Milestones", "Loot", "Money", "Social", "PvP"). A sub-addon with another group shows that group in English.

## Missing core

The first file after `Locales.lua` starts with this guard. It covers a client that loads the sub-addon without the core:

```lua
local ADDON, ns = ...
local L = ns.L

if not Memories or not Memories.RegisterModule then
	print(ADDON .. ": " .. L.CORE_MISSING)
	return
end
```

## The global `Memories`

| Field | Value |
|---|---|
| `API_VERSION` | `1` |
| `VERSION` | the core's TOC `## Version` |
| `RegisterModule(def)` | returns a handle, or `nil, reason` |
| `Addons()` | `{ { addon, state, lines, readOnly }, ... }` |

`Addons()` lists the core first, then the registered sub-addons in registration order, then the ones refused for a
newer API, then the known sub-addons that never registered. `state` is one of:

- `"on"`: registered and its journal is open (or opens at login).
- `"off"`: installed but turned off for this character.
- `"missing"`: not installed.
- `"failed"`: enabled but it never registered, its journal did not open, or the core stopped at login.
- `"newer api"`: it asked for a newer `API_VERSION` than this core has.

## `Memories.RegisterModule(def)`

```lua
local h, reason = Memories.RegisterModule({
	addon = ADDON, -- the folder name
	api = 1, -- the API_VERSION this addon was written for
	saved = "MemoriesCombatCharDB", -- its SavedVariablesPerCharacter global
	kinds = {
		{ kind = "ki", group = "Combat", name = L.KILLED_CREATURE, fields = { "name", "#npc", "ctype" } },
	},
	newOnly = { { key = "kills", label = L.KILLS_NEW_FINDINGS_ONLY, kinds = { "ki" } } },
	OnLogin = function(h) end,
	OnEnterWorld = function(h, isLogin, isReload) end,
})
if not h then
	return
end
```

- `kinds`: each kind is letters or digits, unique across the whole set. A `#` before a field name marks a number.
  The field names `t`, `p`, `m`, `x`, `y`, `k` and `raw` are reserved.
- `newOnly`: the "New findings only" boxes of the Settings page. Each box lists at least one kind, only kinds of this
  addon, and its `key` is unique across the whole set. The box shows under the group of its first kind.
- `addon` and each `group` hold no `;`: `MemoriesDB.kinds` joins them with it.
- `OnLogin(h)`: runs once, after the core's own modules, when the journal is open.
- `OnEnterWorld(h, isLogin, isReload)`: runs on every `PLAYER_ENTERING_WORLD`.

Registration works at any time:

- Before `PLAYER_LOGIN`: the core keeps the def and opens the journal at login.
- After `PLAYER_LOGIN`: the core opens the journal at once and calls `OnLogin(h)`, then `OnEnterWorld(h, false, false)`
  when the world has already loaded. Before that, the first `PLAYER_ENTERING_WORLD` calls `OnEnterWorld`.
  These calls run before `RegisterModule` returns, so `OnLogin` and `OnEnterWorld` use their `h` argument, never the
  return value.

Refusals (the sub-addon must stop):

| Reason | Cause |
|---|---|
| `"bad def"` | `addon`, `saved` or `api` is missing or wrong; `saved` is a core table, another addon's table, or a global that is not a plain table; a kind, field, box or hook is malformed. |
| `"newer api"` | `def.api > Memories.API_VERSION`. The core prints "Memories: <addon> needs a newer Memories" once. |
| `"twice"` | the addon already registered, or `addon` is `"Memories"`. |
| `"kind taken"` | another addon registered one of the kinds. |
| `"error"` | an error inside the registration (see `/memories errors`). |

A refused def registers no kind.

## The saved file

The core opens `_G[def.saved]` as the addon's journal. It creates the table on a first run. The same rules as the core
apply:

- **New character:** when the stored GUID differs from the player's, the old data moves to `MemoriesDB.orphans` with
  `addon = <addon>`, and the journal starts empty with `nt|new character|<old guid>`.
- **Newer schema:** data with `schema` above the core's makes only this addon read-only. The core prints
  "Memories: The saved data comes from a newer version. <addon> does not save changes."

## The handle

| Method | Does |
|---|---|
| `h.addon` | the addon name |
| `h:On(event, fn)` → handle | listens to a game event; `fn(event, ...)` |
| `h:OnUnit(event, unit, fn)` → handle | listens to a unit event of one unit only (`"player"`); `fn(event, unit, ...)`. The client sends no event of another unit. |
| `h:Off(event, handle)` | stops it |
| `h:Listen(msg, fn)` | listens to a core message; `fn(msg, ...)` |
| `h:Hook(target, method, fn)` → bool | `hooksecurefunc` after the function; `target = nil` hooks a global. False when the function is missing. |
| `h:Write(kind, ...)` → line, or `nil, reason` | writes a line now; reasons `"not ready"` (before login), `"read only"`, `"off"` |
| `h:WriteAt(at, kind, ...)` | the same with `at = { t, p, m, x, y }` |
| `h:Count(module, key, n)` → old value | adds `n` (default 1) |
| `h:Counts(module)` | the counts table of a module |
| `h:IsFirst(module, key)` | true when the count is 0 or missing |
| `h:Snap(level, key, value)` | sets a snapshot value, or returns it without `value` |
| `h:State(module)` | the saved state table of a module (`data.state[module]`), created when missing; a read-only journal gives a copy |
| `h:NewOnly(key)` | true when the player turned on the "New findings only" box `key` (`MemoriesDB.settings.newOnly[key]`) |
| `h:Here()` | `{ t, p, m, x, y }` of now; `p` stays empty until the first /played answer of the load; `m`, `x`, `y` stay empty inside an instance and on a world or continent map |
| `h:Level()` | the player's level, the new one already during `PLAYER_LEVEL_UP` |
| `h:InFight()` | true from `PLAYER_REGEN_DISABLED` to `PLAYER_REGEN_ENABLED` |
| `h:InInstance()` | `inside, instanceType` |
| `h:Fight()` | a copy of the current or last fight, else nil (see below) |
| `h:Flight()` | the open flight `{ from, to, cost, t }` (node names, copper, `time()` of take-off), else nil; after a reload in the air only `t` is known |
| `h:Safe(where, fn, ...)` | runs `fn` in an error guard: a failure goes to `/memories errors` and prints one chat line for each `where = "<addon>:<where>"` |
| `h:Print(...)` | a chat line with the "Memories:" prefix |
| `h:R(v)`, `h:RN(...)` | the secret filter |
| `h:Coalesce(key, delay, fn)` | one pending timer per key; keys are per addon |
| `h:AfterCombat(key, fn)` | now out of combat, else after it; keys are per addon |
| `h:SpellName(id)` | the localized spell name, or nil |
| `h:ItemName(id)` | the localized item name, or nil while the client has not loaded the item. The first miss asks the client to load it, one time, and `ITEM_NAME` follows. |
| `h:Utf8Cut(s, maxBytes)` | cuts at a whole UTF-8 character |

Rules:

- `h:Write` and `h:WriteAt` accept only kinds that this addon registered. Another kind raises an error.
- `h:Count`, `h:Counts`, `h:IsFirst`, `h:Snap` and `h:State` raise an error before login, when no journal is open.
- A recorder keeps what it must remember over a reload (the last value it wrote, the names it already saw) in
  `h:State(module)`, never in its journal lines: a kind that is off writes no line, and the state must still be right.
- Every listener, hook and timer runs through the core's error guard. An error never stops the other recorders. It is
  logged with `where = "<addon>:<event or message>"` for a listener, `"<addon>:hook:<method>"` for a hook, and
  `"coalesce:<addon>:<key>"` or `"after combat:<addon>:<key>"` for a timer.
- A kind that is off writes no line (`h:Write` returns `nil, "off"`). Count anyway: counts never stop.

## Fights

`h:Fight()` returns `{ start, stop, casts, target }`:

- `start`, `stop`: `GetTime()` values. `stop` is nil while the fight runs.
- `casts`: the player's `UNIT_SPELLCAST_SUCCEEDED` events in the fight.
- `target`: the name of the first hostile target in the fight, or nil.

A `/reload` in combat starts a new fight at login.

## Messages

`h:Listen` can receive these core messages:

| Message | Arguments | From |
|---|---|---|
| `LOGIN` | — | after every `OnLogin` of the core and of the sub-addons that registered before login |
| `ITEM_NAME` | `id, name` | an item that `h:ItemName` asked for has loaded |
| `LINE_WRITTEN` | `addon, kind, line, ev` | every journal line; `ev` is the decoded line, shared by all listeners: do not change it |
| `FIGHT_START` | — | `PLAYER_REGEN_DISABLED` |
| `FIGHT_END` | `fight` | `PLAYER_REGEN_ENABLED` |
| `LEVEL_UP` | `level` | `PLAYER_LEVEL_UP`, also when the kind `lv` is off |
| `AWAY_CHANGED` | `isAway, state` | the away state changed; `state` is `"afk"`, `"idle"` (120 s without activity) or nil |
| `TRAIL_LIVE` | `m, x, y` | the trail kept a new point (map, x and y 0..10000) |
| `DIED` | `info` | a death was confirmed, also when the kind `de` is off; `info` has the `de` fields: `killer`, `npc`, `spell`, `env`, `place` (`"world"` or the instance name), `boss` and `byPlayer` (booleans), `klevel`, `kclass`, `amount`, `inst` (`"pvp"` or nil). A death that a reload brings back with the same recap fires no second `DIED` |
| `ALIVE` | `how` | the player is alive again, also when the kind `al` is off; `how` is `"corpse"`, `"spirit"`, `"res"` or `"soulstone"` |
| `LOW_HEALTH` | `inCombat` | the game's low-health flash showed (not while dead or behind a fullscreen panel), also when the kind `lh` is off |
| `SETTING_CHANGED` | `path, value` | a setting changed, for example `"kinds.ki"`, `"newOnly.kills"` or `"recordRate"` |
| `RESTORED` | `addon` | a backup replaced the journal of `addon` (data guard); its counts, snapshots and `data.state` are the backup's now |

A recorder that reacts to another recorder listens to these messages, never to `LINE_WRITTEN`: a message fires even when
its kind is off. The core also emits `JOURNAL_OPENED`, `REGISTERED` and `SAVE_REMINDER` for its own UI; a sub-addon
does not use them.

## Settings page

The core builds the Settings page at login, after every sub-addon that registered before it. For each addon and each
group of its kinds, in registration order, the page has a header `<Addon> — <Group>`, an "Enable all" and a
"Disable all" button, one checkbox per kind (labelled with the kind's `name`) and the addon's new-only boxes of that
group. A sub-addon that registers after login gets its section at once. A sub-addon needs no code for it.

The player's choices live in `MemoriesDB.settings` (account-wide): `kinds[kind] = false` turns a kind off, and
`newOnly[key] = true` turns a box on. The choices of an addon that is not loaded stay saved.

## Backups and the data guard

The core backs up every open journal, the sub-addons' too, into `MemoriesDB.backups[guid][addon]`: 5 s after login,
every 15 minutes and on `LEVEL_UP`, one addon per frame and never in combat. A sub-addon needs no code for it.

When a journal opens with 0 lines while its backup has lines, the core holds that backup (no new backup replaces it) and
asks the player to restore it or start fresh. A restore replaces the saved table's content, opens the journal again and
emits `RESTORED(addon)`. A recorder that keeps state in memory listens to `RESTORED` for its own addon and reads its
state again.

## Tests

`spec/fixtures/addons/Memories_Test/` is a sub-addon for the tests. The harness finds addons in `addons/` and in
`spec/fixtures/addons/`:

```lua
local ns, all = wow.boot({ addons = { "Memories", "Memories_Test" } })
local h = all.Memories_Test.handle
h:Write("zz", "what", 1)
```

`order = "reverse"` loads the sub-addon before the core.
