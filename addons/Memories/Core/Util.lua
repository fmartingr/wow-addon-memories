local _, ns = ...

local U = {}
ns.U = U

function U.Split(s, sep)
	assert(sep ~= "", "empty separator")
	local out = {}
	local start = 1
	while true do
		local i, j = string.find(s, sep, start, true)
		if not i then
			out[#out + 1] = string.sub(s, start)
			return out
		end
		out[#out + 1] = string.sub(s, start, i - 1)
		start = j + 1
	end
end

function U.Copy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = U.Copy(v)
	end
	return out
end

function U.Utf8Cut(s, maxBytes)
	if #s <= maxBytes then
		return s
	end
	if maxBytes <= 0 then
		return ""
	end
	local cut = maxBytes
	-- Bytes 0x80-0xBF continue a character, so the cut moves back to the start of that character.
	while cut > 0 do
		local b = string.byte(s, cut + 1)
		if b < 0x80 or b >= 0xC0 then
			break
		end
		cut = cut - 1
	end
	return string.sub(s, 1, cut)
end

-- A nil target hooks the global function named by method.
function U.Hook(target, method, fn)
	local tbl = target or _G
	if type(tbl) ~= "table" or type(tbl[method]) ~= "function" then
		return false
	end
	local where = "hook:" .. method
	local function guarded(...)
		ns.Safe(where, fn, ...)
	end
	if target then
		hooksecurefunc(target, method, guarded)
	else
		hooksecurefunc(method, guarded)
	end
	return true
end
