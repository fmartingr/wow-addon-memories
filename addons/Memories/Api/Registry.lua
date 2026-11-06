local ADDON, ns = ...

local Registry = {}
ns.Registry = Registry

-- The sub-addons of the set, so the status can name the ones that never registered.
Registry.KNOWN =
	{ "Memories_Combat", "Memories_Gathering", "Memories_Character", "Memories_Economy", "Memories_Social" }

-- The core's own tables and _G: a sub-addon that named one would fill or empty it as its journal.
local CORE_SAVED = { MemoriesDB = true, MemoriesCharDB = true, Memories = true, _G = true }

local entries = {}
local byAddon = {}
local bySaved = {}
-- A new-only key is one setting, so two boxes with the same key would toggle each other.
local byBox = {}
local newer, newerSeen = {}, {}
local inWorld = false

local function optional(v, kind)
	return v == nil or type(v) == kind
end

local function checkKinds(def)
	local own = {}
	for _, k in ipairs(def.kinds or {}) do
		if type(k) ~= "table" then
			return "bad def"
		end
		if type(k.kind) == "string" and ns.Kinds.Get(k.kind) then
			return "kind taken"
		end
		if
			own[k.kind]
			or not optional(k.group, "string")
			or not optional(k.name, "string")
			or ns.Kinds.Check(k.kind, { addon = def.addon, group = k.group, fields = k.fields })
		then
			return "bad def"
		end
		own[k.kind] = true
	end
	local boxes = {}
	for _, box in ipairs(def.newOnly or {}) do
		if
			type(box) ~= "table"
			or type(box.key) ~= "string"
			or byBox[box.key]
			or boxes[box.key]
			or not optional(box.label, "string")
			or type(box.kinds) ~= "table"
		then
			return "bad def"
		end
		for _, kind in ipairs(box.kinds) do
			if not own[kind] then
				return "bad def"
			end
		end
		boxes[box.key] = true
	end
end

local function validate(def)
	if
		type(def) ~= "table"
		or type(def.addon) ~= "string"
		or def.addon == ""
		or type(def.saved) ~= "string"
		or not def.saved:match("^[%a_][%w_]*$")
		or type(def.api) ~= "number"
		or def.api < 1
	then
		return "bad def"
	end
	if def.api > ns.API_VERSION then
		return "newer api"
	end
	if def.addon == ADDON or byAddon[def.addon] then
		return "twice"
	end
	-- A saved global is nil on a first run, else the plain table the client loaded: anything else belongs to someone else.
	local current = _G[def.saved]
	if
		CORE_SAVED[def.saved]
		or bySaved[def.saved]
		or (current ~= nil and (type(current) ~= "table" or getmetatable(current) ~= nil))
		or not optional(def.kinds, "table")
		or not optional(def.newOnly, "table")
		or not optional(def.OnLogin, "function")
		or not optional(def.OnEnterWorld, "function")
	then
		return "bad def"
	end
	return checkKinds(def)
end

local function call(entry, hook, ...)
	local fn = entry.def[hook]
	if fn and entry.state == "on" then
		ns.Safe(entry.addon .. ":" .. hook, fn, entry.handle, ...)
	end
end

-- The saved global is the table the client writes back, so a new one goes into _G before the journal fills it.
local function open(entry)
	local ok = ns.Safe(entry.addon .. ":open", function()
		local saved = entry.saved
		if type(_G[saved]) ~= "table" then
			_G[saved] = {}
		end
		entry.journal = ns.Store.Open(entry.addon, _G[saved])
	end)
	if not ok then
		entry.state = "failed"
	end
end

local function register(def)
	local reason = validate(def)
	if reason == "newer api" and not newerSeen[def.addon] then
		newerSeen[def.addon] = true
		newer[#newer + 1] = def.addon
		ns.Print(def.addon .. " needs a newer Memories")
	end
	if reason then
		return nil, reason
	end
	for _, k in ipairs(def.kinds or {}) do
		ns.Kinds.Register(k.kind, { addon = def.addon, group = k.group, name = k.name, fields = k.fields })
	end
	-- saved is kept from the checked def: the def stays the sub-addon's table, and a later change must not reach _G.
	local entry = { addon = def.addon, saved = def.saved, def = def, state = "on" }
	entry.handle = ns.NewHandle(entry)
	entries[#entries + 1] = entry
	byAddon[def.addon] = entry
	bySaved[def.saved] = entry
	for _, box in ipairs(def.newOnly or {}) do
		byBox[box.key] = entry
	end
	if ns.loggedIn then
		ns.Store.SaveKinds()
		open(entry)
		call(entry, "OnLogin")
		-- Before the first PLAYER_ENTERING_WORLD, or during one, that event calls OnEnterWorld with its real flags.
		if inWorld and not ns.enteringWorld then
			call(entry, "OnEnterWorld", false, false)
		end
	elseif ns.stopped then
		entry.state = "failed"
	end
	return entry.handle
end

-- Returns a handle, or nil and a reason: "bad def", "newer api", "twice", "kind taken" or "error".
function ns.Public.RegisterModule(def)
	local ok, h, reason = ns.Safe("register", register, def)
	if not ok then
		return nil, "error"
	end
	return h, reason
end

-- Runs on PLAYER_LOGIN after the core's own modules. A sub-addon that registers from an OnLogin joins this loop, so
-- the kinds are saved after it.
function Registry.Login()
	for _, entry in ipairs(entries) do
		open(entry)
		call(entry, "OnLogin")
	end
	ns.Store.SaveKinds()
end

function Registry.EnterWorld(isLogin, isReload)
	inWorld = true
	for _, entry in ipairs(entries) do
		call(entry, "OnEnterWorld", isLogin, isReload)
	end
end

-- Marks the registered sub-addons as failed when the core stops at login.
function Registry.Stop()
	for _, entry in ipairs(entries) do
		entry.state = "failed"
	end
end

local function status(addon, journal, state)
	return {
		addon = addon,
		state = state,
		lines = journal and journal:LineCount() or 0,
		readOnly = journal ~= nil and not journal:CanWrite(),
	}
end

-- A known sub-addon that never registered: not installed, turned off, or broken before RegisterModule.
local function installState(name)
	if not C_AddOns then
		return "missing"
	end
	local ok, _, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, name)
	if not ok or reason == "MISSING" then
		return "missing"
	end
	local okState, enabled = pcall(C_AddOns.GetAddOnEnableState, name, (ns.R(UnitName("player"))))
	if not okState or type(enabled) ~= "number" or enabled == 0 then
		return "off"
	end
	return "failed"
end

-- One entry per addon: the core, the registered sub-addons, the refused ones, then the known ones that are absent.
function ns.Public.Addons()
	local out = { status(ADDON, ns.Store.Core(), ns.stopped and "failed" or "on") }
	for _, entry in ipairs(entries) do
		out[#out + 1] = status(entry.addon, entry.journal, entry.state)
	end
	for _, name in ipairs(newer) do
		out[#out + 1] = status(name, nil, "newer api")
	end
	for _, name in ipairs(Registry.KNOWN) do
		if not byAddon[name] and not newerSeen[name] then
			out[#out + 1] = status(name, nil, installState(name))
		end
	end
	return out
end
