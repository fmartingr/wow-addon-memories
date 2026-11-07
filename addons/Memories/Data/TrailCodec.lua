local _, ns = ...

-- A trail chunk is { s, t, m, n, d, o }: the session start, the unix time of the first point, the map, the number of
-- points, the points as text, and o = 1 on a chunk filed from the open copy. One string per chunk keeps the saved file
-- far below the client's constant limit.
local TrailCodec = {}
ns.TrailCodec = TrailCodec

local floor = math.floor

TrailCodec.FLAGS = {
	{ "t", "taxi" },
	{ "f", "flying" },
	{ "m", "mounted" },
	{ "g", "ghost" },
	{ "d", "dead" },
	{ "w", "swimming" },
	{ "c", "combat" },
	{ "i", "instance" },
}

-- state holds booleans by the names of FLAGS. A ghost is dead too, so "d" marks only the time at the corpse.
function TrailCodec.Flags(state)
	local out = {}
	for _, f in ipairs(TrailCodec.FLAGS) do
		local on = state[f[2]] == true
		if f[2] == "dead" and state.ghost == true then
			on = false
		end
		if on then
			out[#out + 1] = f[1]
		end
	end
	return #out > 0 and table.concat(out) or "-"
end

local Chunk = {}
Chunk.__index = Chunk

function TrailCodec.New(s, t, m)
	return setmetatable({ s = s, t = t, m = m, n = 0, parts = {} }, Chunk)
end

-- sec counts from the chunk's first point. A point carries its flags only when they differ from the point before.
function Chunk:Add(sec, x, y, flags)
	local text = floor(sec + 0.5) .. "," .. x .. "," .. y
	if flags ~= self.flags then
		text = text .. "," .. flags
		self.flags = flags
	end
	self.n = self.n + 1
	self.parts[self.n] = text
end

function Chunk:Record(copy)
	return { s = self.s, t = self.t, m = self.m, n = self.n, d = table.concat(self.parts, ";"), o = copy and 1 or nil }
end

-- Returns the points of a record as { t, x, y, flags } with absolute times, or nil for a malformed record.
function TrailCodec.Decode(rec)
	if type(rec) ~= "table" or type(rec.d) ~= "string" or type(rec.t) ~= "number" then
		return nil
	end
	local out, flags = {}, "-"
	if rec.d == "" then
		return out
	end
	for _, part in ipairs(ns.U.Split(rec.d, ";")) do
		local sec, x, y, f = part:match("^(%d+),(%d+),(%d+),?(.*)$")
		if not sec then
			return nil
		end
		if f ~= "" then
			flags = f
		end
		out[#out + 1] = { t = rec.t + tonumber(sec), x = tonumber(x), y = tonumber(y), flags = flags }
	end
	return out
end
