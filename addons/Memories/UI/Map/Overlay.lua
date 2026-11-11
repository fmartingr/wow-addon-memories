local _, ns = ...

-- Draws the trail and the pins of MapData on the world map. One data provider owns the drawing: the map calls it when
-- the map changes and when it clears its data, so the overlay follows each zoom with no hook on a game function.
-- Lines and pins sit in pools, and the lines are drawn in slices so that a long trail does not stop a frame.
local Overlay = {}
ns.Overlay = Overlay

Overlay.MAX_LINES = 3000
Overlay.MAX_PINS = 500
Overlay.SLICE = 200
Overlay.LINE_WIDTH = 2

-- The colour of each way of travel, as the website's trail colours.
Overlay.WAY_COLOR = {
	foot = { 1, 0.953, 0.769 },
	mounted = { 1, 0.7, 0.28 },
	taxi = { 1, 0.886, 0.541 },
	swim = { 0.29, 0.84, 0.75 },
	dead = { 0.561, 0.831, 1 },
}

Overlay.GROUP_COLOR = {
	Sessions = { 0.7, 0.7, 0.7 },
	Progress = { 1, 0.82, 0 },
	Deaths = { 1, 0.25, 0.2 },
	Travel = { 0.4, 0.75, 1 },
	Dungeons = { 0.78, 0.55, 1 },
	Screenshots = { 1, 1, 1 },
	Combat = { 1, 0.5, 0.2 },
	Gathering = { 0.4, 0.9, 0.4 },
	Character = { 0.9, 0.9, 0.5 },
	Milestones = { 1, 0.6, 0.9 },
	Loot = { 0.65, 0.85, 0.3 },
	Money = { 1, 0.85, 0.3 },
	Social = { 0.5, 0.9, 0.9 },
	PvP = { 0.9, 0.3, 0.5 },
}
local DEFAULT_COLOR = { 0.85, 0.85, 0.85 }

-- The icon of each group, from the game's own icons of the Classic client.
Overlay.GROUP_ICON = {
	Sessions = "Interface\\Icons\\INV_Misc_PocketWatch_01",
	Progress = "Interface\\Icons\\Spell_Holy_PowerInfusion",
	Deaths = "Interface\\Icons\\Ability_Rogue_FeignDeath",
	Travel = "Interface\\Icons\\Ability_Mount_RidingHorse",
	Dungeons = "Interface\\Icons\\INV_Misc_Key_03",
	Screenshots = "Interface\\Icons\\INV_Misc_Spyglass_03",
	Combat = "Interface\\Icons\\INV_Sword_04",
	Gathering = "Interface\\Icons\\Trade_Herbalism",
	Character = "Interface\\Icons\\INV_Shirt_White_01",
	Milestones = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	Loot = "Interface\\Icons\\INV_Misc_Bag_10",
	Money = "Interface\\Icons\\INV_Misc_Coin_01",
	Social = "Interface\\Icons\\INV_Letter_01",
	PvP = "Interface\\Icons\\INV_BannerPVP_02",
}
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

Overlay.BIG_KINDS = { de = true, lv = true }
Overlay.PIN_SIZE, Overlay.BIG_PIN_SIZE = 12, 20

local provider
local container
local enabled = false
-- The choice of a session from the panel; it is not saved.
local session
-- Counts of the last draw, for the panel.
local stats = { lines = 0, pins = 0, cutLines = 0, cutPins = 0, zones = 0 }
-- Each new draw and each clear raises this, so the slices of an older draw stop.
local generation = 0

local linePool, pinPool = {}, {}
local linesUsed, pinsUsed = 0, 0
-- The lists of the map shown, so a new canvas size places them again without reading the saved data.
local last

function Overlay.Enabled()
	return enabled
end

function Overlay.Session()
	return session
end

function Overlay.Stats()
	return ns.U.Copy(stats)
end

-- The filter of MapData from the settings and the session choice.
function Overlay.Filter()
	local groups = {}
	for _, group in ipairs(ns.MapData.Groups()) do
		if ns.Settings.Get("map.groups." .. group) ~= false then
			groups[group] = true
		end
	end
	return { trail = ns.Settings.Get("map.trail") ~= false, groups = groups, session = session }
end

function Overlay.SetSession(value)
	session = value
	Overlay.Draw()
end

local function release()
	for i = 1, linesUsed do
		linePool[i]:Hide()
	end
	for i = 1, pinsUsed do
		pinPool[i]:Hide()
	end
	linesUsed, pinsUsed = 0, 0
end

function Overlay.Clear()
	generation = generation + 1
	release()
	stats = { lines = 0, pins = 0, cutLines = 0, cutPins = 0, zones = 0 }
end

local function tooltip(pin)
	local pinData = pin.data
	local spec = ns.Kinds.Get(pinData.kind)
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:SetText(spec and spec.name or pinData.kind)
	if type(pinData.t) == "number" then
		GameTooltip:AddLine(date("%Y-%m-%d %H:%M", pinData.t))
	end
	for _, name in ipairs(spec and spec.names or {}) do
		local value = pinData.fields[name]
		if value ~= nil then
			GameTooltip:AddLine(name .. ": " .. tostring(value))
		end
	end
	GameTooltip:Show()
end

local function onEnter(pin)
	ns.Safe("map overlay:tooltip", tooltip, pin)
end

local function onLeave()
	GameTooltip:Hide()
end

local function newPin()
	local pin = CreateFrame("Button", nil, container)
	pin.border = pin:CreateTexture(nil, "BACKGROUND")
	pin.border:SetAllPoints()
	pin.border:SetTexture("Interface\\Buttons\\WHITE8X8")
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetPoint("TOPLEFT", 1, -1)
	pin.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- A pin shows its tooltip but lets the clicks through, so the map still zooms in and out under it.
	if pin.SetMouseClickEnabled then
		pin:SetMouseClickEnabled(false)
	end
	pin:SetScript("OnEnter", onEnter)
	pin:SetScript("OnLeave", onLeave)
	return pin
end

local function placePin(data, w, h)
	local pin = pinPool[pinsUsed + 1]
	if not pin then
		pin = newPin()
		pinPool[pinsUsed + 1] = pin
	end
	pinsUsed = pinsUsed + 1
	local size = Overlay.BIG_KINDS[data.kind] and Overlay.BIG_PIN_SIZE or Overlay.PIN_SIZE
	local color = Overlay.GROUP_COLOR[data.group] or DEFAULT_COLOR
	pin.data = data
	pin:SetSize(size, size)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", container, "TOPLEFT", data.x * w, -data.y * h)
	pin.border:SetVertexColor(color[1], color[2], color[3], 1)
	pin.icon:SetTexture(Overlay.GROUP_ICON[data.group] or DEFAULT_ICON)
	pin:Show()
end

local function placeLine(way, x1, y1, x2, y2, w, h)
	local line = linePool[linesUsed + 1]
	if not line then
		line = container:CreateLine(nil, "ARTWORK")
		line:SetThickness(Overlay.LINE_WIDTH)
		linePool[linesUsed + 1] = line
	end
	linesUsed = linesUsed + 1
	local color = Overlay.WAY_COLOR[way] or Overlay.WAY_COLOR.foot
	line:SetColorTexture(color[1], color[2], color[3], 0.9)
	line:SetStartPoint("TOPLEFT", container, x1 * w, -y1 * h)
	line:SetEndPoint("TOPLEFT", container, x2 * w, -y2 * h)
	line:Show()
end

local function count(set)
	local n = 0
	for _ in pairs(set) do
		n = n + 1
	end
	return n
end

local function finish()
	ns.Emit("MAP_OVERLAY_DRAWN", Overlay.Stats())
end

-- A failed draw leaves the map as the game drew it.
local function fail()
	last = nil
	Overlay.Clear()
	if container then
		container:Hide()
	end
	finish()
end

-- Draws up to SLICE lines of the segments from the position (seg, i), then asks for the next slice.
local function lineSlice(segments, w, h, seg, i, left, token)
	if token ~= generation then
		return
	end
	local drawn = 0
	while seg <= #segments and left > 0 do
		local s = segments[seg]
		if i + 3 > #s.pts then
			seg, i = seg + 1, 1
		elseif drawn >= Overlay.SLICE then
			break
		else
			local p = s.pts
			placeLine(s.way, p[i], p[i + 1], p[i + 2], p[i + 3], w, h)
			i = i + 2
			drawn, left = drawn + 1, left - 1
		end
	end
	stats.lines = linesUsed
	if seg <= #segments and left > 0 then
		C_Timer.After(0, function()
			if not ns.Safe("map overlay:slice", lineSlice, segments, w, h, seg, i, left, token) then
				fail()
			end
		end)
	else
		finish()
	end
end

local function edges(segments)
	local n = 0
	for _, s in ipairs(segments) do
		n = n + #s.pts / 2 - 1
	end
	return n
end

-- The map stacks its own layers, such as the art of the explored areas, by the levels of its pin manager. A plain child
-- of the canvas sits under them, so the overlay takes the level of the game's area pins. Another addon can add levels,
-- so each draw asks again.
local function pinLevel(map)
	if type(map.GetPinFrameLevelsManager) ~= "function" then
		return nil
	end
	local ok, level = pcall(function()
		return map:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI")
	end)
	return ok and type(level) == "number" and level or nil
end

-- The pins and the segments of mapID for the current filter, with the counts of the panel.
local function query(mapID)
	local filter = Overlay.Filter()
	local skipped = {}
	local data = { mapID = mapID, pins = {}, segments = {}, cutPins = 0 }
	if next(filter.groups) then
		local total, zones
		filter.limit = Overlay.MAX_PINS
		data.pins, total, zones = ns.MapData.Pins(mapID, filter)
		data.cutPins = total - #data.pins
		for zone in pairs(zones or {}) do
			skipped[zone] = true
		end
	end
	if filter.trail then
		local zones
		data.segments, zones = ns.MapData.Segments(mapID, filter)
		for zone in pairs(zones or {}) do
			skipped[zone] = true
		end
	end
	data.zones = count(skipped)
	return data
end

local function draw(reuse)
	local map = provider and provider:GetMap()
	if not enabled or not map then
		fail()
		return
	end
	Overlay.Clear()
	-- A hidden map draws again from RefreshAllData when it shows, with the filter of that time.
	if not map:IsShown() then
		last = nil
		finish()
		return
	end
	local canvas = map:GetCanvas()
	if not container or container:GetParent() ~= canvas then
		if container then
			container:Hide()
		end
		container = CreateFrame("Frame", nil, canvas)
		container:SetAllPoints(canvas)
		linePool, pinPool = {}, {}
	end
	local level = pinLevel(map)
	if level then
		container:SetFrameLevel(level)
	end
	container:Show()
	local w, h = canvas:GetSize()
	local mapID = map:GetMapID()
	local data = reuse and last and last.mapID == mapID and last or query(mapID)
	last = data
	local token = generation
	for _, pinData in ipairs(data.pins) do
		placePin(pinData, w, h)
	end
	stats.pins = pinsUsed
	stats.cutPins = data.cutPins
	stats.zones = data.zones
	local total = edges(data.segments)
	stats.cutLines = math.max(0, total - Overlay.MAX_LINES)
	lineSlice(data.segments, w, h, 1, 1, math.min(total, Overlay.MAX_LINES), token)
end

-- Draws again for the map shown. With reuse, a draw of the same map places the lists of the last draw again instead of
-- reading the saved data. A failure goes to /memories errors and leaves the map as the game drew it.
function Overlay.Draw(reuse)
	if not provider then
		return
	end
	if not ns.Safe("map overlay", draw, reuse) then
		fail()
	end
end

function Overlay.Show(on)
	enabled = on == true
	Overlay.Draw()
end

local function newProvider()
	local p = CreateFromMixins(MapCanvasDataProviderMixin)
	function p:OnMapChanged()
		Overlay.Draw()
	end
	function p:RefreshAllData()
		Overlay.Draw()
	end
	function p:RemoveAllData()
		last = nil
		ns.Safe("map overlay:clear", Overlay.Clear)
		finish()
	end
	-- The lines and the pins sit at offsets from the canvas size of the last draw.
	function p:OnCanvasSizeChanged()
		Overlay.Draw(true)
	end
	return p
end

-- Adds the provider to the world map once. It returns false while the map or its API is missing.
function Overlay.Attach()
	if provider then
		return true
	end
	if
		type(WorldMapFrame) ~= "table"
		or type(WorldMapFrame.AddDataProvider) ~= "function"
		or type(MapCanvasDataProviderMixin) ~= "table"
		or type(CreateFromMixins) ~= "function"
	then
		return false
	end
	local p = newProvider()
	WorldMapFrame:AddDataProvider(p)
	provider = p
	return true
end

ns.Listen("LOGIN", function()
	if not Overlay.Attach() then
		local handle
		handle = ns.On("ADDON_LOADED", function(_, name)
			if name == "Blizzard_WorldMap" and Overlay.Attach() then
				ns.Off("ADDON_LOADED", handle)
			end
		end, "map overlay")
	end
end, "map overlay")

ns.Listen("JOURNAL_OPENED", function()
	if enabled then
		Overlay.Draw()
	end
end, "map overlay")
