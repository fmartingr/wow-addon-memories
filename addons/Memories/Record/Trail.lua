local _, ns = ...

local Trail = ns.Module("Trail")
ns.Trail = Trail

local floor, sqrt = math.floor, math.sqrt
local U = ns.U

Trail.TELEPORT = 100
Trail.BOAT = 15
Trail.MOVED = 0.5
Trail.THIN_YARDS = 3
Trail.THIN_UNITS = 4
Trail.PAUSE = 60
Trail.MAX_POINTS = 2000
Trail.COPY_EVERY = 60

local RATES = {}
for _, r in ipairs(ns.Settings.RATES) do
	RATES[r] = true
end

local active = false
local ticker, rate
-- The rate before a change: the first tick at a shorter rate measures time from the last tick at the longer one.
local stallRate
local paused = false
local lastTick
-- The world position of the last tick: { x, y, inst } in yards.
local lastWorld
local broken = false
-- The open stretch: a TrailCodec chunk, the clock of its first point and of the last feed, and the last kept point.
local open
local copyAt
local lastPoint
-- GetTime() of the last feed and of the one before it.
local fedLast, fedBefore

local function round(v)
	return floor(v + 0.5)
end

local function trail()
	local t = U.TableAt(MemoriesCharDB, "trail")
	t.v = t.v or 1
	U.TableAt(t, "chunks")
	return t
end

local function state()
	local inside = ns.InInstance()
	return {
		taxi = UnitOnTaxi("player"),
		flying = IsFlying(),
		mounted = IsMounted(),
		ghost = UnitIsGhost("player"),
		dead = UnitIsDead("player"),
		swimming = IsSwimming(),
		combat = InCombatLockdown(),
		instance = inside,
	}
end

-- Secret flags count as off.
local function readState()
	local s = state()
	for k, v in pairs(s) do
		s[k] = ns.R(v) == true
	end
	return s
end

function Trail.Flags()
	return ns.TrailCodec.Flags(readState())
end

function Trail.Open()
	if open and open.chunk.n > 0 then
		return open.chunk:Record()
	end
end

-- GetTime() of the feed before the latest one, else nil.
function Trail.FedBefore()
	return fedBefore
end

function Trail.LastPoint()
	return lastPoint and U.Copy(lastPoint) or nil
end

-- The last point of this session, else the last point of the saved trail: { m, x, y, t }, or nil.
function Trail.LastKnownPoint()
	if lastPoint then
		return Trail.LastPoint()
	end
	local chunks = trail().chunks
	for i = #chunks, 1, -1 do
		local rec = chunks[i]
		local points = type(rec) == "table" and type(rec.m) == "number" and ns.TrailCodec.Decode(rec)
		local p = points and points[#points]
		if p then
			return { m = rec.m, x = p.x, y = p.y, t = p.t }
		end
	end
end

local function writeCopy()
	trail().open = open and open.chunk.n > 0 and open.chunk:Record(true) or nil
	copyAt = GetTime()
end

function Trail.Close()
	if open and open.chunk.n > 0 then
		local chunks = trail().chunks
		chunks[#chunks + 1] = open.chunk:Record()
	end
	open = nil
	copyAt = nil
	trail().open = nil
end

local function sessionStart()
	local current = ns.Sessions.Current()
	return current and current.start or nil
end

local function far(a, b)
	if a.wx and b.wx then
		return sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) >= Trail.THIN_YARDS
	end
	return sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) >= Trail.THIN_UNITS
end

-- p = { m, x, y, wx, wy, flags }; wx, wy are world yards or nil. teleport starts a new chunk.
function Trail.Feed(p, teleport)
	local now = GetTime()
	fedBefore, fedLast = fedLast, now
	if
		not open
		or teleport
		or open.chunk.m ~= p.m
		or now - open.fedAt > Trail.PAUSE
		or open.chunk.n >= Trail.MAX_POINTS
	then
		Trail.Close()
		open = { chunk = ns.TrailCodec.New(sessionStart(), time(), p.m), clock = now }
	end
	open.fedAt = now
	lastPoint = { m = p.m, x = p.x, y = p.y, t = time() }
	local kept = open.kept
	if kept and kept.flags == p.flags and not far(p, kept) then
		return false
	end
	open.kept = p
	open.chunk:Add(now - open.clock, p.x, p.y, p.flags)
	if not copyAt or now - copyAt >= Trail.COPY_EVERY then
		writeCopy()
	end
	ns.Emit("TRAIL_LIVE", p.m, p.x, p.y)
	return true
end

local function count(module, key, n, level)
	local j = ns.Store.Core()
	j:Count(module, key, n)
	if level then
		j:Count(module, key .. ":" .. level, n)
	end
end

local function activityOf(s, moving)
	if ns.Sessions.Away() then
		return "afk"
	elseif s.ghost or s.dead then
		return "dead"
	elseif s.instance then
		return "dungeon"
	elseif s.combat then
		return "combat"
	elseif moving or s.taxi then
		return "travel"
	end
	return "town"
end

local function modeOf(s, speed)
	if s.taxi or s.flying then
		return "fly"
	elseif s.mounted then
		return "ride"
	elseif s.ghost then
		return "ghost"
	elseif s.swimming then
		return "swim"
	elseif speed > Trail.BOAT then
		return "boat"
	end
	return "foot"
end

function Trail.Tick()
	if paused then
		return
	end
	local now = GetTime()
	local elapsed = lastTick and now - lastTick or 0
	local sec = round(elapsed)
	lastTick = now
	local here = ns.World()
	local dist = 0
	if here and lastWorld and here.inst == lastWorld.inst and elapsed > 0 then
		dist = sqrt((here.x - lastWorld.x) ^ 2 + (here.y - lastWorld.y) ^ 2)
	end
	lastWorld = here
	-- A stalled tick counts nothing, but a teleport during the stall still starts a new chunk.
	local speed = elapsed > 0 and dist / elapsed or 0
	if speed > Trail.TELEPORT then
		dist, speed = 0, 0
		broken = true
	end
	local limit = math.max(rate, stallRate or rate) * 3 + 1
	stallRate = nil
	if sec > limit then
		sec, dist, speed = 0, 0, 0
	end
	local s = readState()
	local moving = ns.R(IsPlayerMoving()) == true or dist > Trail.MOVED
	if moving or s.combat or s.taxi then
		ns.Sessions.MarkActive()
	end
	if sec > 0 then
		local level = ns.Progress.Level()
		count("move", "sec", sec)
		count("activity", activityOf(s, moving), sec, level)
		if moving then
			local mode = modeOf(s, speed)
			count("move", "moving", sec)
			count("move", mode, sec, level)
			local yards = round(dist)
			if yards > 0 then
				count("distance", mode, yards, level)
			end
		end
	end
	local m, x, y = ns.OutdoorPosition(s.instance)
	if m and x then
		local p = { m = m, x = x, y = y, flags = ns.TrailCodec.Flags(s) }
		if here then
			p.wx, p.wy = here.x, here.y
		end
		Trail.Feed(p, broken)
		broken = false
	end
	ns.Sessions.CheckAway()
end

local function rateSetting()
	local r = ns.Settings.Get("recordRate")
	return RATES[r] and r or 2
end

local function restart()
	if ticker then
		ticker:Cancel()
	end
	stallRate = rate
	rate = rateSetting()
	ticker = C_Timer.NewTicker(rate, function()
		ns.Protect("trail:tick", Trail.Tick)
	end)
end

-- A copy in the saved file means the logout step did not run, so its stretch is filed as it was. A restored copy of the
-- running stretch is dropped: the running stretch files all of its points when it closes.
local function fileCopy()
	local t = trail()
	local copy = t.open
	t.open = nil
	local running = open and type(copy) == "table" and copy.s == open.chunk.s and copy.t == open.chunk.t
	if not running and type(copy) == "table" and type(copy.n) == "number" and copy.n > 0 then
		copy.o = 1
		t.chunks[#t.chunks + 1] = copy
	end
end

-- The jump key on a flight path calls JumpOrAscendStart too, but the player does not jump.
local function jump()
	if ns.R(UnitOnTaxi("player")) == true then
		return
	end
	ns.Sessions.MarkActive()
	if ns.R(IsSwimming()) == true or ns.R(IsFlying()) == true then
		count("travel", "ascend", 1)
	else
		count("travel", "jumps", 1, ns.Progress.Level())
	end
end

function Trail:OnLogin()
	local j = ns.Store.Core()
	if not j or not j:CanWrite() then
		return
	end
	active = true
	fileCopy()
	ns.On("LOADING_SCREEN_ENABLED", function()
		Trail.Close()
		lastWorld = nil
		paused = true
	end, "trail:loading")
	ns.On("LOADING_SCREEN_DISABLED", function()
		paused = false
		lastTick = GetTime()
	end, "trail:loading")
	ns.On("PLAYER_LOGOUT", Trail.Close, "trail:logout")
	ns.Settings.OnChange("recordRate", restart)
	ns.Listen("RESTORED", function(_, addon)
		if addon == ns.name then
			fileCopy()
			if open and open.chunk.n > 0 then
				writeCopy()
			end
		end
	end, "trail:restored")
	U.Hook(nil, "JumpOrAscendStart", jump, "trail:jump")
end

-- The ticker starts with the world, after Sessions opens the session that every chunk names.
function Trail:OnEnterWorld()
	if active then
		lastWorld = nil
		lastTick = GetTime()
		if not ticker then
			restart()
		end
	end
end
