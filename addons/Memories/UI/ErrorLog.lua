local _, ns = ...

local L = ns.L

-- /memories errors: the saved error log in a box, ready to copy.
local ErrorLog = {}
ns.ErrorLog = ErrorLog

function ErrorLog.Text()
	local lines = {}
	-- Entries come from the saved file, which a user can edit by hand.
	for _, e in ipairs(ns.Errors()) do
		if type(e) == "table" then
			-- date returns nil for a time out of range.
			local stamp = type(e.t) == "number" and date("%Y-%m-%d %H:%M:%S", e.t) or L["unknown time"]
			lines[#lines + 1] = stamp .. "  " .. tostring(e.where) .. ": " .. tostring(e.msg)
			if e.stack then
				lines[#lines + 1] = tostring(e.stack)
			end
		end
	end
	return table.concat(lines, "\n")
end

local box

local function errorBox()
	if box then
		return box
	end
	box = CreateFrame("Frame", "MemoriesErrorsFrame", UIParent, "BasicFrameTemplateWithInset")
	box:SetSize(640, 420)
	box:SetPoint("CENTER")
	box:SetFrameStrata("DIALOG")
	if UISpecialFrames then
		table.insert(UISpecialFrames, "MemoriesErrorsFrame")
	end
	if box.TitleText then
		box.TitleText:SetText(L["Memories errors"])
	end
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -30)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(590)
	edit:SetScript("OnEscapePressed", function()
		box:Hide()
	end)
	scroll:SetScrollChild(edit)
	box.EditBox = edit
	return box
end

function ErrorLog.Show()
	local text = ErrorLog.Text()
	if text == "" then
		ns.Print(L["no saved errors."])
		return
	end
	local f = errorBox()
	-- An EditBox reads "|" as an escape code; "||" shows and copies as one "|".
	f.EditBox:SetText((text:gsub("|", "||")))
	f:Show()
	f.EditBox:SetFocus()
	f.EditBox:HighlightText()
end

ns.Commands.Register("errors", ErrorLog.Show, "show the saved errors, ready to copy")
