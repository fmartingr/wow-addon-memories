local _, ns = ...

-- What the Journey overlay draws for one map, read from the saved trail and the journal. Nothing here writes saved
-- data or touches a frame. Map coordinates run 0..1 with y down, as the game's C_Map does.
local MapData = {}
ns.MapData = MapData

-- Points closer than this, in map units, are one point. About one pixel on a map of 500 pixels.
MapData.STEP = 0.002

local SCALE = 10000

-- The ways of travel, from the flags of a trail point. The first flag that matches names the way.
local WAYS = { { "dead", "[gd]" }, { "taxi", "t" }, { "swim", "w" }, { "mounted", "[mf]" } }

function MapData.Way(flags)
	for _, way in ipairs(WAYS) do
		if flags:find(way[2]) then
			return way[1]
		end
	end
	return "foot"
end

local function project(zoneMap, x, y, targetMap)
	local continent, world = C_Map.GetWorldPosFromMapPos(zoneMap, CreateVector2D(x, y))
	if not continent or not world then
		return nil
	end
	local _, pos = C_Map.GetMapPosFromWorldPos(continent, world, targetMap)
	if not pos then
		return nil
	end
	local px, py = pos:GetXY()
	if type(px) == "number" and type(py) == "number" then
		return px, py
	end
end

-- The position of x, y of zoneMap on targetMap, inside or outside it, or nil when a game call is missing or fails.
local function projectAny(zoneMap, x, y, targetMap)
	local ok, px, py = pcall(project, zoneMap, x, y, targetMap)
	if ok then
		return px, py
	end
end

local function inside(x, y)
	return x >= 0 and x <= 1 and y >= 0 and y <= 1
end

-- The position on targetMap of the point x, y (0..1) of zoneMap, through the world position. It returns nil when a game
-- call is missing, fails, or gives no position on targetMap.
function MapData.Project(zoneMap, x, y, targetMap)
	local px, py = projectAny(zoneMap, x, y, targetMap)
	if px and inside(px, py) then
		return px, py
	end
end

-- True when zone sits under mapID in the tree of maps.
local function below(zone, mapID)
	local m = zone
	for _ = 1, 8 do
		local info = C_Map.GetMapInfo(m)
		m = type(info) == "table" and ns.R(info.parentMapID)
		if m == mapID then
			return true
		end
		if type(m) ~= "number" then
			return false
		end
	end
	return false
end

-- A zone map and the target map are both rectangles of the world, so a zone point lands on the target through a scale
-- and an offset. Two projected corners give both, and each point then costs no game call.
local function transform(zone, mapID)
	local x0, y0 = projectAny(zone, 0, 0, mapID)
	local x1, y1 = projectAny(zone, 1, 1, mapID)
	if x0 and x1 then
		return { x0, y0, x1 - x0, y1 - y0 }
	end
	return false
end

-- Where the points of each zone land on the target map, a cosmic, world or continent map drawing the zones under it.
-- A zone with no projection is skipped; one under the target map goes in skipped, as the map should show it.
local function newTarget(mapID)
	local target = { map = mapID, higher = ns.IsSkippedMap(mapID), zones = {}, skipped = {} }
	function target:Has(zone)
		if zone == self.map then
			return true
		end
		if not self.higher then
			return false
		end
		if self.zones[zone] == nil then
			self.zones[zone] = transform(zone, self.map)
			if not self.zones[zone] and below(zone, self.map) then
				self.skipped[zone] = true
			end
		end
		return self.zones[zone] ~= false
	end
	function target:Place(zone, x, y)
		if zone == self.map then
			return x, y
		end
		local z = self:Has(zone) and self.zones[zone]
		if not z then
			return nil
		end
		local px, py = z[1] + x * z[3], z[2] + y * z[4]
		if inside(px, py) then
			return px, py
		end
	end
	return target
end

-- The saved chunks, then the open stretch. The saved copy of the open stretch is filed at login only while Trail
-- records.
local function chunks()
	local trail = type(MemoriesCharDB) == "table" and MemoriesCharDB.trail
	local list = type(trail) == "table" and type(trail.chunks) == "table" and trail.chunks or {}
	local open = ns.Trail.Open() or (type(trail) == "table" and type(trail.open) == "table" and trail.open) or nil
	local i, n = 0, #list
	return function()
		i = i + 1
		if i <= n then
			return list[i] or false
		end
		local rec = open
		open = nil
		return rec
	end
end

local function inSession(session, t)
	return not session or (t >= session.start and (session.stop == nil or t <= session.stop))
end

-- A trip that skips the trail leaves two points less than JUMP_GAP seconds apart and at least JUMP_MIN map units apart.
MapData.JUMP_GAP = 120
MapData.JUMP_MIN = 0.03

-- The segments of the trail on mapID: a list of { way, pts = { x1, y1, x2, y2, ... }, ts = { t1, t2, ... } }, with one
-- time for each point. filter.session limits the time.
-- The second result is the set of zones, by id, that have no position on mapID. Trail starts a new chunk at a pause, a
-- teleport, a map change and a new session (its start is the chunk's s), so each of these breaks the line. A full chunk
-- is cut with no pause, so the line goes on into the next one. A long gap inside a chunk is the player standing still,
-- as Trail drops the points of a player who does not move.
-- The third result lists the jumps: { x1, y1, t0, x2, y2, t1 } from the last point of a chunk to the first point of the
-- next one, for a hearthstone, a portal, a summon, a boat or a flight with no recorded points.
function MapData.Segments(mapID, filter)
	filter = filter or {}
	local session = filter.session
	local step2 = (filter.step or MapData.STEP) ^ 2
	local target = newTarget(mapID)
	local out, jumps = {}, {}
	local seg, lx, ly, lt, goesOn
	local px, py, pt
	local function close()
		if seg and #seg.pts >= 4 then
			out[#out + 1] = seg
		end
		seg = nil
	end
	for rec in chunks() do
		local zone = type(rec) == "table" and rec.m
		-- A chunk with a session start belongs to that session whole; only an older chunk is cut by the time.
		local timed = session and not (type(rec) == "table" and type(rec.s) == "number")
		local points = type(zone) == "number"
				and not (session and not timed and rec.s ~= session.start)
				and not (timed and type(rec.t) == "number" and rec.t > (session.stop or math.huge))
				and target:Has(zone)
				and ns.TrailCodec.Decode(rec)
			or {}
		local first = points[1]
		local continued = goesOn
			and first
			and zone == goesOn.m
			and rec.s == goesOn.s
			and first.t - goesOn.t <= ns.Trail.PAUSE
		if not continued then
			close()
		end
		goesOn = nil
		local fresh = not continued
		for _, p in ipairs(points) do
			local fx, fy
			if
				not p.flags:find("i", 1, true)
				and p.x <= SCALE
				and p.y <= SCALE
				and (not timed or inSession(session, p.t))
			then
				fx, fy = target:Place(zone, p.x / SCALE, p.y / SCALE)
			end
			if fx then
				local gap = pt and p.t - pt
				if
					fresh
					and gap
					and gap > 0
					and gap <= MapData.JUMP_GAP
					and (fx - px) ^ 2 + (fy - py) ^ 2 >= MapData.JUMP_MIN ^ 2
				then
					jumps[#jumps + 1] = { x1 = px, y1 = py, t0 = pt, x2 = fx, y2 = fy, t1 = p.t }
				end
				fresh = false
				px, py, pt = fx, fy, p.t
			end
			local way = fx and MapData.Way(p.flags)
			if not fx then
				close()
			-- A point nearer than the step to the last one shows nothing new on the map.
			elseif not (seg and way == seg.way and (fx - lx) ^ 2 + (fy - ly) ^ 2 < step2) then
				if seg and way ~= seg.way then
					close()
					seg = { way = way, pts = { lx, ly }, ts = { lt } }
				end
				seg = seg or { way = way, pts = {}, ts = {} }
				seg.pts[#seg.pts + 1] = fx
				seg.pts[#seg.pts + 1] = fy
				seg.ts[#seg.ts + 1] = p.t
				lx, ly, lt = fx, fy, p.t
			end
		end
		if #points > 0 and type(rec.n) == "number" and rec.n >= ns.Trail.MAX_POINTS then
			goesOn = { m = zone, s = rec.s, t = points[#points].t }
		end
	end
	close()
	return out, target.skipped, jumps
end

-- The two columns of a journal line that decide whether it can be a pin, without splitting the whole line.
local function head(line)
	local t, m, x, y, kind = line:match("^(%d*)|[^|]*|(%d*)|(%d*)|(%d*)|(%w+)")
	return tonumber(t), tonumber(m), tonumber(x), tonumber(y), kind
end

-- The group of a kind, "" for a kind without one, or nil for a kind this client does not know.
local function groupOf(kind)
	local spec = ns.Kinds.Get(kind)
	return spec and (spec.group or "")
end

-- The lines of every open journal that have a position on mapID, as { t, kind, group, x, y, fields }, in journal order
-- with the core journal first. filter.groups holds the shown groups. filter.limit stops the list; the second result is
-- the number of lines that match, the third the set of zones with no position on mapID.
function MapData.Pins(mapID, filter)
	filter = filter or {}
	local groups = filter.groups or {}
	local target = newTarget(mapID)
	local out, total = {}, 0
	for _, item in ipairs(ns.Registry.Journals()) do
		for line in item.journal:Lines() do
			-- The saved file can be edited by hand, so a line may be any value.
			local t, m, x, y, kind
			if type(line) == "string" then
				t, m, x, y, kind = head(line)
			end
			local group = kind and m and x and y and groupOf(kind)
			if group and groups[group] and x <= SCALE and y <= SCALE and inSession(filter.session, t or 0) then
				local fx, fy = target:Place(m, x / SCALE, y / SCALE)
				if fx then
					total = total + 1
					if not filter.limit or total <= filter.limit then
						out[#out + 1] =
							{ t = t, kind = kind, group = group, x = fx, y = fy, fields = ns.Codec.DecodeLine(line) }
					end
				end
			end
		end
	end
	return out, total, target.skipped
end

-- The level ups of the character as { t, level }, by time.
function MapData.Levels()
	local out = {}
	for _, item in ipairs(ns.Registry.Journals()) do
		for line in item.journal:Lines() do
			if type(line) == "string" then
				local t, _, _, _, kind = head(line)
				if kind == "lv" and t then
					local level = ns.Codec.DecodeLine(line).level
					if type(level) == "number" then
						out[#out + 1] = { t = t, level = level }
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.t < b.t
	end)
	return out
end

-- The groups of the registered kinds in registration order, as the tokens of Kinds. A kind without a group has "".
function MapData.Groups()
	local out, seen = {}, {}
	for _, spec in ipairs(ns.Kinds.All()) do
		local g = spec.group or ""
		if not seen[g] then
			seen[g] = true
			out[#out + 1] = g
		end
	end
	return out
end

-- The sessions of the character as { start, stop }, by start, from MemoriesCharDB.sessions as the website reads them.
-- The running session has no stop.
function MapData.Sessions()
	local out = {}
	local list = type(MemoriesCharDB) == "table" and MemoriesCharDB.sessions
	if type(list) ~= "table" then
		return out
	end
	local current = ns.Sessions.Current()
	for _, e in ipairs(list) do
		if type(e) == "table" and type(e.start) == "number" then
			local stop = e ~= current and math.max(type(e.last) == "number" and e.last or e.start, e.start) or nil
			out[#out + 1] = { start = e.start, stop = stop }
		end
	end
	table.sort(out, function(a, b)
		return a.start < b.start
	end)
	return out
end
