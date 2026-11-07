local ADDON, ns = ...

local Journal = {}
Journal.__index = Journal
ns.Journal = Journal

ns.SCHEMA = 1
Journal.CHUNK = 200

local CHUNK = Journal.CHUNK
local EMPTY = {}

function Journal.Now()
	return time()
end

local tableAt = ns.U.TableAt

-- Moves every full block of CHUNK lines from the front of open into chunks, in one pass.
local function pack(l)
	local open = l.open
	local n = #open
	if n < CHUNK then
		return
	end
	local first = 1
	while n - first + 1 >= CHUNK do
		l.chunks[#l.chunks + 1] = table.concat(open, "\n", first, first + CHUNK - 1)
		first = first + CHUNK
	end
	local rest = {}
	for i = first, n do
		rest[#rest + 1] = open[i]
	end
	l.open = rest
end

-- A read-only journal never changes its data table: the data may come from a newer Memories.
function Journal.New(data, opts)
	opts = opts or {}
	local j = setmetatable({ data = data, addon = opts.addon or ADDON, readOnly = opts.readOnly == true }, Journal)
	if j.readOnly then
		return j
	end
	data.schema = data.schema or ns.SCHEMA
	data.addon = j.addon
	data.writtenBy = ns.VERSION
	tableAt(data, "char")
	local log = tableAt(data, "log")
	tableAt(log, "chunks")
	tableAt(log, "open")
	tableAt(data, "counts")
	tableAt(data, "snap")
	tableAt(data, "state")
	-- A full open list can stay behind when the client stopped between two writes.
	pack(log)
	data.lines = j:LineCount()
	return j
end

function Journal:CanWrite()
	return not self.readOnly
end

local function log(self)
	local l = self.data.log
	if type(l) ~= "table" then
		return EMPTY, EMPTY
	end
	return type(l.chunks) == "table" and l.chunks or EMPTY, type(l.open) == "table" and l.open or EMPTY
end

function Journal:LineCount()
	local chunks, open = log(self)
	return #chunks * CHUNK + #open
end

function Journal:WriteAt(at, kind, ...)
	local spec = ns.Kinds.Get(kind)
	assert(spec, "unknown kind " .. tostring(kind))
	if self.readOnly then
		return nil, "read only"
	end
	-- ns.KindOn is the settings' kind gate.
	if not spec.always and not ns.KindOn(kind) then
		return nil, "off"
	end
	local line = ns.Codec.EncodeLine(at.t or Journal.Now(), at.p, at.m, at.x, at.y, kind, ...)
	local l = self.data.log
	l.open[#l.open + 1] = line
	pack(l)
	self.data.lines = self:LineCount()
	-- One decode serves every listener, and none happens while nobody listens.
	local ev = ns.Listening("LINE_WRITTEN") and ns.Codec.DecodeLine(line) or nil
	ns.Emit("LINE_WRITTEN", self.addon, kind, line, ev)
	return line
end

-- ns.Here (Core/Secret.lua) gives the time, played time and place of a line written now.
function Journal:Write(kind, ...)
	return self:WriteAt(ns.Here(), kind, ...)
end

-- Splits one chunk at a time, so a long journal never sits in memory as one list of lines. It yields the lines that
-- exist when it starts: a write during the loop that packs open into a new chunk never yields a line twice.
function Journal:Lines()
	local chunks, open = log(self)
	local nChunks, nOpen = #chunks, #open
	local ci, lines, li, last = 0, nil, 0, 0
	return function()
		while true do
			if li < last then
				li = li + 1
				return lines[li]
			end
			if ci > nChunks then
				return nil
			end
			ci = ci + 1
			li = 0
			if ci <= nChunks then
				lines = ns.U.Split(chunks[ci], "\n")
				last = #lines
			else
				lines, last = open, nOpen
			end
		end
	end
end

-- The counts of a module for reading. A read-only journal gives its saved table or an empty one, and never creates it.
local function countsOf(self, module)
	local counts = self.data.counts
	if self.readOnly then
		return type(counts) == "table" and type(counts[module]) == "table" and counts[module] or EMPTY
	end
	return tableAt(counts, module)
end

-- Returns the value before the add. A read-only journal counts nothing.
function Journal:Count(module, key, n)
	local counts = countsOf(self, module)
	local old = counts[key] or 0
	if not self.readOnly then
		counts[key] = old + (n or 1)
	end
	return old
end

-- A read-only journal returns a copy, so a caller cannot change data that a newer Memories wrote.
function Journal:Counts(module)
	local counts = countsOf(self, module)
	return self.readOnly and ns.U.Copy(counts) or counts
end

function Journal:IsFirst(module, key)
	local v = countsOf(self, module)[key]
	return v == nil or v == 0
end

function Journal:Snap(level, key, value)
	local snap = self.data.snap
	if value == nil then
		local t = type(snap) == "table" and snap[level]
		return type(t) == "table" and t[key] or nil
	end
	if not self.readOnly then
		tableAt(snap, level)[key] = value
	end
end
