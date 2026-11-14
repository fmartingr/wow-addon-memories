local wow = require("helpers.wow")

describe("settings page", function()
	wow.pin_locale("enUS", before_each, after_each)

	local FAILED = "Memories: The settings panel is not available on this client."

	local function def(addon, group, kinds, box)
		local d = { addon = addon, api = 1, saved = addon:gsub("_", "") .. "CharDB", kinds = {} }
		for _, k in ipairs(kinds) do
			d.kinds[#d.kinds + 1] = { kind = k, group = group, name = "Kind " .. k }
		end
		if box then
			d.newOnly = { { key = box, label = group .. ": new findings only", kinds = { kinds[1] } } }
		end
		return d
	end

	-- The four sub-addons with a new-only box, registered before login like the real ones.
	local function bootSet()
		wow.boot({ addons = { "Memories", "Memories_Test" }, login = false })
		assert(Memories.RegisterModule(def("Memories_Combat", "Combat", { "c1", "c2" }, "kills")))
		assert(Memories.RegisterModule(def("Memories_Gathering", "Gathering", { "g1" }, "gathering")))
		local economy = def("Memories_Economy", "Loot", { "e1" }, "loot")
		economy.kinds[#economy.kinds + 1] = { kind = "e2", group = "Money", name = "Kind e2" }
		assert(Memories.RegisterModule(economy))
		local character = def("Memories_Character", "Character", { "h1" }, "consumables")
		character.kinds[#character.kinds + 1] = { kind = "h2", group = "Milestones", name = "Kind h2" }
		assert(Memories.RegisterModule(character))
		wow.login()
		return wow.ns.Memories
	end

	local function page()
		assert.equal(1, #wow.categories)
		return wow.categories[1]
	end

	local function setting(path)
		return page().settings["Memories_" .. path]
	end

	-- The page as a list of strings: "# header", "[button text]", "x path".
	local function outline()
		local out = {}
		for _, item in ipairs(page().items) do
			if item.type == "header" then
				out[#out + 1] = "# " .. item.name
			elseif item.type == "button" then
				out[#out + 1] = "[" .. item.buttonText .. "]"
			else
				out[#out + 1] = item.type .. " " .. item.setting.variable:gsub("^Memories_", "")
			end
		end
		return out
	end

	local function section(title)
		local out, on = {}, false
		for _, row in ipairs(outline()) do
			if row:sub(1, 2) == "# " then
				on = row == "# " .. title
			elseif on then
				out[#out + 1] = row
			end
		end
		return out
	end

	local function find(list, value)
		for i, v in ipairs(list) do
			if v == value then
				return i
			end
		end
	end

	local function calls(name)
		local n = 0
		for _, c in ipairs(wow.settings_calls) do
			if c.name == name then
				n = n + 1
			end
		end
		return n
	end

	it("registers one vertical category named Memories and adds it to the AddOns list", function()
		wow.boot()
		assert.equal("Memories", page().name)
		assert.is_true(page().registered)
		assert.equal("RegisterVerticalLayoutCategory", wow.settings_calls[1].name)
		assert.equal("RegisterAddOnCategory", wow.settings_calls[#wow.settings_calls].name)
	end)

	it("shows the general settings first, with their defaults", function()
		wow.boot()
		assert.same({
			"dropdown recordRate",
			"checkbox saveReminder",
			"checkbox lowHealthFlash",
			"checkbox minimapButton",
		}, section("General"))
		assert.equal("# General", outline()[1])
		assert.equal(2, setting("recordRate"):GetDefaultValue())
		assert.equal("number", setting("recordRate"):GetVariableType())
		assert.is_true(setting("saveReminder"):GetValue())
		assert.is_true(setting("minimapButton"):GetValue())
		assert.is_true(setting("lowHealthFlash"):GetValue())
	end)

	it("offers the recording rates 1, 2, 5 and 10 s", function()
		local ns = wow.boot()
		local dropdown = page().items[2]
		assert.equal("dropdown", dropdown.type)
		local values, labels = {}, {}
		for i, option in ipairs(dropdown.options()) do
			values[i], labels[i] = option.value, option.label
		end
		assert.same({ 1, 2, 5, 10 }, values)
		assert.same({ "1 s", "2 s", "5 s", "10 s" }, labels)
		setting("recordRate"):SetValue(5)
		assert.equal(5, ns.Settings.Get("recordRate"))
	end)

	it("shows one checkbox per registered kind, with the kind's name", function()
		local ns = wow.boot({ addons = { "Memories", "Memories_Test" } })
		local want, got = {}, {}
		for _, spec in ipairs(ns.Kinds.All()) do
			if not spec.always then
				want[#want + 1] = spec.kind
				assert.equal(spec.name, setting("kinds." .. spec.kind):GetName())
			end
		end
		for _, row in ipairs(outline()) do
			local kind = row:match("^checkbox kinds%.(.+)$")
			if kind then
				got[#got + 1] = kind
			end
		end
		assert.same(want, got)
		assert.is_nil(setting("kinds.nt"))
		assert.is_true(MemoriesDB.settings.kinds.zz)
		assert.is_true(setting("kinds.zz"):GetDefaultValue())
	end)

	it("shows one section per addon and group, in catalog order, each with a button pair", function()
		wow.boot({ addons = { "Memories", "Memories_Test" } })
		local headers = {}
		for _, row in ipairs(outline()) do
			if row:sub(1, 2) == "# " then
				headers[#headers + 1] = row:sub(3)
			end
		end
		assert.same({
			"General",
			"Memories — Sessions",
			"Memories — Progress",
			"Memories — Deaths",
			"Memories — Travel",
			"Memories — Dungeons",
			"Memories — Screenshots",
			"Memories — Other addons",
			"Memories — Notes",
			"Memories_Test — Test",
		}, headers)
		assert.same({
			"[Enable all]",
			"[Disable all]",
			"checkbox kinds.zz",
			"checkbox kinds.zy",
			"checkbox newOnly.test",
		}, section("Memories_Test — Test"))
		assert.same({ "[Enable all]", "[Disable all]", "checkbox kinds.ss" }, section("Memories — Screenshots"))
		for _, item in ipairs(page().items) do
			if item.type == "button" then
				assert.is_false(item.addSearchTags)
			end
		end
	end)

	it("places the four new-only boxes under their groups, off by default", function()
		local ns = bootSet()
		assert.same({
			"[Enable all]",
			"[Disable all]",
			"checkbox kinds.g1",
			"checkbox newOnly.gathering",
		}, section("Memories_Gathering — Gathering"))
		assert.same(
			{ "[Enable all]", "[Disable all]", "checkbox kinds.c1", "checkbox kinds.c2", "checkbox newOnly.kills" },
			section("Memories_Combat — Combat")
		)
		assert.same(
			{ "[Enable all]", "[Disable all]", "checkbox kinds.e1", "checkbox newOnly.loot" },
			section("Memories_Economy — Loot")
		)
		assert.same({ "[Enable all]", "[Disable all]", "checkbox kinds.e2" }, section("Memories_Economy — Money"))
		assert.same(
			{ "[Enable all]", "[Disable all]", "checkbox kinds.h1", "checkbox newOnly.consumables" },
			section("Memories_Character — Character")
		)
		assert.same(
			{ "[Enable all]", "[Disable all]", "checkbox kinds.h2" },
			section("Memories_Character — Milestones")
		)
		assert.equal("Gathering: new findings only", setting("newOnly.gathering"):GetName())
		for _, key in ipairs({ "gathering", "kills", "loot", "consumables" }) do
			assert.is_false(setting("newOnly." .. key):GetValue())
			assert.is_false(ns.Settings.NewOnly(key))
		end
		setting("newOnly.kills"):SetValue(true)
		assert.is_true(ns.Settings.NewOnly("kills"))
		assert.is_true(MemoriesDB.settings.newOnly.kills)
	end)

	it("turns a kind off from its checkbox and emits SETTING_CHANGED once", function()
		local ns = wow.boot({ addons = { "Memories", "Memories_Test" } })
		local seen = {}
		ns.Listen("SETTING_CHANGED", function(_, path, value)
			seen[#seen + 1] = { path, value }
		end)
		setting("kinds.zz"):SetValue(false)
		assert.is_false(ns.Settings.KindOn("zz"))
		assert.same({ { "kinds.zz", false } }, seen)
		assert.same({ nil, "off" }, { wow.ns.Memories_Test.handle:Write("zz", "x", 1) })
	end)

	it("sets a whole group with its buttons and shows the change in each checkbox", function()
		local ns = wow.boot()
		local rows = page().items
		local i = find(outline(), "# Memories — Travel")
		local enable, disable = rows[i + 1], rows[i + 2]
		assert.equal("Enable all", enable.buttonText)
		assert.equal("Disable all", disable.buttonText)
		disable.click()
		for _, kind in ipairs({ "zo", "sz", "tx", "jp", "mo", "ml" }) do
			assert.is_false(ns.Settings.KindOn(kind))
			assert.is_false(setting("kinds." .. kind):GetValue())
			assert.equal(1, setting("kinds." .. kind).notified)
		end
		assert.is_true(ns.Settings.KindOn("lv"))
		enable.click()
		for kind, v in pairs(MemoriesDB.settings.kinds) do
			assert.is_true(v, kind)
		end
	end)

	it("shows a change made in code in the checkbox", function()
		local ns = wow.boot()
		ns.Settings.Set("saveReminder", false)
		assert.equal(1, setting("saveReminder").notified)
		assert.is_false(setting("saveReminder"):GetValue())
		ns.Settings.Set("recordRate", 10)
		assert.equal(10, setting("recordRate"):GetValue())
	end)

	it("keeps the saved setting of a kind whose addon is not loaded, with no checkbox", function()
		wow.boot({ saved = { MemoriesDB = { settings = { kinds = { ki = false } } } } })
		assert.is_nil(setting("kinds.ki"))
		assert.is_false(MemoriesDB.settings.kinds.ki)
	end)

	it("adds a section for a sub-addon that registers after login", function()
		local ns = wow.boot()
		local before = #page().items
		assert(Memories.RegisterModule(def("Memories_Combat", "Combat", { "c1" }, "kills")))
		assert.same(
			{ "[Enable all]", "[Disable all]", "checkbox kinds.c1", "checkbox newOnly.kills" },
			section("Memories_Combat — Combat")
		)
		assert.equal(before + 5, #page().items)
		assert.equal(1, #wow.categories)
		setting("kinds.c1"):SetValue(false)
		assert.is_false(ns.Settings.KindOn("c1"))
	end)

	it("adds nothing for a late registration that the registry refuses", function()
		wow.boot()
		local before = #page().items
		assert.is_nil(Memories.RegisterModule({ addon = "Memories_Combat", api = 1 }))
		assert.equal(before, #page().items)
	end)

	it("puts the kinds without a group under the addon's name", function()
		wow.boot()
		assert(Memories.RegisterModule({
			addon = "Memories_Other",
			api = 1,
			saved = "MemoriesOtherCharDB",
			kinds = { { kind = "zx", name = "No group" } },
		}))
		assert.same({ "[Enable all]", "[Disable all]", "checkbox kinds.zx" }, section("Memories_Other"))
	end)

	it("opens the page with /memories options and /memories settings", function()
		wow.boot()
		SlashCmdList.MEMORIES("options")
		assert.equal(page():GetID(), wow.opened)
		wow.opened = nil
		SlashCmdList.MEMORIES("settings")
		assert.equal(page():GetID(), wow.opened)
		assert.equal(2, calls("OpenToCategory"))
		assert.same({}, wow.chat())
	end)

	it("fails safely when a Settings call raises, and /memories options says so", function()
		local ns = wow.boot({ addons = { "Memories", "Memories_Test" }, login = false })
		wow.settings_fail.RegisterAddOnSetting = "settings broke"
		wow.login()
		assert.equal(0, calls("RegisterAddOnCategory"))
		local errors = ns.Errors()
		assert.equal("options", errors[#errors].where)
		assert.matches("settings broke", errors[#errors].msg)
		wow.chat_raw = {}
		SlashCmdList.MEMORIES("options")
		assert.same({ FAILED }, wow.chat())
		assert.is_nil(wow.opened)
		LibDBIcon10_Memories:GetScript("OnClick")(LibDBIcon10_Memories, "RightButton")
		assert.equal(FAILED, wow.chat()[2])
		wow.chat_raw = {}
		SlashCmdList.MEMORIES("status")
		assert.equal("Memories: status:", wow.chat()[1])
		assert.truthy(Memories.RegisterModule(def("Memories_Combat", "Combat", { "c1" })))
		assert.is_true(ns.Settings.KindOn("zz"))
		ns.Settings.SetKind("zz", false)
		assert.is_false(ns.Settings.KindOn("zz"))
	end)

	it("fails safely without the Settings API", function()
		local ns = wow.boot({ login = false })
		_G.Settings = nil
		wow.login()
		local errors = ns.Errors()
		assert.matches("the Settings API is missing", errors[#errors].msg)
		wow.chat_raw = {}
		wow.compartment.Memories("RightButton")
		assert.same({ FAILED }, wow.chat())
	end)

	it("says the page failed before login", function()
		local ns = wow.boot({ login = false })
		assert.is_false(ns.Options.Open())
		assert.same({ FAILED }, wow.chat())
	end)

	it("logs an error of the checkbox update and keeps the page working", function()
		local ns = wow.boot()
		local s = setting("saveReminder")
		s.NotifyUpdate = function()
			error("notify broke")
		end
		ns.Settings.Set("saveReminder", false)
		local errors = ns.Errors()
		assert.equal("options", errors[#errors].where)
		assert.matches("notify broke", errors[#errors].msg)
		local seen = {}
		ns.Listen("SETTING_CHANGED", function(_, path, value)
			seen[#seen + 1] = { path, value }
		end)
		setting("minimapButton"):SetValue(false)
		assert.same({ { "minimapButton", false } }, seen)
		assert.is_false(LibDBIcon10_Memories:IsShown())
	end)
end)
