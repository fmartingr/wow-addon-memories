local _, ns = ...

local Screenshots = ns.Module("Screenshots")
ns.Screenshots = Screenshots

Screenshots.WAIT = 10
Screenshots.LEVEL_DELAY = 1.5
Screenshots.BY_HAND = "by hand"

local EXTENSIONS = { jpeg = ".jpg", jpg = ".jpg", png = ".png", tga = ".tga" }

local active = false
-- Shots that wait for the game's answer, oldest first: { why, clock }. An empty why is a silent shot.
local waiting = {}

local function core()
	return ns.Store.Core()
end

local function screenshotFormat()
	local value = ns.U.GetCVar("screenshotFormat")
	return value and value:lower()
end

-- The game names the file from the local clock when it saves it, with no way to ask for the name.
function Screenshots.FileName(t)
	return "WoWScrnShot_" .. date("%m%d%y_%H%M%S", t) .. (EXTENSIONS[screenshotFormat()] or "")
end

-- The file name and the line share one clock read, so both name the same second.
local function record(why, ok)
	local j = core()
	j:Count("screenshots", ok and "shots" or "shotsFailed")
	local at = ns.Here()
	j:WriteAt(at, "ss", why, ok and "ok" or "failed", ok and Screenshots.FileName(at.t) or nil)
end

local function prune()
	local now = GetTime()
	while waiting[1] and now - waiting[1].clock > Screenshots.WAIT do
		table.remove(waiting, 1)
	end
end

local function answer(ok)
	prune()
	local entry = table.remove(waiting, 1)
	if entry then
		if entry.why ~= "" then
			record(entry.why, ok)
		end
	elseif ok then
		record(Screenshots.BY_HAND, true)
	end
end

-- For a caller that calls Screenshot() itself: Expect right before the call, Cancel when the call fails. An empty why
-- is a silent shot that writes no line.
function Screenshots.Expect(why)
	assert(type(why) == "string", "screenshot why must be text")
	prune()
	local entry = { why = why, clock = GetTime() }
	waiting[#waiting + 1] = entry
	return entry
end

function Screenshots.Cancel(entry)
	for i, other in ipairs(waiting) do
		if other == entry then
			table.remove(waiting, i)
			return true
		end
	end
	return false
end

-- Takes a screenshot and records the game's answer under why, only while the player's setting is on. Returns false when
-- the setting is off, the core journal cannot write or the Screenshot() call raises.
function Screenshots.Take(why, setting)
	assert(type(why) == "string" and why ~= "", "screenshot why must be text")
	assert(type(setting) == "string", "screenshot setting must be named")
	if ns.Settings.Get(setting) ~= true or not active or not core():CanWrite() then
		return false
	end
	local entry = Screenshots.Expect(why)
	if not pcall(Screenshot) then
		Screenshots.Cancel(entry)
		record(why, false)
		return false
	end
	return true
end

local function onLevel(_, level)
	if ns.Settings.Get("shots.level") ~= true then
		return
	end
	-- Take reads the setting again after the delay, so a player who turns it off meanwhile gets no shot. Levels gained
	-- together share one shot with the last level, so no two shots wait for one answer.
	ns.Coalesce("screenshots:level", Screenshots.LEVEL_DELAY, function()
		Screenshots.Take("level " .. tostring(level), "shots.level")
	end)
end

function Screenshots:OnLogin()
	local j = core()
	if not j or not j:CanWrite() then
		return
	end
	active = true
	ns.On("SCREENSHOT_SUCCEEDED", function()
		answer(true)
	end, "screenshots")
	ns.On("SCREENSHOT_FAILED", function()
		answer(false)
	end, "screenshots")
	ns.Listen("LEVEL_UP", onLevel, "screenshots:level")
end
