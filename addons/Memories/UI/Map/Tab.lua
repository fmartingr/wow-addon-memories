local _, ns = ...

local L = ns.L

-- The Journey tab of the world map. The tab and the panel are frames of this addon: the game's tab list is read and
-- never changed. A click on a game tab turns the overlay off.
local Tab = {}
ns.MapTab = Tab

Tab.SIZE = 36
Tab.GAP = 4
Tab.DOCK_OFFSET = -60
-- The quest log nests its rows several levels deep, and the panel must lie over all of them to take their clicks.
Tab.LEVEL_ABOVE_LOG = 100

local button
local hookGameTabs
local selected = false
local hooked = {}

function Tab.Selected()
	return selected
end

function Tab.Button()
	return button
end

-- The tab buttons of the quest log, read only.
local function gameTabs()
	local out = {}
	local log = QuestMapFrame
	if type(log) ~= "table" then
		return out
	end
	if type(log.TabButtons) == "table" then
		for _, tab in ipairs(log.TabButtons) do
			out[#out + 1] = tab
		end
	else
		for _, key in ipairs({ "QuestsTab", "EventsTab", "MapLegendTab" }) do
			if type(log[key]) == "table" then
				out[#out + 1] = log[key]
			end
		end
	end
	return out
end

local function logShown()
	return type(QuestMapFrame) == "table" and QuestMapFrame.IsShown and QuestMapFrame:IsShown() and true or false
end

-- The shown game tab that is lowest in the side column, else nil. Before the game lays the tabs out they have no
-- bottom, and the last one of the list stands for the lowest.
local function lastTab()
	if type(QuestMapFrame) == "table" and not logShown() then
		return nil
	end
	local last, lowest
	for _, tab in ipairs(gameTabs()) do
		if tab.IsShown and tab:IsShown() then
			local bottom = tab.GetBottom and tab:GetBottom()
			if bottom then
				if not lowest or bottom < lowest then
					last, lowest = tab, bottom
				end
			elseif not lowest then
				last = tab
			end
		end
	end
	return last
end

-- Puts the tab under the last game tab, or on the right edge of the map when it has none.
function Tab.Place()
	if not button then
		return
	end
	button:ClearAllPoints()
	local last = lastTab()
	if last then
		button:SetPoint("TOP", last, "BOTTOM", 0, -Tab.GAP)
	else
		button:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 0, Tab.DOCK_OFFSET)
	end
end

-- The panel takes the place of the quest log when it is shown, else it docks beside the map.
local function dock(panel)
	panel:ClearAllPoints()
	if logShown() then
		panel:SetAllPoints(QuestMapFrame)
		panel:SetFrameLevel((QuestMapFrame:GetFrameLevel() or 1) + Tab.LEVEL_ABOVE_LOG)
	else
		panel:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", Tab.SIZE + Tab.GAP, 0)
		panel:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", Tab.SIZE + Tab.GAP, 0)
	end
end

local function look()
	if button then
		button.selected:SetShown(selected)
	end
end

-- Turns the Journey view on or off. save keeps the choice as the tab the map opens on. The state changes only once the
-- panel is in place, so a failed build leaves the tab off.
function Tab.Select(on, save)
	on = on == true
	local panel = ns.MapPanel.Frame()
	if on then
		ns.Safe("map tab:hooks", hookGameTabs)
		panel = ns.MapPanel.Create(WorldMapFrame)
		dock(panel)
		panel:Show()
	elseif panel then
		panel:Hide()
	end
	selected = on
	ns.Overlay.Show(selected)
	look()
	if save ~= false then
		ns.Settings.Set("map.tab", selected and "journey" or "quest")
	end
end

-- A click on a game tab makes it the tab the map opens on, even when the game left Journey before this hook ran.
local function onGameTab()
	if selected then
		Tab.Select(false)
	else
		ns.Settings.Set("map.tab", "quest")
	end
end

-- The game also changes the display mode on its own, such as to show a quest, so the saved tab stays as it is.
local function onDisplayMode()
	if selected then
		Tab.Select(false, false)
	end
end

local function create()
	button = CreateFrame("Button", "MemoriesMapTab", WorldMapFrame)
	button:SetSize(Tab.SIZE, Tab.SIZE)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("CENTER")
	button.icon:SetSize(Tab.SIZE - 8, Tab.SIZE - 8)
	button.icon:SetTexture("Interface\\AddOns\\Memories\\Media\\icon")
	button.selected = button:CreateTexture(nil, "OVERLAY")
	button.selected:SetAllPoints()
	button.selected:SetColorTexture(1, 0.82, 0, 0.3)
	button.selected:Hide()
	button:SetScript("OnClick", function()
		ns.Safe("map tab:click", Tab.Select, not selected)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Journey"])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	Tab.Place()
end

-- The quest log can show or hide while the map is open, so the tab and the panel follow it.
local function follow()
	Tab.Place()
	local panel = ns.MapPanel.Frame()
	if selected and panel then
		dock(panel)
	end
end

-- A click on a game tab leaves the Journey view, and the quest log moves the tab and the panel as it shows or hides.
-- HookScript runs after the game's own script and changes nothing in it. Each map show hooks again what came since.
function hookGameTabs()
	local log = QuestMapFrame
	if type(log) == "table" and not hooked[log] and log.HookScript then
		for _, script in ipairs({ "OnShow", "OnHide" }) do
			log:HookScript(script, function()
				ns.Safe("map tab:quest log", follow)
			end)
		end
		hooked[log] = true
	end
	for _, tab in ipairs(gameTabs()) do
		if not hooked[tab] and tab.HookScript and tab.HasScript then
			-- A side tab can be a plain frame that switches the mode on a mouse up inside it, with no OnClick script.
			if tab:HasScript("OnClick") then
				tab:HookScript("OnClick", function()
					ns.Safe("map tab:game tab", onGameTab)
				end)
			elseif tab:HasScript("OnMouseUp") then
				tab:HookScript("OnMouseUp", function(_, mouse, upInside)
					if mouse == "LeftButton" and upInside ~= false then
						ns.Safe("map tab:game tab", onGameTab)
					end
				end)
			end
			hooked[tab] = true
		end
	end
end

-- The map opens on the tab that was used last. The quest log can change while the map is closed, so the tab and an open
-- panel take their places again.
function Tab.Restore()
	follow()
	ns.Safe("map tab:hooks", hookGameTabs)
	if ns.Settings.Get("map.tab") == "journey" and not selected then
		Tab.Select(true, false)
	end
end

-- Adds the tab to the map once. It returns false while the map is missing.
function Tab.Attach()
	if button then
		return true
	end
	if type(WorldMapFrame) ~= "table" or type(CreateFrame) ~= "function" then
		return false
	end
	create()
	if WorldMapFrame.HookScript then
		WorldMapFrame:HookScript("OnShow", function()
			ns.Safe("map tab:show", Tab.Restore)
		end)
	end
	if type(EventRegistry) == "table" and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("QuestLog.SetDisplayMode", function()
			ns.Safe("map tab:display mode", onDisplayMode)
		end, Tab)
	end
	if WorldMapFrame:IsShown() then
		Tab.Restore()
	end
	return true
end

ns.Listen("LOGIN", function()
	if not Tab.Attach() then
		local handle
		handle = ns.On("ADDON_LOADED", function(_, name)
			if name == "Blizzard_WorldMap" and Tab.Attach() then
				ns.Off("ADDON_LOADED", handle)
			end
		end, "map tab")
	end
end, "map tab")
