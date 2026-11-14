local _, ns = ...

local Travel = ns.Module("Travel")
ns.Travel = Travel

local floor, sqrt = math.floor, math.sqrt
local U = ns.U

Travel.CASTS = 8
Travel.CAST_WINDOW = 15
Travel.WATCH = 0.25
Travel.WATCH_READS = 180
Travel.TRIP_WAIT = 15
Travel.ARRIVE_YARDS = 5
Travel.SETTLE = 2
Travel.FAST_BEFORE = 6
Travel.FAST_FOOT = 12
Travel.FAST_MOUNTED = 18
Travel.FAST_MAX = 60
Travel.MIN_STEP = 0.1
Travel.JUMP_YARDS = 150
Travel.BOAT_WAIT = 30
Travel.REVIVE = 10
Travel.LANDED = 5
Travel.TAXI_RELOAD = 10
Travel.MOUNT_CAST = 5
Travel.LEARN_SAME = 120
-- The world map id that UnitPosition reports in the Deeprun Tram. It is the same in every client language.
Travel.TRAM = 369

local HEARTH = { [8690] = true, [556] = true }
local TELEPORT = {}
for _, id in ipairs({ 3561, 3562, 3563, 3565, 3566, 3567, 10059, 11416, 11417, 11418, 11419, 11420 }) do
	TELEPORT[id] = true
end
-- Riding and the racial riding skills. A racial riding spell has the name of its skill.
local RIDING_SKILLS = { 762, 148, 149, 150, 152, 533, 553, 554, 713 }
local RIDING_SPELLS = { 824, 825, 826, 828, 10861, 10906, 10908, 18995 }

local active = false
-- The player's last casts, oldest first: { spell, clock }.
local casts = {}
-- The trip that waits for its arrival, and the one that waits for a second fast move after a loading screen.
local trip, boat
local watcher
local loading = false
local lastSample, fed = nil, false
local lastFast, lastAlive
local lastOutdoor
local loadName
local flight, node
local offer
local wasMounted = false
local skillPattern, riding

local function core()
	return ns.Store.Core()
end

-- The saved state lives in the core journal's data.state, so a kind that is off still keeps it right.
local function state()
	return core():State("travel")
end

local function count(key, n)
	core():Count("travel", key, n)
end

local text, number, name, flag = U.Text, U.Number, U.Name, U.Flag

local function zoneText()
	return text(GetRealZoneText()) or (GetZoneText and text(GetZoneText()))
end

local function subText()
	return GetSubZoneText and text(GetSubZoneText())
end

-- Straight-line yards between two world positions { x, y, inst }, rounded down; nil across world instances.
function Travel.Yards(a, b)
	if not a or not b or a.inst ~= b.inst then
		return nil
	end
	return floor(sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2))
end

-- An explicit setting wins; else the region, else the client language.
function Travel.DistanceUnit()
	local set = ns.Settings.Get("distanceUnit")
	if set == "yards" or set == "meters" then
		return set
	end
	local region = GetCurrentRegion and number(GetCurrentRegion())
	if region and region >= 1 and region <= 5 then
		return region == 1 and "yards" or "meters"
	end
	local locale = GetLocale and text(GetLocale())
	return (not locale or locale == "enUS") and "yards" or "meters"
end

function Travel.LastOutdoor()
	return lastOutdoor and U.Copy(lastOutdoor) or nil
end

-- The open flight: { from, to, cost, t }, else nil.
function Travel.Flight()
	return flight and { from = flight.from, to = flight.to, cost = flight.cost, t = flight.t } or nil
end

-- Where the player is now: the line place, world yards, map, instance and body state, zone and subzone.
local function read()
	local at = ns.Here()
	return {
		at = at,
		m = at.m,
		clock = GetTime(),
		world = ns.World(),
		inside = ns.InInstance(),
		taxi = flag(UnitOnTaxi, "player"),
		mounted = ns.R(IsMounted()) == true,
		dead = flag(UnitIsDead, "player"),
		ghost = flag(UnitIsGhost, "player"),
		zone = zoneText(),
		sub = subText(),
	}
end

local function tram(p)
	return p.world ~= nil and p.world.inst == Travel.TRAM
end

local function deathWhy(before, after)
	if (after.ghost and not before.ghost) or before.dead then
		return "death"
	elseif before.ghost then
		return "spirit"
	end
end

-- trip = { kind = "summon"|"hearth"|"teleport"|"loading"|"jump", loading, fast, fastAgain, waited, revive, noFeed,
-- otherCast }. Returns the kind to write and the jp reason, "wait" while a fast trip may still prove a boat, or nil.
function Travel.Classify(t, before, after)
	if t.kind == "summon" then
		return "su"
	elseif t.kind == "hearth" then
		return "hs"
	elseif t.kind == "teleport" then
		return "po"
	end
	local jump = t.kind == "jump"
	if (t.revive and (t.loading or jump)) or before.inside or after.inside or before.taxi then
		return nil
	end
	local why = deathWhy(before, after)
	if jump then
		return "jp", why or "other"
	end
	if t.loading and t.fast then
		local changed = before.world and after.world and before.world.inst ~= after.world.inst
		if changed or t.fastAgain then
			return "bt"
		elseif not t.waited then
			return "wait"
		end
	end
	if why then
		return "jp", why
	elseif tram(before) or tram(after) then
		return "jp", "tram"
	elseif t.noFeed or t.otherCast or not before.m or not after.m then
		return "jp", "other"
	end
	return "po"
end

local function write(kind, why, t, before, after)
	local j = core()
	local yards = Travel.Yards(before.world, after.world)
	local from, to = before.m, after.m
	if kind == "su" then
		count("summons")
		j:Count("distance", "portal", yards or 0)
		j:WriteAt(after.at, "su", t.who, t.area, from, to, yards)
	elseif kind == "hs" then
		count("hearths")
		j:Count("distance", "hearth", yards or 0)
		j:WriteAt(after.at, "hs", from, to, text(GetBindLocation()) or after.sub or after.zone, yards)
	elseif kind == "po" then
		count("portals")
		j:Count("distance", "portal", yards or 0)
		j:WriteAt(after.at, "po", after.zone, from, to, t.spell, yards)
	elseif kind == "jp" then
		count("teleports")
		j:WriteAt(after.at, "jp", from, to, yards, why)
	else
		count("boats")
		j:WriteAt(after.at, "bt", from, to, before.sub or before.zone, after.sub or after.zone)
	end
end

local function finish(t, after)
	t.revive = lastAlive ~= nil and lastAlive >= t.start - Travel.REVIVE
	local kind, why = Travel.Classify(t, t.from, after)
	if kind == "wait" then
		t.after = after
		boat = t
		C_Timer.After(Travel.BOAT_WAIT, function()
			ns.Protect("travel:boat", function()
				if boat == t then
					boat, t.waited = nil, true
					finish(t, after)
				end
			end)
		end)
	elseif kind then
		write(kind, why, t, t.from, after)
	end
end

local function stopWatch()
	if watcher then
		watcher:Cancel()
		watcher = nil
	end
end

local function poll()
	local t = trip
	if GetTime() - t.start > Travel.TRIP_WAIT then
		trip = nil
		stopWatch()
		return
	end
	local a, b = t.from.world, ns.World()
	if a and b and (a.inst ~= b.inst or Travel.Yards(a, b) >= Travel.ARRIVE_YARDS) then
		trip = nil
		stopWatch()
		-- The trip owns this move, so the next sample measures no jump across it.
		lastSample = nil
		finish(t, read())
	end
end

local function startTrip(t)
	t.start, t.from = GetTime(), read()
	trip = t
	stopWatch()
	watcher = C_Timer.NewTicker(Travel.WATCH, function()
		ns.Protect("travel:watch", poll)
	end, Travel.WATCH_READS)
end

local function lastCast(within)
	local c = casts[#casts]
	return c and GetTime() - c.clock <= within and c or nil
end

local function onCast(spell)
	spell = number(spell)
	if not spell then
		return
	end
	casts[#casts + 1] = { spell = spell, clock = GetTime() }
	if #casts > Travel.CASTS then
		table.remove(casts, 1)
	end
	if HEARTH[spell] then
		startTrip({ kind = "hearth", spell = spell })
	elseif TELEPORT[spell] then
		startTrip({ kind = "teleport", spell = spell })
	end
end

-- Zones ------------------------------------------------------------------------

local function writeZone(zone)
	local s = state()
	if zone and zone ~= s.zone then
		s.zone, s.sub = zone, nil
		core():Write("zo", zone)
	end
end

local function checkSub()
	if ns.InInstance() then
		return
	end
	local sub, s = subText(), state()
	if sub and sub ~= s.sub then
		s.sub = sub
		core():Write("sz", sub)
	end
end

local function mapName()
	local m = ns.Position()
	local info = m and C_Map.GetMapInfo(m)
	return type(info) == "table" and text(info.name) or nil
end

-- At a login or a loading screen the zone text can name an inn or a building, so only a zone that the map's name
-- confirms replaces it.
local function onEnterWorld()
	local zone = zoneText()
	writeZone(zone)
	loadName = zone
	checkSub()
end

local function onNewArea()
	loadName = nil
	writeZone(zoneText())
	checkSub()
end

local function onZone()
	if loadName and not ns.InInstance() then
		local map, zone = mapName(), zoneText()
		if map == loadName then
			loadName = nil
		elseif zone and zone ~= loadName and zone == map then
			loadName = nil
			writeZone(zone)
		end
	end
	checkSub()
end

-- Loading screens --------------------------------------------------------------

local function onLoadingStart()
	local now = GetTime()
	local at = ns.Here()
	if not ns.InInstance() and not at.x and lastSample then
		at.m, at.x, at.y = lastSample.at.m, lastSample.at.x, lastSample.at.y
	end
	local cast = lastCast(Travel.CAST_WINDOW)
	loading = true
	core():WriteAt(at, "ld", cast and cast.spell, flag(UnitOnTaxi, "player") or nil)
	stopWatch()
	if trip and now - trip.start <= Travel.CAST_WINDOW then
		trip.loading = true
	else
		local from = read()
		if not from.m and lastSample then
			from = lastSample
		end
		trip = {
			kind = "loading",
			start = now,
			from = from,
			loading = true,
			fast = lastFast ~= nil and now - lastFast <= Travel.FAST_BEFORE,
			noFeed = not fed,
			otherCast = cast ~= nil,
		}
	end
	-- No jump is measured across the loading screen.
	lastSample = nil
end

local function onLoadingEnd()
	if loading then
		loading = false
		core():Write("le")
	end
	local t = trip
	if not t then
		return
	end
	t.ended = true
	C_Timer.After(Travel.SETTLE, function()
		ns.Protect("travel:arrive", function()
			-- A second loading screen within the settle time keeps the trip; its own end schedules the arrival.
			if trip == t and not loading then
				trip = nil
				finish(t, read())
			end
		end)
	end)
end

-- Flights ----------------------------------------------------------------------

local function currentNode()
	if NumTaxiNodes then
		for i = 1, number(NumTaxiNodes()) or 0 do
			if ns.R(TaxiNodeGetType(i)) == "CURRENT" then
				return text(TaxiNodeName(i))
			end
		end
	end
	local api, m = C_TaxiMap, ns.Position()
	local current = Enum.FlightPathState and Enum.FlightPathState.Current
	if type(api) ~= "table" or not api.GetAllTaxiNodes or not m or current == nil then
		return nil
	end
	for _, n in ipairs(ns.R(api.GetAllTaxiNodes(m)) or {}) do
		if type(n) == "table" and ns.R(n.state) == current then
			return text(n.name)
		end
	end
end

-- The flight map also calls TakeTaxiNode for a click on the current node, which takes no flight.
local function takeTaxi(slot)
	if ns.R(TaxiNodeGetType(slot)) ~= "REACHABLE" then
		return
	end
	local to = text(TaxiNodeName(slot)) or "?"
	local cost = number(TaxiNodeCost(slot))
	flight = { from = node or "?", to = to, cost = cost, t = time(), clock = GetTime() }
	count("flights")
	core():Write("tx", flight.from, to, cost)
end

local function checkLanded()
	if flight and not flag(UnitOnTaxi, "player") and GetTime() - flight.clock >= Travel.LANDED then
		local to = flight.to
		flight = nil
		core():Write("tl", to)
	end
end

-- A reload in the air keeps no flight, so one with unknown nodes stands in for it.
local function checkTaxi()
	if not flight and flag(UnitOnTaxi, "player") then
		flight = { t = time() - Travel.TAXI_RELOAD, clock = GetTime() - Travel.TAXI_RELOAD }
	end
end

-- Positions --------------------------------------------------------------------

local function fast(prev, now)
	local yards = Travel.Yards(prev.world, now.world)
	if not yards then
		return false, nil, 0
	end
	local speed = yards / math.max(now.clock - prev.clock, Travel.MIN_STEP)
	local limit = now.mounted and Travel.FAST_MOUNTED or Travel.FAST_FOOT
	-- The first sample after a landing still measures the flight.
	local isFast = speed > limit
		and speed < Travel.FAST_MAX
		and not prev.taxi
		and not now.taxi
		and not now.dead
		and not now.ghost
	return isFast, speed, yards
end

-- The trail keeps no point while the player stays within a few yards of the last one, so a move after a pause, like
-- a spirit release, happened after the feed before this one. A stretch with no readable position keeps no feed.
local function jumped(prev, now, yards)
	if yards < Travel.JUMP_YARDS or now.taxi then
		return false
	end
	local seconds = now.clock - math.max(prev.clock, ns.Trail.FedBefore() or prev.clock)
	return yards / math.max(seconds, Travel.MIN_STEP) > Travel.FAST_MAX
end

local function onSample()
	local now = read()
	fed = true
	lastOutdoor = { m = now.at.m, x = now.at.x, y = now.at.y, t = now.at.t }
	checkLanded()
	local prev = lastSample
	lastSample = now
	if not prev then
		return
	end
	local isFast, speed, yards = fast(prev, now)
	if isFast then
		lastFast = now.clock
		if boat then
			local t = boat
			boat, t.fastAgain = nil, true
			finish(t, t.after)
		elseif trip and trip.ended then
			trip.fastAgain = true
		end
	elseif not trip and speed and jumped(prev, now, yards) then
		finish({ kind = "jump", start = prev.clock, from = prev }, now)
	end
end

-- Summons ----------------------------------------------------------------------

-- The summoner and the area read nil once the player accepts, so the offer keeps them.
local function onSummon()
	local api = C_SummonInfo
	offer = { who = name(api.GetSummonConfirmSummoner()), area = name(api.GetSummonConfirmAreaName()) }
	count("offers")
	core():Write("so", offer.who, offer.area)
end

local function onAcceptSummon()
	if offer and not offer.cancelled then
		startTrip({ kind = "summon", who = offer.who, area = offer.area })
	end
	offer = nil
end

-- Mounts -----------------------------------------------------------------------

local function mountApi()
	return type(C_MountJournal) == "table" and C_MountJournal or {}
end

-- The spell and name of the mount the player rode up on: a recent cast of a mount, the active mount, else the cast.
local function findMount()
	local api, now = mountApi(), GetTime()
	for i = #casts, 1, -1 do
		local c = casts[i]
		if now - c.clock > Travel.MOUNT_CAST then
			break
		end
		local id = api.GetMountFromSpell and api.GetMountInfoByID and number(api.GetMountFromSpell(c.spell))
		if id then
			local mountName, spell = ns.RN(api.GetMountInfoByID(id))
			return number(spell) or c.spell, name(mountName)
		end
	end
	for _, id in ipairs(api.GetMountIDs and api.GetMountInfoByID and ns.R(api.GetMountIDs()) or {}) do
		local mountName, spell, _, isActive = ns.RN(api.GetMountInfoByID(id))
		if isActive == true then
			return number(spell), name(mountName)
		end
	end
	local c = lastCast(Travel.MOUNT_CAST)
	if c then
		return c.spell, name(U.SpellName(c.spell))
	end
end

local function onMountDisplay()
	-- A player who stands still after landing feeds no sample, so the open flight would hide this mount-up.
	checkLanded()
	local mounted = ns.R(IsMounted()) == true
	local before = wasMounted
	wasMounted = mounted
	if not mounted or before or flight or flag(UnitOnTaxi, "player") then
		return
	end
	count("mountUps")
	local spell, mountName = findMount()
	local key = spell or mountName
	if key and core():Count("travel", "mount:" .. key) == 0 then
		core():Write("mo", true, spell, mountName)
	end
end

local function learned(what, spell)
	local seen = U.TableAt(state(), "learned")
	local now = ns.Journal.Now()
	for k, t in pairs(seen) do
		if type(t) ~= "number" or now - t > Travel.LEARN_SAME then
			seen[k] = nil
		end
	end
	if not seen[what] then
		seen[what] = now
		core():Write("ml", what, spell)
	end
end

local function onNewMount(_, id)
	local info = mountApi().GetMountInfoByID
	if not info then
		return
	end
	local mountName, spell = ns.RN(info(id))
	learned(name(mountName) or "?", number(spell))
end

-- Localized riding names, each to its spell or false. A login too early to read any name tries again next time.
local function ridingNames()
	if riding then
		return riding
	end
	local names, any = {}, false
	local info = type(C_SkillInfo) == "table" and C_SkillInfo.GetSkillLineInfoByID
	for _, id in ipairs(info and RIDING_SKILLS or {}) do
		local attrs = ns.R(info(id))
		local skill = type(attrs) == "table" and text(attrs.name)
		if skill then
			names[skill], any = false, true
		end
	end
	for _, id in ipairs(RIDING_SPELLS) do
		local spell = text(U.SpellName(id))
		if spell then
			names[spell], any = id, true
		end
	end
	riding = any and names or nil
	return names
end

local function onSkill(_, msg)
	msg = text(msg)
	local skill = msg and skillPattern and msg:match(skillPattern)
	local spell = skill and ridingNames()[skill]
	if spell ~= nil then
		learned(skill, spell or nil)
	end
end

function Travel:OnLogin()
	local j = core()
	if not j or not j:CanWrite() then
		return
	end
	active = true
	skillPattern = ns.Progress.Compile(ERR_SKILL_GAINED_S)
	ns.On("ZONE_CHANGED_NEW_AREA", onNewArea, "travel:zone")
	ns.On("ZONE_CHANGED", onZone, "travel:zone")
	ns.On("ZONE_CHANGED_INDOORS", onZone, "travel:zone")
	ns.On("LOADING_SCREEN_ENABLED", onLoadingStart, "travel:loading")
	ns.On("LOADING_SCREEN_DISABLED", onLoadingEnd, "travel:loading")
	ns.On("CONFIRM_SUMMON", onSummon, "travel:summon")
	ns.On("CANCEL_SUMMON", function()
		if offer then
			offer.cancelled = true
		end
	end, "travel:summon")
	ns.On("TAXIMAP_OPENED", function()
		node = currentNode()
	end, "travel:taxi")
	ns.On("PLAYER_CONTROL_GAINED", checkLanded, "travel:taxi")
	ns.On("PLAYER_MOUNT_DISPLAY_CHANGED", onMountDisplay, "travel:mount")
	ns.On("NEW_MOUNT_ADDED", onNewMount, "travel:mount")
	ns.On("CHAT_MSG_SKILL", onSkill, "travel:riding")
	ns.On("CHAT_MSG_SYSTEM", onSkill, "travel:riding")
	ns.Listen("TRAIL_LIVE", onSample, "travel:sample")
	ns.Listen("ALIVE", function()
		lastAlive = GetTime()
	end, "travel:alive")
	U.Hook(nil, "TakeTaxiNode", takeTaxi, "travel:taxi")
	U.Hook(C_SummonInfo, "ConfirmSummon", onAcceptSummon, "travel:summon")
	ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spell)
		onCast(spell)
	end, "travel:cast")
	wasMounted = ns.R(IsMounted()) == true
end

function Travel:OnEnterWorld()
	if active then
		onEnterWorld()
		checkTaxi()
	end
end
