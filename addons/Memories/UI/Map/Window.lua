local _, ns = ...

local L = ns.L

-- The Journey window: a map of its own, with the trail, the pins and the replay of the journey, the panel and the
-- player bar. It draws the map art itself from the game's map data (the tiles of the map and the areas that the
-- character explored), so it works the same with any world map addon. A left click on a zone opens it, a right click
-- goes up to the map that holds it.
local Window = {}
ns.MapWindow = Window

Window.NAME = "MemoriesJourneyFrame"
Window.MAP_W, Window.MAP_H = 900, 600
Window.PAD = 10
Window.TOP = 30
Window.GAP = 6
-- The frame levels between the canvas and the name of the map, which leave room for the trail, the pins and the bursts.
Window.ABOVE_CANVAS = 20

local frame, view, canvas
local mapID
local tiles, pieces = {}, {}

-- The host of the overlay: the map that this window shows.
local host = {}

function host:GetMapID()
	return mapID
end

function host:GetCanvas()
	return canvas
end

function host:IsShown()
	return frame ~= nil and frame:IsShown()
end

function host:SetMapID(id)
	Window.ShowMap(id)
end

function Window.Frame()
	return frame
end

function Window.MapID()
	return mapID
end

function Window.Canvas()
	return canvas
end

-- The first art layer of a map, or nil for a map with no art, such as most instances.
function Window.Layer(id)
	local get = type(C_Map) == "table" and C_Map.GetMapArtLayers
	local ok, layers = pcall(get or error, id)
	local layer = ok and type(layers) == "table" and layers[1]
	if type(layer) == "table" and (layer.layerWidth or 0) > 0 and (layer.tileWidth or 0) > 0 then
		return layer
	end
end

local function texture(pool, i, layer)
	local t = pool[i]
	if not t then
		t = canvas:CreateTexture(nil, layer)
		pool[i] = t
	end
	t:ClearAllPoints()
	t:Show()
	return t
end

local function hideFrom(pool, n)
	for i = n, #pool do
		pool[i]:Hide()
	end
end

-- The size of the file of the last piece of a row or a column of explored art: the smallest power of two from 16 up
-- that holds it, as the game's own map reads it. A full piece fills its file.
local function fileSize(n, full)
	if n >= full then
		return n
	end
	local size = 16
	while size < n do
		size = size * 2
	end
	return size
end

-- The explored areas of the map, in pieces of at most one tile of the art layer. The last piece of a row or a column
-- is narrower, and its file is the power of two that holds it.
local function paintExplored(id, layer, sx, sy)
	local get = type(C_MapExplorationInfo) == "table" and C_MapExplorationInfo.GetExploredMapTextures
	local ok, list = pcall(get or error, id)
	local tw, th = layer.tileWidth, layer.tileHeight
	local n = 0
	for _, info in ipairs(ok and type(list) == "table" and list or {}) do
		local files = type(info) == "table" and info.fileDataIDs
		if type(files) == "table" and not info.isShownByMouseOver then
			local wide = math.ceil(info.textureWidth / tw)
			local tall = math.ceil(info.textureHeight / th)
			for row = 1, tall do
				for col = 1, wide do
					local file = files[(row - 1) * wide + col]
					if file then
						local pw = col < wide and tw or info.textureWidth - tw * (wide - 1)
						local ph = row < tall and th or info.textureHeight - th * (tall - 1)
						n = n + 1
						local t = texture(pieces, n, "BORDER")
						t:SetTexture(file)
						t:SetTexCoord(0, pw / fileSize(pw, tw), 0, ph / fileSize(ph, th))
						t:SetSize(pw * sx, ph * sy)
						t:SetPoint(
							"TOPLEFT",
							canvas,
							"TOPLEFT",
							(info.offsetX + tw * (col - 1)) * sx,
							-(info.offsetY + th * (row - 1)) * sy
						)
					end
				end
			end
		end
	end
	hideFrom(pieces, n + 1)
end

-- Draws the art of the map: its tiles in rows, scaled to the canvas, then the explored areas over them. The view clips
-- the part of the last tiles that lies past the map.
local function paintArt(id, layer)
	local w, h = canvas:GetSize()
	local sx, sy = w / layer.layerWidth, h / layer.layerHeight
	local ok, files = pcall(C_Map.GetMapArtLayerTextures, id, 1)
	local cols = math.ceil(layer.layerWidth / layer.tileWidth)
	local n = 0
	for i, file in ipairs(ok and type(files) == "table" and files or {}) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		n = i
		local t = texture(tiles, i, "BACKGROUND")
		t:SetTexture(file)
		t:SetSize(layer.tileWidth * sx, layer.tileHeight * sy)
		t:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * layer.tileWidth * sx, -row * layer.tileHeight * sy)
	end
	hideFrom(tiles, n + 1)
	paintExplored(id, layer, sx, sy)
end

local function mapName(id)
	local info = C_Map.GetMapInfo(id)
	return type(info) == "table" and info.name or tostring(id)
end

local function parentOf(id)
	local info = C_Map.GetMapInfo(id)
	local parent = type(info) == "table" and info.parentMapID
	return type(parent) == "number" and parent > 0 and parent or nil
end

-- Shows the art, the name and the Up button of a map. It returns false and changes nothing for a map with no art.
local function setMap(id)
	local layer = frame and type(id) == "number" and Window.Layer(id)
	if not layer then
		return false
	end
	mapID = id
	paintArt(id, layer)
	frame.mapName:SetText(mapName(id))
	local parent = parentOf(id)
	frame.up:SetEnabled(parent ~= nil and Window.Layer(parent) ~= nil)
	return true
end

-- Shows a map in the window and draws the journey on it. It returns false and changes nothing for a map with no art.
function Window.ShowMap(id)
	if not setMap(id) then
		return false
	end
	ns.Overlay.Draw()
	return true
end

-- Goes up to the map that holds the map shown.
function Window.Up()
	local parent = mapID and parentOf(mapID)
	if parent then
		Window.ShowMap(parent)
	end
end

-- The point of the canvas under the cursor, in map units, or nil off the canvas.
local function cursorPoint()
	local cx, cy = GetCursorPosition()
	local scale = canvas:GetEffectiveScale()
	local left, top = canvas:GetLeft(), canvas:GetTop()
	local w, h = canvas:GetSize()
	if not (left and top and scale and w > 0 and h > 0) then
		return nil
	end
	local x, y = (cx / scale - left) / w, (top - cy / scale) / h
	if x < 0 or x > 1 or y < 0 or y > 1 then
		return nil
	end
	return x, y
end

-- A left click opens the zone under the cursor, a right click goes up.
local function click(button)
	if button == "RightButton" then
		Window.Up()
		return
	end
	local x, y = cursorPoint()
	local get = C_Map.GetMapInfoAtPosition
	if not x or type(get) ~= "function" then
		return
	end
	local info = get(mapID, x, y)
	local child = type(info) == "table" and info.mapID
	if child and child ~= mapID then
		Window.ShowMap(child)
	end
end

-- The map that the window opens on: the map of the player, else the first map of the trail, else the nearest map
-- above the player, each only when it has art. Without a trail, a player in an instance gets the zone or continent.
local function firstMap()
	local best = C_Map.GetBestMapForUnit and ns.R(C_Map.GetBestMapForUnit("player"))
	if type(best) == "number" and Window.Layer(best) then
		return best
	end
	for _, visit in ipairs(ns.MapData.Route()) do
		if Window.Layer(visit.m) then
			return visit.m
		end
	end
	local seen = {}
	while type(best) == "number" and not seen[best] do
		if Window.Layer(best) then
			return best
		end
		seen[best] = true
		best = parentOf(best)
	end
end

local function onShow()
	ns.Overlay.SetHost(host)
	ns.MapPanel.Create(frame)
	local panel, bar = ns.MapPanel.Frame(), ns.MapPanel.Bar()
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", view, "TOPRIGHT", Window.PAD, 0)
	panel:SetPoint("BOTTOMLEFT", view, "BOTTOMRIGHT", Window.PAD, -(Window.GAP + ns.MapPanel.BAR_HEIGHT))
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", view, "BOTTOMLEFT", 0, -Window.GAP)
	bar:SetWidth(Window.MAP_W)
	panel:Show()
	-- The art goes first, so the overlay draws once, on the map shown.
	setMap(mapID or firstMap())
	ns.Overlay.Show(true)
	if ns.MapTab then
		ns.MapTab.Look()
	end
end

local function onHide()
	ns.Overlay.Show(false)
	local panel = ns.MapPanel.Frame()
	if panel then
		panel:Hide()
	end
	if ns.MapTab then
		ns.MapTab.Look()
	end
end

local function build()
	-- It opens from the world map; the DIALOG strata of ns.Window keeps it above the map.
	local f = ns.Window.Create(
		Window.NAME,
		Window.PAD * 3 + Window.MAP_W + ns.MapPanel.WIDTH,
		Window.TOP + Window.MAP_H + Window.GAP + ns.MapPanel.BAR_HEIGHT + Window.PAD,
		L["Journey"]
	)
	local v = CreateFrame("Frame", nil, f)
	v:SetPoint("TOPLEFT", Window.PAD, -Window.TOP)
	v:SetSize(Window.MAP_W, Window.MAP_H)
	v:SetClipsChildren(true)
	v.bg = v:CreateTexture(nil, "BACKGROUND")
	v.bg:SetAllPoints()
	v.bg:SetColorTexture(0, 0, 0, 1)
	local c = CreateFrame("Frame", nil, v)
	c:SetPoint("TOPLEFT")
	c:SetSize(Window.MAP_W, Window.MAP_H)
	c:EnableMouse(true)
	c:SetScript("OnMouseUp", function(_, button)
		ns.Protect("journey window:click", click, button)
	end)
	-- The canvas and the overlay are child frames of the view, so the name and the Up button sit on a frame above them.
	local top = CreateFrame("Frame", nil, v)
	top:SetAllPoints()
	top:SetFrameLevel(c:GetFrameLevel() + Window.ABOVE_CANVAS)
	f.mapName = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.mapName:SetPoint("TOPLEFT", 10, -8)
	f.up = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
	f.up:SetSize(60, 22)
	f.up:SetPoint("TOPRIGHT", -8, -8)
	f.up:SetText(L["Up"])
	f.up:SetEnabled(false)
	f.up:SetScript("OnClick", function()
		ns.Protect("journey window:up", Window.Up)
	end)
	f:SetScript("OnShow", function()
		ns.Protect("journey window:show", onShow)
	end)
	f:SetScript("OnHide", function()
		ns.Protect("journey window:hide", onHide)
	end)
	frame, view, canvas = f, v, c
end

-- Opens the window, or closes it when it is open.
function Window.Toggle()
	if not frame then
		build()
	end
	frame:SetShown(not frame:IsShown())
end

function Window.Shown()
	return frame ~= nil and frame:IsShown()
end
