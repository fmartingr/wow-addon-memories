local _, ns = ...

local U = ns.U

-- Where and when the player is now, as { t, p, m, x, y }. The trail replaces it with its current point.
function ns.Here()
	return ns.Journal.At()
end

local levelUp

-- PLAYER_LEVEL_UP carries the new level before UnitLevel reports it.
function ns.Level()
	local level = ns.R(UnitLevel("player"))
	if levelUp and (not level or levelUp > level) then
		return levelUp
	end
	return level
end

ns.On("PLAYER_LEVEL_UP", function(_, level)
	levelUp = ns.R(level)
end, "level")

-- The core owns the fight state, so every sub-addon sees the same fight.
local fight
local inFight = false

function ns.InFight()
	return inFight
end

-- The current fight, else the last one, as a copy: { start, stop, casts, target } with GetTime() values.
function ns.Fight()
	return fight and U.Copy(fight) or nil
end

local function noteTarget()
	if fight.target or not UnitExists("target") then
		return
	end
	local hostile = ns.R(UnitCanAttack("player", "target"))
	if hostile then
		fight.target = ns.R(UnitName("target"))
	end
end

local function startFight()
	inFight = true
	fight = { start = GetTime(), casts = 0 }
	noteTarget()
	ns.Emit("FIGHT_START")
end

ns.On("PLAYER_REGEN_DISABLED", startFight, "fight")

ns.On("PLAYER_REGEN_ENABLED", function()
	if not inFight then
		return
	end
	inFight = false
	fight.stop = GetTime()
	ns.Emit("FIGHT_END", U.Copy(fight))
end, "fight")

ns.On("PLAYER_REGEN_ENABLED", ns.RunAfterCombat, "after combat")

ns.On("PLAYER_TARGET_CHANGED", function()
	if inFight then
		noteTarget()
	end
end, "fight")

-- A /reload during a fight brings no PLAYER_REGEN_DISABLED, so the fight starts at login, once every journal is open.
ns.Listen("LOGIN", function()
	if not inFight and InCombatLockdown() then
		startFight()
	end
end, "fight")

local function countCast()
	fight.casts = fight.casts + 1
end

-- Other units' casts never reach this frame, and a cast outside a fight returns before the error guard, so a crowded
-- place costs nothing.
local casts = CreateFrame("Frame")
casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
casts:SetScript("OnEvent", function(_, _, unit)
	if inFight and unit == "player" then
		ns.Safe("fight", countCast)
	end
end)

-- The handle is the only way a sub-addon reaches the core. Its journal stays private in entries.
local Handle = {}
Handle.__index = Handle
local entries = {}

function ns.NewHandle(entry)
	local h = setmetatable({ addon = entry.addon }, Handle)
	entries[h] = entry
	return h
end

local function where(h, name)
	return entries[h].addon .. ":" .. tostring(name)
end

local function journal(h)
	local j = entries[h].journal
	assert(j, entries[h].addon .. ": the journal opens at login")
	return j
end

-- The owner comes from the private entry: h.addon is a plain field that a sub-addon can change.
local function own(h, kind)
	local addon = entries[h].addon
	local spec = ns.Kinds.Get(kind)
	assert(spec and spec.addon == addon, addon .. " did not register kind " .. tostring(kind))
end

function Handle:On(event, fn)
	return ns.On(event, fn, where(self, event))
end

function Handle:Off(event, handle)
	ns.Off(event, handle)
end

function Handle:Listen(msg, fn)
	return ns.Listen(msg, fn, where(self, msg))
end

function Handle:Hook(target, method, fn)
	return U.Hook(target, method, fn, where(self, "hook:" .. tostring(method)))
end

function Handle:Write(kind, ...)
	return self:WriteAt(ns.Journal.At(), kind, ...)
end

function Handle:WriteAt(at, kind, ...)
	own(self, kind)
	local j = entries[self].journal
	if not j then
		return nil, "not ready"
	end
	return j:WriteAt(at, kind, ...)
end

function Handle:Count(module, key, n)
	return journal(self):Count(module, key, n)
end

function Handle:Counts(module)
	return journal(self):Counts(module)
end

function Handle:IsFirst(module, key)
	return journal(self):IsFirst(module, key)
end

function Handle:Snap(level, key, value)
	return journal(self):Snap(level, key, value)
end

function Handle:NewOnly(key)
	return ns.Settings.NewOnly(key)
end

function Handle:Here()
	return ns.Here()
end

function Handle:Level()
	return ns.Level()
end

function Handle:InFight()
	return ns.InFight()
end

function Handle:InInstance()
	local inside, kind = IsInInstance()
	return inside == true, kind
end

function Handle:Fight()
	return ns.Fight()
end

function Handle:Safe(name, fn, ...)
	return ns.Safe(where(self, name), fn, ...)
end

function Handle:Print(...)
	ns.Print(...)
end

function Handle:R(v)
	return ns.R(v)
end

function Handle:RN(...)
	return ns.RN(...)
end

-- Keys get the addon name, so two sub-addons never cancel each other's work.
function Handle:Coalesce(key, delay, fn)
	ns.Coalesce(where(self, key), delay, fn)
end

function Handle:AfterCombat(key, fn)
	ns.AfterCombat(where(self, key), fn)
end

function Handle:SpellName(id)
	if id == nil or not (C_Spell and C_Spell.GetSpellName) then
		return nil
	end
	return (ns.R(C_Spell.GetSpellName(id)))
end

function Handle:Utf8Cut(s, n)
	return U.Utf8Cut(s, n)
end
