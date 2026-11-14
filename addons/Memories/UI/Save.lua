local _, ns = ...

local L = ns.L

-- The client writes the saved files only at logout or on a UI reload, so a reload is the save.
local Save = {}
ns.Save = Save

Save.REMIND_AFTER = 60 * 60
Save.CHECK_EVERY = 60

local since, ticker
local reminded = false

-- Seconds since the last save: the login or reload that started this session.
function Save.Age()
	return since and GetTime() - since or 0
end

function Save.Now()
	if InCombatLockdown() then
		ns.Print(L.CANNOT_SAVE_IN_COMBAT)
		return false
	end
	C_UI.Reload()
	return true
end

function Save.Check()
	if reminded or not ns.Settings.Get("saveReminder") or Save.Age() < Save.REMIND_AFTER then
		return
	end
	reminded = true
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	ns.Print(L.SAVE_DUE)
	ns.Emit("SAVE_REMINDER")
end

ns.Settings.AddToggle("saveReminder", "SAVE_REMINDER", "SAVE_REMINDER_TIP", true)

ns.Listen("LOGIN", function()
	since = GetTime()
	reminded = false
	ticker = C_Timer.NewTicker(Save.CHECK_EVERY, function()
		ns.Protect("save", Save.Check)
	end)
end, "save")
