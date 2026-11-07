local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

MinimapButton.DEFAULT_ANGLE = 225
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

local button
-- A MemoriesDB from a newer Memories is never written, so the angle lives in memory for the session, starting from
-- the saved one.
local sessionOnly

local function saved()
	local t
	if ns.Store.ReadOnlyAll() then
		if not sessionOnly then
			local stored = type(MemoriesDB.minimap) == "table" and MemoriesDB.minimap or {}
			sessionOnly = { angle = stored.angle }
		end
		t = sessionOnly
	else
		t = ns.U.TableAt(MemoriesDB, "minimap")
	end
	if type(t.angle) ~= "number" then
		t.angle = MinimapButton.DEFAULT_ANGLE
	end
	return t
end

-- Puts the button on the minimap edge at angle, in degrees counter-clockwise from the right.
local function place(angle)
	local rad = math.rad(angle)
	local radius = Minimap:GetWidth() / 2 + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

-- The cursor position is in screen pixels, the minimap center in its own scaled units.
function MinimapButton.Drag()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local t = saved()
	t.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	place(t.angle)
end

function MinimapButton.Tooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText("Memories")
	GameTooltip:AddLine(("%d min since the last save"):format(math.floor(ns.Save.Age() / 60)), 1, 1, 1)
	GameTooltip:AddLine("Left click: save (reload)")
	GameTooltip:AddLine("Right click: settings")
	GameTooltip:Show()
end

local function pulse(self)
	-- One full fade in and out every 1.5 s.
	self.glow:SetAlpha(0.5 + 0.5 * math.sin(GetTime() * math.pi * 4 / 3))
end

function MinimapButton.Pulse(on)
	if not button then
		return
	end
	button.pulsing = on == true
	button.glow:SetShown(button.pulsing)
	-- A drag owns OnUpdate until it stops; OnDragStop sets the pulse again.
	if not button.dragging then
		button:SetScript("OnUpdate", button.pulsing and pulse or nil)
	end
end

function MinimapButton.Refresh()
	if button then
		button:SetShown(ns.Settings.Get("minimapButton"))
	end
end

function MinimapButton.Create()
	if button then
		return button
	end
	button = CreateFrame("Button", "MemoriesMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture(ICON)
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 7, -5)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	local glow = button:CreateTexture(nil, "OVERLAY")
	glow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	glow:SetAllPoints()
	glow:Hide()
	button.glow = glow

	button:SetScript("OnClick", function(_, which)
		ns.Safe("minimap:click", ns.Save.Click, which)
	end)
	button:SetScript("OnEnter", function(self)
		ns.Safe("minimap:tooltip", MinimapButton.Tooltip, self)
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:SetScript("OnUpdate", function()
			ns.Safe("minimap:drag", MinimapButton.Drag)
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self.dragging = false
		MinimapButton.Pulse(self.pulsing)
	end)

	place(saved().angle)
	MinimapButton.Refresh()
	return button
end

ns.Listen("LOGIN", MinimapButton.Create, "minimap")
ns.Listen("SAVE_REMINDER", function()
	MinimapButton.Pulse(true)
end, "minimap")
ns.Listen("SETTING_CHANGED", function(_, path)
	if path == "minimapButton" then
		MinimapButton.Refresh()
	end
end, "minimap")
