local _, ns = ...

local L = ns.L

-- Draws the trail and the pins of MapData on the world map, and replays them. One data provider owns the drawing: the
-- map calls it when the map changes, when it clears its data and when its canvas changes, so the overlay follows each
-- zoom with no hook on a game function. Lines and pins sit in pools. A replay moves a playhead along the timeline of
-- Replay: a step of the trail shows when the playhead passes it, and a pin pops in with an animation. With no replay
-- running, the whole journey shows.
local Overlay = {}
ns.Overlay = Overlay

Overlay.MAX_LINES = 3000
Overlay.MAX_PINS = 500
Overlay.SLICE = 200
Overlay.LINE_WIDTH = 2

-- The colour of each way of travel, as the website's trail colours.
Overlay.WAY_COLOR = ns.Replay.WAY_COLOR

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
Overlay.PIN_SIZE, Overlay.BIG_PIN_SIZE = 16, 24
-- A continent or the world packs a whole journey into a small space, so its pins show at this part of their size.
Overlay.HIGH_MAP_PIN = 0.5
Overlay.HEAD_SIZE = 22
-- Seconds of the pop of a new pin.
Overlay.POP = 0.45
-- A pin that pops in while the replay jumps over many pins at once shows with no pop beyond this count.
Overlay.MAX_POPS = 8
-- A burst plays at a pin when the playhead passes an event of these kinds: a ring grows and fades and a label rises and
-- fades. The colour follows the kind. At most MAX_BURSTS play at once.
Overlay.BURST_TIME = 1.2
Overlay.MAX_BURSTS = 4
Overlay.BURST = {
	lv = { 1, 0.85, 0.2 },
	de = { 1, 0.25, 0.2 },
	tx = { 0.4, 0.75, 1 },
	bt = { 0.4, 0.75, 1 },
	hs = { 0.4, 0.75, 1 },
	po = { 0.78, 0.55, 1 },
	su = { 0.78, 0.55, 1 },
	dn = { 0.78, 0.55, 1 },
	bo = { 0.78, 0.55, 1 },
	wb = { 1, 0.5, 0.2 },
}
-- The size of a pin or a line is in screen units. The canvas scale of the map is clamped to this range.
Overlay.MIN_SCALE, Overlay.MAX_SCALE = 0.1, 10

local provider
local container
local head
local enabled = false
-- The choice of a session from the panel; it is not saved.
local session
-- Counts of the last draw, for the panel.
local stats = { lines = 0, pins = 0, cutLines = 0, cutPins = 0, zones = 0 }
-- Each new draw and each clear raises this, so an older draw never touches the new pools.
local generation = 0

local linePool, pinPool, burstPool = {}, {}, {}
-- The replay: the timeline of the map shown, the playhead, and how many lines and pins show.
local timeline
local pos, playing, speed = 0, false, ns.Replay.SPEEDS[1]
local shownEdges, shownPins = 0, 0
-- The canvas size, and the canvas units of one screen unit.
local width, height, unit = 0, 0, 1
-- The size factor of the pins on the map shown.
local pinScale = 1
-- Follow: with the clock of the whole journey, the replay shows the map of the playhead. It waits this long after it
-- changes the map, so the player sees the new map before the replay goes on.
Overlay.MAP_PAUSE = 0.6
-- Following is off until Play, a seek or the Follow box, after a map change that the overlay did not ask for.
local hold = false
local pauseLeft = 0
-- The playhead that the draw inside SetMapID of Follow keeps: { pos, playing }.
local resume
-- The map that Follow asked for, and the map of the last draw.
local expectedMap, drawnMap
-- The clock of the last draw: whether it spans the whole journey, and its session. A playhead means a moment only on
-- the clock it was read on.
local drawnFollow, drawnSession = false, nil
-- Whether the map shown shows the zone of the playhead, by map of the zone.
local shows = {}
-- True for the first frame after a draw that kept the playhead, so the pins it passes do not pop.
local quiet = false
-- The colour mode of the trail and the palette, as the settings were at the last draw.
local look = { mode = "way", blind = false }
function Overlay.Enabled()
	return enabled
end

function Overlay.Session()
	return session
end

function Overlay.Stats()
	return ns.U.Copy(stats)
end

-- The playhead and the length of the replay, in played seconds.
function Overlay.Position()
	return pos, timeline and timeline.total or 0
end

-- The chapters of the replay: { level, t, c } for the start and each level up. They are empty with nothing to play.
-- Reading the level ups scans every journal, so the chapters are kept with the timeline of the draw.
function Overlay.Chapters()
	if not timeline then
		return {}
	end
	if not timeline.chapters then
		timeline.chapters = ns.Replay.Chapters(timeline, timeline.levels or ns.MapData.Levels())
	end
	return timeline.chapters
end

function Overlay.Playing()
	return playing
end

function Overlay.Speed()
	return speed
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

local function changed()
	ns.Emit("MAP_REPLAY_CHANGED")
end

local function canvasScale(map, canvas)
	local scale
	if type(map.GetCanvasScale) == "function" then
		local ok, value = pcall(map.GetCanvasScale, map)
		scale = ok and value or nil
	end
	if type(scale) ~= "number" and canvas.GetScale then
		scale = canvas:GetScale()
	end
	if type(scale) ~= "number" or scale ~= scale then
		return 1
	end
	return math.min(math.max(scale, Overlay.MIN_SCALE), Overlay.MAX_SCALE)
end

local function release()
	for _, line in ipairs(linePool) do
		line:Hide()
	end
	for _, pin in ipairs(pinPool) do
		pin:Hide()
		pin.popAt = nil
	end
	for _, burst in ipairs(burstPool) do
		burst:Hide()
		burst.startAt = nil
	end
	if head then
		head:Hide()
	end
	shownEdges, shownPins = 0, 0
end

local function clear()
	generation = generation + 1
	release()
	if container then
		container:SetScript("OnUpdate", nil)
	end
	timeline, playing, pos, pauseLeft = nil, false, 0, 0
	stats ={ lines = 0, pins = 0, cutLines = 0, cutPins = 0, zones = 0 }
end

function Overlay.Clear()
	clear()
	ns.Emit("MAP_REPLAY_RESET")
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
	pin.glow = pin:CreateTexture(nil, "BACKGROUND")
	pin.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	pin.glow:SetBlendMode("ADD")
	pin.glow:SetPoint("CENTER")
	pin.border = pin:CreateTexture(nil, "BORDER")
	pin.border:SetTexture("Interface\\Buttons\\WHITE8X8")
	pin.border:SetPoint("CENTER")
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	pin.icon:SetPoint("CENTER")
	-- A pin shows its tooltip but lets the clicks through, so the map still zooms in and out under it.
	if pin.SetMouseClickEnabled then
		pin:SetMouseClickEnabled(false)
	end
	pin:SetScript("OnEnter", onEnter)
	pin:SetScript("OnLeave", onLeave)
	return pin
end

-- The size of a pin in canvas units, with the pop factor k.
local function sizePin(pin, k)
	local base = (Overlay.BIG_KINDS[pin.data.kind] and Overlay.BIG_PIN_SIZE or Overlay.PIN_SIZE) * pinScale
	local size = math.max(base * unit * k, 0.01)
	local inner = math.max(size - 2 * unit * k * pinScale, 0.01)
	pin:SetSize(size, size)
	pin.border:SetSize(size, size)
	pin.icon:SetSize(inner, inner)
	pin.glow:SetSize(size * 1.9, size * 1.9)
end

local function placePin(i, animate)
	local data = timeline.pins[i]
	local pin = pinPool[i]
	if not pin then
		pin = newPin()
		pinPool[i] = pin
	end
	pin.data = data
	local color = Overlay.GROUP_COLOR[data.group] or DEFAULT_COLOR
	pin.border:SetVertexColor(color[1], color[2], color[3], 1)
	pin.glow:SetVertexColor(color[1], color[2], color[3], 1)
	pin.icon:SetTexture(Overlay.GROUP_ICON[data.group] or DEFAULT_ICON)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", container, "TOPLEFT", data.x * width, -data.y * height)
	pin.popAt = animate and GetTime() or nil
	pin.glow:SetAlpha(Overlay.BIG_KINDS[data.kind] and 0.4 or 0)
	sizePin(pin, animate and 0 or 1)
	pin:Show()
end

local function placeLine(i)
	local e = timeline.edges[i]
	local line = linePool[i]
	if not line then
		line = container:CreateLine(nil, "ARTWORK")
		linePool[i] = line
	end
	line:SetThickness(Overlay.LINE_WIDTH * unit)
	line:SetColorTexture(ns.Replay.Color(e, look.mode, look.blind))
	line:SetStartPoint("TOPLEFT", container, e.x1 * width, -e.y1 * height)
	line:SetEndPoint("TOPLEFT", container, e.x2 * width, -e.y2 * height)
	line:Show()
end

local function newHead()
	local frame = CreateFrame("Frame", nil, container)
	frame.glow = frame:CreateTexture(nil, "BACKGROUND")
	frame.glow:SetTexture("Interface\\Cooldown\\star4")
	frame.glow:SetBlendMode("ADD")
	frame.glow:SetPoint("CENTER")
	-- The arrow of the game's own minimap, in silver, turned along the route.
	frame.arrow = frame:CreateTexture(nil, "ARTWORK")
	frame.arrow:SetTexture("Interface\\Minimap\\ROTATING-MINIMAPARROW")
	frame.arrow:SetDesaturated(true)
	frame.arrow:SetVertexColor(0.85, 0.88, 0.92, 1)
	frame.arrow:SetPoint("CENTER")
	return frame
end

local function placeHead(now)
	local x, y, _, dx, dy = ns.Replay.Head(timeline, pos)
	if not x or (not playing and pos >= timeline.total) then
		head:Hide()
		return
	end
	local pulse = 0.5 + 0.5 * math.sin(now * 5)
	local size = Overlay.HEAD_SIZE * unit
	head:SetSize(size, size)
	head.arrow:SetSize(size, size)
	-- The arrow art points up and SetRotation turns it counterclockwise. The step is in map units, so it turns on the
	-- canvas size to follow the line as it shows. A step of no length keeps the last turn.
	if dx ~= 0 or dy ~= 0 then
		head.turn = math.atan2(-dx * width, -dy * height)
	end
	head.arrow:SetRotation(head.turn or 0)
	head.glow:SetSize(size * (1.3 + 0.5 * pulse), size * (1.3 + 0.5 * pulse))
	head.glow:SetVertexColor(0.8, 0.85, 1, 0.5 + 0.4 * pulse)
	head:ClearAllPoints()
	head:SetPoint("CENTER", container, "TOPLEFT", x * width, -y * height)
	head:Show()
end

-- The pop of a pin that just showed, and the pulse of a pin that is new in played time. Both end by themselves.
local function animatePins(now)
	local busy = false
	for i = 1, shownPins do
		local pin = pinPool[i]
		local k = 1
		if pin.popAt then
			local t = (now - pin.popAt) / Overlay.POP
			if t >= 1 then
				pin.popAt = nil
			else
				k = 1 + 2.70158 * (t - 1) ^ 3 + 1.70158 * (t - 1) ^ 2
				busy = true
			end
			sizePin(pin, k)
		end
		local age = pos - pin.data.c
		if playing and age >= 0 and age < ns.Replay.PULSE then
			pin.glow:SetAlpha(0.5 + 0.5 * math.sin(now * 9))
			busy = true
		elseif pin.glowing then
			pin.glow:SetAlpha(Overlay.BIG_KINDS[pin.data.kind] and 0.4 or 0)
		end
		pin.glowing = playing and age >= 0 and age < ns.Replay.PULSE
	end
	return busy
end

local function newBurst()
	local frame = CreateFrame("Frame", nil, container)
	frame:SetSize(1, 1)
	frame.ring = frame:CreateTexture(nil, "BACKGROUND")
	frame.ring:SetTexture("Interface\\Cooldown\\star4")
	frame.ring:SetBlendMode("ADD")
	frame.ring:SetPoint("CENTER")
	frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	return frame
end

-- The label of a burst: the level for a level up, else the name of the kind.
local function burstLabel(data)
	local level = data.fields and data.fields.level
	if data.kind == "lv" and type(level) == "number" then
		return L["Level %d"]:format(level)
	end
	local spec = ns.Kinds.Get(data.kind)
	return spec and spec.name or data.kind
end

-- Starts the burst of a pin of a kind that has one. It plays nothing when MAX_BURSTS already play.
local function startBurst(data, now)
	local color = Overlay.BURST[data.kind]
	if not color then
		return
	end
	local burst
	for _, b in ipairs(burstPool) do
		if not b.startAt then
			burst = b
			break
		end
	end
	if not burst then
		if #burstPool >= Overlay.MAX_BURSTS then
			return
		end
		burst = newBurst()
		burstPool[#burstPool + 1] = burst
	end
	burst.startAt, burst.x, burst.y = now, data.x, data.y
	burst.ring:SetVertexColor(color[1], color[2], color[3], 1)
	burst.label:SetTextColor(color[1], color[2], color[3], 1)
	burst.label:SetText(burstLabel(data))
	burst:Show()
end

-- The ring grows and fades, and the label rises and fades. The frame is scaled to the screen, so it keeps its size at
-- each zoom. A burst ends by itself.
local function animateBursts(now)
	local busy = false
	for _, burst in ipairs(burstPool) do
		if burst.startAt then
			local t = (now - burst.startAt) / Overlay.BURST_TIME
			if t >= 1 then
				burst.startAt = nil
				burst:Hide()
			else
				busy = true
				local grow = 1 - (1 - t) ^ 3
				local ring = Overlay.BIG_PIN_SIZE * (0.6 + 3.4 * grow)
				burst:SetScale(unit)
				burst:ClearAllPoints()
				burst:SetPoint("CENTER", container, "TOPLEFT", burst.x * width / unit, -burst.y * height / unit)
				burst.ring:SetSize(ring, ring)
				burst.ring:SetAlpha((1 - t) ^ 1.2)
				burst.label:ClearAllPoints()
				burst.label:SetPoint("CENTER", burst, "CENTER", 0, 18 + 26 * t)
				local fade = t < 0.15 and t / 0.15 or 1 - ((t - 0.15) / 0.85) ^ 2
				burst.label:SetAlpha(fade)
			end
		end
	end
	return busy
end

local function finish()
	ns.Emit("MAP_OVERLAY_DRAWN", Overlay.Stats())
end

-- A failed draw leaves the map as the game drew it.
local function fail()
	resume = nil
	Overlay.Clear()
	if container then
		container:Hide()
	end
	finish()
	changed()
end

-- Shows the map of the playhead when it is not the map shown and the map shown does not show its zone. It keeps the
-- playhead, calls SetMapID, a public call, and waits MAP_PAUSE. It returns true when it asked for a map, and then the
-- redraw of the map change replaces the timeline.
local function goTo()
	local m = ns.Replay.MapAt(timeline.route, pos)
	if not m or m == drawnMap then
		return false
	end
	if shows[m] == nil then
		shows[m] = ns.MapData.Shows(drawnMap, m)
	end
	if shows[m] then
		return false
	end
	local map = provider and provider:GetMap()
	local from, before = drawnMap, timeline
	-- A map that cannot be shown leaves following off, so the replay does not ask for it again and again.
	hold = true
	-- The game's SetMapID sizes the canvas from the art layers of the map and raises an error for a map with none.
	local art = C_Map.GetMapArtLayers
	if map and type(map.SetMapID) == "function" and (type(art) ~= "function" or (art(m) or {})[1]) then
		resume, expectedMap = { pos = pos, playing = playing }, m
		-- The game's SetMapID calls OnMapChanged of each provider before it returns, so the draw is done here.
		pcall(map.SetMapID, map, m)
		if drawnMap == m then
			hold = false
			pauseLeft = Overlay.MAP_PAUSE
			return true
		end
		resume, expectedMap = nil, nil
		-- An error inside SetMapID leaves the map on the new id with the art of the old map.
		if map:GetMapID() ~= from then
			pcall(map.SetMapID, map, from)
		end
	end
	ns.LogError("map overlay:follow", "the map " .. m .. " cannot be shown", nil, true)
	return timeline ~= before
end

-- One step of the replay: it moves the playhead, shows or hides the lines and the pins that the playhead passed, and
-- animates. It stops its own OnUpdate once nothing moves.
local function update(dt)
	if not timeline or width <= 0 or height <= 0 then
		-- A canvas with no size wakes the replay again from Relayout.
		container:SetScript("OnUpdate", nil)
		return
	end
	local now = GetTime()
	-- The pins that the playhead reaches on the frame that ends the replay still pop in.
	local wasPlaying = playing
	if pauseLeft > 0 then
		pauseLeft = pauseLeft - dt
		dt = 0
	end
	if playing then
		pos, playing = ns.Replay.Advance(pos, dt, speed, timeline.total)
		if not playing then
			changed()
		end
		if timeline.route and not hold and pauseLeft <= 0 and goTo() then
			return
		end
	end
	local wantEdges, wantPins = ns.Replay.Counts(timeline, pos)
	if wantEdges < shownEdges then
		for i = wantEdges + 1, shownEdges do
			linePool[i]:Hide()
		end
		shownEdges = wantEdges
	else
		-- A slice of the new lines each frame, so a long trail never stops a frame.
		local upto = math.min(wantEdges, shownEdges + Overlay.SLICE)
		for i = shownEdges + 1, upto do
			placeLine(i)
		end
		shownEdges = upto
	end
	if wantPins < shownPins then
		for i = wantPins + 1, shownPins do
			pinPool[i]:Hide()
			pinPool[i].popAt = nil
		end
		shownPins = wantPins
		ns.Emit("MAP_REPLAY_RESET")
	else
		local animate = wasPlaying and not quiet and wantPins - shownPins <= Overlay.MAX_POPS
		for i = shownPins + 1, wantPins do
			placePin(i, animate)
			if animate then
				startBurst(timeline.pins[i], now)
				ns.Emit("MAP_REPLAY_EVENT", timeline.pins[i])
			end
		end
		shownPins = wantPins
	end
	quiet = false
	local busy = animatePins(now)
	busy = animateBursts(now) or busy
	placeHead(now)
	if not (playing or busy or shownEdges < wantEdges) then
		container:SetScript("OnUpdate", nil)
	end
	ns.Emit("MAP_REPLAY_TICK", pos, timeline.total, playing)
end

local function onUpdate(_, dt)
	if not ns.Safe("map overlay:update", update, dt) then
		fail()
	end
end

local function wake()
	if container and timeline then
		container:SetScript("OnUpdate", onUpdate)
	end
end

-- Starts the replay at the start, or goes on from the playhead.
function Overlay.Play()
	if not timeline or timeline.total <= 0 then
		return
	end
	if pos >= timeline.total then
		pos = 0
	end
	playing = true
	hold = false
	wake()
	changed()
end

function Overlay.Pause()
	if playing then
		playing = false
		changed()
	end
end

function Overlay.Toggle()
	if playing then
		Overlay.Pause()
	else
		Overlay.Play()
	end
end

function Overlay.Seek(c)
	if not timeline or type(c) ~= "number" then
		return
	end
	pos = math.min(math.max(c, 0), timeline.total)
	if pos >= timeline.total then
		playing = false
	end
	hold = false
	wake()
	changed()
end

-- A speed of Replay.SPEEDS.
function Overlay.SetSpeed(value)
	for _, s in ipairs(ns.Replay.SPEEDS) do
		if s == value then
			speed = value
			changed()
			return
		end
	end
end

function Overlay.CycleSpeed()
	local speeds = ns.Replay.SPEEDS
	for i, s in ipairs(speeds) do
		if s == speed then
			Overlay.SetSpeed(speeds[i % #speeds + 1])
			return
		end
	end
	Overlay.SetSpeed(speeds[1])
end

local function count(set)
	local n = 0
	for _ in pairs(set) do
		n = n + 1
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
local function query(mapID, filter)
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
		data.segments, zones, data.jumps = ns.MapData.Segments(mapID, filter)
		for zone in pairs(zones or {}) do
			skipped[zone] = true
		end
		-- The level ups are read only for the colour mode that needs them.
		if look.mode == "level" then
			data.levels = ns.MapData.Levels()
		end
	end
	data.zones = count(skipped)
	return data
end

local function measure(map, canvas)
	local w, h = canvas:GetSize()
	width, height = tonumber(w) or 0, tonumber(h) or 0
	unit = 1 / canvasScale(map, canvas)
end

local function draw()
	local map = provider and provider:GetMap()
	if not enabled or not map then
		fail()
		return
	end
	-- A draw during a replay keeps the playhead, since each map shares the clock of the journey.
	local keepPos, keepPlaying = pos, playing
	-- The panel empties its feed only when the playhead does not stay.
	clear()
	-- A hidden map draws again from RefreshAllData when it shows, with the filter of that time.
	if not map:IsShown() then
		ns.Emit("MAP_REPLAY_RESET")
		finish()
		changed()
		return
	end
	local canvas = map:GetCanvas()
	if not container or container:GetParent() ~= canvas then
		if container then
			container:Hide()
		end
		container = CreateFrame("Frame", nil, canvas)
		container:SetAllPoints(canvas)
		linePool, pinPool, burstPool = {}, {}, {}
		head = newHead()
		head:Hide()
	end
	local level = pinLevel(map)
	if level then
		container:SetFrameLevel(level)
	end
	container:Show()
	measure(map, canvas)
	local mapID = map:GetMapID()
	pinScale = ns.IsSkippedMap(mapID) and Overlay.HIGH_MAP_PIN or 1
	look = { mode = ns.Settings.Get("map.color"), blind = ns.Settings.Get("map.colorblind") == true }
	local filter = Overlay.Filter()
	local data = query(mapID, filter)
	-- With nothing to show, no clock spans the journey, so the replay has nothing to play.
	local following = ns.Settings.Get("map.follow") ~= false and (filter.trail or next(filter.groups) ~= nil)
	local clock, route
	if following then
		local visits = ns.MapData.Route(filter)
		-- With no trail saved, the replay plays on the clock of this map, as with Follow off.
		following = #visits > 0
		clock = ns.Replay.Clock(visits)
		route = following and ns.Replay.Route(visits, clock) or nil
	end
	timeline = ns.Replay.Build(data, Overlay.MAX_LINES, clock)
	timeline.route = route
	timeline.levels = data.levels
	stats.lines = #timeline.edges
	stats.pins = #timeline.pins
	stats.cutLines = timeline.cut
	stats.cutPins = data.cutPins
	stats.zones = data.zones
	-- The playhead stays for the map change of Follow and for a draw during a replay. With no replay running the whole
	-- journey shows. A map change that nobody asked for during a replay is the player's, and it stops following.
	-- A playhead on another clock, from Follow off or another session, would land on an unrelated moment.
	local keep
	if following and drawnFollow and drawnSession == session then
		if resume and expectedMap == mapID then
			keep = resume
		elseif keepPlaying then
			keep = { pos = keepPos, playing = true }
			hold = hold or (expectedMap ~= mapID and drawnMap ~= mapID)
		end
	end
	resume, expectedMap, drawnMap, shows = nil, nil, mapID, {}
	drawnFollow, drawnSession = following, session
	quiet = keep ~= nil
	if keep then
		pos = math.min(keep.pos, timeline.total)
		playing = keep.playing and pos < timeline.total
	else
		pos = timeline.total
		ns.Emit("MAP_REPLAY_RESET")
	end
	if width > 0 and height > 0 then
		wake()
	end
	finish()
	changed()
end

-- Draws again for the map shown, from the saved data. A failure goes to /memories errors and leaves the map as the game
-- drew it.
function Overlay.Draw()
	if not provider then
		return
	end
	if not ns.Safe("map overlay", draw) then
		fail()
	end
end

-- Turns Follow on or off, and draws again with the clock that fits it.
function Overlay.SetFollow(on)
	ns.Settings.Set("map.follow", on == true)
	hold = false
	Overlay.Draw()
end

function Overlay.SetSession(value)
	session = value
	Overlay.Draw()
end

-- Places the lines and the pins that show again for a new canvas size, with no change of the playhead. A new zoom
-- (sizeOnly) keeps the canvas offsets and only sizes them again, as the map fires it on each frame of a zoom.
function Overlay.Relayout(sizeOnly)
	local map = provider and provider:GetMap()
	if not (enabled and timeline and container and map and map:IsShown()) then
		return
	end
	local ok = ns.Safe("map overlay:relayout", function()
		measure(map, map:GetCanvas())
		if width <= 0 or height <= 0 then
			return
		end
		for i = 1, shownEdges do
			if sizeOnly then
				linePool[i]:SetThickness(Overlay.LINE_WIDTH * unit)
			else
				placeLine(i)
			end
		end
		for i = 1, shownPins do
			local pin = pinPool[i]
			if not sizeOnly then
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", container, "TOPLEFT", pin.data.x * width, -pin.data.y * height)
			end
			sizePin(pin, 1)
		end
		wake()
	end)
	if not ok then
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
		ns.Safe("map overlay:clear", Overlay.Clear)
		finish()
		changed()
	end
	-- The lines and the pins sit at offsets from the canvas size and show at a size that follows the zoom.
	function p:OnCanvasSizeChanged()
		Overlay.Relayout()
	end
	function p:OnCanvasScaleChanged()
		Overlay.Relayout(true)
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
