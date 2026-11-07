local wow = require("helpers.wow")

describe("settings", function()
	local function boot(opts)
		opts = opts or {}
		opts.addons = opts.addons or { "Memories", "Memories_Test" }
		local ns, all = wow.boot(opts)
		return ns, all.Memories_Test and all.Memories_Test.handle
	end

	local function changes(ns)
		local seen = {}
		ns.Listen("SETTING_CHANGED", function(_, path, value)
			seen[#seen + 1] = { path, value }
		end)
		return seen
	end

	it("has a default for each key", function()
		local ns = boot({ login = false })
		local S = ns.Settings
		assert.same({}, S.Get("kinds"))
		assert.same({}, S.Get("newOnly"))
		assert.equal(2, S.Get("recordRate"))
		assert.same({ level = false, lastBoss = false }, S.Get("shots"))
		assert.is_false(S.Get("shots.level"))
		assert.is_false(S.Get("shots.lastBoss"))
		assert.is_true(S.Get("saveReminder"))
		assert.is_true(S.Get("minimapButton"))
		assert.is_true(S.Get("lowHealthFlash"))
		assert.is_true(S.Get("kinds.lv"))
		assert.is_false(S.Get("newOnly.kills"))
		assert.is_nil(S.Get("nope"))
		assert.is_nil(S.Get("shots.level.deep"))
		assert.same({ 1, 2, 5, 10 }, S.RATES)
	end)

	it("returns a copy of a table setting, so only Set changes it", function()
		local ns = boot()
		ns.Settings.Get("shots").level = true
		ns.Settings.Get("kinds").lv = false
		assert.is_false(ns.Settings.Get("shots.level"))
		assert.is_true(ns.Settings.KindOn("lv"))
	end)

	it("uses the default for a key that is missing in old data", function()
		local ns = boot({ saved = { MemoriesDB = { settings = { saveReminder = false } } } })
		assert.is_false(ns.Settings.Get("saveReminder"))
		assert.equal(2, ns.Settings.Get("recordRate"))
		assert.is_false(ns.Settings.Get("shots.level"))
		assert.is_true(ns.Settings.KindOn("lv"))
		assert.is_false(ns.Settings.NewOnly("test"))
	end)

	it("drops values of the wrong type from an edited file", function()
		local ns = boot({
			saved = {
				MemoriesDB = {
					settings = {
						recordRate = 3,
						shots = "yes",
						minimapButton = "yes",
						kinds = { lv = "no", gh = false },
						newOnly = { test = 1 },
					},
				},
			},
		})
		local S = ns.Settings
		assert.equal(2, S.Get("recordRate"))
		assert.is_false(S.Get("shots.level"))
		assert.is_true(S.Get("minimapButton"))
		assert.is_true(S.KindOn("lv"))
		assert.is_false(S.KindOn("gh"))
		assert.is_false(S.NewOnly("test"))
		assert.is_true(MemoriesDB.settings.kinds.lv)
		assert.is_false(MemoriesDB.settings.kinds.gh)
	end)

	it("replaces settings that are not a table", function()
		local ns = boot({ saved = { MemoriesDB = { settings = "junk" } } })
		assert.equal(2, ns.Settings.Get("recordRate"))
		assert.is_table(MemoriesDB.settings)
		MemoriesDB.settings = { recordRate = 10 }
		assert.equal(10, ns.Settings.Get("recordRate"))
	end)

	it("gives the defaults before MemoriesDB exists", function()
		wow.reset()
		local ns = wow.load_addon("Memories")
		assert.is_nil(MemoriesDB)
		assert.equal(2, ns.Settings.Get("recordRate"))
		assert.is_true(ns.Settings.KindOn("lv"))
	end)

	it("sets a value and emits SETTING_CHANGED", function()
		local ns = boot()
		local seen = changes(ns)
		ns.Settings.Set("recordRate", 5)
		ns.Settings.Set("shots.level", true)
		ns.Settings.Set("newOnly.test", true)
		assert.equal(5, MemoriesDB.settings.recordRate)
		assert.is_true(MemoriesDB.settings.shots.level)
		assert.is_true(ns.Settings.NewOnly("test"))
		assert.same({ { "recordRate", 5 }, { "shots.level", true }, { "newOnly.test", true } }, seen)
	end)

	it("keeps a new-only key with a dot as one key", function()
		local ns = boot()
		ns.Settings.Set("newOnly.a.b", true)
		assert.is_true(MemoriesDB.settings.newOnly["a.b"])
		assert.is_true(ns.Settings.Get("newOnly.a.b"))
	end)

	it("refuses an unknown path or a bad value", function()
		local ns = boot()
		local seen = changes(ns)
		for _, case in ipairs({
			{ "nope", true },
			{ "kinds", {} },
			{ "shots", {} },
			{ "recordRate", 3 },
			{ "recordRate", "2" },
			{ "saveReminder", "yes" },
			{ "kinds.lv", "off" },
			{ "newOnly.test", 1 },
		}) do
			assert.has_error(function()
				ns.Settings.Set(case[1], case[2])
			end)
		end
		assert.same({}, seen)
		assert.equal(2, ns.Settings.Get("recordRate"))
	end)

	it("turns one kind off and on", function()
		local ns = boot()
		local seen = changes(ns)
		ns.Settings.SetKind("lv", false)
		assert.is_false(ns.Settings.KindOn("lv"))
		assert.is_false(MemoriesDB.settings.kinds.lv)
		ns.Settings.SetKind("lv", true)
		assert.is_true(ns.Settings.KindOn("lv"))
		assert.same({ { "kinds.lv", false }, { "kinds.lv", true } }, seen)
	end)

	it("never gates a kind with always = true", function()
		local ns = boot()
		MemoriesDB.settings.kinds.nt = false
		assert.is_true(ns.Settings.KindOn("nt"))
		assert.truthy(ns.Store.Core():Write("nt", "test", "x"))
	end)

	it("sets every kind of one group", function()
		local ns = boot()
		local seen = changes(ns)
		assert.equal(6, ns.Settings.SetGroup("Memories", "Sessions", false))
		for _, kind in ipairs({ "in", "out", "pl", "gp", "pc", "af" }) do
			assert.is_false(ns.Settings.KindOn(kind))
		end
		assert.is_true(ns.Settings.KindOn("lv"))
		assert.equal(6, #seen)
		assert.same({ "kinds.in", false }, seen[1])
		assert.equal(2, ns.Settings.SetGroup("Memories_Test", "Test", false))
		assert.is_false(ns.Settings.KindOn("zz"))
		assert.equal(0, ns.Settings.SetGroup("Memories", "Nope", false))
	end)

	it("leaves no false entry after Disable all and Enable all", function()
		local ns = boot()
		ns.Settings.SetGroup("Memories", "Travel", false)
		ns.Settings.SetGroup("Memories", "Travel", true)
		for kind, v in pairs(MemoriesDB.settings.kinds) do
			assert.is_true(v, kind)
		end
	end)

	it("sets the kinds without a group", function()
		local ns = boot({ login = false })
		Memories.RegisterModule({
			addon = "Memories_Other",
			api = 1,
			saved = "MemoriesOtherCharDB",
			kinds = { { kind = "zx", name = "No group" } },
		})
		wow.login()
		assert.equal(1, ns.Settings.SetGroup("Memories_Other", nil, false))
		assert.is_false(ns.Settings.KindOn("zx"))
	end)

	it("stops the lines of a kind that is off and keeps its counts", function()
		local ns, h = boot()
		ns.Settings.SetKind("zz", false)
		local line, why = h:Write("zz", "x", 1)
		assert.is_nil(line)
		assert.equal("off", why)
		assert.equal(0, h:Count("test", "x"))
		assert.equal(1, h:Counts("test").x)
		assert.equal(0, MemoriesTestCharDB.lines)
		assert.truthy(h:Write("zy", "still on"))
		ns.Settings.SetKind("lv", false)
		assert.same({ nil, "off" }, { ns.Store.Core():Write("lv", 2) })
		ns.Settings.SetKind("zz", true)
		assert.truthy(h:Write("zz", "x", 1))
	end)

	it("gives a sub-addon its new-only setting", function()
		local ns, h = boot()
		assert.is_false(h:NewOnly("test"))
		ns.Settings.Set("newOnly.test", true)
		assert.is_true(h:NewOnly("test"))
		assert.is_false(h:NewOnly("other"))
	end)

	it("keeps the settings across a reload", function()
		local ns = boot()
		ns.Settings.SetKind("zz", false)
		ns.Settings.Set("recordRate", 10)
		ns = wow.reload()
		assert.is_false(ns.Settings.KindOn("zz"))
		assert.equal(10, ns.Settings.Get("recordRate"))
	end)

	it("keeps changes in memory when all of Memories is read-only", function()
		local ns = boot({ saved = { MemoriesDB = { schema = 99, settings = { recordRate = 5 } } } })
		assert.equal(5, ns.Settings.Get("recordRate"))
		ns.Settings.Set("recordRate", 1)
		ns.Settings.SetKind("lv", false)
		assert.equal(1, ns.Settings.Get("recordRate"))
		assert.is_false(ns.Settings.KindOn("lv"))
		assert.same({ recordRate = 5 }, MemoriesDB.settings)
	end)

	it("starts an empty session copy when a read-only MemoriesDB has no settings", function()
		local ns = boot({ saved = { MemoriesDB = { schema = 99 } } })
		ns.Settings.Set("saveReminder", false)
		assert.is_false(ns.Settings.Get("saveReminder"))
		assert.is_nil(MemoriesDB.settings)
	end)
end)
