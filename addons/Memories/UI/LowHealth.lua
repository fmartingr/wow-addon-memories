local _, ns = ...

local L = ns.L

-- Close calls need the client's low-health flash, since the player's health is always secret. The flash is the account
-- CVar doNotFlashLowHealthWarning: "0" flashes (the client default), "1" does not. It is the only CVar Memories
-- changes, and only on the player's click.
local LowHealth = {}
ns.LowHealth = LowHealth

LowHealth.CVAR = "doNotFlashLowHealthWarning"
local CVAR = LowHealth.CVAR
local POPUP = "MEMORIES_LOW_HEALTH"

LowHealth.TITLE = L["Memories needs this setting on"]
LowHealth.BODY =
	L["Memories needs the low-health flash to record close calls. With it off, close calls are not counted."]

local dialog
-- The value of our own CVar write, so its CVAR_UPDATE is no change by the player.
local expect
-- True while LowHealth saves the setting, so SETTING_CHANGED does not take it for a click on the Settings page.
local saving = false
local entered = false

local function save(on)
	saving = true
	ns.Settings.Set("lowHealthFlash", on)
	saving = false
end

-- A CVar that cannot be read leaves the answer to the setting.
function LowHealth.IsOn()
	local v = ns.U.GetCVar(CVAR)
	if v == nil then
		return ns.Settings.Get("lowHealthFlash") == true
	end
	return v ~= "1"
end

function LowHealth.Set(on)
	local value = on and "0" or "1"
	local set = ns.U.CVarApi("SetCVar")
	expect = value
	-- C_CVar.SetCVar answers false for a refused write instead of raising.
	local ok, res = pcall(set, CVAR, value)
	if not ok or res == false then
		expect = nil
		ns.LogError("low health:cvar", ok and "SetCVar refused " .. value or res, nil, true)
	end
	save(on == true)
	LowHealth.Hide()
end

function LowHealth.Ask()
	if dialog then
		return
	end
	dialog = StaticPopup_Show(POPUP)
end

-- The untick of the option: the flash stays on until a button of the popup is pressed.
function LowHealth.RequestOff()
	save(true)
	LowHealth.Ask()
end

function LowHealth.Hide()
	if dialog then
		dialog = nil
		StaticPopup_Hide(POPUP)
	end
end

function LowHealth.Shown()
	return dialog ~= nil
end

StaticPopupDialogs[POPUP] = {
	text = "|cffffd100" .. LowHealth.TITLE .. "|r\n\n" .. LowHealth.BODY,
	button1 = L["Keep it on"],
	button2 = L["Turn it off"],
	OnAccept = function()
		ns.Safe("low health:on", LowHealth.Set, true)
	end,
	OnCancel = function(_, _, reason)
		if reason == "clicked" then
			ns.Safe("low health:off", LowHealth.Set, false)
		end
	end,
	OnHide = function()
		dialog = nil
	end,
	timeout = 0,
	whileDead = 1,
}

ns.On("CVAR_UPDATE", function(_, name, value)
	if name ~= CVAR then
		return
	end
	value = ns.R(value)
	local mine = expect ~= nil and expect == value
	expect = nil
	if mine then
		return
	end
	if value == "1" then
		LowHealth.Ask()
	elseif value == "0" then
		save(true)
		LowHealth.Hide()
	end
end, "low health")

ns.On("PLAYER_ENTERING_WORLD", function()
	if entered then
		return
	end
	entered = true
	local on = LowHealth.IsOn()
	if ns.Settings.Get("lowHealthFlash") ~= on then
		save(on)
	end
	if not on then
		-- The flash can come back on during the fight.
		ns.AfterCombat("low health", function()
			if not LowHealth.IsOn() then
				LowHealth.Ask()
			end
		end)
	end
end, "low health")

-- A click on the option of the Settings page arrives here as a changed setting.
ns.Listen("SETTING_CHANGED", function(_, path, value)
	if path ~= "lowHealthFlash" or saving then
		return
	end
	if value then
		LowHealth.Set(true)
	else
		LowHealth.RequestOff()
	end
end, "low health")
