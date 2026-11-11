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
-- A pin of a new event pulses for this many played seconds.
Replay.PULSE = 6

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

-- data = { segments, pins } of MapData. It returns { edges, pins, total, cut }: each edge is one step of the trail with
-- its clock c (where it ends) and c0 (where it starts), each pin has its clock c, and both lists are in clock order. At
-- most maxEdges edges stay, the oldest ones, and cut counts the others.
function Replay.Build(data, maxEdges)
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
	local pins = {}
	for _, pin in ipairs(data.pins or {}) do
		if type(pin.t) == "number" then
			pins[#pins + 1] = pin
		end
	end
	local stamps = {}
	for _, e in ipairs(edges) do
		stamps[#stamps + 1] = e.t0
		stamps[#stamps + 1] = e.t
	end
	for _, pin in ipairs(pins) do
		stamps[#stamps + 1] = pin.t
	end
	table.sort(stamps)
	local times, clocks = {}, {}
	for _, t in ipairs(stamps) do
		local n = #times
		if n == 0 or t > times[n] then
			times[n + 1] = t
			clocks[n + 1] = n == 0 and 0 or clocks[n] + math.min(t - times[n], Replay.GAP)
		end
	end
	for _, e in ipairs(edges) do
		e.c0, e.c = clockAt(times, clocks, e.t0), clockAt(times, clocks, e.t)
	end
	for _, pin in ipairs(pins) do
		pin.c = clockAt(times, clocks, pin.t)
	end
	table.sort(pins, function(a, b)
		return a.c < b.c
	end)
	return { edges = edges, pins = pins, total = clocks[#clocks] or 0, cut = cut }
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

-- The place of the playhead at the clock c: x, y and the way of travel of the step it is on, or nil without a trail.
-- Between two steps it stays at the end of the last one; inside a step it glides along it.
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
			following.way
	end
	local edge = edges[math.max(shown, 1)]
	if shown == 0 then
		return edge.x1, edge.y1, edge.way
	end
	return edge.x2, edge.y2, edge.way
end

-- The clock text of the panel: m:ss, or h:mm:ss from one hour.
function Replay.ClockText(c)
	c = math.max(0, math.floor(c))
	if c >= 3600 then
		return ("%d:%02d:%02d"):format(c / 3600, c % 3600 / 60, c % 60)
	end
	return ("%d:%02d"):format(c / 60, c % 60)
end
