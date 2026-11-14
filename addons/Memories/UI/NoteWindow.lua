local _, ns = ...

local L = ns.L

-- The window where the player writes a note for the journey. A shift-click or a drag puts a link to an item or a quest
-- in the text as a token (see Record/Notes.lua).
local NoteWindow = {}
ns.NoteWindow = NoteWindow

local Notes = ns.Notes

local frame, edit, counter, save
-- True while the player writes in the box. A shift-click on a link makes the game open the chat box, which takes the
-- focus before the hook runs, so the flag stays up until the next frame.
local typing = false

local function reasonText(why)
	if why == "empty" then
		return L["the note is empty."]
	elseif why == "off" then
		return L["notes are off in the settings."]
	end
	return L["the journal is read only; the note was not saved."]
end

local function refresh()
	local text = edit:GetText() or ""
	counter:SetText(("%d / %d"):format(#text, Notes.MAX))
	if #text >= Notes.MAX then
		counter:SetTextColor(1, 0.2, 0.2)
	else
		counter:SetTextColor(1, 1, 1)
	end
	save:SetEnabled(Notes.Clean(text) ~= "")
end

local function trySave()
	local line, why = Notes.Add(edit:GetText())
	if not line then
		ns.Print(reasonText(why))
		return
	end
	frame:Hide()
	ns.Print(L["note saved."])
end

-- Puts a token at the cursor when it fits in the bytes that are left.
local function insert(token)
	if #(edit:GetText() or "") + #token > Notes.MAX then
		ns.Print(L["the link does not fit in the note."])
		return false
	end
	edit:Insert(token)
	refresh()
	return true
end

local function onDrop()
	local kind, id, link = GetCursorInfo()
	if kind ~= "item" then
		return
	end
	local token = Notes.TokenFromLink(link) or Notes.ItemToken(id, "item " .. tostring(id))
	if token then
		insert(token)
		ClearCursor()
	end
end

local function create()
	frame = CreateFrame("Frame", "MemoriesNoteFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(420, 290)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	if UISpecialFrames then
		table.insert(UISpecialFrames, "MemoriesNoteFrame")
	end
	if frame.TitleText then
		frame.TitleText:SetText(L["Write a note"])
	end

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -30)
	scroll:SetPoint("BOTTOMRIGHT", -32, 96)
	edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(360)
	edit:SetMaxBytes(Notes.MAX)
	scroll:SetScrollChild(edit)
	edit:SetScript("OnEscapePressed", function()
		frame:Hide()
	end)
	edit:SetScript("OnTextChanged", refresh)
	edit:SetScript("OnEditFocusGained", function()
		typing = true
	end)
	edit:SetScript("OnEditFocusLost", function()
		C_Timer.After(0, function()
			typing = edit:HasFocus() == true
		end)
	end)
	edit:SetScript("OnReceiveDrag", onDrop)
	edit:SetScript("OnMouseUp", onDrop)
	-- The box is only as tall as its text, so the empty part of the scroll frame takes the click and the drop too.
	scroll:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)
	scroll:SetScript("OnReceiveDrag", onDrop)
	scroll:SetScript("OnMouseUp", onDrop)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOMLEFT", 14, 60)
	hint:SetWidth(392)
	hint:SetJustifyH("LEFT")
	hint:SetText(L["Line breaks become spaces. Shift-click an item or quest to link it."])
	counter = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	counter:SetPoint("BOTTOMRIGHT", -14, 42)

	save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	save:SetSize(100, 24)
	save:SetPoint("BOTTOMRIGHT", -14, 12)
	save:SetText(L["Save"])
	save:SetScript("OnClick", function()
		ns.Protect("notewindow:save", trySave)
	end)
	local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	cancel:SetSize(100, 24)
	cancel:SetPoint("RIGHT", save, "LEFT", -6, 0)
	cancel:SetText(L["Cancel"])
	cancel:SetScript("OnClick", function()
		frame:Hide()
	end)

	frame:SetScript("OnHide", function()
		typing = false
	end)
	frame:Hide()
end

-- A link that the player shift-clicked into the chat box of the slash command becomes a token. The colour of a link is
-- a hex "|cAARRGGBB" or a named "|cnIQ4:".
local function linksToTokens(text)
	text = text:gsub("|c[^|]*(|H.-|h%[.-%]|h)|r", "%1")
	return (
		text:gsub("|H(.-)|h(%[.-%])|h", function(target, name)
			return Notes.TokenFromLink("|H" .. target .. "|h" .. name .. "|h") or name
		end)
	)
end

-- An open call on a shown window with no text keeps the draft of the player.
function NoteWindow.Open(prefill)
	if not frame then
		create()
	end
	local text = type(prefill) == "string" and linksToTokens(prefill) or ""
	if not frame:IsShown() or text ~= "" then
		edit:SetText(text)
	end
	refresh()
	frame:Show()
	edit:SetFocus()
end

local function onInsertLink(link)
	if not (frame and frame:IsShown() and typing) then
		return
	end
	local token = Notes.TokenFromLink(link)
	if not token then
		return
	end
	insert(token)
	local chat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
	-- The chat box that the shift-click opened holds the link; it would come back on the next Enter.
	if chat and chat.GetText and chat:GetText() == link then
		chat:SetText("")
	end
	if chat and ChatEdit_DeactivateChat then
		ChatEdit_DeactivateChat(chat)
	end
	edit:SetFocus()
end

ns.Listen("LOGIN", function()
	ns.U.Hook(nil, "ChatEdit_InsertLink", onInsertLink, "notes:link")
end, "notewindow")

ns.Commands.Register("note", NoteWindow.Open, "write a note in the journey")
