local _, ns = ...

local Api = {}
ns.Api = Api

local floor = math.floor
local U = ns.U

Api.RATE = 30
Api.WINDOW = 60
Api.KEEP = 120
-- Each new source name makes a bucket, so an addon that changes its source on every call could still grow the table
-- and flood the journal within the 2 minutes a bucket is kept.
Api.MAX_SOURCES = 50
Api.FILE = "^WoWScrnShot_%d%d%d%d%d%d_%d%d%d%d%d%d%.%a%a%a%a?$"

local buckets = {}
local nBuckets = 0
local lastSweep
local busy = false

-- Trims the leading space before the cut, so a long run of spaces never reaches the cut or a slow pattern. Control
-- characters count as space: the codec stores them as spaces, so a value made only of them is empty.
local function clean(v, limit)
	local first = v:find("[^%s%c]")
	if not first then
		return ""
	end
	-- One byte past the limit is enough for Utf8Cut to find the character boundary.
	local s = U.Utf8Cut(v:sub(first, first + limit), limit)
	return (s:gsub("[%s%c]+$", ""))
end

-- Returns the clean text, nil for a missing optional value, or false when the value is refused.
local function text(v, field)
	local value, secret = ns.R(v)
	if secret then
		return false
	end
	if type(value) == "number" then
		value = tostring(value)
	elseif value ~= nil and type(value) ~= "string" then
		return false
	end
	value = value and clean(value, field.limit)
	if value == nil or value == "" then
		if field.required then
			return false
		end
		return nil
	end
	if field.pattern and not value:match(field.pattern) then
		return false
	end
	return value
end

local function window()
	return floor(GetTime() / Api.WINDOW)
end

local function sweep(now)
	if lastSweep == now then
		return
	end
	lastSweep = now
	local oldest = now - floor(Api.KEEP / Api.WINDOW)
	for source, b in pairs(buckets) do
		if b.window <= oldest then
			buckets[source] = nil
			nBuckets = nBuckets - 1
		end
	end
end

-- Returns the source's bucket for this window, or nil when the source is at its limit.
local function bucket(source)
	local now = window()
	sweep(now)
	local b = buckets[source]
	if not b then
		if nBuckets >= Api.MAX_SOURCES then
			return nil
		end
		b = { window = now, n = 0 }
		buckets[source] = b
		nBuckets = nBuckets + 1
	elseif b.window ~= now then
		b.window, b.n = now, 0
	end
	return b.n < Api.RATE and b or nil
end

function Api.Sources()
	return nBuckets
end

local function record(kind, fields, ...)
	if not ns.loggedIn then
		return false, "not ready"
	end
	local j = ns.Store.Core()
	if not j:CanWrite() then
		return false, "read only"
	end
	if not ns.KindOn(kind) then
		return false, "off"
	end
	local values = {}
	for i, field in ipairs(fields) do
		local v = text((select(i, ...)), field)
		if v == false then
			return false, "bad " .. field.name
		end
		values[i] = v
	end
	local b = bucket(values[1])
	if not b then
		return false, "rate limit"
	end
	-- Write checks the same read-only flag and kind gate as above, so it cannot refuse the line here.
	j:Write(kind, values[1], values[2], values[3])
	b.n = b.n + 1
	return true
end

-- A call from inside a call, for example from an error handler that the inner call triggers, is refused, so the two
-- can never loop.
local function public(where, ...)
	if busy then
		return false, "error"
	end
	busy = true
	-- The pcall keeps busy from staying set when the error log itself raises.
	local called, ok, done, reason = pcall(ns.Protect, where, record, ...)
	busy = false
	if not (called and ok) then
		return false, "error"
	end
	return done, reason
end

local EVENT = {
	{ name = "source", limit = 40, required = true },
	{ name = "what", limit = 100, required = true },
	{ name = "detail", limit = 200 },
}

function ns.Public.RecordEvent(source, what, detail)
	return public("api:RecordEvent", "ex", EVENT, source, what, detail)
end

local NOTE = {
	{ name = "source", limit = 40, required = true },
	{ name = "note", limit = 200, required = true },
	{ name = "file", limit = 80, pattern = Api.FILE },
}

-- Call it after SCREENSHOT_SUCCEEDED, with the file name that the caller predicts.
function ns.Public.RecordScreenshot(source, note, file)
	return public("api:RecordScreenshot", "sn", NOTE, source, note, file)
end
