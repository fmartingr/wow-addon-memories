-- Writes tables in the form of a WoW saved file and loads them back, so a test can prove a save-and-load round trip.
local serialize = {}

local ESCAPES = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r" }

local function quote(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return ESCAPES[c] or string.format("\\%03d", c:byte())
	end) .. '"'
end

local function number(n)
	assert(n == n and n ~= math.huge and n ~= -math.huge, "cannot serialize " .. tostring(n))
	if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
		return string.format("%d", n)
	end
	return string.format("%.17g", n)
end

local KEY_ORDER = { number = 1, string = 2, boolean = 3 }

local function key_less(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return KEY_ORDER[ta] < KEY_ORDER[tb]
	end
	if ta == "boolean" then
		return not a and b
	end
	return a < b
end

local function key_text(k)
	local t = type(k)
	if t == "string" then
		return "[" .. quote(k) .. "]"
	elseif t == "number" then
		return "[" .. number(k) .. "]"
	elseif t == "boolean" then
		return "[" .. tostring(k) .. "]"
	end
	error("cannot serialize a key of type " .. t)
end

local value

local function table_text(t, indent, seen, out)
	assert(not seen[t], "cannot serialize a table cycle")
	seen[t] = true
	out[#out + 1] = "{\n"
	local inner = indent .. "\t"
	local n = #t
	for i = 1, n do
		out[#out + 1] = inner
		value(t[i], inner, seen, out)
		out[#out + 1] = ", -- [" .. i .. "]\n"
	end
	local keys = {}
	for k in pairs(t) do
		if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys, key_less)
	for _, k in ipairs(keys) do
		out[#out + 1] = inner .. key_text(k) .. " = "
		value(t[k], inner, seen, out)
		out[#out + 1] = ",\n"
	end
	out[#out + 1] = indent .. "}"
	seen[t] = nil
end

value = function(v, indent, seen, out)
	local t = type(v)
	if t == "string" then
		out[#out + 1] = quote(v)
	elseif t == "number" then
		out[#out + 1] = number(v)
	elseif t == "boolean" then
		out[#out + 1] = tostring(v)
	elseif t == "table" then
		table_text(v, indent, seen, out)
	else
		error("cannot serialize a value of type " .. t)
	end
end

function serialize.value(v)
	local out = {}
	value(v, "", {}, out)
	return table.concat(out)
end

-- globals maps a global name to its value; nil values are left out, as the game does.
function serialize.file(globals)
	local names = {}
	for name in pairs(globals) do
		names[#names + 1] = name
	end
	table.sort(names)
	local out = {}
	for _, name in ipairs(names) do
		out[#out + 1] = name .. " = "
		value(globals[name], "", {}, out)
		out[#out + 1] = "\n"
	end
	return table.concat(out)
end

-- Returns a table of the globals that the text sets, or nil and the load error.
function serialize.load(text)
	local chunk, err = loadstring(text, "=SavedVariables")
	if not chunk then
		return nil, err
	end
	local env = {}
	setfenv(chunk, env)
	chunk()
	return env
end

return serialize
