local _, ns = ...

local Deaths = ns.Module("Deaths")
ns.Deaths = Deaths

local floor, sqrt = math.floor, math.sqrt
local U = ns.U

Deaths.RECAP_WAIT = 1
Deaths.SOULSTONE = 15
Deaths.ACCEPT = 15
Deaths.OFFER = 90
Deaths.XP_LOSS = 120
Deaths.CORPSE = 30
Deaths.SPIRIT_YARDS = 60
Deaths.SETTLE = 3
Deaths.HOOK_RETRY = 3
Deaths.MAX_CREATURES = 1500
Deaths.MAX_PLAYERS = 200

local active = false
-- The dead state of this load, the open death that waits for its recap, and the revive marks by GetTime().
local dead, ghost = false, false
local pending
local marks = {}
local spot
local encounter = false
local lastDeadClock
-- Names are hidden inside instances, so they are learned outdoors and kept for a death after a relog.
local creatures, creatureCount = {}, 0
local players, playerCount = {}, 0
local guidErrors = 0
local episode

local function core()
	return ns.Store.Core()
end

-- The saved state lives in the core journal's data.state, so a kind that is off still keeps it right.
local function state()
	return core():State("deaths")
end

local function count(key, n)
	core():Count("deaths", key, n)
end

local flag = U.Flag

local function deadNow()
	return flag(UnitIsDeadOrGhost, "player")
end

local function inCombat()
	return ns.R(InCombatLockdown()) == true or flag(UnitAffectingCombat, "player")
end

local function hardcore()
	local fn = type(C_GameRules) == "table" and C_GameRules.IsHardcoreActive
	return type(fn) == "function" and ns.R(fn()) == true
end

-- place is "world" or the instance name; inst is "pvp" in a battleground or an arena.
local function where()
	if not ns.InInstance() then
		return "world", nil
	end
	local name, kind = ns.RN(GetInstanceInfo())
	local inst = (kind == "pvp" or kind == "arena") and "pvp" or nil
	return type(name) == "string" and name ~= "" and name or "?", inst
end

-- An outdoor death with no map position takes the last trail point. inside is ns.InInstance().
local function deathAt(inside)
	local at = ns.Here()
	if not inside and not at.x then
		local p = ns.Trail.LastKnownPoint()
		if p then
			at.m, at.x, at.y = p.m, p.x, p.y
		end
	end
	return at
end

local text, number = U.Text, U.Number

local selfGuid

local function isOtherPlayer(guid)
	selfGuid = selfGuid or ns.R(UnitGUID("player"))
	return guid:match("^Player%-") ~= nil and guid ~= selfGuid
end

-- The entry with the highest timestamp is the killing blow; a tie goes to the later entry. Returns it and its stamp.
local function readRecap()
	local api = C_DeathRecap
	if type(api) ~= "table" or type(api.HasRecapEvents) ~= "function" or type(api.GetRecapEvents) ~= "function" then
		return nil
	end
	local ok, has = pcall(api.HasRecapEvents)
	if not ok or ns.R(has) ~= true then
		return nil
	end
	local events
	ok, events = pcall(api.GetRecapEvents)
	events = ok and ns.R(events) or nil
	if type(events) ~= "table" then
		return nil
	end
	local best, bestStamp
	for _, e in ipairs(events) do
		if type(e) == "table" then
			local stamp = number(e.timestamp) or 0
			if not best or stamp >= bestStamp then
				best, bestStamp = e, stamp
			end
		end
	end
	return best, bestStamp
end

-- The killer of a recap entry. Forever adds a surname to a stranger in the recap, so a learned name wins.
local function killer(e, info)
	info.killer = U.Name(e.sourceName)
	info.spell = text(e.spellName)
	local env = text(e.environmentalType)
	info.env = env and env:lower()
	info.amount = number(e.amount)
	local guid = text(e.sourceGUID)
	if not guid then
		return
	end
	local npc = U.NpcID(guid)
	if npc then
		info.npc = npc
		local known = creatures[npc]
		if known then
			info.killer, info.klevel, info.kclass = known.name, known.level, known.class
		end
	elseif isOtherPlayer(guid) then
		info.byPlayer = true
		local known = players[guid]
		if known then
			info.klevel, info.kclass = known.level, known.class
		end
	end
end

local function writeGhost()
	state().ghost = true
	core():Write("gh")
end

local function counted(info)
	count("total")
	if info.inst == "pvp" then
		count("battleground")
	elseif info.place == "world" then
		count("world")
	else
		count("dungeon")
	end
	if info.byPlayer then
		count("player")
	end
	if info.env then
		count("env." .. info.env)
	end
	if info.boss then
		count("boss")
	end
	local all = core():Counts("deaths")
	if info.amount and (type(all.hardest) ~= "number" or info.amount > all.hardest) then
		all.hardest = info.amount
	end
end

-- d = { at, place, inst, boss }. The recap stamp dedupes the same death across reloads.
local function writeDeath(d)
	d.written = true
	local s = state()
	s.open = true
	local e, stamp = readRecap()
	if e and stamp > 0 and stamp == s.lastRecap then
		if d.ghostAfter and not s.ghost then
			writeGhost()
		end
		return
	end
	if e and stamp > 0 then
		s.lastRecap = stamp
	end
	s.ghost = false
	local info = { place = d.place, inst = d.inst }
	if e then
		killer(e, info)
	end
	info.boss = d.boss == true or info.kclass == "worldboss"
	info.byPlayer = info.byPlayer == true
	counted(info)
	if s.visit then
		s.visit = (tonumber(s.visit) or 0) + 1
	end
	local j = core()
	j:WriteAt(
		d.at,
		"de",
		info.killer,
		info.npc,
		info.spell,
		info.env,
		info.place,
		info.boss or nil,
		info.klevel,
		info.kclass,
		info.amount,
		info.byPlayer and 1 or nil,
		info.inst
	)
	ns.Emit("DIED", U.Copy(info))
	if hardcore() then
		j:WriteAt(d.at, "hc", info.killer)
	end
	if d.ghostAfter then
		writeGhost()
	end
end

local function startDeath()
	local inside = ns.InInstance()
	local place, inst = where()
	dead, ghost = true, false
	marks = {}
	spot = ns.World()
	pending = { at = deathAt(inside), place = place, inst = inst, boss = encounter }
	return pending
end

local function readLater(d)
	C_Timer.After(Deaths.RECAP_WAIT, function()
		ns.Safe("deaths:recap", function()
			if d ~= pending or d.written then
				return
			end
			-- Alive again with no revive seen: the client took the death back.
			if not deadNow() then
				dead, pending = false, nil
				return
			end
			writeDeath(d)
		end)
	end)
end

local function onDead()
	lastDeadClock = GetTime()
	if dead then
		return
	end
	if deadNow() then
		readLater(startDeath())
		return
	end
	C_Timer.After(Deaths.RECAP_WAIT, function()
		ns.Safe("deaths:dead", function()
			if not dead and deadNow() then
				-- A release during the wait fired PLAYER_ALIVE while dead was still false.
				local d = startDeath()
				ghost = flag(UnitIsGhost, "player")
				d.ghostAfter = ghost
				writeDeath(d)
			end
		end)
	end)
end

local function within(mark, limit)
	return mark ~= nil and GetTime() - mark <= limit
end

local function far()
	local here = ns.World()
	if not spot or not here or here.inst ~= spot.inst then
		return false
	end
	return sqrt((here.x - spot.x) ^ 2 + (here.y - spot.y) ^ 2) > Deaths.SPIRIT_YARDS
end

-- noGhost is true for PLAYER_ALIVE without a ghost step: a resurrection where the body lies.
-- The order follows the spec; the first match wins.
local function howOf(noGhost)
	if within(marks.soulstone, Deaths.SOULSTONE) then
		return "soulstone"
	elseif within(marks.accept, Deaths.ACCEPT) or within(marks.offer, Deaths.OFFER) or noGhost then
		return "res"
	elseif within(marks.xpLoss, Deaths.XP_LOSS) then
		return "spirit"
	elseif within(marks.corpse, Deaths.CORPSE) then
		return "corpse"
	elseif far() then
		return "spirit"
	end
	return "corpse"
end

local function revive(noGhost)
	if pending and not pending.written then
		writeDeath(pending)
	end
	local how = howOf(noGhost)
	local by = how == "res" and marks.by or nil
	count("revive." .. how)
	state().open = false
	core():Write("al", how, by)
	dead, ghost, pending, spot = false, false, nil, nil
	marks = {}
	ns.Emit("ALIVE", how)
end

local function onAlive()
	if not dead then
		return
	end
	if flag(UnitIsGhost, "player") then
		if not ghost then
			ghost = true
			if pending and not pending.written then
				pending.ghostAfter = true
			elseif not state().ghost then
				writeGhost()
			end
		end
		return
	end
	-- Most loading screens and reloads fire it while the body is still dead.
	if deadNow() then
		return
	end
	revive(not ghost)
end

local function onUnghost()
	if dead then
		revive(false)
	end
end

local function mark(key)
	return function()
		marks[key] = GetTime()
	end
end

local function onOffer(_, inviter)
	marks.offer = GetTime()
	marks.by = text(inviter)
end

-- The flag mirrors the CVar for the converter: close calls need the flash.
local function noteFlash()
	U.TableAt(MemoriesCharDB, "flags").lowHealthFlash = ns.LowHealth.IsOn()
end

local function learn(unit)
	if type(unit) ~= "string" or ns.InInstance() then
		return
	end
	-- UnitGUID raises on some PvP-restricted units; that is no error of Memories.
	local ok, guid = pcall(UnitGUID, unit)
	if not ok then
		guidErrors = guidErrors + 1
		return
	end
	guid = text(guid)
	if not guid then
		return
	end
	local name = text(UnitName(unit))
	if not name then
		return
	end
	local level = number(UnitLevel(unit))
	local npc = U.NpcID(guid)
	if npc then
		local known = creatures[npc]
		if not known then
			if creatureCount >= Deaths.MAX_CREATURES then
				return
			end
			creatureCount = creatureCount + 1
			known = { name = name }
			creatures[npc] = known
		elseif #name < #known.name then
			known.name = name
		end
		known.level = level or known.level
		known.class = text(UnitClassification(unit)) or known.class
	elseif isOtherPlayer(guid) then
		local known = players[guid]
		if not known then
			if playerCount >= Deaths.MAX_PLAYERS then
				players, playerCount = {}, 0
			end
			playerCount = playerCount + 1
			known = {}
			players[guid] = known
		end
		local _, class = UnitClass(unit)
		known.name = name
		known.level = level or known.level
		known.class = text(class) or known.class
	end
end

function Deaths.GuidErrors()
	return guidErrors
end

function Deaths.State()
	return { dead = dead, ghost = ghost }
end

-- Dungeons opens a visit at dn and closes it at dx; every death in between counts, also with de off.
function Deaths.StartVisit()
	if active then
		state().visit = 0
	end
end

function Deaths.VisitDeaths()
	return active and tonumber(state().visit) or 0
end

function Deaths.EndVisit()
	if not active then
		return 0
	end
	local s = state()
	local n = tonumber(s.visit) or 0
	s.visit = nil
	return n
end

-- The low-health flash and close calls. The client flashes the edge in combat with a fullscreen panel at any health,
-- so such a show is no warning.
local function settle()
	local e = episode
	if not e or (LowHealthFrame and LowHealthFrame:IsShown()) then
		return
	end
	if ns.R(InCombatLockdown()) == true then
		return
	end
	episode = nil
	if (lastDeadClock and lastDeadClock >= e.start) or deadNow() then
		return
	end
	local j = e.journal
	if j ~= core() or not j:CanWrite() then
		return
	end
	j:Count("deaths", "closeCalls")
	j:WriteAt(e.at, "cc", math.max(1, floor(e.shown + 0.5)), e.combat)
end

local function settleSoon()
	if episode then
		ns.Coalesce("deaths:closecall", Deaths.SETTLE, settle)
	end
end

local function onFlashShow()
	if deadNow() or (GetUIPanel and GetUIPanel("fullscreen")) then
		return
	end
	local combat = inCombat()
	local now = GetTime()
	if not episode then
		episode = { start = now, at = ns.Here(), journal = core(), shown = 0, combat = false }
	end
	episode.combat = episode.combat or combat
	episode.since = episode.since or now
	count("lowHealth")
	core():Write("lh", combat)
	ns.Emit("LOW_HEALTH", combat)
end

local function onFlashHide()
	if not episode or not episode.since then
		return
	end
	episode.shown = episode.shown + GetTime() - episode.since
	episode.since = nil
	settleSoon()
end

-- Runs at login and, when the frame is missing, once more 3 s later.
local function hook(retry)
	local f = LowHealthFrame
	if type(f) == "table" and type(f.HookScript) == "function" then
		f:HookScript("OnShow", function()
			ns.Safe("deaths:flash", onFlashShow)
		end)
		f:HookScript("OnHide", function()
			ns.Safe("deaths:flash", onFlashHide)
		end)
	elseif retry then
		C_Timer.After(Deaths.HOOK_RETRY, function()
			ns.Safe("deaths:hook", hook, false)
		end)
	end
end

-- Runs after every recorder's login handler: a character dead at login gets its death line once.
local function recover()
	local s = state()
	if not deadNow() then
		s.open = false
		return
	end
	local isGhost = flag(UnitIsGhost, "player")
	if not s.open then
		local inside = ns.InInstance()
		local at = ns.Here()
		if not inside then
			local p = ns.Trail.LastKnownPoint()
			if p then
				at.m, at.x, at.y = p.m, p.x, p.y
			end
		end
		local place, inst = where()
		writeDeath({ at = at, place = place, inst = inst })
	end
	dead = true
	ghost = isGhost
	if ghost and not s.ghost then
		writeGhost()
	end
end

function Deaths:OnLogin()
	local j = core()
	if not j or not j:CanWrite() then
		return
	end
	active = true
	ns.On("PLAYER_DEAD", onDead, "deaths:dead")
	ns.On("PLAYER_ALIVE", onAlive, "deaths:alive")
	ns.On("PLAYER_UNGHOST", onUnghost, "deaths:alive")
	ns.On("CONFIRM_XP_LOSS", mark("xpLoss"), "deaths:mark")
	ns.On("RESURRECT_REQUEST", onOffer, "deaths:mark")
	U.Hook(nil, "AcceptResurrect", mark("accept"), "deaths:accept")
	U.Hook(nil, "RetrieveCorpse", mark("corpse"), "deaths:corpse")
	U.Hook(C_DeathInfo, "UseSelfResurrectOption", mark("soulstone"), "deaths:soulstone")
	ns.On("ENCOUNTER_START", function()
		encounter = true
	end, "deaths:boss")
	ns.On("ENCOUNTER_END", function()
		encounter = false
	end, "deaths:boss")
	ns.On("LOADING_SCREEN_ENABLED", function()
		encounter = false
	end, "deaths:boss")
	ns.On("PLAYER_REGEN_ENABLED", settleSoon, "deaths:closecall")
	ns.On("CVAR_UPDATE", function(_, name)
		if name == ns.LowHealth.CVAR then
			noteFlash()
		end
	end, "deaths:flash")
	ns.On("PLAYER_TARGET_CHANGED", function()
		learn("target")
	end, "deaths:names")
	ns.On("UPDATE_MOUSEOVER_UNIT", function()
		learn("mouseover")
	end, "deaths:names")
	ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
		learn(unit)
	end, "deaths:names")
	ns.Listen("LOGIN", recover, "deaths:login")
	noteFlash()
	hook(true)
end
