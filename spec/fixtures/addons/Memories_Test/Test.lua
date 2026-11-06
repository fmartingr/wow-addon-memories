local ADDON, ns = ...

if not Memories or not Memories.RegisterModule then
	print(ADDON .. ": Memories is not loaded.")
	return
end

ns.logins = 0
ns.worlds = {}

ns.handle, ns.reason = Memories.RegisterModule({
	addon = ADDON,
	api = 1,
	saved = "MemoriesTestCharDB",
	kinds = {
		{ kind = "zz", group = "Test", name = "Test line", fields = { "what", "#n" } },
		{ kind = "zy", group = "Test", name = "Other test line", fields = { "note" } },
	},
	newOnly = { { key = "test", label = "Test: new findings only", kinds = { "zz" } } },
	OnLogin = function()
		ns.logins = ns.logins + 1
	end,
	OnEnterWorld = function(_, isLogin, isReload)
		ns.worlds[#ns.worlds + 1] = { isLogin, isReload }
	end,
})
