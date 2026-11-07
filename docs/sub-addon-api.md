# Sub-addon API

A Memories sub-addon (`Memories_Combat`, `Memories_Gathering`, ...) records its own kinds into its own saved file. It
reaches the core only through the global `Memories` and the handle that `Memories.RegisterModule` returns.

## TOC

```
## Interface: 16001
## Title: Memories - <Part>
## Notes: <what it records>
## Version: 0.1.0
## Dependencies: Memories
## Group: Memories
## SavedVariablesPerCharacter: Memories<Part>CharDB
## LoadSavedVariablesFirst: 1
## X-Memories-API: 1

<Part>.lua
```

- `## Dependencies: Memories`: the client loads the core first and skips the sub-addon when the core is missing.
- `## Group: Memories`: the AddOn list shows the whole set as one group.
- The saved table is per character only. Account data (settings, backups, orphans) lives in the core's `MemoriesDB`.

## Missing core

The first file starts with this guard. It covers a client that loads the sub-addon without the core:

```lua
local ADDON, ns = ...

if not Memories or not Memories.RegisterModule then
	print(ADDON .. ": Memories is not loaded.")
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
		{ kind = "ki", group = "Combat", name = "Killed a creature", fields = { "name", "#npc", "ctype" } },
	},
	newOnly = { { key = "kills", label = "Kills: new findings only", kinds = { "ki" } } },
	OnLogin = function(h) end,
	OnEnterWorld = function(h, isLogin, isReload) end,
})
if not h then
	return
end
```

- `kinds`: each kind is letters or digits, unique across the whole set. A `#` before a field name marks a number.
  The field names `t`, `p`, `m`, `x`, `y`, `k` and `raw` are reserved.
- `newOnly`: the "New findings only" boxes of the Settings page. Each box lists only kinds of this addon, and its
  `key` is unique across the whole set.
- `addon` and each `group` hold no `;`: `MemoriesDB.kinds` joins them with it.
- `OnLogin(h)`: runs once, after the core's own modules, when the journal is open.
- `OnEnterWorld(h, isLogin, isReload)`: runs on every `PLAYER_ENTERING_WORLD`.

Registration works at any time:

- Before `PLAYER_LOGIN`: the core keeps the def and opens the journal at login.
- After `PLAYER_LOGIN`: the core opens the journal at once and calls `OnLogin(h)`, then `OnEnterWorld(h, false, false)`
  when the world has already loaded. Before that, the first `PLAYER_ENTERING_WORLD` calls `OnEnterWorld`.

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
  "Memories: <addon>: saved data from a newer version; this addon will not write".

## The handle

| Method | Does |
|---|---|
| `h.addon` | the addon name |
| `h:On(event, fn)` → handle | listens to a game event; `fn(event, ...)` |
| `h:Off(event, handle)` | stops it |
| `h:Listen(msg, fn)` | listens to a core message; `fn(msg, ...)` |
| `h:Hook(target, method, fn)` → bool | `hooksecurefunc` after the function; `target = nil` hooks a global. False when the function is missing. |
| `h:Write(kind, ...)` → line, or `nil, reason` | writes a line now; reasons `"not ready"` (before login), `"read only"`, `"off"` |
| `h:WriteAt(at, kind, ...)` | the same with `at = { t, p, m, x, y }` |
| `h:Count(module, key, n)` → old value | adds `n` (default 1) |
| `h:Counts(module)` | the counts table of a module |
| `h:IsFirst(module, key)` | true when the count is 0 or missing |
| `h:Snap(level, key, value)` | sets a snapshot value, or returns it without `value` |
| `h:NewOnly(key)` | the "New findings only" setting of a box |
| `h:Here()` | `{ t, p, m, x, y }` of now; `m`, `x`, `y` stay empty inside an instance |
| `h:Level()` | the player's level, the new one already during `PLAYER_LEVEL_UP` |
| `h:InFight()` | true from `PLAYER_REGEN_DISABLED` to `PLAYER_REGEN_ENABLED` |
| `h:InInstance()` | `inside, instanceType` |
| `h:Fight()` | a copy of the current or last fight, else nil (see below) |
| `h:Safe(where, fn, ...)` | `ns.Safe` with `where = "<addon>:<where>"` |
| `h:Print(...)` | a chat line with the "Memories:" prefix |
| `h:R(v)`, `h:RN(...)` | the secret filter |
| `h:Coalesce(key, delay, fn)` | one pending timer per key; keys are per addon |
| `h:AfterCombat(key, fn)` | now out of combat, else after it; keys are per addon |
| `h:SpellName(id)` | the localized spell name, or nil |
| `h:Utf8Cut(s, maxBytes)` | cuts at a whole UTF-8 character |

Rules:

- `h:Write` and `h:WriteAt` accept only kinds that this addon registered. Another kind raises an error.
- `h:Count`, `h:Counts`, `h:IsFirst` and `h:Snap` raise an error before login, when no journal is open.
- Every listener, hook and timer runs through the core's error guard. An error is logged with
  `where = "<addon>:<event or message>"` and never stops the other recorders.
- A kind that is off writes no line. Count anyway: counts never stop.

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
| `LINE_WRITTEN` | `addon, kind, line, ev` | every journal line; `ev` is the decoded line, shared by all listeners: do not change it |
| `FIGHT_START` | — | `PLAYER_REGEN_DISABLED` |
| `FIGHT_END` | `fight` | `PLAYER_REGEN_ENABLED` |
| `LEVEL_UP` | `level` | Sessions/Progress (Task 6) |
| `AWAY_CHANGED` | `isAway` | Task 6 |
| `TRAIL_LIVE` | `m, x, y` | Task 6 |
| `DIED` | `info` | Task 7 |
| `ALIVE` | `how` | Task 7 |
| `LOW_HEALTH` | `inCombat` | Task 7 |
| `RESTORED` | `addon` | a backup replaced the journal of `addon` (data guard); its counts, snapshots and `data.state` are the backup's now |

A recorder that reacts to another recorder listens to these messages, never to `LINE_WRITTEN`: a message fires even when
its kind is off.

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
