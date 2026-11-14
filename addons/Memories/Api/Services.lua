local _, ns = ...

local U = ns.U

local levelUp

-- PLAYER_LEVEL_UP carries the new level before UnitLevel reports it.
function ns.Level()
	local level = ns.R(UnitLevel("player"))
	if levelUp and (not level or levelUp > level) then
		return levelUp
	end
	return level
end

-- A secret level means one level more than the client reports; with both secret the level stays unknown.
ns.On("PLAYER_LEVEL_UP", function(_, level)
	local current = ns.R(UnitLevel("player"))
	levelUp = ns.R(level) or (type(current) == "number" and current + 1 or nil)
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

ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function()
	if inFight then
		countCast()
	end
end, "fight")

-- Item names ---------------------------------------------------------------

-- pending[id] is true while the client loads an item that ns.ItemName asked for; false once it asked.
local pending = {}
local watching = false

local function nameNow(id)
	local get = type(C_Item) == "table" and C_Item.GetItemNameByID
	if type(get) ~= "function" then
		return nil
	end
	local ok, name = pcall(get, id)
	name = ok and ns.R(name) or nil
	return type(name) == "string" and name ~= "" and name or nil
end

local function onItemInfo(_, id, ok)
	if pending[id] then
		pending[id] = false
		if ok then
			ns.Emit("ITEM_NAME", id, nameNow(id))
		end
	end
end

-- The name of an item, or nil while the client has not loaded it. The first miss of an item asks the client to load
-- it, one time. GET_ITEM_INFO_RECEIVED then emits ITEM_NAME, so a window can draw the name. A journal line is written
-- once, so a recorder gets the name from the next call.
function ns.ItemName(id)
	if type(id) ~= "number" then
		return nil
	end
	local name = nameNow(id)
	if name or pending[id] ~= nil then
		return name
	end
	local load = type(C_Item) == "table" and C_Item.RequestLoadItemDataByID
	if type(load) ~= "function" then
		return nil
	end
	pending[id] = true
	if not watching then
		watching = true
		ns.On("GET_ITEM_INFO_RECEIVED", onItemInfo, "item names")
	end
	pcall(load, id)
	return nil
end

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

function Handle:OnUnit(event, unit, fn)
	return ns.OnUnit(event, unit, fn, where(self, event))
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
	return self:WriteAt(ns.Here(), kind, ...)
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

function Handle:State(module)
	return journal(self):State(module)
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
	local inside, kind = ns.RN(IsInInstance())
	return inside == true, kind
end

function Handle:Fight()
	return ns.Fight()
end

function Handle:Flight()
	return ns.Travel.Flight()
end

function Handle:Safe(name, fn, ...)
	return ns.Protect(where(self, name), fn, ...)
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
	return (ns.R(U.SpellName(id)))
end

function Handle:ItemName(id)
	return ns.ItemName(id)
end

function Handle:Utf8Cut(s, n)
	return U.Utf8Cut(s, n)
end
