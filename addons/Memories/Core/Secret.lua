local _, ns = ...

local floor = math.floor

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

function ns.R(v)
	if isSecret(v) then
		return nil, true
	end
	return v, false
end

-- Returns each value with the secret ones as nil, then one more value: true when any value was secret.
function ns.RN(...)
	local n = select("#", ...)
	local values = { ... }
	local any = false
	for i = 1, n do
		if isSecret(values[i]) then
			values[i] = nil
			any = true
		end
	end
	values[n + 1] = any
	return unpack(values, 1, n + 1)
end

function ns.Position()
	local mapID = ns.R(C_Map.GetBestMapForUnit("player"))
	if not mapID then
		return nil
	end
	local pos = ns.R(C_Map.GetPlayerMapPosition(mapID, "player"))
	if not pos then
		return mapID
	end
	local x, y, secret = ns.RN(pos:GetXY())
	-- The client reports coordinates outside 0-1 when the player stands beyond the map's rectangle.
	if secret or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then
		return mapID
	end
	return mapID, floor(x * 10000 + 0.5), floor(y * 10000 + 0.5)
end

local mapTypes = {}

-- Types 0-2 are the cosmic, world and continent maps, which the client reports for a while after a loading screen.
function ns.IsSkippedMap(m)
	if mapTypes[m] == nil then
		local info = C_Map.GetMapInfo(m)
		local mapType = type(info) == "table" and ns.R(info.mapType) or nil
		-- A map without info yet is asked again on the next point.
		if type(mapType) ~= "number" then
			return false
		end
		mapTypes[m] = mapType <= 2
	end
	return mapTypes[m]
end

-- A secret answer counts as outside.
function ns.InInstance()
	return ns.R(IsInInstance()) == true
end

-- The map position outside an instance and off a skipped map, else nil. inside is the caller's ns.InInstance().
function ns.OutdoorPosition(inside)
	if inside then
		return nil
	end
	local m, x, y = ns.Position()
	if not m or ns.IsSkippedMap(m) then
		return nil
	end
	return m, x, y
end

-- Where and when the player is now, as { t, p, m, x, y }; no place inside an instance or on a skipped map.
function ns.Here()
	local at = { t = ns.Journal.Now(), p = ns.Store.PlayedNow() }
	at.m, at.x, at.y = ns.OutdoorPosition(ns.InInstance())
	return at
end

-- The player's world position as { x, y, inst } in yards, else nil.
function ns.World()
	local y, x, _, inst, secret = ns.RN(UnitPosition("player"))
	if secret or type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return { x = x, y = y, inst = inst }
end
