local _, ns = ...

local Sessions = ns.Module("Sessions")
ns.Sessions = Sessions

local floor = math.floor
local U = ns.U

Sessions.ASK_DELAY = 3
Sessions.UNMUTE_DELAY = 0.5
Sessions.UNMUTE_TIMEOUT = 10
Sessions.SAVE_EVERY = 60
Sessions.IDLE = 120
Sessions.GAP = 120

local active = false
local entry, prev
local startClock, startAt
local answered = false
local reason
local muted, unmuteTimer
local afk
local lastActive = 0
local away

local function core()
	return ns.Store.Core()
end

local function sessions()
	return U.TableAt(MemoriesCharDB, "sessions")
end

-- The account's computer id: 6 random hex digits, made once, so the converter can tell computers apart.
function Sessions.Computer()
	if type(MemoriesDB.computer) ~= "string" then
		MemoriesDB.computer = ("%06x"):format(math.random(0, 0xffffff))
	end
	return MemoriesDB.computer
end

-- Seconds that the client clock is ahead of UTC at t. Screenshot names use local time, so the converter needs it.
function Sessions.TimeZone(t)
	local l, u = date("*t", t), date("!*t", t)
	local days = l.yday - u.yday
	if l.year ~= u.year then
		days = l.year > u.year and 1 or -1
	end
	return ((days * 24 + l.hour - u.hour) * 60 + l.min - u.min) * 60
end

function Sessions.Current()
	return entry
end

local function unmute()
	if unmuteTimer then
		unmuteTimer:Cancel()
		unmuteTimer = nil
	end
	for _, frame in ipairs(muted or {}) do
		frame:RegisterEvent("TIME_PLAYED_MSG")
	end
	muted = nil
end

-- One timer at a time: a new request replaces the unmute of an earlier answer, so its own answer stays muted.
local function unmuteIn(delay)
	if unmuteTimer then
		unmuteTimer:Cancel()
	end
	unmuteTimer = C_Timer.NewTimer(delay, function()
		ns.Safe("sessions:unmute", unmute)
	end)
end

-- The chat frames print every answer, so they stop listening while the addon asks.
local function mute()
	if type(CHAT_FRAMES) ~= "table" then
		return
	end
	if not muted then
		muted = {}
		for _, name in ipairs(CHAT_FRAMES) do
			local frame = _G[name]
			if type(frame) == "table" and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
				frame:UnregisterEvent("TIME_PLAYED_MSG")
				muted[#muted + 1] = frame
			end
		end
	end
	unmuteIn(Sessions.UNMUTE_TIMEOUT)
end

-- why is "login", "ding" or "dev". It belongs to the next answer only.
function Sessions.RequestPlayed(why)
	reason = why
	mute()
	RequestTimePlayed()
end

function Sessions.Away()
	return away
end

function Sessions.CheckAway()
	local state
	if afk then
		state = "afk"
	elseif GetTime() - lastActive >= Sessions.IDLE then
		state = "idle"
	end
	if state ~= away then
		away = state
		ns.Emit("AWAY_CHANGED", state ~= nil, state)
	end
	return away
end

function Sessions.MarkActive()
	lastActive = GetTime()
	if away == "idle" then
		Sessions.CheckAway()
	end
end

local function save()
	if not entry then
		return
	end
	entry.last = time()
	local played = ns.Store.PlayedNow()
	if played then
		entry.played1 = played
	end
end

-- Levels and a gap found by the first answer belong to the start of the load, with /played of that moment.
local function firstAnswer(total)
	local atLogin = floor(total - (GetTime() - startClock))
	local at = U.Copy(startAt)
	at.p = atLogin
	ns.Progress.CatchUp(ns.R(UnitLevel("player")), at)
	if prev and type(prev.played1) == "number" and atLogin - prev.played1 > Sessions.GAP then
		core():WriteAt(at, "gp", atLogin - prev.played1, type(prev.last) == "number" and prev.last or nil)
	end
end

local function onPlayed(_, total, levelSeconds)
	local why = reason
	reason = nil
	if muted then
		unmuteIn(Sessions.UNMUTE_DELAY)
	end
	total, levelSeconds = ns.RN(total, levelSeconds)
	if type(total) ~= "number" then
		return
	end
	ns.Store.SetPlayed(total)
	if entry then
		entry.played1 = floor(total)
		entry.played0 = entry.played0 or floor(total - (GetTime() - startClock))
	end
	ns.Progress.NotePlayed(total, levelSeconds)
	if not answered and entry then
		answered = true
		firstAnswer(total)
	end
	if why == "login" or why == "ding" then
		core():Write("pl", floor(total))
	end
end

local function readAfk()
	local v, secret = ns.R(UnitIsAFK("player"))
	if secret then
		return nil, true
	end
	return v == true, false
end

local function onFlags(_, unit)
	if unit ~= "player" then
		return
	end
	local now, secret = readAfk()
	if secret then
		return
	end
	if now ~= afk then
		afk = now
		core():Write("af", now)
		if not now then
			Sessions.MarkActive()
		end
	end
	Sessions.CheckAway()
end

local function readRules()
	local rules = C_GameRules
	if type(rules) ~= "table" then
		return
	end
	local flags = U.TableAt(MemoriesCharDB, "flags")
	for key, fn in pairs({ hardcore = rules.IsHardcoreActive, selfFoundAllowed = rules.IsSelfFoundAllowed }) do
		if type(fn) == "function" then
			local v = ns.R(fn())
			if type(v) == "boolean" then
				flags[key] = v
			end
		end
	end
end

-- The running entry stays the one this load updates; a restored list gets it back in place of its older copy.
local function adopt()
	local list = sessions()
	for i, e in ipairs(list) do
		if type(e) == "table" and e.start == entry.start and e.computer == entry.computer then
			list[i] = entry
			return
		end
	end
	list[#list + 1] = entry
end

local function start(isLogin, isReload)
	local how = (isReload and not isLogin) and "reload" or "login"
	local list = sessions()
	prev = type(list[#list]) == "table" and list[#list] or nil
	startClock = GetTime()
	startAt = ns.Here()
	local computer = Sessions.Computer()
	entry = { start = startAt.t, last = startAt.t, how = how, computer = computer, tz = Sessions.TimeZone(startAt.t) }
	list[#list + 1] = entry
	if how == "login" then
		ns.Store.EndFirstWait()
	end
	core():WriteAt(startAt, "in", how)
	if how == "login" then
		core():WriteAt(startAt, "pc", computer)
	end
	C_Timer.After(Sessions.ASK_DELAY, function()
		ns.Safe("sessions:played", Sessions.RequestPlayed, "login")
	end)
	C_Timer.NewTicker(Sessions.SAVE_EVERY, function()
		ns.Safe("sessions:save", save)
	end)
end

local function activity()
	Sessions.MarkActive()
end

-- Handlers register only once the core journal is open and writable: a stopped or read-only core records nothing.
function Sessions:OnLogin()
	if not core() or not core():CanWrite() then
		return
	end
	active = true
	lastActive = GetTime()
	afk = readAfk() == true
	readRules()
	ns.On("TIME_PLAYED_MSG", onPlayed, "sessions:played")
	ns.On("PLAYER_FLAGS_CHANGED", onFlags, "sessions:afk")
	ns.On("PLAYER_REGEN_DISABLED", activity, "sessions:active")
	ns.On("PLAYER_LOGOUT", function()
		core():Write("out")
		save()
	end, "sessions:logout")
	ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function()
		lastActive = GetTime()
		if away == "idle" then
			Sessions.CheckAway()
		end
	end, "sessions:active")
	ns.Listen("RESTORED", function(_, addon)
		if addon == ns.name and entry then
			adopt()
		end
	end, "sessions:restored")
end

function Sessions:OnEnterWorld(isLogin, isReload)
	if active and not entry then
		start(isLogin, isReload)
	end
end
