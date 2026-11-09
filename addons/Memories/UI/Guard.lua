local _, ns = ...

local L = ns.L

local Guard = {}
ns.Guard = Guard

local GUARD, RELOAD = "MEMORIES_GUARD", "MEMORIES_RELOAD"

local queue, queued = {}, {}
local showing
local restored = false

function Guard.Text(addon, rec)
	local stamp = type(rec.t) == "number" and date("%Y-%m-%d %H:%M", rec.t) or L["an unknown date"]
	return L["Memories: %s came back empty. A backup from %s has %s lines."]:format(addon, stamp, tostring(rec.lines))
end

local function showNext()
	if showing then
		return
	end
	local addon = table.remove(queue, 1)
	if not addon then
		if restored then
			restored = false
			StaticPopup_Show(RELOAD)
		end
		return
	end
	queued[addon] = nil
	local rec = ns.Backup.Record(addon)
	if not rec or not rec.hold then
		return showNext()
	end
	showing = addon
	-- With every popup slot taken nothing shows and the hold stays for the next login. The client cancels the popup
	-- first, which already moves the queue on; the check covers a refusal without that cancel.
	if not StaticPopup_Show(GUARD, Guard.Text(addon, rec), nil, addon) and showing == addon then
		showing = nil
		return showNext()
	end
end

-- The popup hides after its handler returns, so the next one shows on the next frame.
local function answered()
	showing = nil
	C_Timer.After(0, showNext)
end

function Guard.Restore(addon)
	local ok, err = ns.Backup.Restore(addon)
	if ok then
		restored = true
	else
		ns.Print(L["%s: the backup was not restored (%s). See /memories errors."]:format(addon, tostring(err)))
	end
	return ok
end

function Guard.StartFresh(addon)
	local rec = ns.Backup.Record(addon)
	if not rec or not rec.hold then
		return
	end
	rec.hold = nil
	local item = ns.Registry.Journal(addon)
	if item then
		item.journal:Write("nt", "started fresh", rec.lines)
	end
end

-- A journal that opens empty while its backup has lines holds that backup: no backup write replaces it until the
-- player answers. The hold is saved in the backup record, so it lasts through a logout without an answer.
function Guard.Check(addon, j)
	if not j:CanWrite() then
		return
	end
	local rec = ns.Backup.Record(addon)
	if not rec then
		return
	end
	if not rec.hold and not (j:LineCount() == 0 and type(rec.lines) == "number" and rec.lines > 0) then
		return
	end
	rec.hold = true
	if not queued[addon] and showing ~= addon then
		queued[addon] = true
		queue[#queue + 1] = addon
	end
	if ns.loggedIn then
		showNext()
	end
end

StaticPopupDialogs[GUARD] = {
	text = "%s",
	button1 = L["Restore"],
	button2 = L["Start fresh"],
	OnAccept = function(_, addon)
		ns.Safe("guard:restore", Guard.Restore, addon)
		answered()
	end,
	-- Only the button counts as an answer: a popup that another one replaces keeps the hold for the next login.
	OnCancel = function(_, addon, reason)
		if reason == "clicked" then
			ns.Safe("guard:fresh", Guard.StartFresh, addon)
		end
		answered()
	end,
	-- A popup hidden without a button or a cancel (another addon's StaticPopup_Hide) would leave the queue stuck. One
	-- hidden with its parent (Alt+Z) is still shown and comes back with the UI, so it still waits for an answer.
	OnHide = function(dialog, addon)
		if showing == addon and not dialog:IsShown() then
			answered()
		end
	end,
	timeout = 0,
	whileDead = 1,
}

StaticPopupDialogs[RELOAD] = {
	text = L["Memories: backup restored. Reload the UI now to save it?"],
	button1 = L["Reload"],
	button2 = L["Later"],
	OnAccept = function()
		ns.Safe("guard:reload", ns.Save.Now)
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

ns.Listen("JOURNAL_OPENED", function(_, addon, j)
	Guard.Check(addon, j)
end, "guard")

ns.Listen("LOGIN", showNext, "guard")
