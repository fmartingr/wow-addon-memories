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
		each("OnLogin")
		ns.loggedIn = true
		ns.Emit("LOGIN")
	end)
end, "login")

ns.On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
	if isLogin or isReload then
		timed("world", each, "OnEnterWorld", isLogin, isReload)
	else
		each("OnEnterWorld", isLogin, isReload)
	end
end, "enter world")
