local _, ns = ...

local Dungeons = ns.Module("Dungeons")
ns.Dungeons = Dungeons

local floor = math.floor
local U = ns.U

Dungeons.CHECK_DELAY = 1
Dungeons.SHOT_DELAY = 1
Dungeons.WORLD_BOSS_SAME = 600
Dungeons.WORLD_BOSS_KEEP = 6

local WORLD_BOSSES = {
	Azuregos = true,
	["Lord Kazzak"] = true,
	Ysondre = true,
	Lethon = true,
	Emeriss = true,
	Taerar = true,
}

local active = false
-- True once this load saw the player inside the open visit's instance.
local seenInside = false
-- Pull times by encounter id, GetTime() values.
local pulls = {}

local function core()
	return ns.Store.Core()
end

-- The saved state lives in the core journal's data.state, so a kind that is off still keeps it right.
local function state()
	return core():State("dungeons")
end

local text, number, flag = U.Text, U.Number, U.Flag

-- A raid count has its own key: "visits" becomes "raidVisits".
local function key(itype, k)
	return itype == "raid" and "raid" .. k:sub(1, 1):upper() .. k:sub(2) or k
end

local function count(k, n)
	core():Count("dungeons", k, n)
end

local function openVisit()
	local v = state().visit
	return type(v) == "table" and v or nil
end

-- The open visit { name, instance, itype, t }, else nil.
function Dungeons.Visit()
	return active and U.Copy(openVisit()) or nil
end

-- "party" or "raid" with the instance's name, difficulty, size and id; nil anywhere else.
local function partyOrRaid()
	local inside, itype = ns.RN(IsInInstance())
	if inside ~= true or (itype ~= "party" and itype ~= "raid") then
		return nil
	end
	local name, _, difficulty, _, size, _, _, id = ns.RN(GetInstanceInfo())
	return {
		name = text(name) or "?",
		itype = itype,
		difficulty = number(difficulty),
		size = number(size),
		id = number(id),
	}
end

-- A visit that this load never saw from inside ended at the logout that left it open.
local function close(visit)
	local now = ns.Journal.Now()
	local leave = not seenInside and tonumber(visit.out) or now
	local seconds = math.max(0, leave - (tonumber(visit.t) or leave))
	local deaths = ns.Deaths.EndVisit()
	state().visit = nil
	count(key(visit.itype, "seconds"), seconds)
	local at = ns.Here()
	at.t = leave
	core():WriteAt(at, "dx", visit.name, visit.instance, seconds, deaths)
end

-- The entrance is the last outdoor point before the loading screen.
local function open(inst)
	local at = ns.Here()
	local p = ns.Trail.LastPoint() or ns.Travel.LastOutdoor()
	if p then
		at.m, at.x, at.y = p.m, p.x, p.y
	end
	state().visit = { name = inst.name, instance = inst.id, itype = inst.itype, t = at.t }
	seenInside = true
	ns.Deaths.StartVisit()
	count(key(inst.itype, "visits"))
	core():WriteAt(at, "dn", inst.name, inst.id, inst.itype, inst.difficulty, inst.size)
end

local function check()
	local inst = partyOrRaid()
	local visit = openVisit()
	if visit and inst and inst.id == visit.instance then
		-- An older logout no longer ends this visit: a crash after this point keeps no stale end.
		seenInside, visit.out = true, nil
		return
	end
	-- A release inside puts the ghost at a graveyard outside; the corpse run back is the same visit. The revive checks
	-- again.
	if visit and not inst and flag(UnitIsDeadOrGhost, "player") then
		return
	end
	if visit then
		close(visit)
	end
	if inst then
		open(inst)
	end
end

local function checkSoon()
	ns.Coalesce("dungeons:check", Dungeons.CHECK_DELAY, check)
end

local function worldBoss(name, npc)
	local list = U.TableAt(state(), "worldBosses")
	local now = ns.Journal.Now()
	for _, e in ipairs(list) do
		if type(e) == "table" and e.name == name and now - (tonumber(e.t) or 0) < Dungeons.WORLD_BOSS_SAME then
			return
		end
	end
	list[#list + 1] = { name = name, t = now }
	while #list > Dungeons.WORLD_BOSS_KEEP do
		table.remove(list, 1)
	end
	count("worldBosses")
	core():Write("wb", name, npc)
end

local function longest(k, seconds)
	local all = core():Counts("dungeons")
	if type(all[k]) ~= "number" or seconds > all[k] then
		all[k] = seconds
	end
end

local function shotLater(boss)
	local j = core()
	C_Timer.After(Dungeons.SHOT_DELAY, function()
		ns.Safe("dungeons:shot", function()
			if core() == j then
				ns.Screenshots.Take("last boss " .. boss, "shots.lastBoss")
			end
		end)
	end)
end

local function onEncounterStart(_, id)
	id = number(id)
	if id then
		pulls[id] = GetTime()
	end
end

local function onEncounterEnd(_, id, encounterName, _, _, success)
	id, success = ns.RN(id, success)
	id = type(id) == "number" and id or nil
	local boss = U.Name(encounterName) or "?"
	local won = success == 1 or success == true
	local pull = id and pulls[id]
	if id then
		pulls[id] = nil
	end
	if not ns.InInstance() then
		if won then
			worldBoss(boss, nil)
		end
		return
	end
	local inst = partyOrRaid()
	if not inst then
		return
	end
	local seconds = pull and floor(GetTime() - pull) or nil
	local last = won and ns.Bosses.Place(boss) ~= nil
	if won then
		count(key(inst.itype, "bosses"))
		count("kills:" .. boss)
		if last then
			count(key(inst.itype, "clears"))
		end
		if seconds then
			longest(key(inst.itype, "longest") .. ":" .. boss, seconds)
		end
	else
		count(key(inst.itype, "wipes"))
	end
	core():Write("bo", boss, id, won, last or nil, inst.name, seconds)
	if last then
		shotLater(boss)
	end
end

local function onFightEnd()
	if ns.InInstance() or not flag(UnitExists, "target") then
		return
	end
	if not flag(UnitIsDead, "target") or flag(UnitIsPlayer, "target") then
		return
	end
	local name = U.Name(UnitName("target"))
	if ns.R(UnitClassification("target")) ~= "worldboss" and not WORLD_BOSSES[name] then
		return
	end
	local guid = text(UnitGUID("target"))
	worldBoss(name or "?", guid and U.NpcID(guid))
end

function Dungeons:OnLogin()
	local j = core()
	if not j or not j:CanWrite() then
		return
	end
	active = true
	ns.On("PLAYER_ENTERING_WORLD", checkSoon, "dungeons:check")
	ns.On("ZONE_CHANGED_NEW_AREA", checkSoon, "dungeons:check")
	ns.Listen("ALIVE", checkSoon, "dungeons:check")
	ns.On("ENCOUNTER_START", onEncounterStart, "dungeons:boss")
	ns.On("ENCOUNTER_END", onEncounterEnd, "dungeons:boss")
	ns.On("PLAYER_REGEN_ENABLED", onFightEnd, "dungeons:worldboss")
	ns.On("PLAYER_LOGOUT", function()
		local visit = openVisit()
		if visit then
			visit.out = ns.Journal.Now()
		end
	end, "dungeons:logout")
end
