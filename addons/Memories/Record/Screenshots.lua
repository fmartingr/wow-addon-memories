local _, ns = ...

local Screenshots = ns.Module("Screenshots")
ns.Screenshots = Screenshots

-- Memories takes no screenshot itself, so every saved shot comes from the player or another addon such as Paparazzi.
Screenshots.BY_HAND = "by hand"

local EXTENSIONS = { jpeg = ".jpg", jpg = ".jpg", png = ".png", tga = ".tga" }

local function screenshotFormat()
	local value = ns.U.GetCVar("screenshotFormat")
	return value and value:lower()
end

-- The game names the file from the local clock when it saves it, with no way to ask for the name.
function Screenshots.FileName(t)
	return "WoWScrnShot_" .. date("%m%d%y_%H%M%S", t) .. (EXTENSIONS[screenshotFormat()] or "")
end

-- The file name and the line share one clock read, so both name the same second.
local function record()
	local j = ns.Store.Core()
	j:Count("screenshots", "shots")
	local at = ns.Here()
	j:WriteAt(at, "ss", Screenshots.BY_HAND, "ok", Screenshots.FileName(at.t))
end

function Screenshots:OnLogin()
	local j = ns.Store.Core()
	if not j or not j:CanWrite() then
		return
	end
	ns.On("SCREENSHOT_SUCCEEDED", record, "screenshots")
end
