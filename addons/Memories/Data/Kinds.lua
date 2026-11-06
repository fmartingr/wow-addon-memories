local ADDON, ns = ...

local Kinds = {}
ns.Kinds = Kinds

local byKind = {}
local order = {}

-- Codec.DecodeLine puts the fixed columns and raw under these keys, so a field may not use them.
local RESERVED = { t = true, p = true, m = true, x = true, y = true, k = true, raw = true }

-- spec = { addon, group, name, fields = { "name", "#npc", ... }, always }. A "#" marks a numeric field. A kind with
-- always = true has no setting: the kind gate never stops it.
function Kinds.Register(kind, spec)
	assert(type(kind) == "string" and kind:match("^%w+$"), "bad kind " .. tostring(kind))
	assert(not byKind[kind], "duplicate kind " .. kind)
	assert(type(spec) == "table" and type(spec.addon) == "string", "bad spec for kind " .. kind)
	local fields = spec.fields or {}
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
	for i, field in ipairs(fields) do
		assert(type(field) == "string" and field:match("^#?%w+$"), "bad field " .. tostring(field) .. " in " .. kind)
		local name = field:gsub("^#", "")
		assert(not RESERVED[name], "reserved field " .. name .. " in " .. kind)
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
	{ "Sessions", "in", "Login or reload", "how" },
	{ "Sessions", "out", "Logout or reload" },
	{ "Sessions", "pl", "Total /played", "#played" },
	{ "Sessions", "gp", "Gap (game ran, nothing saved)", "#seconds", "#lastSave" },
	{ "Sessions", "pc", "Computer this session ran on", "computer" },
	{ "Sessions", "af", "Away from keyboard", "on" },
	{ "Progress", "lv", "Level up", "#level" },
	{ "Progress", "xp", "Experience gained", "#amount", "src", "name", "#bonus" },
	{ "Progress", "qt", "Quest turned in", "#quest", "#xp", "#money", "title" },
	{ "Progress", "di", "Discovered an area", "area", "#xp" },
	{ "Progress", "rs", "Rested state", "#rested" },
	{
		"Deaths",
		"de",
		"Died",
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
	{ "Deaths", "gh", "Released spirit" },
	{ "Deaths", "al", "Alive again", "how", "by" },
	{ "Deaths", "cc", "Close call", "#seconds", "combat" },
	{ "Deaths", "lh", "Low-health warning", "combat" },
	{ "Deaths", "hc", "Hardcore death", "killer" },
	{ "Travel", "zo", "Entered a zone", "zone" },
	{ "Travel", "sz", "Entered a subzone", "sub" },
	{ "Travel", "ld", "Loading screen started", "#spell", "taxi" },
	{ "Travel", "le", "Loading screen ended" },
	{ "Travel", "tx", "Took a flight", "from", "to", "#cost" },
	{ "Travel", "tl", "Flight landed", "at" },
	{ "Travel", "bt", "Boat or zeppelin", "#fromMap", "#toMap", "from", "to" },
	{ "Travel", "hs", "Hearthstone", "#fromMap", "#toMap", "to", "#yards" },
	{ "Travel", "so", "Summon offered", "who", "area" },
	{ "Travel", "su", "Summoned", "who", "area", "#fromMap", "#toMap", "#yards" },
	{ "Travel", "po", "Portal or teleport", "dest", "#fromMap", "#toMap", "#spell", "#yards" },
	{ "Travel", "jp", "Other teleport", "#fromMap", "#toMap", "#yards", "why" },
	{ "Travel", "mo", "Mount up or down", "on", "#spell", "name" },
	{ "Travel", "ml", "Learned a mount or riding", "name", "#spell" },
	{ "Dungeons", "dn", "Entered a dungeon or raid", "name", "#instance", "itype", "#difficulty", "#size" },
	{ "Dungeons", "dx", "Left a dungeon or raid", "name", "#instance", "#seconds", "#deaths" },
	{ "Dungeons", "bo", "Boss fight ended", "name", "#encounter", "#success", "last", "place", "#seconds" },
	{ "Dungeons", "wb", "World boss killed", "name", "#npc" },
	{ "Screenshots", "ss", "Screenshot saved", "why", "result", "file" },
	{ "Other addons", "sn", "Screenshot note from another addon", "source", "note", "file" },
	{ "Other addons", "ex", "Event from another addon", "source", "what", "detail" },
}

for _, row in ipairs(CORE) do
	Kinds.Register(row[2], { addon = ADDON, group = row[1], name = row[3], fields = { select(4, unpack(row)) } })
end

Kinds.Register("nt", { addon = ADDON, name = "Note from Memories", fields = { "what", "detail" }, always = true })
