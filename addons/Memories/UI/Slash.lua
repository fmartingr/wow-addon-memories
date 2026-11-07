local _, ns = ...

local Slash = { commands = {} }
ns.Slash = Slash

function Slash.Add(name, fn, help)
	name = name:lower()
	for _, c in ipairs(Slash.commands) do
		assert(c.name ~= name, "duplicate slash command " .. name)
	end
	Slash.commands[#Slash.commands + 1] = { name = name, fn = fn, help = help or "" }
end

function Slash.Help()
	ns.Print("commands:")
	for _, c in ipairs(Slash.commands) do
		DEFAULT_CHAT_FRAME:AddMessage("  /memories " .. c.name .. " - " .. c.help)
	end
end

function Slash.Run(msg)
	local name, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	name = name:lower()
	for _, c in ipairs(Slash.commands) do
		if c.name == name then
			ns.Safe("slash:" .. c.name, c.fn, rest)
			return
		end
	end
	Slash.Help()
end

function Slash.ErrorText()
	local lines = {}
	-- Entries come from the saved file, which a user can edit by hand.
	for _, e in ipairs(ns.Errors()) do
		if type(e) == "table" then
			-- date returns nil for a time out of range.
			local stamp = type(e.t) == "number" and date("%Y-%m-%d %H:%M:%S", e.t) or "unknown time"
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
		box.TitleText:SetText("Memories errors")
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

Slash.Add("errors", function()
	local text = Slash.ErrorText()
	if text == "" then
		ns.Print("no saved errors.")
		return
	end
	local f = errorBox()
	-- An EditBox reads "|" as an escape code; "||" shows and copies as one "|".
	f.EditBox:SetText((text:gsub("|", "||")))
	f:Show()
	f.EditBox:SetFocus()
	f.EditBox:HighlightText()
end, "show the saved errors, ready to copy")

SLASH_MEMORIES1 = "/memories"
SLASH_MEMORIES2 = "/mem"
SlashCmdList.MEMORIES = function(msg)
	ns.Safe("slash", Slash.Run, msg)
end

-- The right click of the minimap button and of the compartment entry. The Settings page replaces it.
function ns.OpenSettings()
	Slash.Help()
end

function Memories_OnAddonCompartmentClick(_, button)
	ns.Safe("compartment", ns.Save.Click, button)
end
