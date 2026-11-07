local _, ns = ...

local Progress = ns.Module("Progress")
ns.Progress = Progress

local floor = math.floor
local U = ns.U

Progress.QUEST_MATCH = 2
Progress.XP_WAIT = 1.5
Progress.TITLE_RETRY = 2
Progress.DISCOVERY_WAIT = 1.5
Progress.DISCOVERY_SAME = 3

local active = false
local patterns = {}
-- Quest turn-ins of the last seconds, for a nameless XP line: { xp, title, clock, used, waitTitle, held }.
local turnIns = {}
-- Nameless XP lines that wait for a turn-in: { amount, bonus, at, inst, timer }.
local waiting = {}
local lastDiscovery
local rested

local MAGIC = "[%^%$%(%)%.%[%]%*%+%-%?]"

-- Turns a GlobalStrings format into a Lua pattern. Returns the pattern and, for each capture, the format argument it
-- holds, since a translation may reorder the arguments with "%2$d". A "%s" at the very end takes the rest of the text.
function Progress.Compile(fmt)
	if type(fmt) ~= "string" or fmt == "" then
		return nil
	end
	local parts, order, arg = { "^" }, {}, 0
	local i, n = 1, #fmt
	while i <= n do
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
				if conv == "d" then
					parts[#parts + 1] = "(%d[%d,%.]*)"
				else
					parts[#parts + 1] = nxt > n and "(.+)" or "(.-)"
				end
			end
			i = nxt
		else
			parts[#parts + 1] = c:match(MAGIC) and "%" .. c or c
			i = i + 1
		end
	end
	parts[#parts + 1] = "()"
	return table.concat(parts), order
end

-- Returns the format arguments in their own order and the text after the match, or nil.
local function match(list, text)
	for _, p in ipairs(list or {}) do
		local caps = { text:match(p.pattern) }
		if #caps > 0 then
			local out = {}
			for k, argIndex in ipairs(p.order) do
				out[argIndex] = caps[k]
			end
			return out, text:sub(caps[#caps])
		end
	end
	return nil
end

-- Thousands separators differ by client language; XP is always a whole number.
local function number(s)
	return s and tonumber((s:gsub("[,%.%s]", ""))) or nil
end

-- Patterns come only from the client's GlobalStrings; a missing one matches nothing.
local function formats(name)
	local fmt = _G[name]
	return type(fmt) == "string" and { fmt } or {}
end

local function compile(name, fixEnd)
	local list = {}
	for _, fmt in ipairs(formats(name)) do
		if fixEnd then
			fmt = fmt:gsub("%.$", "")
		end
		local pattern, order = Progress.Compile(fmt)
		if pattern then
			list[#list + 1] = { pattern = pattern, order = order }
		end
	end
	patterns[name] = list
end

-- The words after the bonus number in COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP mark the group bonus: a rested kill
-- also shows its rested bonus as "+N" after the gain.
local function groupPattern(fmt)
	local tail = type(fmt) == "string" and fmt:match("%%%d*%$?d([^%%]*)$")
	tail = tail and tail:gsub("[%s%p]+$", "")
	return tail and tail ~= "" and "(%d[%d,%.]*)" .. tail:gsub(MAGIC, "%%%0") or nil
end

function Progress.Patterns()
	compile("COMBATLOG_XPGAIN_FIRSTPERSON")
	compile("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED")
	compile("ERR_ZONE_EXPLORED_XP")
	compile("ERR_ZONE_EXPLORED", true)
	patterns.group = {}
	for _, fmt in ipairs(formats("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP")) do
		patterns.group[#patterns.group + 1] = groupPattern(fmt)
	end
end

local function bonusIn(rest)
	for _, p in ipairs(patterns.group or {}) do
		local bonus = number(rest:match(p))
		if bonus then
			return bonus
		end
	end
	return nil
end

-- Returns amount, name (nil for a nameless gain) and group bonus, or nil.
function Progress.ParseXP(text)
	if type(text) ~= "string" then
		return nil
	end
	local args, rest = match(patterns.COMBATLOG_XPGAIN_FIRSTPERSON, text)
	if args then
		return number(args[2]), args[1], bonusIn(rest)
	end
	args, rest = match(patterns.COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED, text)
	if args then
		return number(args[1]), nil, bonusIn(rest)
	end
end

-- Returns area and XP (nil for a discovery without XP), or nil.
function Progress.ParseDiscovery(text)
	if type(text) ~= "string" then
		return nil
	end
	local args = match(patterns.ERR_ZONE_EXPLORED_XP, text)
	if args then
		return args[1], number(args[2])
	end
	args = match(patterns.ERR_ZONE_EXPLORED, text)
	if args then
		return (args[1]:gsub("%.$", ""))
	end
end

local function core()
	return ns.Store.Core()
end

function Progress.Level()
	return ns.Level() or 1
end

local function char()
	return U.TableAt(MemoriesCharDB, "char")
end

local function raise(level)
	local c = char()
	if type(c.level) ~= "number" or level > c.level then
		c.level = level
	end
	if level >= 60 then
		c.dinged60 = true
	end
end

-- The highest level that the saved data has seen: the first level, or a snapshot level with a time.
function Progress.KnownLevel()
	local first = char().first
	local known = type(first) == "table" and type(first.level) == "number" and first.level or 0
	local snap = MemoriesCharDB.snap
	for level, s in pairs(type(snap) == "table" and snap or {}) do
		if type(level) == "number" and level > known and type(s) == "table" and s.t then
			known = level
		end
	end
	return known
end

-- Writes lv for each level between the known one and level, as reached while nothing was recorded. Returns how many.
function Progress.CatchUp(level, at)
	local known = Progress.KnownLevel()
	if type(level) ~= "number" or known <= 0 or level <= known then
		return 0
	end
	local j = core()
	for l = known + 1, level do
		j:WriteAt(at, "lv", l)
		j:Snap(l, "t", at.t)
		j:Snap(l, "gap", 1)
		j:Count("progress", "levels")
	end
	raise(level)
	return level - known
end

function Progress.NotePlayed(total, levelSeconds)
	if type(total) ~= "number" or type(levelSeconds) ~= "number" then
		return
	end
	local j = core()
	local level = Progress.Level()
	if j:Snap(level, "played") == nil then
		j:Snap(level, "played", math.max(0, floor(total - levelSeconds)))
	end
end

local function readRested()
	local v, secret = ns.R(GetXPExhaustion())
	if secret or (v ~= nil and type(v) ~= "number") then
		return nil
	end
	return v or 0
end

-- ns.Level already holds the new level: Services.lua registers its PLAYER_LEVEL_UP handler first. An unknown level
-- is written later by CatchUp.
local function onLevel()
	local level = ns.Level()
	if not level then
		return
	end
	local j = core()
	local at = ns.Here()
	j:WriteAt(at, "lv", level)
	raise(level)
	j:Snap(level, "t", at.t)
	local zone = ns.R(GetRealZoneText())
	if zone and zone ~= "" then
		j:Snap(level, "zone", zone)
	end
	if ns.InInstance() then
		local name = ns.R(GetInstanceInfo())
		if name and name ~= "" then
			j:Snap(level, "inst", name)
		end
	end
	local pool = readRested()
	if pool then
		j:Snap(level, "rested", pool)
	end
	j:Count("progress", "levels")
	ns.Emit("LEVEL_UP", level)
	ns.Sessions.RequestPlayed("ding")
end

local function countXP(amount, src, inst, level)
	local j = core()
	j:Count("xp", "all", amount)
	j:Count("xp", src, amount)
	local cat = src
	if inst then
		j:Count("xp", "dungeon", amount)
		cat = "dungeon"
	end
	j:Count("xp", cat .. ":" .. level, amount)
end

-- level is the one at the gain: a held line is written after the ding that its XP caused.
local function writeXP(at, amount, src, name, bonus, inst, level)
	countXP(amount, src, inst, level or Progress.Level())
	core():WriteAt(at, "xp", amount, src, name, bonus)
end

local function pruneTurnIns()
	local now = GetTime()
	for i = #turnIns, 1, -1 do
		if now - turnIns[i].clock > Progress.QUEST_MATCH then
			table.remove(turnIns, i)
		end
	end
end

-- A turn-in whose title is not read yet holds its XP line until the title retry.
local function questXP(ti, at, amount, bonus, inst, level)
	ti.used = true
	if ti.waitTitle then
		ti.held = { at = at, amount = amount, bonus = bonus, inst = inst, level = level }
		return
	end
	writeXP(at, amount, "quest", ti.title, bonus, inst, level)
end

local function recentTurnIn(amount)
	pruneTurnIns()
	for i = #turnIns, 1, -1 do
		local ti = turnIns[i]
		if not ti.used and ti.xp == amount then
			return ti
		end
	end
end

local function onXP(_, text)
	local amount, name, bonus = Progress.ParseXP((ns.R(text)))
	if type(amount) ~= "number" or amount <= 0 then
		return
	end
	local at = ns.Here()
	local inst = ns.InInstance()
	local level = Progress.Level()
	if name then
		writeXP(at, amount, "kill", name, bonus, inst, level)
		return
	end
	local ti = recentTurnIn(amount)
	if ti then
		questXP(ti, at, amount, bonus, inst, level)
		return
	end
	local w = { amount = amount, bonus = bonus, at = at, inst = inst, level = level }
	w.timer = C_Timer.NewTimer(Progress.XP_WAIT, function()
		ns.Safe("progress:xp", function()
			for i, other in ipairs(waiting) do
				if other == w then
					table.remove(waiting, i)
					writeXP(w.at, w.amount, "other", nil, w.bonus, w.inst, w.level)
					return
				end
			end
		end)
	end)
	waiting[#waiting + 1] = w
end

local function title(id)
	local t = ns.R(C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id))
	return type(t) == "string" and t ~= "" and t or nil
end

local function onTurnIn(_, questID, xp, money)
	questID, xp, money = ns.RN(questID, xp, money)
	if type(questID) ~= "number" then
		return
	end
	local at = ns.Here()
	local ti = { xp = xp, title = title(questID), clock = GetTime(), used = false }
	ti.waitTitle = ti.title == nil
	core():Count("progress", "quests")
	for i, w in ipairs(waiting) do
		if w.amount == xp then
			table.remove(waiting, i)
			w.timer:Cancel()
			questXP(ti, w.at, w.amount, w.bonus, w.inst, w.level)
			break
		end
	end
	pruneTurnIns()
	turnIns[#turnIns + 1] = ti
	if ti.title then
		core():WriteAt(at, "qt", questID, xp, money, ti.title)
		return
	end
	C_Timer.After(Progress.TITLE_RETRY, function()
		ns.Safe("progress:quest", function()
			ti.title, ti.waitTitle = title(questID), nil
			core():WriteAt(at, "qt", questID, xp, money, ti.title)
			local h = ti.held
			if h then
				writeXP(h.at, h.amount, "quest", ti.title, h.bonus, h.inst, h.level)
			end
		end)
	end)
end

local function discovered(at, area, xp)
	core():Count("progress", "discoveries")
	core():WriteAt(at, "di", area, xp)
	lastDiscovery = { area = area, clock = GetTime() }
end

local function onSystem(_, text)
	local area, xp = Progress.ParseDiscovery((ns.R(text)))
	if not area or not xp then
		return
	end
	local at = ns.Here()
	discovered(at, area, xp)
	if xp > 0 then
		writeXP(at, xp, "discover", area, nil, ns.InInstance())
	end
end

-- The XP line of the same discovery can come after this message, so it waits and writes only when none came.
local function onInfo(_, _, message)
	local area, xp = Progress.ParseDiscovery((ns.R(message)))
	if not area or xp then
		return
	end
	local at = ns.Here()
	C_Timer.After(Progress.DISCOVERY_WAIT, function()
		ns.Safe("progress:discovery", function()
			local last = lastDiscovery
			if last and last.area == area and GetTime() - last.clock <= Progress.DISCOVERY_SAME then
				return
			end
			discovered(at, area)
		end)
	end)
end

local function onRested()
	local v = readRested()
	if v == nil then
		return
	end
	if rested and v < rested then
		core():Count("xp", "rested", rested - v)
		if v == 0 then
			core():Write("rs", 0)
		end
	end
	rested = v
end

function Progress:OnLogin()
	local j = core()
	if not j or not j:CanWrite() then
		return
	end
	active = true
	Progress.Patterns()
	ns.On("PLAYER_LEVEL_UP", onLevel, "progress:level")
	ns.On("CHAT_MSG_COMBAT_XP_GAIN", onXP, "progress:xp")
	ns.On("QUEST_TURNED_IN", onTurnIn, "progress:quest")
	ns.On("CHAT_MSG_SYSTEM", onSystem, "progress:discovery")
	ns.On("UI_INFO_MESSAGE", onInfo, "progress:discovery")
	ns.On("PLAYER_XP_UPDATE", onRested, "progress:rested")
	ns.On("UPDATE_EXHAUSTION", onRested, "progress:rested")
	ns.Listen("RESTORED", function(_, addon)
		if addon == ns.name then
			Progress.CatchUp(ns.R(UnitLevel("player")), ns.Here())
		end
	end, "progress:restored")
end

local loaded = false

function Progress:OnEnterWorld()
	if not active or loaded then
		return
	end
	loaded = true
	rested = readRested()
	if rested then
		core():Write("rs", rested)
	end
end
