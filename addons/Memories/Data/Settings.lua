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
	shots = { level = false, lastBoss = false },
	saveReminder = true,
	minimapButton = true,
	lowHealthFlash = true,
}

-- Keys of these tables are kind names and box keys, never paths. Each maps to the default of one entry.
local MAPS = { kinds = true, newOnly = false }

-- MemoriesDB is a file the player can edit, so a missing value or one of the wrong type takes its default. The client's
-- Settings page writes the default of every setting it shows in the same way.
local function clean(t, defaults)
	for key, default in pairs(defaults) do
		if type(default) == "table" then
			clean(U.TableAt(t, key), default)
		elseif type(t[key]) ~= type(default) then
			t[key] = default
		end
	end
end

local checked, session

-- Cleans a settings table once, the first time it is used.
local function check(t)
	if checked == t then
		return t
	end
	clean(t, DEFAULTS)
	for map in pairs(MAPS) do
		for key, v in pairs(t[map]) do
			if type(v) ~= "boolean" then
				t[map][key] = nil
			end
		end
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

local function parts(path)
	local head, rest = path:match("^([^.]+)%.(.+)$")
	if head and MAPS[head] ~= nil then
		return { head, rest }
	end
	return U.Split(path, ".")
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

function Settings.Default(path)
	local list = parts(path)
	if #list == 2 and MAPS[list[1]] ~= nil then
		return MAPS[list[1]]
	end
	return U.Copy(walk(DEFAULTS, list))
end

-- The value at a dotted path such as "shots.level", else its default.
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
	assert(type(value) == want and (path ~= "recordRate" or RATE[value]), "bad value for setting " .. path)
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
