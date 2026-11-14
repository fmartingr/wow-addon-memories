local ADDON, ns = ...
local L = ns.L

if not Memories or not Memories.RegisterModule then
	print(ADDON .. ": " .. L.CORE_MISSING)
	return
end

local floor = math.floor

local PAIR_WINDOW = 2.5
local SETTLE_DELAY = 2.6
local SCAN_EVERY = 0.5
local SCAN_AFTER = 5
local ENGAGED_TTL = 120
local DEAD_TTL = 600
local TARGET_DELAY = 1
local LEARNED_MAX = 400
local LONG_FIGHT = 20
local PLATES = 40
-- The creature type id of critters: the type name is localized.
local CRITTER = 8
local ELITE = { elite = true, rareelite = true }
local RARE = { rare = true, rareelite = true }
local DETAILS = { "npc", "ctype", "ctypeID", "class", "level" }
local MAGIC = "[%^%$%(%)%.%[%]%*%+%-%?]"

local h
-- { pattern, order }: order maps each capture to its format argument, since a translation may reorder them.
local xpPattern
-- Units that the player's group fights, by key: { name, npc, ctype, ctypeID, class, level, seen }.
local engaged = {}
-- The GetTime() of each key's death: a key dies once.
local dead = {}
-- Kills that wait to settle: { name, plate, named, xp, at, here, zone, inst }. A plate death and an XP line of the same
-- name pair into one kill.
local pending = {}
-- Creature details by name, for a kill that no engaged plate described. It lives in memory only.
local learned, learnedCount = {}, 0
local ticker, scanUntil
-- The fight that Combat follows: { target, class, level, low, died }; nil outside a fight and for a fight that was
-- already on at login, whose start is unknown.
local fight, skipFight = nil, false

local function pass(ok, ...)
	if ok then
		return ...
	end
end

-- An optional game call: nothing when the function is missing or fails.
local function call(fn, ...)
	if type(fn) == "function" then
		return pass(pcall(fn, ...))
	end
end

local function text(v)
	v = h:R(v)
	return type(v) == "string" and v ~= "" and v or nil
end

local function number(v)
	v = h:R(v)
	return type(v) == "number" and v or nil
end

local function flag(fn, ...)
	return h:R(call(fn, ...)) == true
end

-- Turns a GlobalStrings format into a pattern anchored at the start: the rested and group variants of the XP line only
-- add text after it.
local function compile(fmt)
	if type(fmt) ~= "string" or fmt == "" then
		return nil
	end
	local parts, order, arg, i = { "^" }, {}, 0, 1
	while i <= #fmt do
		if fmt:sub(i, i) == "%" then
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
				parts[#parts + 1] = conv == "d" and "(%d[%d,%.]*)" or nxt > #fmt and "(.+)" or "(.-)"
			end
			i = nxt
		else
			local c = fmt:sub(i, i)
			parts[#parts + 1] = c:match(MAGIC) and "%" .. c or c
			i = i + 1
		end
	end
	return { pattern = table.concat(parts), order = order }
end

-- Returns the creature's name and the XP of a "<name> dies, you gain <N> experience" line, or nil.
local function parseXP(msg)
	if not xpPattern or not msg then
		return nil
	end
	local caps, args = { msg:match(xpPattern.pattern) }, {}
	for k, argIndex in ipairs(xpPattern.order) do
		args[argIndex] = caps[k]
	end
	-- Thousands separators differ by client language; XP is always a whole number.
	local xp = args[2] and tonumber((args[2]:gsub("[,%.]", "")))
	if args[1] and xp then
		return args[1], xp
	end
end

-- "party" or "raid" inside a dungeon or raid, where plates and names are secret. Battlegrounds count as open world.
local function instanceType()
	local inside, itype = h:InInstance()
	return inside and (itype == "party" or itype == "raid") and itype or nil
end

-- GUID form Type-0-server-instance-zone-ID-spawn.
local function npcOf(guid)
	local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-([^-]*)")
	if kind == "Creature" or kind == "Vehicle" then
		return tonumber(id)
	end
end

-- A creature that no player controls: players and their pets are never kills.
local function creature(unit)
	return flag(UnitExists, unit) and not flag(UnitIsPlayer, unit) and not flag(UnitPlayerControlled, unit)
end

local function describe(unit, guid)
	local ctype, ctypeID = call(UnitCreatureType, unit)
	return {
		name = text(UnitName(unit)) or "?",
		npc = guid and npcOf(guid),
		ctype = text(ctype),
		ctypeID = number(ctypeID),
		class = text(call(UnitClassification, unit)),
		level = number(UnitLevel(unit)),
	}
end

local function learn(info)
	local name = info.name
	if name == "?" then
		return
	end
	local known = learned[name]
	if not known then
		-- Starting over keeps the table small in a long session; the next plate or target fills it again.
		if learnedCount >= LEARNED_MAX then
			learned, learnedCount = {}, 0
		end
		known = {}
		learned[name], learnedCount = known, learnedCount + 1
	end
	for _, field in ipairs(DETAILS) do
		if info[field] ~= nil then
			known[field] = info[field]
		end
	end
end

local function learnUnit(unit)
	if instanceType() or not creature(unit) then
		return
	end
	learn(describe(unit, text(UnitGUID(unit))))
end

-- The plate token that shows the target, so a targeted creature with a hidden GUID gets one name key, not two.
local function tokenOf(unit)
	if unit == "target" then
		for i = 1, PLATES do
			local plate = "nameplate" .. i
			if flag(UnitIsUnit, unit, plate) then
				return plate
			end
		end
	end
	return unit
end

-- The unit's key and GUID: the GUID, else its name and unit token. nil when both are hidden.
local function keyOf(unit)
	local guid = text(UnitGUID(unit))
	if guid then
		return guid, guid
	end
	local name = text(UnitName(unit))
	if not name then
		return nil
	end
	local key = "name:" .. name .. ":" .. tokenOf(unit)
	local own = "name:" .. name .. ":" .. unit
	if key ~= own then
		-- The target engaged before its plate showed: the plate key takes over its entry, else one death counts twice
		-- or a death seen in the plate's first scan is lost.
		engaged[key] = engaged[key] or engaged[own]
		engaged[own] = nil
	end
	return key
end

-- A name key holds a unit token, and the game gives that token to another unit next: the old key ends with it.
local function forgetToken(unit)
	local suffix = ":" .. unit
	for key in pairs(engaged) do
		if key:sub(1, 5) == "name:" and key:sub(-#suffix) == suffix then
			engaged[key] = nil
		end
	end
end

-- A unit tapped by someone else is never the player's kill, even with threat on it.
local function mine(unit)
	if flag(UnitIsTapDenied, unit) then
		return false
	end
	if number(call(UnitThreatSituation, "player", unit)) or number(call(UnitThreatSituation, "pet", unit)) then
		return true
	end
	-- The fight flag alone also marks guards, escorts and creatures that fight them: only an attackable unit counts.
	return flag(UnitAffectingCombat, unit) and h:R(UnitCanAttack("player", unit)) == true
end

local function settle(k)
	for i, p in ipairs(pending) do
		if p == k then
			table.remove(pending, i)
			break
		end
	end
	local plate, known = k.plate or {}, not k.inst and learned[k.name] or {}
	local d = {}
	for _, field in ipairs(DETAILS) do
		d[field] = plate[field]
		if d[field] == nil then
			d[field] = known[field]
		end
	end
	local name, class = k.name, d.class
	local first
	if d.npc then
		first = h:IsFirst("kills", "npc:" .. d.npc)
	elseif name ~= "?" then
		first = h:IsFirst("kills", "n:" .. name)
	end
	-- A kill with no id and a hidden name cannot be told apart from another, so it always writes.
	local write = first or ELITE[class] or RARE[class] or (not d.npc and name == "?") or not h:NewOnly("kills")
	if write then
		h:WriteAt(k.here, "ki", name, d.npc, d.ctype, class, k.xp, d.level, k.inst, first and 1 or nil)
	end
	if RARE[class] then
		h:WriteAt(k.here, "ra", name, d.npc, d.level)
		h:Count("kills", "rare")
	end
	h:Count("kills", "total")
	if d.npc then
		h:Count("kills", "npc:" .. d.npc)
	end
	local named = name ~= "?"
	if named then
		h:Count("kills", "n:" .. name)
	end
	if k.inst then
		h:Count("kills", "inst")
		return
	end
	h:Count("kills", k.xp and "xp" or "noxp")
	h:Count("kills", "t:" .. (d.ctype or "?"))
	if d.ctypeID == CRITTER then
		h:Count("kills", "critter")
	end
	if named and k.zone then
		h:Count("kills", "nz:" .. name .. "@" .. k.zone)
	end
	if ELITE[class] then
		h:Count("kills", "elite")
		if named then
			h:Count("kills", "e:" .. name)
		end
	end
end

local function newKill(name, now, inst)
	local k = { name = name, at = now, here = h:Here(), inst = inst }
	if not inst then
		k.zone = text(GetRealZoneText())
	end
	pending[#pending + 1] = k
	C_Timer.After(SETTLE_DELAY, function()
		h:Safe("settle", settle, k)
	end)
	return k
end

-- A pending kill of this name, seen within the pair window, that has the one half and lacks the other.
local function partner(name, now, has, lacks)
	for _, k in ipairs(pending) do
		if k[has] and not k[lacks] and k.name == name and now - k.at <= PAIR_WINDOW then
			return k
		end
	end
end

local function died(key, now)
	local info = engaged[key]
	engaged[key], dead[key] = nil, now
	local k = info.name ~= "?" and partner(info.name, now, "named", "plate") or newKill(info.name, now)
	k.plate = info
end

local function onXP(_, msg)
	local name, xp = parseXP(text(msg))
	if not name then
		return
	end
	local now = GetTime()
	local inst = instanceType()
	local k = not inst and partner(name, now, "plate", "named")
	if not k then
		if not inst and not learned[name] and text(UnitName("target")) == name then
			learnUnit("target")
		end
		k = newKill(name, now, inst)
	end
	k.named, k.xp = true, xp
end

local function scanUnit(unit, now)
	if not creature(unit) then
		return
	end
	local key, guid = keyOf(unit)
	if not key then
		return
	end
	local isDead = flag(UnitIsDead, unit)
	if dead[key] then
		-- A name key holds a unit token, and the game gives that token to the next creature of the same name.
		if guid or isDead then
			return
		end
		dead[key] = nil
	end
	-- A creature that another player tagged since it was engaged is never the player's kill, even when it died between
	-- two scans.
	if engaged[key] and flag(UnitIsTapDenied, unit) then
		engaged[key] = nil
	elseif isDead then
		if engaged[key] then
			died(key, now)
		end
	elseif engaged[key] then
		engaged[key].seen = now
	elseif mine(unit) then
		local info = describe(unit, guid)
		info.seen = now
		engaged[key] = info
		learn(info)
	end
end

local function prune(now)
	for key, info in pairs(engaged) do
		if now - info.seen > ENGAGED_TTL then
			engaged[key] = nil
		end
	end
	for key, at in pairs(dead) do
		if now - at > DEAD_TTL then
			dead[key] = nil
		end
	end
end

local function inCombat()
	return h:InFight() or h:R(InCombatLockdown()) == true
end

-- Prunes first: a scan between fights would otherwise refresh entries that the TTL has already dropped.
local function scan()
	local now = GetTime()
	prune(now)
	if not instanceType() then
		for i = 1, PLATES do
			scanUnit("nameplate" .. i, now)
		end
		scanUnit("target", now)
	end
end

-- The stop check stays outside the scan, so an error in a scan never keeps the ticker running.
local function startScan()
	if not ticker then
		ticker = C_Timer.NewTicker(SCAN_EVERY, function()
			h:Safe("scan", scan)
			if not inCombat() and GetTime() >= (scanUntil or 0) then
				ticker:Cancel()
				ticker = nil
			end
		end)
	end
end

local function onPlateRemoved(_, unit)
	if instanceType() or not creature(unit) then
		return
	end
	local key, guid = keyOf(unit)
	if not key or not engaged[key] then
		return
	end
	if flag(UnitIsTapDenied, unit) then
		engaged[key] = nil
	elseif flag(UnitIsDead, unit) then
		died(key, GetTime())
	elseif not guid then
		forgetToken(unit)
	end
end

-- The game's restrictions on the target switch after the fight starts, so the target is read a moment later.
local function readTarget(cur)
	if fight ~= cur then
		return
	end
	if not flag(UnitExists, "target") or flag(UnitIsPlayer, "target") then
		return
	end
	if h:R(UnitCanAttack("player", "target")) ~= true then
		return
	end
	fight.target = text(UnitName("target")) or "?"
	fight.class = text(call(UnitClassification, "target"))
	fight.level = number(UnitLevel("target"))
end

local function onFightStart()
	startScan()
	if skipFight then
		skipFight, fight = false, nil
		return
	end
	local cur = {}
	fight = cur
	C_Timer.After(TARGET_DELAY, function()
		h:Safe("fight target", readTarget, cur)
	end)
end

local function onFightEnd(_, ended)
	scanUntil = GetTime() + SCAN_AFTER
	local cur = fight
	fight, skipFight = nil, false
	if not cur or type(ended) ~= "table" or not ended.start or not ended.stop then
		return
	end
	local seconds = floor(ended.stop - ended.start + 0.5)
	local deadNow = cur.died or flag(UnitIsDeadOrGhost, "player")
	h:Count("fights", "n")
	h:Count("fights", "sec", seconds)
	local counts = h:Counts("fights")
	if seconds > (counts.longest or 0) then
		counts.longest = seconds
	end
	if deadNow then
		h:Count("fights", "died")
	end
	if seconds >= LONG_FIGHT or deadNow or cur.low then
		h:Write("fi", seconds, cur.target, cur.class, cur.level, deadNow and 1 or nil, ended.casts)
	end
end

-- The core emits LEVEL_UP only with a known level.
local function onLevelUp(_, level)
	local counts = h:Counts("kills")
	h:Snap(level, "kills", { total = counts.total or 0, xp = counts.xp or 0, inst = counts.inst or 0 })
end

-- A registration after login calls OnLogin before RegisterModule returns, so the handle comes from the argument.
local function onLogin(handle)
	h = handle
	xpPattern = compile(COMBATLOG_XPGAIN_FIRSTPERSON)
	h:On("CHAT_MSG_COMBAT_XP_GAIN", onXP)
	h:On("PLAYER_TARGET_CHANGED", function()
		forgetToken("target")
		learnUnit("target")
	end)
	h:On("NAME_PLATE_UNIT_ADDED", function(_, unit)
		learnUnit(unit)
	end)
	h:On("NAME_PLATE_UNIT_REMOVED", onPlateRemoved)
	h:Listen("FIGHT_START", onFightStart)
	h:Listen("FIGHT_END", onFightEnd)
	h:Listen("LOW_HEALTH", function()
		if fight then
			fight.low = true
		end
	end)
	h:Listen("DIED", function()
		if fight then
			fight.died = true
		end
	end)
	h:Listen("LEVEL_UP", onLevelUp)
	-- After a login or reload in combat the core starts a fight at LOGIN with no known start: it gets no fi and no fight
	-- counts. A late registration inside a fight sees no FIGHT_START at all.
	if h:R(InCombatLockdown()) == true then
		skipFight = not h:InFight()
		startScan()
	end
end

Memories.RegisterModule({
	addon = ADDON,
	api = 1,
	saved = "MemoriesCombatCharDB",
	kinds = {
		{
			kind = "ki",
			group = "Combat",
			name = L.KILLED_CREATURE,
			fields = { "name", "#npc", "ctype", "class", "#xp", "#level", "inst", "#first" },
		},
		{ kind = "ra", group = "Combat", name = L.KILLED_RARE, fields = { "name", "#npc", "#level" } },
		{
			kind = "fi",
			group = "Combat",
			name = L.LONG_FIGHT,
			fields = { "#seconds", "target", "class", "#level", "died", "#casts" },
		},
	},
	newOnly = { { key = "kills", label = L.KILLS_NEW_FINDINGS_ONLY, kinds = { "ki" } } },
	OnLogin = onLogin,
})
