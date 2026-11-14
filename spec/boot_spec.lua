local wow = require("helpers.wow")

describe("boot", function()
	wow.pin_locale("enUS", before_each, after_each)

	local function start(opts)
		wow.reset(opts)
		local ns = wow.load_addon("Memories", opts and opts.saved)
		local calls = {}
		for _, name in ipairs({ "First", "Second" }) do
			local module = ns.Module(name)
			module.OnInit = function(self)
				calls[#calls + 1] = self.name .. ":init"
			end
			module.OnLogin = function(self)
				calls[#calls + 1] = self.name .. ":login:" .. tostring(ns.loggedIn)
			end
			module.OnEnterWorld = function(self, isLogin, isReload)
				calls[#calls + 1] = self.name .. ":world:" .. tostring(isLogin) .. ":" .. tostring(isReload)
			end
		end
		return ns, calls
	end

	it("loads the files of the TOC in order", function()
		local toc = wow.read_toc("Memories")
		assert.equal("16001", toc.meta.Interface)
		assert.same({ "MemoriesDB", "MemoriesCharDB" }, toc.saved)
		assert.equal("addons/Memories/Libs/LibStub/LibStub.lua", toc.files[1])
		assert.equal("addons/Memories/Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua", toc.files[4])
		assert.equal("addons/Memories/Locales.lua", toc.files[5])
		assert.equal("addons/Memories/Core/Core.lua", toc.files[6])
		assert.equal("addons/Memories/Init.lua", toc.files[#toc.files])
	end)

	it("calls each module hook once in load order", function()
		local ns, calls = start()
		ns.Listen("LOGIN", function()
			calls[#calls + 1] = "LOGIN:" .. tostring(ns.loggedIn)
		end)
		wow.fire("ADDON_LOADED", "Memories")
		wow.fire("ADDON_LOADED", "Memories")
		wow.login()
		assert.same({
			"First:init",
			"Second:init",
			"First:login:nil",
			"Second:login:nil",
			"LOGIN:true",
			"First:world:true:false",
			"Second:world:true:false",
		}, calls)
	end)

	it("ignores ADDON_LOADED of other addons", function()
		local _, calls = start()
		wow.fire("ADDON_LOADED", "Paparazzi")
		assert.same({}, calls)
		assert.is_nil(MemoriesDB)
	end)

	it("passes the reload flags to OnEnterWorld", function()
		local _, calls = start()
		wow.fire("ADDON_LOADED", "Memories")
		wow.login(true)
		wow.fire("PLAYER_ENTERING_WORLD", false, false)
		assert.same({ "First:world:false:true", "Second:world:false:true" }, { calls[5], calls[6] })
		assert.same({ "First:world:false:false", "Second:world:false:false" }, { calls[7], calls[8] })
	end)

	it("keeps calling the other modules when a hook fails", function()
		local ns, calls = start()
		ns.GetModule("First").OnInit = function()
			error("init failed", 0)
		end
		wow.fire("ADDON_LOADED", "Memories")
		assert.same({ "Second:init" }, calls)
		assert.equal("First:OnInit", MemoriesDB.errors[1].where)
		assert.equal("init failed", MemoriesDB.errors[1].msg)
	end)

	it("creates the saved tables when they are nil and keeps existing ones", function()
		start()
		wow.fire("ADDON_LOADED", "Memories")
		assert.same({ errors = {} }, MemoriesDB)
		assert.same({}, MemoriesCharDB)

		local db, char = { settings = { x = 1 } }, { log = {} }
		start({ saved = { MemoriesDB = db, MemoriesCharDB = char } })
		wow.fire("ADDON_LOADED", "Memories")
		assert.equal(db, MemoriesDB)
		assert.equal(char, MemoriesCharDB)
		assert.same({ x = 1 }, MemoriesDB.settings)
	end)

	it("replaces saved values that are not tables", function()
		start({ saved = { MemoriesDB = "broken", MemoriesCharDB = 5 } })
		wow.fire("ADDON_LOADED", "Memories")
		assert.same({ errors = {} }, MemoriesDB)
		assert.same({}, MemoriesCharDB)
	end)

	it("replaces a saved error list that is not a table", function()
		local ns = start({ saved = { MemoriesDB = { errors = "broken" } } })
		wow.fire("ADDON_LOADED", "Memories")
		ns.LogError("late", "boom")
		assert.equal("boom", MemoriesDB.errors[1].msg)
	end)

	it("writes an error from before MemoriesDB existed into it", function()
		local ns = start()
		ns.LogError("early", "too soon")
		assert.is_nil(MemoriesDB)
		wow.fire("ADDON_LOADED", "Memories")
		assert.equal(1, #MemoriesDB.errors)
		assert.equal("early", MemoriesDB.errors[1].where)
	end)

	it("records the time of each login step", function()
		local ns = start()
		ns.GetModule("First").OnLogin = function()
			wow.clock = wow.clock + 0.25
		end
		wow.fire("ADDON_LOADED", "Memories")
		wow.login()
		assert.equal(0, ns.loginTime.init)
		assert.equal(250, ns.loginTime.login)
		assert.equal(0, ns.loginTime.world)
	end)

	describe("slash commands", function()
		it("registers /memories and /mem", function()
			wow.boot()
			assert.equal("/memories", SLASH_MEMORIES1)
			assert.equal("/mem", SLASH_MEMORIES2)
		end)

		it("prints the command list with no argument or an unknown one", function()
			wow.boot()
			SlashCmdList.MEMORIES("")
			assert.same({
				"Memories: Commands:",
				"Memories: /memories help - show this list",
				"Memories: /memories errors - show the saved errors, ready to copy",
				"Memories: /memories note - write a note in the journey",
				"Memories: /memories options - open the settings page",
				"Memories: /memories settings - open the settings page",
				"Memories: /memories status - show the state of each Memories addon",
				"Memories: /memories minimap - show or hide the minimap button",
			}, wow.chat())
			SlashCmdList.MEMORIES("nope")
			assert.equal(16, #wow.chat())
			SlashCmdList.MEMORIES("help")
			assert.equal(24, #wow.chat())
		end)

		it("opens the settings page on a right click of the addon compartment", function()
			wow.boot()
			wow.compartment.Memories("RightButton")
			assert.equal(wow.categories[1]:GetID(), wow.opened)
			assert.same({}, wow.chat())
			assert.equal(0, wow.reloads)
		end)

		it("saves on a shift + left click of the addon compartment, never in combat", function()
			wow.boot()
			wow.shift = true
			wow.combat = true
			wow.compartment.Memories("LeftButton")
			assert.equal(0, wow.reloads)
			assert.same({ "Memories: cannot save in combat." }, wow.chat())
			wow.combat = false
			wow.compartment.Memories("LeftButton")
			assert.equal(1, wow.reloads)
		end)

		it("adds a sub-command", function()
			local ns = wow.boot()
			local got
			ns.Commands.Register("probe", function(rest)
				got = rest
			end, "probe")
			SlashCmdList.MEMORIES("  PROBE  all now ")
			assert.equal("all now", got)
			ns.Commands.Register("probe", function(rest)
				got = "again " .. rest
			end, "probe")
			SlashCmdList.MEMORIES("probe x")
			assert.equal("again x", got)
		end)

		it("runs a sub-command added with capital letters", function()
			local ns = wow.boot()
			local ran = false
			ns.Commands.Register("Backup", function()
				ran = true
			end)
			SlashCmdList.MEMORIES("backup")
			assert.is_true(ran)
			SlashCmdList.MEMORIES("")
			assert.equal("Memories: /memories backup - ", wow.chat()[#wow.chat()])
		end)

		it("shows a logged error in a copyable box", function()
			local ns = wow.boot()
			ns.LogError("Trail:OnLogin", "attempt to index a nil value|cff", "stack line")
			SlashCmdList.MEMORIES("errors")
			local box = _G.MemoriesErrorsFrame
			assert.is_true(box:IsShown())
			assert.matches(
				"Trail:OnLogin: attempt to index a nil value||cff\nstack line",
				box.EditBox:GetText(),
				1,
				true
			)
			assert.is_true(box.EditBox.highlighted)
			assert.is_true(box.EditBox.focused)
			box.EditBox:GetScript("OnEscapePressed")()
			assert.is_false(box:IsShown())
		end)

		it("shows saved errors with a missing or out-of-range time", function()
			wow.boot({
				saved = {
					MemoriesDB = {
						errors = {
							{ t = 1e20, where = "far", msg = "a" },
							{ where = "none", msg = "b" },
						},
					},
				},
			})
			local ns = wow.ns.Memories
			assert.equal("unknown time  far: a\nunknown time  none: b", ns.ErrorLog.Text())
		end)

		it("prints a line when there are no errors", function()
			wow.boot()
			SlashCmdList.MEMORIES("errors")
			assert.same({ "Memories: no saved errors." }, wow.chat())
			assert.is_nil(_G.MemoriesErrorsFrame)
		end)

		it("logs an error inside a command", function()
			local ns = wow.boot()
			ns.Commands.Register("boom", function()
				error("command failed", 0)
			end, "fail")
			SlashCmdList.MEMORIES("boom")
			assert.equal("command failed", MemoriesDB.errors[1].msg)
			assert.equal("slash:boom", MemoriesDB.errors[1].where)
			assert.same(
				{ "Memories: The command failed. Some functions can be missing. [slash:boom: command failed]" },
				wow.chat()
			)
		end)
	end)

	describe("reload", function()
		it("keeps MemoriesDB.errors through a save and load", function()
			local ns = wow.boot()
			ns.LogError("where", 'a "quoted"\nmessage|with\0bytes')
			local saved = MemoriesDB
			ns = wow.reload()
			assert.are_not.equal(saved, MemoriesDB)
			assert.same(saved.errors, MemoriesDB.errors)
			assert.equal('a "quoted"\nmessage|with\0bytes', ns.Errors()[1].msg)
		end)

		it("fires PLAYER_LOGOUT before the save and enters the world as a reload", function()
			local ns = wow.boot()
			ns.On("PLAYER_LOGOUT", function()
				MemoriesCharDB.loggedOut = true
			end)
			local flags
			ns = wow.reload()
			assert.is_true(MemoriesCharDB.loggedOut)
			ns.Module("Late").OnEnterWorld = function(_, isLogin, isReload)
				flags = { isLogin, isReload }
			end
			wow.fire("PLAYER_ENTERING_WORLD", false, true)
			assert.same({ false, true }, flags)
		end)
	end)
end)
