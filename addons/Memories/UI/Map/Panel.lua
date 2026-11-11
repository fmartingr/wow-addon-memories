local _, ns = ...

local L = ns.L

-- The Journey panel of the world map: a check box for each group of kinds and for the trail, the sessions, and the
-- counts of the last draw. The player bar sits at the bottom of the map: play and pause, the speed, a slider and the
-- clock of the replay. Both are plain frames, so they never taint a game frame.
local Panel = {}
ns.MapPanel = Panel

Panel.WIDTH = 270
Panel.ROW = 18
Panel.LIST_HEIGHT = 110
Panel.VISIBLE = math.ceil(Panel.LIST_HEIGHT / Panel.ROW) + 1
Panel.BOX = 22
-- The boxes sit in two columns, so the core and every sub-addon group still fit in the height of the quest log.
Panel.COLUMN = 125
Panel.BAR_WIDTH, Panel.BAR_HEIGHT = 440, 48
-- The bar lies over the map. The map lays its pins at the levels of its pin manager, near 2000 and up, so the bar sits
-- above the topmost of them, and at least this far above the map.
Panel.BAR_LEVEL = 500
Panel.ABOVE_PINS = 10

local frame
local bar
local paintRows
local boxes = {}
local rows = {}
local sessionList = {}

function Panel.Frame()
	return frame
end

local function groupLabel(group)
	if group == "" then
		return L["Other"]
	end
	return ns.Options.GROUPS[group] or group
end

local function check(parent, text, slot, onClick)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box:SetPoint("TOPLEFT", 12 + (slot % 2) * Panel.COLUMN, -40 - math.floor(slot / 2) * Panel.BOX)
	box:SetSize(Panel.BOX, Panel.BOX)
	box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	box.label:SetPoint("LEFT", box, "RIGHT", 4, 0)
	box.label:SetWidth(Panel.COLUMN - Panel.BOX - 6)
	box.label:SetJustifyH("LEFT")
	box.label:SetText(text)
	box:SetScript("OnClick", function(self)
		ns.Safe("map panel:check", onClick, self:GetChecked() == true)
	end)
	return box
end

local function setter(path)
	return function(on)
		ns.Settings.Set(path, on)
		ns.Overlay.Draw()
	end
end

local function chooseSession(session)
	ns.Overlay.SetSession(session)
	paintRows()
end

-- The text of a session row: the date and the length.
function Panel.SessionText(session)
	local stop = session.stop or time()
	local length = ns.Status.Age(math.max(0, stop - session.start))
	return ("%s, %s"):format(date("%Y-%m-%d %H:%M", session.start), length)
end

local function row(slot)
	if rows[slot] then
		return rows[slot]
	end
	local button = CreateFrame("Button", nil, frame.content)
	button:SetSize(Panel.WIDTH - 50, Panel.ROW)
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", 4, 0)
	button.mark = button:CreateTexture(nil, "BACKGROUND")
	button.mark:SetAllPoints()
	button.mark:SetColorTexture(1, 0.82, 0, 0.25)
	button:SetScript("OnClick", function(self)
		ns.Safe("map panel:session", chooseSession, self.session)
	end)
	rows[slot] = button
	return button
end

-- A character can have thousands of sessions, so only the rows in view exist and they move with the scroll.
function paintRows()
	local chosen = ns.Overlay.Session()
	-- The newest session comes first, under the row for all of them.
	local n = #sessionList + 1
	local first = math.floor((frame.scroll:GetVerticalScroll() or 0) / Panel.ROW)
	local shown = math.max(0, math.min(Panel.VISIBLE, n - first))
	for slot = 1, shown do
		local i = first + slot
		local button = row(slot)
		local session = i > 1 and sessionList[n - i + 1] or nil
		button.session = session
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 0, -(i - 1) * Panel.ROW)
		button.text:SetText(session and Panel.SessionText(session) or L["All"])
		button.mark:SetShown(session == chosen or (session ~= nil and chosen ~= nil and session.start == chosen.start))
		button:Show()
	end
	for slot = shown + 1, #rows do
		rows[slot]:Hide()
	end
end

local function refreshSessions()
	sessionList = ns.MapData.Sessions()
	frame.content:SetHeight((#sessionList + 1) * Panel.ROW)
	paintRows()
end

-- The counts line from the stats of a draw.
function Panel.CountText(stats)
	local text = L["%d lines, %d pins"]:format(stats.lines, stats.pins)
	if stats.cutLines > 0 or stats.cutPins > 0 then
		text = text .. "\n" .. L["Cut at %d lines and %d pins."]:format(ns.Overlay.MAX_LINES, ns.Overlay.MAX_PINS)
	end
	if stats.zones > 0 then
		text = text .. "\n" .. L["%d zones not shown"]:format(stats.zones)
	end
	return text
end

function Panel.SetStats(stats)
	if frame then
		frame.count:SetText(Panel.CountText(stats))
	end
end

-- Sets each box from the filter the overlay draws with, and each row from the overlay.
function Panel.Refresh()
	if not frame then
		return
	end
	local filter = ns.Overlay.Filter()
	boxes.trail:SetChecked(filter.trail)
	for group, box in pairs(boxes.groups) do
		box:SetChecked(filter.groups[group] == true)
	end
	refreshSessions()
	Panel.SetStats(ns.Overlay.Stats())
	Panel.UpdateBar()
end

function Panel.Bar()
	return bar
end

-- The level for a frame of this addon that lies over the canvas of map. Another addon can add pin levels, so each show
-- asks again.
function Panel.LevelOver(map)
	local base = (map:GetFrameLevel() or 1) + Panel.BAR_LEVEL
	if type(map.GetPinFrameLevelsManager) ~= "function" then
		return base
	end
	local ok, level = pcall(function()
		return map:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST", math.huge)
	end)
	return ok and type(level) == "number" and math.max(base, level + Panel.ABOVE_PINS) or base
end

-- Sets the bar from the replay: the text of the play button, the speed, the slider and the clock.
function Panel.UpdateBar()
	if not bar then
		return
	end
	local at, total = ns.Overlay.Position()
	local ready = total > 0
	bar.play:SetText(ns.Overlay.Playing() and L["Pause"] or L["Play"])
	bar.speed:SetText(ns.Overlay.Speed() .. "x")
	bar.play:SetEnabled(ready)
	bar.speed:SetEnabled(ready)
	bar.slider:SetEnabled(ready)
	bar.updating = true
	bar.slider:SetMinMaxValues(0, math.max(total, 1))
	bar.updating = false
	Panel.Tick(at, total)
end

-- Each frame of a replay moves only the slider and the clock.
function Panel.Tick(at, total)
	if not bar then
		return
	end
	-- A thumb in the player's hand stays where the mouse holds it.
	if not bar.dragging then
		bar.updating = true
		bar.slider:SetValue(at)
		bar.updating = false
	end
	bar.time:SetText(ns.Replay.ClockText(at) .. " / " .. ns.Replay.ClockText(total))
end

local function buildBar(parent)
	local b = CreateFrame("Frame", nil, parent)
	b:Hide()
	b:SetSize(Panel.BAR_WIDTH, Panel.BAR_HEIGHT)
	-- The level is set before the children exist, so they take theirs above it.
	b:SetFrameLevel(Panel.LevelOver(parent))
	b:EnableMouse(true)
	b:SetPoint("BOTTOM", parent.ScrollContainer or parent, "BOTTOM", 0, 14)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0.05, 0.04, 0.03, 0.85)
	b.play = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.play:SetSize(76, 24)
	b.play:SetPoint("LEFT", 10, 0)
	b.play:SetScript("OnClick", function()
		ns.Safe("map panel:play", ns.Overlay.Toggle)
	end)
	b.speed = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.speed:SetSize(46, 24)
	b.speed:SetPoint("LEFT", b.play, "RIGHT", 4, 0)
	b.speed:SetScript("OnClick", function()
		ns.Safe("map panel:speed", ns.Overlay.CycleSpeed)
	end)
	b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.time:SetPoint("RIGHT", -10, 0)
	b.time:SetWidth(100)
	b.time:SetJustifyH("RIGHT")
	b.slider = CreateFrame("Slider", nil, b)
	b.slider:SetOrientation("HORIZONTAL")
	-- A slider takes no drag without the mouse, and its thumb shows only at a size of its own, as in the game's
	-- templates.
	b.slider:EnableMouse(true)
	b.slider:SetHeight(16)
	b.slider:SetPoint("LEFT", b.speed, "RIGHT", 10, 0)
	b.slider:SetPoint("RIGHT", b.time, "LEFT", -10, 0)
	b.track = b.slider:CreateTexture(nil, "BACKGROUND")
	b.track:SetColorTexture(1, 0.82, 0, 0.35)
	b.track:SetPoint("LEFT")
	b.track:SetPoint("RIGHT")
	b.track:SetHeight(3)
	b.thumb = b.slider:CreateTexture(nil, "OVERLAY")
	b.thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	b.thumb:SetSize(32, 32)
	b.slider:SetThumbTexture(b.thumb)
	b.slider:SetMinMaxValues(0, 1)
	b.slider:SetScript("OnMouseDown", function()
		b.dragging = true
	end)
	b.slider:SetScript("OnMouseUp", function()
		b.dragging = false
	end)
	b.slider:SetScript("OnValueChanged", function(_, value, byUser)
		if byUser and not b.updating then
			ns.Safe("map panel:seek", ns.Overlay.Seek, value)
		end
	end)
	return b
end

-- The panel is kept only once it is whole, so a failed build is tried again on the next click.
function Panel.Create(parent)
	if frame then
		return frame
	end
	local f = CreateFrame("Frame", nil, parent)
	-- Hidden from the start, so a build that fails halfway leaves nothing over the map.
	f:Hide()
	f:SetFrameLevel(Panel.LevelOver(parent))
	f:SetWidth(Panel.WIDTH)
	-- The panel lies over the quest log, so it takes the clicks and the wheel that would reach the log under it.
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.05, 0.04, 0.03, 0.95)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.title:SetText(L["Journey"])
	-- Refresh sets each box from the settings when the panel shows.
	local built = { trail = check(f, L["Trail"], 0, setter("map.trail")), groups = {} }
	local slot = 0
	for _, group in ipairs(ns.MapData.Groups()) do
		slot = slot + 1
		built.groups[group] = check(f, groupLabel(group), slot, setter("map.groups." .. group))
	end
	local y = -40 - (math.floor(slot / 2) + 1) * Panel.BOX - 12
	f.sessionsTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.sessionsTitle:SetPoint("TOPLEFT", 14, y)
	f.sessionsTitle:SetText(L["Sessions"])
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 14, y - 18)
	scroll:SetSize(Panel.WIDTH - 50, Panel.LIST_HEIGHT)
	f.content = CreateFrame("Frame", nil, scroll)
	f.content:SetSize(Panel.WIDTH - 50, Panel.ROW)
	scroll:SetScrollChild(f.content)
	scroll:HookScript("OnVerticalScroll", function()
		ns.Safe("map panel:scroll", paintRows)
	end)
	f.scroll = scroll
	f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.count:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -10)
	f.count:SetWidth(Panel.WIDTH - 30)
	f.count:SetJustifyH("LEFT")
	local playerBar = buildBar(parent)
	f:SetScript("OnShow", function()
		local level = Panel.LevelOver(parent)
		f:SetFrameLevel(level)
		playerBar:SetFrameLevel(level)
		playerBar:Show()
		ns.Safe("map panel:show", Panel.Refresh)
	end)
	f:SetScript("OnHide", function()
		playerBar.dragging = false
		playerBar:Hide()
	end)
	frame, boxes, bar = f, built, playerBar
	return frame
end

ns.Listen("MAP_OVERLAY_DRAWN", function(_, stats)
	Panel.SetStats(stats)
end, "map panel")

ns.Listen("MAP_REPLAY_CHANGED", Panel.UpdateBar, "map panel")
ns.Listen("MAP_REPLAY_TICK", function(_, at, total)
	Panel.Tick(at, total)
end, "map panel")
