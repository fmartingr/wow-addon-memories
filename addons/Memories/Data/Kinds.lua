local ADDON, ns = ...

local L = ns.L

local Kinds = {}
ns.Kinds = Kinds

local byKind = {}
local order = {}

-- Codec.DecodeLine puts the fixed columns and raw under these keys, so a field may not use them.
local RESERVED = { t = true, p = true, m = true, x = true, y = true, k = true, raw = true }

-- Returns why kind and spec cannot be registered, or nil when they can.
function Kinds.Check(kind, spec)
	if type(kind) ~= "string" or not kind:match("^%w+$") then
		return "bad kind " .. tostring(kind)
	end
	if byKind[kind] then
		return "duplicate kind " .. kind
	end
	if type(spec) ~= "table" or type(spec.addon) ~= "string" then
		return "bad spec for kind " .. kind
	end
	-- Describe joins addon and group with ";", so a ";" in either shifts the fields that the converter reads.
	if spec.addon:find(";", 1, true) or (type(spec.group) == "string" and spec.group:find(";", 1, true)) then
		return "bad spec for kind " .. kind
	end
	if spec.fields ~= nil and type(spec.fields) ~= "table" then
		return "bad fields in " .. kind
	end
	local seen = {}
	for _, field in ipairs(spec.fields or {}) do
		if type(field) ~= "string" or not field:match("^#?%w+$") then
			return "bad field " .. tostring(field) .. " in " .. kind
		end
		local name = field:gsub("^#", "")
		if RESERVED[name] then
			return "reserved field " .. name .. " in " .. kind
		end
		-- A decoded line holds one value per name.
		if seen[name] then
			return "duplicate field " .. name .. " in " .. kind
		end
		seen[name] = true
	end
end

-- spec = { addon, group, name, fields = { "name", "#npc", ... }, always }. A "#" marks a numeric field. A kind with
-- always = true has no setting: the kind gate never stops it.
function Kinds.Register(kind, spec)
	local err = Kinds.Check(kind, spec)
	assert(not err, err)
	local entry = {
		kind = kind,
		addon = spec.addon,
		group = spec.group,
		name = spec.name or kind,
		fields = {},
		names = {},
		numeric = {},
		always = spec.always == true,
	}
	for i, field in ipairs(spec.fields or {}) do
		local name = field:gsub("^#", "")
		entry.fields[i] = field
		entry.names[i] = name
		entry.numeric[i] = name ~= field
	end
	byKind[kind] = entry
	order[#order + 1] = entry
	return entry
end

function Kinds.Get(kind)
	return byKind[kind]
end

-- Kinds in registration order.
function Kinds.All()
	return { unpack(order) }
end

-- The kind metadata for MemoriesDB.kinds, so a reader of the saved files can name each field.
function Kinds.Describe()
	local out = {}
	for _, entry in ipairs(order) do
		out[entry.kind] = entry.addon .. ";" .. (entry.group or "") .. ";" .. table.concat(entry.fields, ",")
	end
	return out
end

local CORE = {
	{ "Sessions", "in", L.LOGIN_OR_RELOAD, "how" },
	{ "Sessions", "out", L.LOGOUT_OR_RELOAD },
	{ "Sessions", "pl", L.TOTAL_PLAYED, "#played" },
	{ "Sessions", "gp", L.GAP, "#seconds", "#lastSave" },
	{ "Sessions", "pc", L.SESSION_COMPUTER, "computer" },
	{ "Sessions", "af", L.AWAY_FROM_KEYBOARD, "on" },
	{ "Progress", "lv", L.LEVEL_UP, "#level" },
	{ "Progress", "xp", L.EXPERIENCE_GAINED, "#amount", "src", "name", "#bonus" },
	{ "Progress", "qt", L.QUEST_TURNED_IN, "#quest", "#xp", "#money", "title" },
	{ "Progress", "di", L.DISCOVERED_AREA, "area", "#xp" },
	{ "Progress", "rs", L.RESTED_STATE, "#rested" },
	{
		"Deaths",
		"de",
		L.DIED,
		"killer",
		"#npc",
		"spell",
		"env",
		"place",
		"boss",
		"#klevel",
		"kclass",
		"#amount",
		"#byPlayer",
		"inst",
	},
	{ "Deaths", "gh", L.RELEASED_SPIRIT },
	{ "Deaths", "al", L.ALIVE_AGAIN, "how", "by" },
	{ "Deaths", "cc", L.CLOSE_CALL, "#seconds", "combat" },
	{ "Deaths", "lh", L.LOW_HEALTH_WARNING, "combat" },
	{ "Deaths", "hc", L.HARDCORE_DEATH, "killer" },
	{ "Travel", "zo", L.ENTERED_ZONE, "zone" },
	{ "Travel", "sz", L.ENTERED_SUBZONE, "sub" },
	{ "Travel", "ld", L.LOADING_SCREEN_STARTED, "#spell", "taxi" },
	{ "Travel", "le", L.LOADING_SCREEN_ENDED },
	{ "Travel", "tx", L.TOOK_FLIGHT, "from", "to", "#cost" },
	{ "Travel", "tl", L.FLIGHT_LANDED, "at" },
	{ "Travel", "bt", L.BOAT_OR_ZEPPELIN, "#fromMap", "#toMap", "from", "to" },
	{ "Travel", "hs", L.HEARTHSTONE, "#fromMap", "#toMap", "to", "#yards" },
	{ "Travel", "so", L.SUMMON_OFFERED, "who", "area" },
	{ "Travel", "su", L.SUMMONED, "who", "area", "#fromMap", "#toMap", "#yards" },
	{ "Travel", "po", L.PORTAL_OR_TELEPORT, "dest", "#fromMap", "#toMap", "#spell", "#yards" },
	{ "Travel", "jp", L.OTHER_TELEPORT, "#fromMap", "#toMap", "#yards", "why" },
	{ "Travel", "mo", L.MOUNT_UP_OR_DOWN, "on", "#spell", "name" },
	{ "Travel", "ml", L.LEARNED_MOUNT_OR_RIDING, "name", "#spell" },
	{ "Dungeons", "dn", L.ENTERED_DUNGEON_OR_RAID, "name", "#instance", "itype", "#difficulty", "#size" },
	{ "Dungeons", "dx", L.LEFT_DUNGEON_OR_RAID, "name", "#instance", "#seconds", "#deaths" },
	{ "Dungeons", "bo", L.BOSS_FIGHT_ENDED, "name", "#encounter", "#success", "last", "place", "#seconds" },
	{ "Dungeons", "wb", L.WORLD_BOSS_KILLED, "name", "#npc" },
	{ "Screenshots", "ss", L.SCREENSHOT_SAVED, "why", "result", "file" },
	{ "Other addons", "sn", L.SCREENSHOT_NOTE_FROM_ANOTHER_ADDON, "source", "note", "file" },
	{ "Other addons", "ex", L.EVENT_FROM_ANOTHER_ADDON, "source", "what", "detail" },
	{ "Notes", "un", L.NOTE, "text" },
}

for _, row in ipairs(CORE) do
	Kinds.Register(row[2], { addon = ADDON, group = row[1], name = row[3], fields = { select(4, unpack(row)) } })
end

Kinds.Register("nt", { addon = ADDON, name = L.NOTE_FROM_MEMORIES, fields = { "what", "detail" }, always = true })
