local wow = require("helpers.wow")

describe("low-health popup", function()
	local CVAR = "doNotFlashLowHealthWarning"
	local POPUP = "MEMORIES_LOW_HEALTH"

	local ns

	local function popups()
		local n = 0
		for _, p in ipairs(wow.popups) do
			if p.which == POPUP then
				n = n + 1
			end
		end
		return n
	end

	local function last()
		return wow.popups[#wow.popups]
	end

	local function setting()
		return ns.Settings.Get("lowHealthFlash")
	end

	it("shows at the first world entry when the flash is off, and saves the setting as off", function()
		ns = wow.boot({ cvars = { [CVAR] = "1" } })
		assert.equal(1, popups())
		assert.is_false(setting())
		assert.is_true(ns.LowHealth.Shown())
		local info = last().info
		assert.truthy(info.text:find(ns.LowHealth.TITLE, 1, true))
		assert.truthy(info.text:find(ns.LowHealth.BODY, 1, true))
		assert.equal("Keep it on", info.button1)
		assert.equal("Turn it off", info.button2)
		wow.fire("PLAYER_ENTERING_WORLD", false, false)
		assert.equal(1, popups())
	end)

	it("waits for the end of combat at the first world entry", function()
		ns = wow.boot({ cvars = { [CVAR] = "1" }, login = false })
		wow.combat = true
		wow.login()
		assert.equal(0, popups())
		assert.is_false(setting())
		wow.combat = false
		wow.fire("PLAYER_REGEN_ENABLED")
		assert.equal(1, popups())
	end)

	it("skips the waiting popup when the flash came back on during the fight", function()
		ns = wow.boot({ cvars = { [CVAR] = "1" }, login = false })
		wow.combat = true
		wow.login()
		wow.cvars[CVAR] = "0"
		wow.fire("CVAR_UPDATE", CVAR, "0")
		wow.combat = false
		wow.fire("PLAYER_REGEN_ENABLED")
		assert.equal(0, popups())
		assert.is_true(setting())
	end)

	it("stays quiet at the first world entry when the flash is on", function()
		ns = wow.boot()
		assert.equal(0, popups())
		assert.is_true(setting())
	end)

	it("keeps it on: CVar 0, setting on, popup hidden, no popup from the echo", function()
		ns = wow.boot({ cvars = { [CVAR] = "1" } })
		last().info.OnAccept(last(), last().data)
		assert.equal("0", wow.cvars[CVAR])
		assert.is_true(setting())
		assert.is_false(ns.LowHealth.Shown())
		assert.is_true(last().hidden)
		assert.equal(1, popups())
		assert.same({ { CVAR, "0" } }, wow.cvar_sets)
	end)

	it("turns it off: CVar 1, setting off, no popup from the echo", function()
		ns = wow.boot()
		ns.LowHealth.Ask()
		last().info.OnCancel(last(), last().data, "clicked")
		assert.equal("1", wow.cvars[CVAR])
		assert.is_false(setting())
		assert.is_false(ns.LowHealth.Shown())
		assert.equal(1, popups())
	end)

	it("changes nothing when the popup closes without a button", function()
		ns = wow.boot()
		ns.LowHealth.Ask()
		last().info.OnCancel(last(), last().data, "override")
		last().info.OnHide(last())
		assert.equal("0", wow.cvars[CVAR])
		assert.is_true(setting())
		assert.is_false(ns.LowHealth.Shown())
		assert.same({}, wow.cvar_sets)
	end)

	it("shows when the game turns the flash off", function()
		ns = wow.boot()
		wow.cvars[CVAR] = "1"
		wow.fire("CVAR_UPDATE", CVAR, "1")
		assert.equal(1, popups())
		wow.fire("CVAR_UPDATE", CVAR, "1")
		assert.equal(1, popups())
	end)

	it("saves the setting as on when the game turns the flash on, with no popup", function()
		ns = wow.boot({ cvars = { [CVAR] = "1" } })
		ns.LowHealth.Hide()
		wow.cvars[CVAR] = "0"
		wow.fire("CVAR_UPDATE", CVAR, "0")
		assert.is_true(setting())
		assert.equal(1, popups())
	end)

	it("hides an open popup when the game turns the flash on", function()
		ns = wow.boot({ cvars = { [CVAR] = "1" } })
		assert.is_true(ns.LowHealth.Shown())
		wow.cvars[CVAR] = "0"
		wow.fire("CVAR_UPDATE", CVAR, "0")
		assert.is_false(ns.LowHealth.Shown())
		assert.is_true(setting())
		assert.equal("0", wow.cvars[CVAR])
	end)

	it("ignores other CVars and a secret value", function()
		ns = wow.boot()
		wow.fire("CVAR_UPDATE", "screenEdgeFlash", "1")
		wow.fire("CVAR_UPDATE", CVAR, wow.secret("1"))
		assert.equal(0, popups())
	end)

	it("reads the setting when the CVar cannot be read", function()
		ns = wow.boot()
		wow.cvar_fail.get = "no CVar"
		ns.Settings.Root().lowHealthFlash = false
		assert.is_false(ns.LowHealth.IsOn())
		ns.Settings.Root().lowHealthFlash = true
		assert.is_true(ns.LowHealth.IsOn())
		wow.cvar_fail.get = nil
		wow.cvars[CVAR] = wow.secret("1")
		assert.is_true(ns.LowHealth.IsOn())
	end)

	it("falls back to GetCVar and SetCVar without C_CVar", function()
		ns = wow.boot()
		_G.C_CVar = nil
		wow.cvars[CVAR] = "1"
		assert.is_false(ns.LowHealth.IsOn())
		ns.LowHealth.Set(true)
		assert.equal("0", wow.cvars[CVAR])
		_G.GetCVar, _G.SetCVar = nil, nil
		assert.is_true(ns.LowHealth.IsOn())
		ns.LowHealth.Set(false)
		assert.is_false(ns.LowHealth.IsOn())
		assert.equal("low health:cvar", MemoriesDB.errors[1].where)
	end)

	it("logs a failed CVar write without a chat line and still saves the setting", function()
		ns = wow.boot()
		wow.cvar_fail.set = "protected"
		ns.LowHealth.Ask()
		ns.LowHealth.Set(false)
		assert.is_false(setting())
		assert.is_false(ns.LowHealth.Shown())
		assert.equal("low health:cvar", MemoriesDB.errors[1].where)
		assert.same({}, wow.chat())
		assert.same({}, wow.errors)
	end)

	it("logs a CVar write that SetCVar answers false", function()
		ns = wow.boot()
		_G.C_CVar.SetCVar = function()
			return false
		end
		ns.LowHealth.Set(false)
		assert.is_false(setting())
		assert.equal("low health:cvar", MemoriesDB.errors[1].where)
		assert.same({}, wow.chat())
	end)

	describe("Settings page option", function()
		local function option()
			return wow.categories[1].settings["Memories_lowHealthFlash"]
		end

		it("asks on an untick and changes nothing until a button is pressed", function()
			ns = wow.boot()
			option():SetValue(false)
			assert.equal(1, popups())
			assert.is_true(setting())
			assert.is_true(option():GetValue())
			assert.same({}, wow.cvar_sets)
			last().info.OnCancel(last(), last().data, "clicked")
			assert.is_false(setting())
			assert.is_false(option():GetValue())
			assert.equal("1", wow.cvars[CVAR])
		end)

		it("turns the flash on when ticked", function()
			ns = wow.boot({ cvars = { [CVAR] = "1" } })
			assert.is_false(option():GetValue())
			option():SetValue(true)
			assert.equal("0", wow.cvars[CVAR])
			assert.is_true(setting())
			assert.is_false(ns.LowHealth.Shown())
		end)
	end)
end)
