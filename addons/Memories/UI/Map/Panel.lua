local _, ns = ...

local L = ns.L

-- The Journey panel of the world map: a check box for each group of kinds and for the trail, the sessions, and the
-- counts of the last draw. It is a plain frame, so it never taints a game frame.
local Panel = {}
ns.MapPanel = Panel

Panel.WIDTH = 270
Panel.ROW = 18
Panel.LIST_HEIGHT = 120
Panel.VISIBLE = math.ceil(Panel.LIST_HEIGHT / Panel.ROW) + 1
Panel.BOX = 22
-- The boxes sit in two columns, so the core and every sub-addon group still fit in the height of the quest log.
Panel.COLUMN = 125

local frame
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
end

-- The panel is kept only once it is whole, so a failed build is tried again on the next click.
function Panel.Create(parent)
	if frame then
		return frame
	end
	local f = CreateFrame("Frame", nil, parent)
	-- Hidden from the start, so a build that fails halfway leaves nothing over the map.
	f:Hide()
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
	f:SetScript("OnShow", function()
		ns.Safe("map panel:show", Panel.Refresh)
	end)
	frame, boxes = f, built
	return frame
end

ns.Listen("MAP_OVERLAY_DRAWN", function(_, stats)
	Panel.SetStats(stats)
end, "map panel")
