local _, ns = ...

-- Builds the windows of Memories: a Blizzard panel frame that moves, stays on the screen and closes with Escape.
-- Each window calls Create on its first open.
local Window = {}
ns.Window = Window

-- The inset of ButtonFrameTemplate leaves room for tabs under the title. It fills the window here, as the inset of
-- BasicFrameTemplateWithInset does, so the content of a window has the same place with either template.
local function fillInset(frame)
	if frame.Inset and frame.Inset.ClearAllPoints then
		frame.Inset:ClearAllPoints()
		frame.Inset:SetPoint("TOPLEFT", 4, -24)
		frame.Inset:SetPoint("BOTTOMRIGHT", -6, 4)
	end
end

local function newFrame(name)
	local ok, frame = pcall(CreateFrame, "Frame", name, UIParent, "ButtonFrameTemplate")
	if ok and frame then
		if ButtonFrameTemplate_HidePortrait then
			pcall(ButtonFrameTemplate_HidePortrait, frame)
		end
		fillInset(frame)
		return frame
	end
	return CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
end

function Window.SetTitle(frame, text)
	if frame.SetTitle then
		frame:SetTitle(text)
	elseif frame.TitleText then
		frame.TitleText:SetText(text)
	end
end

function Window.Create(name, width, height, title)
	local frame = newFrame(name)
	frame:Hide()
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
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
	Window.SetTitle(frame, title)
	if type(UISpecialFrames) == "table" then
		local listed = false
		for _, special in ipairs(UISpecialFrames) do
			listed = listed or special == name
		end
		if not listed then
			table.insert(UISpecialFrames, name)
		end
	end
	return frame
end
