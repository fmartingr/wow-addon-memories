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
	{ "Sessions", "in", L["Login or reload"], "how" },
	{ "Sessions", "out", L["Logout or reload"] },
	{ "Sessions", "pl", L["Total /played"], "#played" },
	{ "Sessions", "gp", L["Gap (game ran, nothing saved)"], "#seconds", "#lastSave" },
	{ "Sessions", "pc", L["Computer this session ran on"], "computer" },
	{ "Sessions", "af", L["Away from keyboard"], "on" },
	{ "Progress", "lv", L["Level up"], "#level" },
	{ "Progress", "xp", L["Experience gained"], "#amount", "src", "name", "#bonus" },
	{ "Progress", "qt", L["Quest turned in"], "#quest", "#xp", "#money", "title" },
	{ "Progress", "di", L["Discovered an area"], "area", "#xp" },
	{ "Progress", "rs", L["Rested state"], "#rested" },
	{
		"Deaths",
		"de",
		L["Died"],
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
	{ "Deaths", "gh", L["Released spirit"] },
	{ "Deaths", "al", L["Alive again"], "how", "by" },
	{ "Deaths", "cc", L["Close call"], "#seconds", "combat" },
	{ "Deaths", "lh", L["Low-health warning"], "combat" },
	{ "Deaths", "hc", L["Hardcore death"], "killer" },
	{ "Travel", "zo", L["Entered a zone"], "zone" },
	{ "Travel", "sz", L["Entered a subzone"], "sub" },
	{ "Travel", "ld", L["Loading screen started"], "#spell", "taxi" },
	{ "Travel", "le", L["Loading screen ended"] },
	{ "Travel", "tx", L["Took a flight"], "from", "to", "#cost" },
	{ "Travel", "tl", L["Flight landed"], "at" },
	{ "Travel", "bt", L["Boat or zeppelin"], "#fromMap", "#toMap", "from", "to" },
	{ "Travel", "hs", L["Hearthstone"], "#fromMap", "#toMap", "to", "#yards" },
	{ "Travel", "so", L["Summon offered"], "who", "area" },
	{ "Travel", "su", L["Summoned"], "who", "area", "#fromMap", "#toMap", "#yards" },
	{ "Travel", "po", L["Portal or teleport"], "dest", "#fromMap", "#toMap", "#spell", "#yards" },
	{ "Travel", "jp", L["Other teleport"], "#fromMap", "#toMap", "#yards", "why" },
	{ "Travel", "mo", L["Mount up or down"], "on", "#spell", "name" },
	{ "Travel", "ml", L["Learned a mount or riding"], "name", "#spell" },
	{ "Dungeons", "dn", L["Entered a dungeon or raid"], "name", "#instance", "itype", "#difficulty", "#size" },
	{ "Dungeons", "dx", L["Left a dungeon or raid"], "name", "#instance", "#seconds", "#deaths" },
	{ "Dungeons", "bo", L["Boss fight ended"], "name", "#encounter", "#success", "last", "place", "#seconds" },
	{ "Dungeons", "wb", L["World boss killed"], "name", "#npc" },
	{ "Screenshots", "ss", L["Screenshot saved"], "why", "result", "file" },
	{ "Other addons", "sn", L["Screenshot note from another addon"], "source", "note", "file" },
	{ "Other addons", "ex", L["Event from another addon"], "source", "what", "detail" },
}

for _, row in ipairs(CORE) do
	Kinds.Register(row[2], { addon = ADDON, group = row[1], name = row[3], fields = { select(4, unpack(row)) } })
end

Kinds.Register("nt", { addon = ADDON, name = L["Note from Memories"], fields = { "what", "detail" }, always = true })
