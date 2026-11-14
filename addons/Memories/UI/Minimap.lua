local _, ns = ...

local L = ns.L

-- One LibDataBroker launcher drives the minimap button and the addon compartment entry, through LibDBIcon.
local Minimap = {}
ns.Minimap = Minimap

Minimap.NAME = "Memories"
local ICON = "Interface\\AddOns\\Memories\\Media\\icon"
local GLOW = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
-- One full fade in and out every 1.5 s.
local PULSE_HALF = 0.75

function Minimap.OnClick(_, which)
	if which == "RightButton" then
		ns.Options.Open()
	elseif IsShiftKeyDown() then
		ns.Save.Now()
	else
		ns.NoteWindow.Open()
	end
end

function Minimap.OnTooltipShow(tooltip)
	tooltip:AddLine("Memories")
	tooltip:AddLine(L["%d min since the last save"]:format(math.floor(ns.Save.Age() / 60)), 1, 1, 1)
	tooltip:AddLine(L["Left click: write a note"])
	tooltip:AddLine(L["Shift + left click: save (reload)"])
	tooltip:AddLine(L["Right click: settings"])
	tooltip:AddLine(L["Drag: move the button"])
end

-- LibDBIcon writes the position into its table. A MemoriesDB from a newer Memories is never written, so it gets a
-- copy for the session. minimap.angle is the position of the button of Memories 0.4.0 and earlier, in the same degrees
-- as minimapPos.
function Minimap.IconDB()
	local db
	if ns.Store.ReadOnlyAll() then
		local saved = type(MemoriesDB.minimap) == "table" and MemoriesDB.minimap or {}
		db = { minimapPos = saved.minimapPos or saved.angle }
	else
		db = ns.U.TableAt(MemoriesDB, "minimap")
		if db.minimapPos == nil then
			db.minimapPos = db.angle
		end
		db.angle = nil
	end
	if type(db.minimapPos) ~= "number" then
		db.minimapPos = nil
	end
	db.hide = not ns.Settings.Get("minimapButton")
	return db
end

function Minimap.Register()
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	local icon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not ldb or not icon then
		return false
	end
	local object = ldb:NewDataObject(Minimap.NAME, {
		type = "launcher",
		icon = ICON,
		OnClick = function(frame, which)
			ns.Safe("minimap:click", Minimap.OnClick, frame, which)
		end,
		OnTooltipShow = function(tooltip)
			ns.Safe("minimap:tooltip", Minimap.OnTooltipShow, tooltip)
		end,
	})
	Minimap.icon = icon
	Minimap.db = Minimap.IconDB()
	icon:Register(Minimap.NAME, object, Minimap.db)
	icon:AddButtonToCompartment(Minimap.NAME)
	return true
end

function Minimap.Button()
	return Minimap.icon and Minimap.icon:GetMinimapButton(Minimap.NAME)
end

local function glow(button)
	if button.memoriesGlow then
		return button.memoriesGlow
	end
	local texture = button:CreateTexture(nil, "OVERLAY")
	texture:SetTexture(GLOW)
	texture:SetAllPoints()
	texture:SetBlendMode("ADD")
	texture:Hide()
	local group = texture:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local alpha = group:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(PULSE_HALF)
	texture.pulse = group
	button.memoriesGlow = texture
	return texture
end

function Minimap.Pulse(on)
	local button = Minimap.Button()
	if not button then
		return
	end
	local texture = glow(button)
	texture:SetShown(on == true)
	if on then
		texture.pulse:Play()
	else
		texture.pulse:Stop()
	end
end

function Minimap.Apply(shown)
	if not Minimap.icon then
		return
	end
	Minimap.db.hide = not shown
	if shown then
		Minimap.icon:Show(Minimap.NAME)
	else
		Minimap.icon:Hide(Minimap.NAME)
	end
end

function Minimap.Toggle()
	local shown = not ns.Settings.Get("minimapButton")
	ns.Settings.Set("minimapButton", shown)
	ns.Print(shown and L["Minimap button shown."] or L["Minimap button hidden."])
end

ns.Slash.Add("minimap", Minimap.Toggle, L["show or hide the minimap button"])
ns.Listen("LOGIN", Minimap.Register, "minimap")
ns.Listen("SAVE_REMINDER", function()
	Minimap.Pulse(true)
end, "minimap")
-- LibDBIcon reads minimap.hide; the minimapButton setting decides it.
ns.Listen("SETTING_CHANGED", function(_, path, value)
	if path == "minimapButton" then
		Minimap.Apply(value)
	end
end, "minimap")
