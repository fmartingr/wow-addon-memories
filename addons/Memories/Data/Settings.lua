local _, ns = ...

local U = ns.U

-- Account-wide settings in MemoriesDB.settings.
local Settings = {}
ns.Settings = Settings

Settings.RATES = { 1, 2, 5, 10 }

local RATE = {}
for _, r in ipairs(Settings.RATES) do
	RATE[r] = true
end

local DEFAULTS = {
	kinds = {},
	newOnly = {},
	recordRate = 2,
	saveReminder = true,
	minimapButton = true,
	lowHealthFlash = true,
	-- "yards" or "meters"; any other value lets the region and the client language decide.
	distanceUnit = "auto",
	-- The Journey window: the shown groups, the trail, the colour of the trail ("way", "level" or "age"), the
	-- colourblind palette and whether the replay follows the journey across maps.
	map = { groups = {}, trail = true, color = "way", colorblind = false, follow = true },
}

-- Keys of these tables are kind names, box keys and group names, never paths. Each maps to the default of one entry.
-- A group is shown unless its entry is false.
local MAPS = { kinds = true, newOnly = false, ["map.groups"] = true }

Settings.COLORS = { "way", "level", "age" }
local COLOR = {}
for _, mode in ipairs(Settings.COLORS) do
	COLOR[mode] = true
end

-- MemoriesDB is a file the player can edit, so a missing value or one of the wrong type takes its default. The client's
-- Settings page writes the default of every setting it shows in the same way. A MAPS table keeps its free keys; any
-- other table drops the keys it has no default for.
local function clean(t, defaults, path)
	for key, default in pairs(defaults) do
		if type(default) == "table" then
			clean(U.TableAt(t, key), default, path and path .. "." .. key or key)
		elseif type(t[key]) ~= type(default) then
			t[key] = default
		end
	end
	if MAPS[path] == nil then
		for key in pairs(t) do
			if defaults[key] == nil then
				t[key] = nil
			end
		end
	end
end

local function walk(t, list)
	for i = 1, #list do
		if type(t) ~= "table" then
			return nil
		end
		t = t[list[i]]
	end
	return t
end

local checked, session

-- Cleans a settings table once, the first time it is used.
local function check(t)
	if checked == t then
		return t
	end
	clean(t, DEFAULTS)
	for map in pairs(MAPS) do
		local entries = walk(t, U.Split(map, "."))
		for key, v in pairs(entries) do
			if type(v) ~= "boolean" then
				entries[key] = nil
			end
		end
	end
	if not COLOR[t.map.color] then
		t.map.color = DEFAULTS.map.color
	end
	if not RATE[t.recordRate] then
		t.recordRate = DEFAULTS.recordRate
	end
	checked = t
	return t
end

-- The live settings table. A MemoriesDB from a newer Memories is never written, so its settings live in a copy for the
-- session.
function Settings.Root()
	if type(MemoriesDB) ~= "table" then
		return check({})
	end
	if ns.Store.ReadOnlyAll() then
		if not session then
			session = type(MemoriesDB.settings) == "table" and U.Copy(MemoriesDB.settings) or {}
		end
		return check(session)
	end
	return check(U.TableAt(MemoriesDB, "settings"))
end

-- The MAPS prefix of a path such as "newOnly.kills" or "map.groups.Travel", and the key after it.
local function mapKey(path)
	-- The rest may be empty: "map.groups." is the group of the kinds that have none.
	local prefix, rest = path:match("^([^.]+%.[^.]+)%.(.*)$")
	if not (prefix and MAPS[prefix] ~= nil) then
		prefix, rest = path:match("^([^.]+)%.(.*)$")
	end
	if prefix and MAPS[prefix] ~= nil then
		return prefix, rest
	end
end

local function parts(path)
	local prefix, rest = mapKey(path)
	if prefix then
		local list = U.Split(prefix, ".")
		list[#list + 1] = rest
		return list
	end
	return U.Split(path, ".")
end

function Settings.Default(path)
	local prefix = mapKey(path)
	if prefix then
		return MAPS[prefix]
	end
	return U.Copy(walk(DEFAULTS, parts(path)))
end

-- The value at a dotted path such as "newOnly.kills", else its default.
function Settings.Get(path)
	local list = parts(path)
	local v = walk(Settings.Root(), list)
	if v == nil then
		return Settings.Default(path)
	end
	-- A copy, so a caller cannot change a setting past Set's checks and SETTING_CHANGED.
	return U.Copy(v)
end

local function expected(path)
	local default = Settings.Default(path)
	return default ~= nil and type(default) ~= "table" and type(default) or nil
end

-- The table and key that hold the setting at path.
function Settings.Slot(path)
	local list = parts(path)
	local t = Settings.Root()
	for i = 1, #list - 1 do
		t = U.TableAt(t, list[i])
	end
	return t, list[#list]
end

-- Raises an error on an unknown path or a value of the wrong type.
function Settings.Set(path, value)
	local want = type(path) == "string" and expected(path)
	assert(want, "unknown setting " .. tostring(path))
	assert(
		type(value) == want and (path ~= "recordRate" or RATE[value]) and (path ~= "map.color" or COLOR[value]),
		"bad value for setting " .. path
	)
	local t, key = Settings.Slot(path)
	t[key] = value
	ns.Emit("SETTING_CHANGED", path, value)
end

-- A kind is off only when its entry is false. A kind with always = true has no setting.
function Settings.KindOn(kind)
	local spec = ns.Kinds.Get(kind)
	if spec and spec.always then
		return true
	end
	return Settings.Root().kinds[kind] ~= false
end

function Settings.SetKind(kind, on)
	Settings.Set("kinds." .. kind, on ~= false)
end

-- Sets every kind of one group of an addon. A nil group is the group of the kinds that have none.
function Settings.SetGroup(addon, group, on)
	local n = 0
	for _, spec in ipairs(ns.Kinds.All()) do
		if spec.addon == addon and (spec.group or "") == (group or "") and not spec.always then
			Settings.SetKind(spec.kind, on)
			n = n + 1
		end
	end
	return n
end

function Settings.NewOnly(key)
	return Settings.Root().newOnly[key] == true
end

ns.KindOn = Settings.KindOn
