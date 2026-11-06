local _, ns = ...

local Codec = {}
ns.Codec = Codec

local SEP = "|"
local FIXED = { "t", "p", "m", "x", "y" }

-- "|" separates fields and "\n" separates lines in a chunk, so neither may appear inside a field.
local function clean(c)
	return c == SEP and "/" or " "
end

function Codec.Field(v)
	if v == nil then
		return ""
	elseif v == true then
		return "1"
	elseif v == false then
		return "0"
	end
	return (tostring(v):gsub("[%z\1-\31\127|]", clean))
end

function Codec.EncodeLine(t, p, m, x, y, kind, ...)
	local Field = Codec.Field
	local parts = { Field(t), Field(p), Field(m), Field(x), Field(y), Field(kind) }
	local fields = { ... }
	for i = 1, select("#", ...) do
		parts[6 + i] = Field(fields[i])
	end
	while #parts > 6 and parts[#parts] == "" do
		parts[#parts] = nil
	end
	return table.concat(parts, SEP)
end

-- Returns { t, p, m, x, y, k, <named fields>, raw = { field strings after the kind } }. An empty field decodes as nil.
-- A line of an unknown kind has only the fixed columns and raw.
function Codec.DecodeLine(line)
	local cols = ns.U.Split(line, SEP)
	local ev = { k = cols[6] }
	for i, name in ipairs(FIXED) do
		ev[name] = tonumber(cols[i])
	end
	local raw = {}
	for i = 7, #cols do
		raw[i - 6] = cols[i]
	end
	ev.raw = raw
	local spec = ns.Kinds.Get(ev.k)
	if spec then
		for i, name in ipairs(spec.names) do
			local v = raw[i]
			if v == "" then
				v = nil
			elseif spec.numeric[i] then
				v = tonumber(v)
			end
			ev[name] = v
		end
	end
	return ev
end
