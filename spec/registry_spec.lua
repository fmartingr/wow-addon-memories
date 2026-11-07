local wow = require("helpers.wow")

describe("sub-addon registry", function()
	local function lines(data)
		local out = {}
		for _, chunk in ipairs(data.log.chunks) do
			for line in chunk:gmatch("[^\n]+") do
				out[#out + 1] = line
			end
		end
		for _, line in ipairs(data.log.open) do
			out[#out + 1] = line
		end
		return out
	end

	local function has(list, text)
		for _, v in ipairs(list) do
			if v == text then
				return true
			end
		end
		return false
	end

	local function count(list, text)
		local n = 0
		for _, v in ipairs(list) do
			if v == text then
				n = n + 1
			end
		end
		return n
	end

	local function boot(opts)
		opts = opts or {}
		opts.addons = opts.addons or { "Memories", "Memories_Test" }
		local ns, all = wow.boot(opts)
		return ns, all.Memories_Test
	end

	local function def(over)
		local d = { addon = "Memories_Other", api = 1, saved = "MemoriesOtherCharDB" }
		for k, v in pairs(over or {}) do
			d[k] = v
		end
		return d
	end

	local function byAddon(list)
		local out = {}
		for _, e in ipairs(list) do
			out[e.addon] = e
		end
		return out
	end

	it("creates the public global with the API and TOC versions", function()
		wow.boot()
		assert.equal(1, Memories.API_VERSION)
		assert.equal("0.1.0", Memories.VERSION)
		assert.is_function(Memories.RegisterModule)
		assert.is_function(Memories.Addons)
	end)

	it("gives a sub-addon its own journal in its own saved global", function()
		local ns, test = boot()
		local h = test.handle
		assert.is_table(h)
		assert.is_nil(test.reason)
		assert.equal("Memories_Test", h.addon)
		assert.is_string(h:Write("zz", "first", 3))
		assert.is_string(h:Write("zy", "a note"))
		assert.equal("Memories_Test", MemoriesTestCharDB.addon)
		assert.equal(2, MemoriesTestCharDB.lines)
		assert.equal("Player-1234-0ABCDEF0", MemoriesTestCharDB.char.guid)
		local at = wow.wall .. "||1453|5000|2500|"
		assert.same({ at .. "zz|first|3", at .. "zy|a note" }, lines(MemoriesTestCharDB))
		assert.equal(0, ns.Store.Core():LineCount())
		assert.same({}, lines(MemoriesCharDB))
	end)

	it("writes a line at a given time and place", function()
		local _, test = boot()
		local line = test.handle:WriteAt({ t = 7, p = 3, m = 1, x = 2, y = 4 }, "zy", "then")
		assert.equal("7|3|1|2|4|zy|then", line)
		assert.equal(1, MemoriesTestCharDB.lines)
	end)

	it("opens the sub-addon at login after the core's modules, then calls its hooks", function()
		local ns, test = boot({ login = false })
		local order = {}
		ns.Module("Probe").OnLogin = function()
			order[#order + 1] = "core"
			assert.is_nil(MemoriesTestCharDB)
		end
		ns.Listen("LOGIN", function()
			order[#order + 1] = "LOGIN"
		end)
		test.handle:Listen("LOGIN", function()
			order[#order + 1] = "sub LOGIN"
		end)
		assert.equal(0, test.logins)
		wow.login()
		assert.same({ "core", "LOGIN", "sub LOGIN" }, order)
		assert.equal(1, test.logins)
		assert.same({ { true, false } }, test.worlds)
		wow.fire("PLAYER_ENTERING_WORLD", false, false)
		assert.same({ { true, false }, { false, false } }, test.worlds)
	end)

	it("creates the saved global on a first run and keeps both files over a reload", function()
		local ns, test = boot()
		assert.is_table(MemoriesTestCharDB)
		test.handle:Write("zz", "kept", 1)
		ns.Store.Core():Write("lv", 11)
		wow.advance(10)
		ns, test = wow.reload()
		test = test.Memories_Test
		assert.is_table(test.handle)
		assert.equal(1, #lines(MemoriesTestCharDB))
		assert.truthy(lines(MemoriesTestCharDB)[1]:find("|zz|kept|1$"))
		assert.equal(1, ns.Store.Core():LineCount())
		assert.truthy(lines(MemoriesCharDB)[1]:find("|lv|11$"))
		assert.same({ { false, true } }, test.worlds)
	end)

	it("stops a sub-addon that loads before the core with one chat line", function()
		local _, test = boot({ order = "reverse" })
		assert.is_true(has(wow.chat(), "Memories_Test: Memories is not loaded."))
		assert.is_nil(test.handle)
		assert.is_nil(MemoriesTestCharDB)
		assert.is_nil(MemoriesDB.kinds.zz)
	end)

	it("lists the sub-addon kinds in MemoriesDB.kinds", function()
		boot()
		assert.equal("Memories_Test;Test;what,#n", MemoriesDB.kinds.zz)
		assert.equal("Memories_Test;Test;note", MemoriesDB.kinds.zy)
		assert.equal("Memories;Sessions;how", MemoriesDB.kinds["in"])
	end)

	it("keeps the kinds of a sub-addon that is off on a later login", function()
		boot()
		local saved = { MemoriesDB = MemoriesDB, MemoriesCharDB = MemoriesCharDB }
		wow.boot({ saved = saved, installed = { Memories_Test = "disabled" } })
		assert.equal("Memories_Test;Test;what,#n", MemoriesDB.kinds.zz)
	end)

	it("sends LINE_WRITTEN with the addon name and the decoded line", function()
		local ns, test = boot()
		local got
		ns.Listen("LINE_WRITTEN", function(_, addon, kind, line, ev)
			got = { addon = addon, kind = kind, line = line, ev = ev }
		end)
		local line = test.handle:Write("zz", "x", 7)
		assert.equal("Memories_Test", got.addon)
		assert.equal("zz", got.kind)
		assert.equal(line, got.line)
		assert.equal("x", got.ev.what)
		assert.equal(7, got.ev.n)
	end)

	it("refuses a write of a kind that the addon did not register", function()
		local _, test = boot()
		assert.has_error(function()
			test.handle:Write("lv", 2)
		end)
		assert.has_error(function()
			test.handle:WriteAt({}, "qq")
		end)
		assert.equal(0, MemoriesTestCharDB.lines)
	end)

	it("keeps the owner of a handle when its addon field changes", function()
		local _, test = boot()
		test.handle.addon = "Memories"
		assert.has_error(function()
			test.handle:Write("lv", 2)
		end)
		assert.truthy(test.handle:Write("zz", "a", 1))
	end)

	it("answers not ready to a write before login", function()
		local _, test = boot({ login = false })
		assert.same({ nil, "not ready" }, { test.handle:Write("zz", "early") })
		assert.same({ nil, "not ready" }, { test.handle:WriteAt({ t = 5 }, "zz") })
		assert.has_error(function()
			test.handle:Count("test", "a")
		end)
	end)

	describe("refusals", function()
		it("refuses a def with a missing or bad addon, saved or api", function()
			wow.boot()
			for _, d in ipairs({
				"not a table",
				{ api = 1, saved = "X" },
				{ addon = "", api = 1, saved = "X" },
				{ addon = "A", api = 1 },
				{ addon = "A", api = 1, saved = "1bad" },
				{ addon = "A", saved = "X" },
				{ addon = "A", saved = "X", api = 0 },
			}) do
				assert.same({ nil, "bad def" }, { Memories.RegisterModule(d) })
			end
		end)

		it("refuses a def that names a core saved table or another addon's saved table", function()
			boot()
			assert.same({ nil, "bad def" }, { Memories.RegisterModule(def({ saved = "MemoriesCharDB" })) })
			assert.same({ nil, "bad def" }, { Memories.RegisterModule(def({ saved = "MemoriesDB" })) })
			assert.same({ nil, "bad def" }, { Memories.RegisterModule(def({ saved = "MemoriesTestCharDB" })) })
			assert.same({ nil, "bad def" }, { Memories.RegisterModule(def({ saved = "Memories" })) })
			assert.same({ nil, "bad def" }, { Memories.RegisterModule(def({ saved = "_G" })) })
			assert.same({ nil, "bad def" }, { Memories.RegisterModule(def({ saved = "UnitName" })) })
			assert.same({ nil, "bad def" }, { Memories.RegisterModule(def({ saved = "UIParent" })) })
			assert.is_function(UnitName)
			assert.is_nil(Memories.log)
			assert.same({}, lines(MemoriesCharDB))
		end)

		it("refuses bad kinds, new-only boxes and hooks without registering any kind", function()
			wow.boot()
			for _, over in ipairs({
				{ kinds = "zz" },
				{ kinds = { "zz" } },
				{ kinds = { { kind = "z z" } } },
				{ kinds = { { kind = "zq", fields = { "bad field" } } } },
				{ kinds = { { kind = "zq", fields = { "t" } } } },
				{ kinds = { { kind = "zq", fields = "what" } } },
				{ kinds = { { kind = "zq", fields = { "name", "#name" } } } },
				{ kinds = { { kind = "zq", group = 3 } } },
				{ kinds = { { kind = "zq", group = "a;b" } } },
				{ addon = "Memories;Other", kinds = { { kind = "zq" } } },
				{ kinds = { { kind = "zq" }, { kind = "zq" } } },
				{ kinds = { { kind = "zq" } }, newOnly = { { key = "x", kinds = { "lv" } } } },
				{ kinds = { { kind = "zq" } }, newOnly = { "x" } },
				{ kinds = { { kind = "zq" } }, newOnly = { { key = "x", label = 3, kinds = { "zq" } } } },
				{ kinds = { { kind = "zq" } }, newOnly = { { key = "x", kinds = {} } } },
				{ kinds = { { kind = "zq" } }, newOnly = { { key = "x", kinds = { nil, "zq" } } } },
				{ kinds = { { kind = "zq" } }, newOnly = { { key = "x", kinds = { "zq", [3] = "zq" } } } },
				{ kinds = { { kind = "zq" } }, newOnly = { { key = "x", kinds = { "zq", other = "zq" } } } },
				{
					kinds = { { kind = "zq" } },
					newOnly = { { key = "x", kinds = { "zq", [3] = "zq", other = "zq" } } },
				},
				{ kinds = { { kind = "zq" } }, newOnly = { { key = "x", kinds = "zq" } } },
				{
					kinds = { { kind = "zq" } },
					newOnly = { { key = "x", kinds = { "zq" } }, { key = "x", kinds = { "zq" } } },
				},
				{ OnLogin = "nope" },
			}) do
				assert.same({ nil, "bad def" }, { Memories.RegisterModule(def(over)) })
			end
			local ns = wow.ns.Memories
			assert.is_nil(ns.Kinds.Get("zq"))
		end)

		it("refuses a newer api, prints once and lists the addon as newer api", function()
			local ns = boot()
			local d = def({ addon = "Memories_Combat", api = 2, saved = "MemoriesCombatCharDB" })
			assert.same({ nil, "newer api" }, { Memories.RegisterModule(d) })
			assert.same({ nil, "newer api" }, { Memories.RegisterModule(d) })
			assert.equal(1, count(wow.chat(), "Memories: Memories_Combat needs a newer Memories"))
			assert.is_nil(MemoriesCombatCharDB)
			local states = byAddon(Memories.Addons())
			assert.equal("newer api", states.Memories_Combat.state)
			assert.is_nil(ns.Kinds.Get("ki"))
		end)

		it("refuses the same addon twice and the core name", function()
			boot()
			assert.same({ nil, "twice" }, { Memories.RegisterModule(def({ addon = "Memories_Test" })) })
			assert.same({ nil, "twice" }, { Memories.RegisterModule(def({ addon = "Memories" })) })
		end)

		it("refuses a new-only key that another addon registered", function()
			local ns = boot()
			local d = def({ kinds = { { kind = "zq" } }, newOnly = { { key = "test", kinds = { "zq" } } } })
			assert.same({ nil, "bad def" }, { Memories.RegisterModule(d) })
			assert.is_nil(ns.Kinds.Get("zq"))
		end)

		it("refuses a kind that another addon registered", function()
			boot()
			assert.same({ nil, "kind taken" }, { Memories.RegisterModule(def({ kinds = { { kind = "zz" } } })) })
			assert.same({ nil, "kind taken" }, { Memories.RegisterModule(def({ kinds = { { kind = "lv" } } })) })
		end)

		it("answers error when registration itself fails", function()
			local ns = boot()
			ns.Kinds.Register = function()
				error("broken")
			end
			assert.same({ nil, "error" }, { Memories.RegisterModule(def({ kinds = { { kind = "zq" } } })) })
		end)
	end)

	it("opens a late registration at once and calls OnLogin and OnEnterWorld", function()
		local ns = boot()
		local calls = {}
		local h = Memories.RegisterModule(def({
			kinds = { { kind = "zq", group = "Other", name = "Other", fields = { "#v" } } },
			OnLogin = function(handle)
				calls[#calls + 1] = { "login", handle }
			end,
			OnEnterWorld = function(handle, isLogin, isReload)
				calls[#calls + 1] = { "world", handle, isLogin, isReload }
			end,
		}))
		assert.same({ { "login", h }, { "world", h, false, false } }, calls)
		assert.is_table(MemoriesOtherCharDB)
		assert.equal("Memories_Other;Other;#v", MemoriesDB.kinds.zq)
		assert.truthy(h:Write("zq", 4):find("|zq|4$"))
		assert.equal(1, MemoriesOtherCharDB.lines)
		assert.equal(0, ns.Store.Core():LineCount())
	end)

	it("calls OnEnterWorld once for a registration between login and entering the world", function()
		boot({ login = false })
		local worlds = {}
		wow.ns.Memories.Listen("LOGIN", function()
			Memories.RegisterModule(def({
				OnEnterWorld = function(_, isLogin, isReload)
					worlds[#worlds + 1] = { isLogin, isReload }
				end,
			}))
		end)
		wow.login()
		assert.same({ { true, false } }, worlds)
	end)

	it("calls OnEnterWorld once for a registration during a later PLAYER_ENTERING_WORLD", function()
		boot()
		local worlds, armed = {}, false
		Memories.RegisterModule(def({
			OnEnterWorld = function()
				if not armed then
					return
				end
				Memories.RegisterModule(def({
					addon = "Memories_Third",
					saved = "MemoriesThirdCharDB",
					OnEnterWorld = function(_, isLogin, isReload)
						worlds[#worlds + 1] = { isLogin, isReload }
					end,
				}))
			end,
		}))
		armed = true
		wow.fire("PLAYER_ENTERING_WORLD", false, true)
		assert.same({ { false, true } }, worlds)
	end)

	it("checks the api against the core, not the public table", function()
		boot()
		Memories.API_VERSION = 99
		assert.same({ nil, "newer api" }, { Memories.RegisterModule(def({ api = 2 })) })
	end)

	it("opens the saved global named at registration when the def changes later", function()
		local d = def()
		boot({ login = false })
		assert.truthy(Memories.RegisterModule(d))
		d.saved = "MemoriesCharDB"
		wow.login()
		assert.is_table(MemoriesOtherCharDB)
		assert.equal("Memories_Other", MemoriesOtherCharDB.addon)
		assert.equal("Memories", MemoriesCharDB.addon)
	end)

	it("saves the kinds of a sub-addon that registers from another sub-addon's OnLogin", function()
		boot({ login = false })
		Memories.RegisterModule(def({
			addon = "Memories_Combat",
			saved = "MemoriesCombatCharDB",
			OnLogin = function()
				Memories.RegisterModule(def({ kinds = { { kind = "zq", group = "Other", fields = { "#v" } } } }))
			end,
		}))
		wow.login()
		assert.equal("Memories_Other;Other;#v", MemoriesDB.kinds.zq)
	end)

	it("marks a sub-addon failed when its journal does not open, and skips its hooks", function()
		local ns, test = boot({ login = false })
		local open = ns.Store.Open
		ns.Store.Open = function(addon, data)
			assert(addon ~= "Memories_Test", "cannot open")
			return open(addon, data)
		end
		wow.login()
		assert.equal(0, test.logins)
		assert.same({}, test.worlds)
		assert.same({ nil, "not ready" }, { test.handle:Write("zz") })
		local states = byAddon(Memories.Addons())
		assert.equal("failed", states.Memories_Test.state)
		assert.equal("on", states.Memories.state)
	end)

	it("states the known sub-addons as missing when the AddOns API is absent", function()
		boot()
		_G.C_AddOns = nil
		assert.equal("missing", byAddon(Memories.Addons()).Memories_Combat.state)
	end)

	it("leaves MemoriesDB.kinds alone for a late registration when all of Memories is read-only", function()
		wow.boot({ saved = { MemoriesDB = { schema = 2, kinds = { zz = "x" } } } })
		local h = Memories.RegisterModule(def({ kinds = { { kind = "zq" } } }))
		assert.same({ zz = "x" }, MemoriesDB.kinds)
		assert.same({ nil, "read only" }, { h:Write("zq") })
	end)

	it("logs an error in a sub-addon hook and keeps the others", function()
		local ns, test = boot({ login = false })
		Memories.RegisterModule(def({
			OnLogin = function()
				error("boom")
			end,
		}))
		wow.login()
		assert.equal(1, test.logins)
		local errors = ns.Errors()
		assert.equal("Memories_Other:OnLogin", errors[#errors].where)
		assert.equal("on", byAddon(Memories.Addons()).Memories_Other.state)
	end)

	it("moves the data of a sub-addon to the orphans for a new GUID", function()
		local old = {
			schema = 1,
			char = { guid = "Player-1234-OLD", name = "Kaelys", realm = "Brumamar" },
			log = { chunks = {}, open = { "1|||||zz|old" } },
		}
		boot({ saved = { MemoriesDB = {}, MemoriesTestCharDB = old } })
		local orphan = MemoriesDB.orphans[1]
		assert.equal("Memories_Test", orphan.addon)
		assert.equal("Player-1234-OLD", orphan.guid)
		assert.same({ "1|||||zz|old" }, orphan.data.log.open)
		assert.equal(old, MemoriesTestCharDB)
		assert.equal("Player-1234-0ABCDEF0", MemoriesTestCharDB.char.guid)
		local got = lines(MemoriesTestCharDB)
		assert.equal(1, #got)
		assert.truthy(got[1]:find("|nt|new character|Player%-1234%-OLD$"))
		assert.same({}, lines(MemoriesCharDB))
	end)

	it("makes only the sub-addon read-only for newer-schema data", function()
		local newer = { schema = 99, char = { guid = "Player-1234-0ABCDEF0" }, log = { chunks = {}, open = { "1" } } }
		local ns, test = boot({ saved = { MemoriesDB = {}, MemoriesTestCharDB = newer } })
		assert.same({ nil, "read only" }, { test.handle:Write("zz", "no") })
		assert.equal(0, test.handle:Count("test", "a"))
		assert.equal(0, test.handle:Count("test", "a"))
		assert.same({ "1" }, MemoriesTestCharDB.log.open)
		assert.is_true(
			has(wow.chat(), "Memories: Memories_Test: saved data from a newer version; this addon will not write")
		)
		assert.truthy(ns.Store.Core():Write("lv", 2))
		local states = byAddon(Memories.Addons())
		assert.is_true(states.Memories_Test.readOnly)
		assert.equal(1, states.Memories_Test.lines)
		assert.is_false(states.Memories.readOnly)
	end)

	it("states each addon in Memories.Addons()", function()
		local ns, test = boot({
			installed = { Memories_Gathering = "disabled", Memories_Economy = "enabled" },
		})
		test.handle:Write("zz", "a")
		ns.Store.Core():Write("lv", 2)
		ns.Store.Core():Write("lv", 3)
		local list = Memories.Addons()
		assert.same({ addon = "Memories", state = "on", lines = 2, readOnly = false }, list[1])
		assert.same({ addon = "Memories_Test", state = "on", lines = 1, readOnly = false }, list[2])
		local states = byAddon(list)
		assert.equal("missing", states.Memories_Combat.state)
		assert.equal("off", states.Memories_Gathering.state)
		assert.equal("failed", states.Memories_Economy.state)
		assert.equal("missing", states.Memories_Social.state)
		assert.equal(7, #list)
	end)

	it("marks every addon failed when the core store fails at login", function()
		local ns = boot({ login = false })
		ns.Store.Init = function()
			error("store broken")
		end
		wow.login()
		Memories.RegisterModule(def())
		local states = byAddon(Memories.Addons())
		assert.equal("failed", states.Memories.state)
		assert.equal("failed", states.Memories_Test.state)
		assert.equal("failed", states.Memories_Other.state)
		assert.is_nil(MemoriesTestCharDB)
	end)

	describe("fight state", function()
		it("follows PLAYER_REGEN_* and counts the player's casts and the first hostile target", function()
			local ns, test = boot({ units = { target = { name = "Lobo", hostile = true } } })
			local h = test.handle
			local events = {}
			h:Listen("FIGHT_START", function()
				events[#events + 1] = "start"
			end)
			h:Listen("FIGHT_END", function(_, fight)
				events[#events + 1] = fight
			end)
			assert.is_false(h:InFight())
			assert.is_nil(h:Fight())
			wow.advance(5)
			wow.fire("PLAYER_REGEN_DISABLED")
			assert.is_true(h:InFight())
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 133)
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "target", "cast-2", 99)
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 133)
			wow.units.target = { name = "Oso", hostile = true }
			wow.fire("PLAYER_TARGET_CHANGED")
			assert.same({ start = 5, casts = 2, target = "Lobo" }, h:Fight())
			wow.advance(12)
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.is_false(h:InFight())
			assert.same({ "start", { start = 5, stop = 17, casts = 2, target = "Lobo" } }, events)
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 133)
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal(2, #events)
			assert.same({ start = 5, stop = 17, casts = 2, target = "Lobo" }, ns.Fight())
		end)

		it("takes a hostile target picked during the fight and ignores a friendly one", function()
			local _, test = boot({ units = { target = { name = "Ana", hostile = false } } })
			local h = test.handle
			wow.fire("PLAYER_REGEN_DISABLED")
			assert.is_nil(h:Fight().target)
			wow.units.target = { name = wow.secret("Oculto"), hostile = true }
			wow.fire("PLAYER_TARGET_CHANGED")
			assert.is_nil(h:Fight().target)
			wow.units.target = { name = "Jabalí", hostile = true }
			wow.fire("PLAYER_TARGET_CHANGED")
			assert.equal("Jabalí", h:Fight().target)
			local copy = h:Fight()
			copy.casts = 99
			assert.equal(0, h:Fight().casts)
		end)

		it("ends the fight before the functions that wait for the end of combat run", function()
			local _, test = boot()
			local h = test.handle
			wow.combat = true
			wow.fire("PLAYER_REGEN_DISABLED")
			local seen
			h:AfterCombat("k", function()
				seen = { h:InFight(), h:Fight().stop ~= nil }
			end)
			wow.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.same({ false, true }, seen)
		end)

		it("starts a fight at login when the player is already in combat", function()
			local _, test = boot({ login = false })
			local wrote
			test.handle:Listen("FIGHT_START", function()
				wrote = test.handle:Write("zz", "fight", 1)
			end)
			wow.combat = true
			wow.login(true)
			assert.is_true(test.handle:InFight())
			assert.is_string(wrote)
		end)
	end)

	describe("handle services", function()
		it("runs listeners through the error guard with the addon name", function()
			local ns, test = boot()
			local h = test.handle
			local handle = h:On("PLAYER_MONEY", function()
				error("bad money")
			end)
			wow.fire("PLAYER_MONEY")
			local errors = ns.Errors()
			assert.equal("Memories_Test:PLAYER_MONEY", errors[#errors].where)
			h:Off("PLAYER_MONEY", handle)
			h:Off("PLAYER_XP_UPDATE", handle)
			wow.fire("PLAYER_MONEY")
			assert.equal(1, #ns.Errors())
			h:Listen("SOMETHING", function()
				error("bad msg")
			end)
			ns.Emit("SOMETHING")
			assert.equal("Memories_Test:SOMETHING", ns.Errors()[2].where)
			assert.is_false(h:Safe("work", error, "x"))
			assert.equal("Memories_Test:work", ns.Errors()[3].where)
			assert.same({ true, 3 }, { h:Safe("sum", function(a, b)
				return a + b
			end, 1, 2) })
		end)

		it("hooks a function with the addon name in the error log", function()
			local ns, test = boot()
			local seen
			_G.SomeBlizzardFunc = function()
				return "orig"
			end
			assert.is_true(test.handle:Hook(nil, "SomeBlizzardFunc", function(v)
				seen = v
				error("hook broke")
			end))
			assert.equal("orig", SomeBlizzardFunc(4))
			assert.equal(4, seen)
			assert.equal("Memories_Test:hook:SomeBlizzardFunc", ns.Errors()[1].where)
			assert.is_false(test.handle:Hook(nil, "MissingFunc", function() end))
		end)

		it("counts, snaps and asks for firsts in its own journal", function()
			local _, test = boot()
			local h = test.handle
			assert.is_true(h:IsFirst("test", "copper"))
			assert.equal(0, h:Count("test", "copper"))
			assert.equal(1, h:Count("test", "copper", 2))
			assert.is_false(h:IsFirst("test", "copper"))
			assert.same({ copper = 3 }, h:Counts("test"))
			h:Snap(10, "money", 50)
			assert.equal(50, h:Snap(10, "money"))
			assert.same({ test = { copper = 3 } }, MemoriesTestCharDB.counts)
			assert.same({ [10] = { money = 50 } }, MemoriesTestCharDB.snap)
			assert.is_nil(MemoriesCharDB.counts.test)
		end)

		it("gives the place, level, instance, new-only, names and text helpers", function()
			local _, test = boot({ spells = { [2575] = "Minería" } })
			local h = test.handle
			assert.same({ t = wow.wall, m = 1453, x = 5000, y = 2500 }, h:Here())
			wow.instance = { type = "party" }
			assert.same({ t = wow.wall }, h:Here())
			assert.same({ true, "party" }, { h:InInstance() })
			wow.instance = nil
			assert.same({ false, "none" }, { h:InInstance() })
			assert.is_false(h:NewOnly("test"))
			assert.equal(10, h:Level())
			wow.fire("PLAYER_LEVEL_UP", 11)
			assert.equal(11, h:Level())
			wow.player.level = 12
			assert.equal(12, h:Level())
			assert.equal("Minería", h:SpellName(2575))
			assert.is_nil(h:SpellName(1))
			assert.is_nil(h:SpellName(nil))
			wow.spells[3] = wow.secret("Oculto")
			assert.is_nil(h:SpellName(3))
			assert.equal("Miner", h:Utf8Cut("Minería", 6))
			assert.same({ nil, true }, { h:R(wow.secret(1)) })
			assert.same({ 1, nil, true }, { h:RN(1, wow.secret(2)) })
			h:Print("hola")
			assert.equal("Memories: hola", wow.chat()[#wow.chat()])
		end)

		it("keeps the Coalesce and AfterCombat keys of each addon apart", function()
			local ns, test = boot()
			local ran = {}
			test.handle:Coalesce("save", 1, function()
				ran[#ran + 1] = "sub"
			end)
			ns.Coalesce("save", 1, function()
				ran[#ran + 1] = "core"
			end)
			wow.advance(2)
			table.sort(ran)
			assert.same({ "core", "sub" }, ran)
			wow.combat = true
			ran = {}
			test.handle:AfterCombat("x", function()
				ran[#ran + 1] = "sub"
			end)
			ns.AfterCombat("x", function()
				ran[#ran + 1] = "core"
			end)
			wow.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.same({ "sub", "core" }, ran)
		end)
	end)
end)
