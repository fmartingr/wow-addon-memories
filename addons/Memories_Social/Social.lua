local ADDON, ns = ...
local L = ns.L

if not Memories or not Memories.RegisterModule then
	print(ADDON .. ": " .. L["Memories is not loaded."])
	return
end

local Social = {}
ns.Social = Social

local floor = math.floor

local MAGIC = "[%^%$%(%)%.%[%]%*%+%-%?]"
local GROUP_DELAY = 1
local GUILD_DELAY = 2
local LOGIN_GROUP = 5
local LOGIN_GUILD = 7
local CAPS = { enemy = 400, other = 100 }
local RAID_MAX = 40
local PARTY_MAX = 4
local FONTS = { korean = "Fonts\\2002.TTF", chinese = "Fonts\\ARKai_T.ttf", japanese = "Fonts\\ARKai_T.ttf" }
-- The client locales that already draw a script with their own font.
local NATIVE = { koKR = "korean", zhCN = "chinese", zhTW = "chinese" }

local h
-- The player memory of this session: records by full name, the latest full name by first name, and the records kept
-- per bucket ("enemy" or "other").
local memory, byFirst, kept = {}, {}, { enemy = 0, other = 0 }
-- GetGuildInfo failures on other units this session; ns.Log keeps only the first one.
Social.guildFailures = 0

local function pass(ok, ...)
	if ok then
		return ...
	end
end

-- An optional game call: nothing when the function is missing or fails.
function ns.Call(fn, ...)
	if type(fn) == "function" then
		return pass(pcall(fn, ...))
	end
end

-- A function of an optional game table.
function ns.Api(t, name)
	return type(t) == "table" and t[name] or nil
end

function ns.Text(v)
	v = ns.h:R(v)
	return type(v) == "string" and v ~= "" and v or nil
end

function ns.Number(v)
	v = ns.h:R(v)
	return type(v) == "number" and v or nil
end

function ns.Flag(fn, ...)
	return ns.h:R(ns.Call(fn, ...)) == true
end

local logged = {}

-- Logs an error through the core's error guard once per place and session, without stopping the caller. The guard
-- calls the client's error handler on every log, so a call that keeps failing must not reach it each time.
function ns.Log(where, msg)
	if logged[where] then
		return
	end
	logged[where] = true
	ns.h:Safe(where, error, tostring(msg), 0)
end

-- A GlobalStrings format as a pattern for the whole text, or nil. Each argument is captured by its position in the
-- format, so a translation that reorders them with "%2$s" still fills the right one.
function ns.Compile(fmt)
	if type(fmt) ~= "string" or fmt == "" then
		return nil
	end
	local parts, order, arg, i = { "^" }, {}, 0, 1
	while i <= #fmt do
		local c = fmt:sub(i, i)
		if c == "%" then
			local pos, conv, nxt = fmt:match("^(%d+)%$([sd])()", i + 1)
			if not pos then
				conv, nxt = fmt:match("^([sd%%])()", i + 1)
			end
			if not conv then
				return nil
			end
			if conv == "%" then
				parts[#parts + 1] = "%%"
			else
				arg = arg + 1
				order[#order + 1] = tonumber(pos) or arg
				-- Thousands separators differ by client language.
				parts[#parts + 1] = conv == "d" and "(%d[%d,%.]*)" or "(.-)"
			end
			i = nxt
		else
			parts[#parts + 1] = c:match(MAGIC) and "%" .. c or c
			i = i + 1
		end
	end
	parts[#parts + 1] = "$"
	return { pattern = table.concat(parts), order = order }
end

-- The arguments of a text that matches a compiled format, by their position in the format, else nil.
function ns.Match(compiled, s)
	if not compiled or not s then
		return nil
	end
	local caps = { s:match(compiled.pattern) }
	if #caps == 0 then
		return nil
	end
	local args = {}
	for k, pos in ipairs(compiled.order) do
		args[pos] = caps[k]
	end
	return args
end

-- A whole number from a captured "%d", with any thousands separator.
function ns.Whole(s)
	return s and tonumber((s:gsub("[,%.]", "")))
end

local call, api, text, number, flag = ns.Call, ns.Api, ns.Text, ns.Number, ns.Flag

-- Names ------------------------------------------------------------------------

-- "First Surname" when the unit has a surname, else the first name; nil when the name is unknown. Forever gives the
-- surname as the second value of UnitName.
function Social.FullName(unit)
	local first, surname = h:RN(UnitName(unit))
	first, surname = text(first), text(surname)
	-- A unit whose data has not arrived yet is named UNKNOWNOBJECT.
	if not first or first == UNKNOWNOBJECT then
		return nil
	end
	return surname and first .. " " .. surname or first, first
end

-- Chat and duel requests join the name and the surname with "-".
function Social.NameFromText(s)
	s = text(s)
	return s and (s:gsub("%-", " ", 1))
end

-- The script of a name, from its first UTF-8 lead byte that marks one.
function Social.Script(s)
	if type(s) ~= "string" then
		return "latin"
	end
	for i = 1, #s do
		local b = s:byte(i)
		if b == 0xD0 or b == 0xD1 then
			return "cyrillic"
		elseif b >= 0xEA and b <= 0xED then
			return "korean"
		elseif b >= 0xE4 and b <= 0xE9 then
			return "chinese"
		elseif b == 0xE3 then
			return "japanese"
		end
	end
	return "latin"
end

-- The font that draws a name, or nil when the default font already does.
function Social.Font(s)
	local script = Social.Script(s)
	if NATIVE[text(call(GetLocale))] == script then
		return nil
	end
	return FONTS[script]
end

-- Player memory ----------------------------------------------------------------

-- Keeps a record and returns the kept one (or the given one over the cap) and true when its guild was just learned.
-- Known values overwrite; unknown ones never erase.
function Social.Remember(rec)
	local old = memory[rec.name]
	if old then
		local late = old.guild == nil and rec.guild ~= nil
		for k, v in pairs(rec) do
			old[k] = v
		end
		old.seen = (old.seen or 0) + 1
		byFirst[old.first or old.name] = old.name
		return old, late
	end
	rec.seen = 1
	local bucket = rec.enemy and "enemy" or "other"
	if kept[bucket] < CAPS[bucket] then
		kept[bucket] = kept[bucket] + 1
		memory[rec.name] = rec
		byFirst[rec.first or rec.name] = rec.name
	end
	return rec, false
end

-- A record by full name, else by the first word of the name unless exact is true.
function Social.Find(name, exact)
	name = text(name)
	if not name then
		return nil
	end
	if memory[name] or exact then
		return memory[name]
	end
	local full = byFirst[name:match("^(%S+)")]
	return full and memory[full]
end

-- A failed read on a PvP-restricted unit counts as an unknown guild.
local function guildOf(unit)
	local ok, guild = pcall(GetGuildInfo, unit)
	if not ok then
		Social.guildFailures = Social.guildFailures + 1
		ns.Log("guild read", guild)
		return nil
	end
	return text(guild)
end

-- True for a unit that exists, is a player and is not you.
function Social.IsOther(unit)
	return flag(UnitExists, unit) and flag(UnitIsPlayer, unit) and not flag(UnitIsUnit, unit, "player")
end

-- Reads another player's unit into the memory. Returns the record and true when the guild was just learned, else nil.
function Social.Read(unit, source)
	if not Social.IsOther(unit) then
		return nil
	end
	local name, first = Social.FullName(unit)
	if not name then
		return nil
	end
	local _, class = h:RN(call(UnitClass, unit))
	local _, race = h:RN(call(UnitRace, unit))
	local level = number(call(UnitLevel, unit))
	local mine, theirs = text(call(UnitFactionGroup, "player")), text(call(UnitFactionGroup, unit))
	-- nil when a faction is unknown, so a merge never erases a known enemy.
	local isEnemy
	if mine and theirs then
		isEnemy = mine ~= theirs
	end
	return Social.Remember({
		name = name,
		first = first,
		class = text(class),
		race = text(race),
		level = level and level > 0 and level or nil,
		guild = guildOf(unit),
		enemy = isEnemy,
		at = GetTime(),
		source = source,
	})
end

-- Group ------------------------------------------------------------------------

local function members()
	return h:State("group")
end

function Social.OpenMembers()
	local out = {}
	for name in pairs(members()) do
		out[#out + 1] = name
	end
	table.sort(out)
	return out
end

local function groupUnits()
	local units = {}
	if flag(IsInRaid) then
		local n = math.min(number(call(GetNumGroupMembers)) or 0, RAID_MAX)
		for i = 1, n do
			units[#units + 1] = "raid" .. i
		end
	else
		for i = 1, PARTY_MAX do
			units[#units + 1] = "party" .. i
		end
	end
	return units
end

-- The remembered group lives in the saved state, so a reload writes no second join and a member who left during a
-- crash gets a leave on the next scan.
local function scanGroup()
	local remembered = members()
	local present, joins, unknown = {}, {}, false
	for _, unit in ipairs(groupUnits()) do
		if flag(UnitExists, unit) and not flag(UnitIsUnit, unit, "player") then
			local rec = Social.Read(unit, "group")
			if rec then
				present[rec.name] = true
				if not remembered[rec.name] then
					joins[#joins + 1] = rec
				end
			else
				unknown = true
			end
		end
	end
	local myGuild = Social.MyGuild()
	for _, rec in ipairs(joins) do
		remembered[rec.name] = true
		h:Count("social", "joins")
		if myGuild and rec.guild == myGuild then
			h:Count("social", "guildmateJoins")
		end
		h:Write("gj", rec.name, rec.guild, rec.class, rec.level)
	end
	-- A member whose name is not known yet is still in the group: no leave until every member reads.
	if unknown then
		return
	end
	local leaves = {}
	for name in pairs(remembered) do
		if not present[name] then
			leaves[#leaves + 1] = name
		end
	end
	table.sort(leaves)
	for _, name in ipairs(leaves) do
		remembered[name] = nil
		h:Write("gl", name)
	end
end

-- Guild ------------------------------------------------------------------------

local function guildState()
	return h:State("guild")
end

-- Your guild from the last gu, or nil.
function Social.MyGuild()
	return text(guildState().guild)
end

local function round3(v)
	return floor(v * 1000 + 0.5) / 1000
end

local function color(c)
	c = h:R(c)
	if type(c) ~= "table" then
		return nil
	end
	local r, g, b = number(c.r), number(c.g), number(c.b)
	if r and g and b then
		return { round3(r), round3(g), round3(b) }
	end
end

local function logoColor(v, i)
	local r, g, b = number(v[i]), number(v[i + 1]), number(v[i + 2])
	if r and g and b then
		return { round3(r / 255), round3(g / 255), round3(b / 255) }
	end
end

local function readTabard()
	local fn = api(C_GuildInfo, "GetGuildTabardInfo")
	if fn then
		local ok, info = pcall(fn, "player")
		if not ok then
			ns.Log("tabard", info)
		end
		info = ok and h:R(info)
		if type(info) == "table" then
			return {
				background = color(info.backgroundColor),
				border = color(info.borderColor),
				emblem = color(info.emblemColor),
				file = number(info.emblemFileID),
				style = number(info.emblemStyle),
			}
		end
	end
	local v = { call(GetGuildLogoInfo) }
	if number(v[1]) and number(v[10]) then
		return {
			background = logoColor(v, 1),
			border = logoColor(v, 4),
			emblem = logoColor(v, 7),
			file = number(v[10]),
			style = number(v[11]),
		}
	end
end

local function snapGuild(name, rank, index, tabard, force)
	local level = h:Level()
	if not level then
		return
	end
	local old = h:Snap(level, "guild")
	-- A failed tabard read keeps the saved tabard; a fresh one replaces it, so a redesigned tabard reaches the snap.
	if force or type(old) ~= "table" or old.name ~= name or tabard or not old.tabard then
		tabard = tabard or h:State("tabards")[name]
		h:Snap(level, "guild", { name = name, rank = rank, index = index, tabard = tabard })
	end
end

local function readGuild()
	local name, rank, index = call(GetGuildInfo, "player")
	name, rank, index = text(name), text(rank), number(index)
	local s = guildState()
	if not name then
		-- In a guild whose name the client has not sent yet: the roster event reads it again.
		if flag(IsInGuild) or not s.guild or s.guild == "" then
			return
		end
		s.guild, s.rank = "", nil
		h:Count("social", "guildChanges")
		h:Write("gu", "", nil)
		return
	end
	local tabard = readTabard()
	if tabard then
		h:State("tabards")[name] = tabard
	end
	if s.guild == name and s.rank == rank then
		snapGuild(name, rank, index, tabard, false)
		return
	end
	s.guild, s.rank = name, rank
	h:Count("social", "guildChanges")
	h:Write("gu", name, rank)
	snapGuild(name, rank, index, tabard, true)
end

-- Start ------------------------------------------------------------------------

local function later(delay, where, fn)
	C_Timer.After(delay, function()
		h:Safe(where, fn)
	end)
end

function Social.Start(handle)
	h = handle
	h:On("GROUP_ROSTER_UPDATE", function()
		h:Coalesce("group", GROUP_DELAY, scanGroup)
	end)
	for _, event in ipairs({ "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "GUILDTABARD_UPDATE" }) do
		h:On(event, function()
			h:Coalesce("guild", GUILD_DELAY, readGuild)
		end)
	end
	-- A restored journal brings its own remembered group and guild.
	h:Listen("RESTORED", function(_, addon)
		if addon == ADDON then
			h:Coalesce("group", GROUP_DELAY, scanGroup)
			h:Coalesce("guild", GUILD_DELAY, readGuild)
		end
	end)
	later(LOGIN_GROUP, "login group", scanGroup)
	later(LOGIN_GUILD, "login guild", readGuild)
	if flag(IsInGuild) then
		call(api(C_GuildInfo, "GuildRoster"))
	end
end
