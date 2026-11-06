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
