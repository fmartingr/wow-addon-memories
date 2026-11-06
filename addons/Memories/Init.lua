local ADDON, ns = ...

ns.loginTime = {}

local function each(hook, ...)
	for _, module in ipairs(ns.modules) do
		if module[hook] then
			ns.Safe(module.name .. ":" .. hook, module[hook], module, ...)
		end
	end
end

local function timed(step, fn, ...)
	local start = debugprofilestop()
	fn(...)
	ns.loginTime[step] = debugprofilestop() - start
end

local loaded
loaded = ns.On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then
		return
	end
	ns.Off("ADDON_LOADED", loaded)
	timed("init", function()
		if type(MemoriesDB) ~= "table" then
			MemoriesDB = {}
		end
		if type(MemoriesCharDB) ~= "table" then
			MemoriesCharDB = {}
		end
		ns.Errors()
		each("OnInit")
	end)
end, "init")

ns.On("PLAYER_LOGIN", function()
	timed("login", function()
		-- Every recorder writes through the core journal, so without it they stay off instead of failing one by one.
		if not ns.Safe("store", ns.Store.Init) then
			ns.stopped = true
			ns.Registry.Stop()
			return
		end
		each("OnLogin")
		ns.Safe("registry", ns.Registry.Login)
		ns.loggedIn = true
		ns.Emit("LOGIN")
	end)
end, "login")

-- A registration while this runs waits for the loop below, so its OnEnterWorld runs once.
local function enterWorld(isLogin, isReload)
	ns.enteringWorld = true
	each("OnEnterWorld", isLogin, isReload)
	ns.Safe("registry", ns.Registry.EnterWorld, isLogin, isReload)
	ns.enteringWorld = false
end

ns.On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
	if ns.stopped then
		return
	end
	if isLogin or isReload then
		timed("world", enterWorld, isLogin, isReload)
	else
		enterWorld(isLogin, isReload)
	end
end, "enter world")
