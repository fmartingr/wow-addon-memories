local _, ns = ...

local L = ns.L

-- The Journey panel of the Journey window: a check box for each group of kinds and for the trail, the colour of the
-- trail, a list of chapters to jump to or of sessions to show, the counts of the last draw, and the Highlights feed
-- of the events that the replay passed. The player bar sits under the map: play and pause, the speed, a slider and
-- the clock of the replay. Both are plain frames, so they never taint a game frame.
local Panel = {}
ns.MapPanel = Panel

Panel.WIDTH = 270
Panel.ROW = 18
Panel.LIST_HEIGHT = 110
Panel.VISIBLE = math.ceil(Panel.LIST_HEIGHT / Panel.ROW) + 1
Panel.BOX = 22
-- The boxes sit in two columns, so the core and every sub-addon group still fit in the height of the map.
Panel.COLUMN = 125
Panel.BAR_WIDTH, Panel.BAR_HEIGHT = 520, 48
-- The panel and the bar sit this far above the window, over the levels of the map, its trail and its pins.
Panel.BAR_LEVEL = 500

local frame
local bar
local paintRows
local boxes = {}
local rows = {}
-- The rows of the list, and what the list shows: "chapters" or "sessions". The choice is not saved.
local items = {}
local listMode = "chapters"
local chapterNow
local feed = {}
Panel.FEED_SIZE = 6

function Panel.Frame()
	return frame
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
		ns.Protect("map panel:check", onClick, self:GetChecked() == true)
	end)
	return box
end

local COLOR_LABEL = { way = L.WAY, level = L.LEVEL, age = L.AGE }

local function colorText()
	return L.COLOR:format(COLOR_LABEL[ns.Settings.Get("map.color")] or "")
end

-- A click on the colour button goes to the next colour mode of the trail.
local function cycleColor()
	local modes = ns.Settings.COLORS
	local now = ns.Settings.Get("map.color")
	for i, mode in ipairs(modes) do
		if mode == now then
			ns.Settings.Set("map.color", modes[i % #modes + 1])
			break
		end
	end
	frame.color:SetText(colorText())
	ns.Overlay.Draw()
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

-- The row of the chapter that holds the playhead: the last one that starts at or before it.
local function chapterAt(at)
	local found
	for i, item in ipairs(items) do
		if item.chapter and item.c <= at then
			found = i
		end
	end
	return found
end

local function pick(item)
	-- A seek moves the mark of the chapter through the tick of the player bar.
	if item.chapter then
		ns.Overlay.Seek(item.c)
	else
		chooseSession(item.session)
	end
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
		ns.Protect("map panel:pick", pick, self.item)
	end)
	rows[slot] = button
	return button
end

local function marked(item, i)
	if item.chapter then
		return i == chapterNow
	end
	local chosen = ns.Overlay.Session()
	local session = item.session
	return session == chosen or (session ~= nil and chosen ~= nil and session.start == chosen.start)
end

-- A character can have thousands of sessions, so only the rows in view exist and they move with the scroll.
function paintRows()
	local n = #items
	local first = math.floor((frame.scroll:GetVerticalScroll() or 0) / Panel.ROW)
	local shown = math.max(0, math.min(Panel.VISIBLE, n - first))
	for slot = 1, shown do
		local i = first + slot
		local item = items[i]
		local button = row(slot)
		button.item = item
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 0, -(i - 1) * Panel.ROW)
		button.text:SetText(item.text)
		button.mark:SetShown(marked(item, i))
		button:Show()
	end
	for slot = shown + 1, #rows do
		rows[slot]:Hide()
	end
end

-- Builds the rows of the list. The chapters run from the start, and the sessions run from the newest, under the row
-- for all of them.
local function refreshList()
	items = {}
	if listMode == "sessions" then
		items[1] = { text = L.ALL }
		local sessions = ns.MapData.Sessions()
		for i = #sessions, 1, -1 do
			items[#items + 1] = { text = Panel.SessionText(sessions[i]), session = sessions[i] }
		end
	else
		for _, chapter in ipairs(ns.Overlay.Chapters()) do
			local text = chapter.level and L.LEVEL_N:format(chapter.level) or L.START
			items[#items + 1] = { text = text, chapter = true, c = chapter.c }
		end
		chapterNow = chapterAt((ns.Overlay.Position()))
	end
	frame.content:SetHeight(math.max(#items, 1) * Panel.ROW)
	paintRows()
	frame.chapters:SetEnabled(listMode ~= "chapters")
	frame.sessions:SetEnabled(listMode ~= "sessions")
end

local function setListMode(mode)
	listMode = mode
	refreshList()
end

-- The counts line from the stats of a draw.
function Panel.CountText(stats)
	local text = L.LINES_PINS:format(stats.lines, stats.pins)
	if stats.cutLines > 0 or stats.cutPins > 0 then
		text = text .. "\n" .. L.CUT_AT_LINES_AND_PINS:format(ns.Overlay.MAX_LINES, ns.Overlay.MAX_PINS)
	end
	if stats.zones > 0 then
		text = text .. "\n" .. L.ZONES_NOT_SHOWN:format(stats.zones)
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
	boxes.blind:SetChecked(ns.Settings.Get("map.colorblind") == true)
	frame.color:SetText(colorText())
	for group, box in pairs(boxes.groups) do
		box:SetChecked(filter.groups[group] == true)
	end
	refreshList()
	Panel.SetStats(ns.Overlay.Stats())
	Panel.UpdateBar()
end

function Panel.Bar()
	return bar
end

-- The level for the panel and the bar: above the map of the window, its trail and its pins, so they take the clicks.
function Panel.LevelOver(parent)
	return (parent:GetFrameLevel() or 1) + Panel.BAR_LEVEL
end

-- Sets the bar from the replay: the text of the play button, the speed, the slider and the clock.
function Panel.UpdateBar()
	if not bar then
		return
	end
	local at, total = ns.Overlay.Position()
	local ready = total > 0
	bar.play:SetText(ns.Overlay.Playing() and L.PAUSE or L.PLAY)
	bar.speed:SetText(ns.Overlay.Speed() .. "x")
	bar.play:SetEnabled(ready)
	bar.speed:SetEnabled(ready)
	bar.slider:SetEnabled(ready)
	bar.follow:SetChecked(ns.Settings.Get("map.follow") ~= false)
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
	if frame and listMode == "chapters" then
		local now = chapterAt(at)
		if now ~= chapterNow then
			chapterNow = now
			paintRows()
		end
	end
end

local function buildBar(parent)
	local b = CreateFrame("Frame", nil, parent)
	b:Hide()
	b:SetSize(Panel.BAR_WIDTH, Panel.BAR_HEIGHT)
	-- The level is set before the children exist, so they take theirs above it.
	b:SetFrameLevel(Panel.LevelOver(parent))
	b:EnableMouse(true)
	b:SetPoint("BOTTOM", parent, "BOTTOM", 0, 14)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0.05, 0.04, 0.03, 0.85)
	b.play = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.play:SetSize(76, 24)
	b.play:SetPoint("LEFT", 10, 0)
	b.play:SetScript("OnClick", function()
		ns.Protect("map panel:play", ns.Overlay.Toggle)
	end)
	b.speed = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.speed:SetSize(46, 24)
	b.speed:SetPoint("LEFT", b.play, "RIGHT", 4, 0)
	b.speed:SetScript("OnClick", function()
		ns.Protect("map panel:speed", ns.Overlay.CycleSpeed)
	end)
	b.follow = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
	b.follow:SetSize(22, 22)
	b.follow:SetPoint("LEFT", b.speed, "RIGHT", 8, 0)
	b.follow.label = b.follow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.follow.label:SetPoint("LEFT", b.follow, "RIGHT", 2, 0)
	b.follow.label:SetText(L.FOLLOW)
	b.follow:SetScript("OnClick", function(self)
		ns.Protect("map panel:follow", ns.Overlay.SetFollow, self:GetChecked() == true)
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
	b.slider:SetPoint("LEFT", b.follow.label, "RIGHT", 12, 0)
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
			ns.Protect("map panel:seek", ns.Overlay.Seek, value)
		end
	end)
	return b
end

local DETAIL = { "level", "name", "to", "dest", "area", "killer", "zone", "title", "from" }

-- The line of the feed for a pin: its icon, its kind name and its main field.
function Panel.HighlightText(pin)
	local spec = ns.Kinds.Get(pin.kind)
	local text = spec and spec.name or pin.kind
	for _, key in ipairs(DETAIL) do
		local value = pin.fields and pin.fields[key]
		if value ~= nil then
			text = text .. ": " .. tostring(value)
			break
		end
	end
	local icon = ns.MapIcons.Get(pin.kind) or ns.Overlay.GROUP_ICON[pin.group]
	return icon and ("|T%s:14|t %s"):format(icon, text) or text
end

local function paintFeed()
	if not frame then
		return
	end
	for i, line in ipairs(frame.feed) do
		line:SetText(feed[i] or "")
	end
end

-- The feed keeps the last FEED_SIZE events, newest first.
function Panel.Highlight(pin)
	table.insert(feed, 1, Panel.HighlightText(pin))
	feed[Panel.FEED_SIZE + 1] = nil
	paintFeed()
end

function Panel.ClearFeed()
	feed = {}
	paintFeed()
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
	-- The panel takes the clicks and the wheel, so none reaches the map under it.
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.05, 0.04, 0.03, 0.95)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.title:SetText(L.JOURNEY)
	-- Refresh sets each box from the settings when the panel shows.
	local built = { trail = check(f, L.TRAIL, 0, setter("map.trail")), groups = {} }
	local slot = 0
	for _, item in ipairs(ns.Overlay.GROUPS) do
		slot = slot + 1
		built.groups[item.group] = check(f, item.label, slot, setter("map.groups." .. item.group))
	end
	slot = slot + 1
	built.blind = check(f, L.COLORBLIND_PALETTE, slot, setter("map.colorblind"))
	f.color = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.color:SetSize(112, 20)
	f.color:SetPoint("TOPRIGHT", -14, -10)
	f.color:SetScript("OnClick", function()
		ns.Protect("map panel:color", cycleColor)
	end)
	local y = -40 - (math.floor(slot / 2) + 1) * Panel.BOX - 12
	f.chapters = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.chapters:SetSize(100, 20)
	f.chapters:SetPoint("TOPLEFT", 14, y)
	f.chapters:SetText(L.CHAPTERS)
	f.chapters:SetScript("OnClick", function()
		ns.Protect("map panel:chapters", setListMode, "chapters")
	end)
	f.sessions = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.sessions:SetSize(100, 20)
	f.sessions:SetPoint("LEFT", f.chapters, "RIGHT", 4, 0)
	f.sessions:SetText(L.SESSIONS)
	f.sessions:SetScript("OnClick", function()
		ns.Protect("map panel:sessions", setListMode, "sessions")
	end)
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 14, y - 24)
	scroll:SetSize(Panel.WIDTH - 50, Panel.LIST_HEIGHT)
	f.content = CreateFrame("Frame", nil, scroll)
	f.content:SetSize(Panel.WIDTH - 50, Panel.ROW)
	scroll:SetScrollChild(f.content)
	scroll:HookScript("OnVerticalScroll", function()
		ns.Protect("map panel:scroll", paintRows)
	end)
	f.scroll = scroll
	f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.count:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -10)
	f.count:SetWidth(Panel.WIDTH - 30)
	f.count:SetJustifyH("LEFT")
	f.feedTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.feedTitle:SetPoint("TOPLEFT", f.count, "BOTTOMLEFT", 0, -8)
	f.feedTitle:SetText(L.HIGHLIGHTS)
	f.feed = {}
	for i = 1, Panel.FEED_SIZE do
		local line = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line:SetPoint("TOPLEFT", i == 1 and f.feedTitle or f.feed[i - 1], "BOTTOMLEFT", 0, -3)
		line:SetWidth(Panel.WIDTH - 30)
		line:SetJustifyH("LEFT")
		f.feed[i] = line
	end
	local playerBar = buildBar(parent)
	f:SetScript("OnShow", function()
		local level = Panel.LevelOver(parent)
		f:SetFrameLevel(level)
		playerBar:SetFrameLevel(level)
		playerBar:Show()
		ns.Protect("map panel:show", Panel.Refresh)
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
	if frame and frame:IsShown() then
		-- Only the chapters depend on a draw. The sessions are many, so a draw only paints their rows again.
		ns.Protect("map panel:list", listMode == "chapters" and refreshList or paintRows)
	end
end, "map panel")

ns.Listen("MAP_REPLAY_EVENT", function(_, pin)
	Panel.Highlight(pin)
end, "map panel")

ns.Listen("MAP_REPLAY_RESET", Panel.ClearFeed, "map panel")

ns.Listen("MAP_REPLAY_CHANGED", Panel.UpdateBar, "map panel")
ns.Listen("MAP_REPLAY_TICK", function(_, at, total)
	Panel.Tick(at, total)
end, "map panel")
