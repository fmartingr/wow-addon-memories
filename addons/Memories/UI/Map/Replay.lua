local _, ns = ...

-- The timeline of the Journey replay: what shows at each moment of the journey. It is pure data, with no frame, so the
-- busted suite tests it alone. The clock counts played seconds. A pause longer than GAP counts as GAP, so a journey
-- that spans many sessions plays with no dead time.
local Replay = {}
ns.Replay = Replay

-- Played seconds for each real second at speed 1, as the website.
Replay.BASE_RATE = 40
Replay.SPEEDS = { 1, 2, 4, 8, 16 }
Replay.GAP = 20

-- The colour of each way of travel. The colourblind palette keeps the five ways apart for the common types of colour
-- blindness, as it uses the luminance and the hue together.
Replay.WAY_COLOR = {
	foot = { 1, 0.953, 0.769 },
	mounted = { 1, 0.7, 0.28 },
	taxi = { 1, 0.886, 0.541 },
	swim = { 0.29, 0.84, 0.75 },
	dead = { 0.561, 0.831, 1 },
	arc = { 0.78, 0.65, 1 },
}
Replay.BLIND_WAY_COLOR = {
	foot = { 0.94, 0.89, 0.26 },
	mounted = { 0.9, 0.62, 0 },
	taxi = { 0.34, 0.71, 0.91 },
	swim = { 0, 0.62, 0.45 },
	dead = { 0.8, 0.47, 0.65 },
	arc = { 1, 1, 1 },
}
-- The stops of the colour of a level or of an age: { position 0..1, { r, g, b } }.
local RAMP = {
	{ 0, { 0.25, 0.45, 1 } },
	{ 0.35, { 0.2, 0.85, 0.8 } },
	{ 0.65, { 1, 0.9, 0.3 } },
	{ 1, { 1, 0.4, 0.25 } },
}
local BLIND_RAMP = {
	{ 0, { 0.27, 0, 0.33 } },
	{ 0.33, { 0.23, 0.32, 0.55 } },
	{ 0.66, { 0.13, 0.57, 0.55 } },
	{ 1, { 0.99, 0.9, 0.14 } },
}
-- The last level of the character, which ends the colour ramp of the level mode.
Replay.MAX_LEVEL = 60

local function ramp(stops, f)
	f = math.min(math.max(f, 0), 1)
	for i = 2, #stops do
		local a, b = stops[i - 1], stops[i]
		if f <= b[1] then
			local k = (f - a[1]) / (b[1] - a[1])
			return a[2][1] + (b[2][1] - a[2][1]) * k,
				a[2][2] + (b[2][2] - a[2][2]) * k,
				a[2][3] + (b[2][3] - a[2][3]) * k
		end
	end
	local last = stops[#stops][2]
	return last[1], last[2], last[3]
end

-- The colour of a step of the trail: r, g, b, a. mode is "way", "level" or "age". In the level mode a step with no
-- known level shows the colour of its way. An older step in the age mode is cooler and dimmer.
function Replay.Color(edge, mode, blind)
	local ways = blind and Replay.BLIND_WAY_COLOR or Replay.WAY_COLOR
	local stops = blind and BLIND_RAMP or RAMP
	if mode == "level" and edge.level then
		local r, g, b = ramp(stops, (edge.level - 1) / (Replay.MAX_LEVEL - 1))
		return r, g, b, 0.9
	elseif mode == "age" and edge.age then
		local r, g, b = ramp(stops, edge.age)
		return r, g, b, 0.4 + 0.5 * edge.age
	end
	local c = ways[edge.way] or ways.foot
	return c[1], c[2], c[3], 0.9
end

local function lastAtOrBefore(list, key, value)
	local lo, hi, found = 1, #list, 0
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		if list[mid][key] <= value then
			found, lo = mid, mid + 1
		else
			hi = mid - 1
		end
	end
	return found
end

-- The clock of a unix time, from the sorted times and the clock of each.
local function clockAt(times, clocks, t)
	local n = #times
	if n == 0 or t <= times[1] then
		return 0
	end
	if t >= times[n] then
		return clocks[n]
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local span = times[hi] - times[lo]
	local step = clocks[hi] - clocks[lo]
	return clocks[lo] + (span > 0 and (t - times[lo]) / span * step or 0)
end

-- The level of the character at the unix time t from the level ups, sorted by time. Before the first level up it is the
-- level below it, and without level ups it is nil.
local function levelAt(levels, t)
	local first = levels[1]
	if not first then
		return nil
	end
	if t < first.t then
		return math.max(first.level - 1, 1)
	end
	local found = lastAtOrBefore(levels, "t", t)
	return levels[found].level
end

-- The clock of the whole journey from its visits ({ m, t0, t1 }, by t0): real time inside a visit and at most GAP for
-- each gap between visits. It returns { times, clocks, total, at }, where at gives the clock of a unix time. Visits
-- that overlap count once.
function Replay.Clock(visits)
	local times, clocks = {}, {}
	local function add(t, inside)
		local n = #times
		if n == 0 then
			times[1], clocks[1] = t, 0
		elseif t > times[n] then
			local dt = t - times[n]
			times[n + 1], clocks[n + 1] = t, clocks[n] + (inside and dt or math.min(dt, Replay.GAP))
		end
	end
	for _, v in ipairs(visits) do
		add(v.t0, false)
		add(v.t1, true)
	end
	return {
		times = times,
		clocks = clocks,
		total = clocks[#clocks] or 0,
		at = function(t)
			return clockAt(times, clocks, t)
		end,
	}
end

-- The visits with the clock of their start and end: { m, c0, c1 }, in clock order.
function Replay.Route(visits, clock)
	local out = {}
	for _, v in ipairs(visits) do
		out[#out + 1] = { m = v.m, c0 = clock.at(v.t0), c1 = clock.at(v.t1) }
	end
	return out
end

-- The map of the playhead at the clock c: the map of the last visit that started at or before it, or nil before the
-- first.
function Replay.MapAt(route, c)
	local found = lastAtOrBefore(route, "c0", c)
	return found > 0 and route[found].m or nil
end

-- The curve of a trip that skips the trail: ARC_STEPS steps along a quadratic curve that bows to the north.
Replay.ARC_STEPS = 10
Replay.ARC_BOW = 0.25

local function arcEdges(edges, j)
	local dx, dy = j.x2 - j.x1, j.y2 - j.y1
	local nx, ny = -dy, dx
	if ny > 0 then
		nx, ny = -nx, -ny
	end
	local cx = (j.x1 + j.x2) / 2 + nx * Replay.ARC_BOW
	local cy = (j.y1 + j.y2) / 2 + ny * Replay.ARC_BOW
	local steps = Replay.ARC_STEPS
	local px, py = j.x1, j.y1
	for i = 1, steps do
		local u = i / steps
		local a, b, c = (1 - u) ^ 2, 2 * (1 - u) * u, u ^ 2
		local x, y = a * j.x1 + b * cx + c * j.x2, a * j.y1 + b * cy + c * j.y2
		edges[#edges + 1] = {
			x1 = px,
			y1 = py,
			x2 = x,
			y2 = y,
			way = "arc",
			t0 = j.t0 + (i - 1) / steps * (j.t1 - j.t0),
			t = j.t0 + u * (j.t1 - j.t0),
			n = #edges + 1,
		}
		px, py = x, y
	end
end

-- data = { segments, pins } of MapData. It returns { edges, pins, total, cut }: each edge is one step of the trail with
-- its clock c (where it ends) and c0 (where it starts), each pin has its clock c, and both lists are in clock order. At
-- most maxEdges edges stay, the oldest ones, and cut counts the others.
function Replay.Build(data, maxEdges, clock)
	local edges = {}
	for _, seg in ipairs(data.segments or {}) do
		local pts, ts = seg.pts, seg.ts or {}
		for i = 1, #pts / 2 - 1 do
			local t0, t1 = ts[i], ts[i + 1]
			if type(t0) == "number" and type(t1) == "number" then
				edges[#edges + 1] = {
					x1 = pts[2 * i - 1],
					y1 = pts[2 * i],
					x2 = pts[2 * i + 1],
					y2 = pts[2 * i + 2],
					way = seg.way,
					t0 = t0,
					t = t1,
					n = #edges + 1,
				}
			end
		end
	end
	for _, j in ipairs(data.jumps or {}) do
		arcEdges(edges, j)
	end
	table.sort(edges, function(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return a.n < b.n
	end)
	local cut = math.max(0, #edges - (maxEdges or #edges))
	if cut > 0 then
		for i = #edges, maxEdges + 1, -1 do
			edges[i] = nil
		end
	end
	-- A clock with no visits cannot place anything, so the clock of this map takes its place.
	if clock and #clock.times == 0 then
		clock = nil
	end
	-- An event far outside the time of the journey has no place on the clock of the whole journey, so it is left out.
	local from = clock and clock.times[1] - Replay.GAP
	local to = clock and clock.times[#clock.times] + Replay.GAP
	local pins = {}
	for _, pin in ipairs(data.pins or {}) do
		if type(pin.t) == "number" and (not clock or (pin.t >= from and pin.t <= to)) then
			pins[#pins + 1] = pin
		end
	end
	-- With a clock of the whole journey, every map shares one clock. Without it, the clock counts the steps and the
	-- pins of this map only, and each pause counts as at most GAP.
	if not clock then
		local stamps = {}
		for _, e in ipairs(edges) do
			stamps[#stamps + 1] = e.t0
			stamps[#stamps + 1] = e.t
		end
		for _, pin in ipairs(pins) do
			stamps[#stamps + 1] = pin.t
		end
		table.sort(stamps)
		local visits = {}
		for _, t in ipairs(stamps) do
			visits[#visits + 1] = { t0 = t, t1 = t }
		end
		clock = Replay.Clock(visits)
	end
	local times, clocks = clock.times, clock.clocks
	local first, span = edges[1] and edges[1].t0, edges[#edges] and edges[#edges].t - edges[1].t0
	local levels = data.levels or {}
	for _, e in ipairs(edges) do
		e.c0, e.c = clockAt(times, clocks, e.t0), clockAt(times, clocks, e.t)
		e.level = levelAt(levels, e.t)
		e.age = span > 0 and (e.t - first) / span or 1
	end
	for _, pin in ipairs(pins) do
		pin.c = clockAt(times, clocks, pin.t)
	end
	table.sort(pins, function(a, b)
		return a.c < b.c
	end)
	return {
		edges = edges,
		pins = pins,
		total = clocks[#clocks] or 0,
		cut = cut,
		first = times[1],
		last = times[#times],
		clockAt = function(t)
			return clockAt(times, clocks, t)
		end,
	}
end

-- The chapters of the journey as { level, t, c }: the start, then one for each level up inside the timeline. The start
-- has no level. There are none with nothing to play.
function Replay.Chapters(timeline, levels)
	if not timeline.first then
		return {}
	end
	local out = { { c = 0 } }
	for _, lv in ipairs(levels or {}) do
		if lv.t > timeline.first and lv.t <= timeline.last then
			out[#out + 1] = { level = lv.level, t = lv.t, c = timeline.clockAt(lv.t) }
		end
	end
	return out
end

-- The playhead after dt real seconds at the speed, and whether it still plays.
function Replay.Advance(c, dt, speed, total)
	local next = math.min(total, c + math.max(0, dt) * Replay.BASE_RATE * speed)
	return next, next < total
end

-- How many edges and how many pins show at the clock c.
function Replay.Counts(timeline, c)
	return lastAtOrBefore(timeline.edges, "c", c), lastAtOrBefore(timeline.pins, "c", c)
end

-- The place of the playhead at the clock c: x, y, the way of travel of the step it is on and the direction of that step
-- (dx, dy), or nil without a trail. Between two steps it stays at the end of the last one; inside a step it glides
-- along it.
function Replay.Head(timeline, c)
	local edges = timeline.edges
	if #edges == 0 then
		return nil
	end
	local shown = lastAtOrBefore(edges, "c", c)
	local following = edges[shown + 1]
	if following and c > following.c0 then
		local span = following.c - following.c0
		local f = span > 0 and math.min(1, (c - following.c0) / span) or 1
		return following.x1 + (following.x2 - following.x1) * f,
			following.y1 + (following.y2 - following.y1) * f,
			following.way,
			following.x2 - following.x1,
			following.y2 - following.y1
	end
	local edge = edges[math.max(shown, 1)]
	local x, y = edge.x2, edge.y2
	if shown == 0 then
		x, y = edge.x1, edge.y1
	end
	return x, y, edge.way, edge.x2 - edge.x1, edge.y2 - edge.y1
end

-- The clock text of the panel: m:ss, or h:mm:ss from one hour.
function Replay.ClockText(c)
	c = math.max(0, math.floor(c))
	if c >= 3600 then
		return ("%d:%02d:%02d"):format(c / 3600, c % 3600 / 60, c % 60)
	end
	return ("%d:%02d"):format(c / 60, c % 60)
end
