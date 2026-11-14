local ADDON, ns = ...

local L = ns.L

ns.name = ADDON
ns.modules = {}
ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

-- The public table exists from the first core file on, so a sub-addon that loads right after the core finds it.
-- The registry checks ns.API_VERSION: any addon can change the fields of the public table.
ns.API_VERSION = 1
Memories = { API_VERSION = ns.API_VERSION, VERSION = ns.VERSION }
ns.Public = Memories

local MAX_ERRORS = 100
local PREFIX = "|cff9fd3ffMemories|r:"

local byName = {}

function ns.Module(name)
	assert(not byName[name], "duplicate module " .. tostring(name))
	local module = { name = name }
	byName[name] = module
	ns.modules[#ns.modules + 1] = module
	return module
end

function ns.GetModule(name)
	return byName[name]
end

function ns.Print(...)
	local parts = { PREFIX }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	DEFAULT_CHAT_FRAME:AddMessage(table.concat(parts, " "))
end

-- Errors logged before MemoriesDB exists wait here until ns.Errors() moves them.
local pending = {}
local reported = {}

-- The key names the failed feature and err is the Lua error, so a player report says what broke without a debugger.
function ns.ReportOnce(key, msg, err)
	if reported[key] then
		return false
	end
	reported[key] = true
	if err ~= nil then
		ns.Print(("%s [%s: %s]"):format(msg, key, tostring(err)))
	else
		ns.Print(("%s [%s]"):format(msg, key))
	end
	return true
end

local function push(list, entry)
	list[#list + 1] = entry
	while #list > MAX_ERRORS do
		table.remove(list, 1)
	end
end

function ns.Errors()
	if type(MemoriesDB) ~= "table" then
		return pending
	end
	if type(MemoriesDB.errors) ~= "table" then
		MemoriesDB.errors = {}
	end
	local list = MemoriesDB.errors
	for i = 1, #pending do
		push(list, pending[i])
	end
	pending = {}
	return list
end

-- quiet saves the error for /memories errors without a chat line or the client's error handler. msg is the chat
-- line: L.HOOK_FAILED unless the caller names another one.
function ns.LogError(where, err, stack, quiet, msg)
	where = tostring(where)
	local entry = { t = time(), where = where, msg = tostring(err), stack = stack }
	push(ns.Errors(), entry)
	if quiet then
		return
	end
	ns.ReportOnce(where, msg or L.HOOK_FAILED, entry.msg)
	local handler = geterrorhandler and geterrorhandler()
	if handler then
		pcall(handler, entry.msg)
	end
end

local function capture(err)
	return { err = err, stack = debugstack and debugstack(2) or nil }
end

-- Runs fn and logs its error; msg is the chat line (see ns.LogError). Returns true and the first 4 results of fn.
function ns.ProtectWith(msg, where, fn, ...)
	local n = select("#", ...)
	local args = { ... }
	local ok, a, b, c, d = xpcall(function()
		return fn(unpack(args, 1, n))
	end, capture)
	if not ok then
		-- When capture itself fails, xpcall returns a plain message instead of its table.
		if type(a) ~= "table" then
			a = { err = a }
		end
		ns.LogError(where, a.err, a.stack, false, msg)
		return false
	end
	return true, a, b, c, d
end

function ns.Protect(where, fn, ...)
	return ns.ProtectWith(nil, where, fn, ...)
end

-- Lists are replaced, never changed in place, so a dispatch that is running keeps the list it started with.
local function add(map, key, handle)
	local list = map[key] or {}
	local copy = { unpack(list) }
	copy[#copy + 1] = handle
	map[key] = copy
end

local function remove(map, key, handle)
	local list = map[key]
	if not list then
		return false
	end
	local copy = {}
	for _, h in ipairs(list) do
		if h ~= handle then
			copy[#copy + 1] = h
		end
	end
	map[key] = #copy > 0 and copy or nil
	return #copy == 0
end

local function dispatch(list, name, ...)
	if not list then
		return
	end
	for i = 1, #list do
		ns.Protect(list[i].where, list[i].fn, name, ...)
	end
end

local frame = CreateFrame("Frame")
local listeners = {}
local refused = {}

frame:SetScript("OnEvent", function(_, event, ...)
	dispatch(listeners[event], event, ...)
end)

function ns.On(event, fn, where)
	if refused[event] then
		return nil
	end
	if not listeners[event] then
		local ok, err = pcall(frame.RegisterEvent, frame, event)
		if not ok then
			refused[event] = true
			ns.LogError(where or event, err)
			return nil
		end
	end
	local handle = { fn = fn, where = where or event }
	add(listeners, event, handle)
	return handle
end

function ns.Off(event, handle)
	if remove(listeners, event, handle) then
		frame:UnregisterEvent(event)
	end
end

-- RegisterUnitEvent filters a whole frame, so the core keeps one frame for each unit. The client then sends it only
-- the events of that unit, and a crowded place costs nothing.
local unitFrames, unitListeners = {}, {}

local function unitFrame(unit)
	if not unitFrames[unit] then
		local map = {}
		local f = CreateFrame("Frame")
		f:SetScript("OnEvent", function(_, event, ...)
			dispatch(map[event], event, ...)
		end)
		unitFrames[unit], unitListeners[unit] = f, map
	end
	return unitFrames[unit], unitListeners[unit]
end

function ns.OnUnit(event, unit, fn, where)
	local key = event .. ":" .. tostring(unit)
	if refused[key] then
		return nil
	end
	local f, map = unitFrame(unit)
	if not map[event] then
		local ok, err = pcall(f.RegisterUnitEvent, f, event, unit)
		if not ok then
			refused[key] = true
			ns.LogError(where or event, err)
			return nil
		end
	end
	local handle = { fn = fn, where = where or event }
	add(map, event, handle)
	return handle
end

local messages = {}

function ns.Listen(msg, fn, where)
	local handle = { fn = fn, where = where or msg }
	add(messages, msg, handle)
	return handle
end

function ns.Listening(msg)
	return messages[msg] ~= nil
end

function ns.Emit(msg, ...)
	dispatch(messages[msg], msg, ...)
end

local coalesced = {}

-- Each request restarts the key's timer, so the work runs once the events have settled.
function ns.Coalesce(key, delay, fn)
	assert(type(fn) == "function", "coalesce needs a function")
	if coalesced[key] then
		coalesced[key]:Cancel()
	end
	coalesced[key] = C_Timer.NewTimer(delay, function()
		coalesced[key] = nil
		ns.Protect("coalesce:" .. tostring(key), fn)
	end)
end

local waiting, waitingOrder = {}, {}

function ns.AfterCombat(key, fn)
	if not InCombatLockdown() then
		ns.Protect("after combat:" .. tostring(key), fn)
		return
	end
	if not waiting[key] then
		waitingOrder[#waitingOrder + 1] = key
	end
	waiting[key] = fn
end

-- Services.lua registers it on PLAYER_REGEN_ENABLED after the fight ends, so a waiting function sees the fight over.
function ns.RunAfterCombat()
	local fns, order = waiting, waitingOrder
	waiting, waitingOrder = {}, {}
	for _, key in ipairs(order) do
		ns.Protect("after combat:" .. tostring(key), fns[key])
	end
end
