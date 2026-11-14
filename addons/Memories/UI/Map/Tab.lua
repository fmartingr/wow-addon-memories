local _, ns = ...

local L = ns.L

-- The Journey button of the world map: a click opens the Journey window, or closes it. The button is a frame of this
-- addon. The game's tab list is read to place it, and never changed.
local Tab = {}
ns.MapTab = Tab

Tab.SIZE = 36
Tab.GAP = 4
Tab.DOCK_OFFSET = -60

local button

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

-- Puts the button under the last game tab, or on the right edge of the map when it has none.
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

-- The button is lit while the Journey window is open.
function Tab.Look()
	if button then
		button.selected:SetShown(ns.MapWindow.Shown())
	end
end

local function create()
	button = CreateFrame("Button", "MemoriesMapTab", WorldMapFrame)
	button:SetSize(Tab.SIZE, Tab.SIZE)
	button:SetClampedToScreen(true)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("CENTER")
	button.icon:SetSize(Tab.SIZE - 8, Tab.SIZE - 8)
	button.icon:SetTexture("Interface\\AddOns\\Memories\\assets\\icon")
	button.selected = button:CreateTexture(nil, "OVERLAY")
	button.selected:SetAllPoints()
	button.selected:SetColorTexture(1, 0.82, 0, 0.3)
	button.selected:Hide()
	button:SetScript("OnClick", function()
		ns.Protect("map tab:click", ns.MapWindow.Toggle)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.JOURNEY)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	Tab.Place()
end

-- Adds the button to the world map once. It returns false while the map is missing.
function Tab.Attach()
	if button then
		return true
	end
	if type(WorldMapFrame) ~= "table" or type(CreateFrame) ~= "function" then
		return false
	end
	create()
	-- The quest log can show or hide while the map is open, and the button follows its tabs. HookScript runs after the
	-- game's own script and changes nothing in it.
	for _, owner in ipairs({ WorldMapFrame, QuestMapFrame }) do
		if type(owner) == "table" and owner.HookScript then
			for _, script in ipairs(owner == WorldMapFrame and { "OnShow" } or { "OnShow", "OnHide" }) do
				owner:HookScript(script, function()
					ns.Protect("map tab:place", Tab.Place)
				end)
			end
		end
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
