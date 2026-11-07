local wow = require("helpers.wow")

describe("save reminder and minimap button", function()
	local REMINDER = "Memories: 1 hour since the last save. Click the minimap button to save (reloads the UI)."

	local function count(list, text)
		local n = 0
		for _, v in ipairs(list) do
			if v == text then
				n = n + 1
			end
		end
		return n
	end

	local function button()
		return MemoriesMinimapButton
	end

	describe("save reminder", function()
		it("prints once after 60 minutes without a save and makes the button pulse", function()
			wow.boot()
			assert.is_falsy(button().pulsing)
			wow.advance(59 * 60)
			assert.equal(0, count(wow.chat(), REMINDER))
			wow.advance(60)
			assert.equal(1, count(wow.chat(), REMINDER))
			assert.is_true(button().pulsing)
			assert.is_true(button().glow:IsShown())
			assert.is_function(button():GetScript("OnUpdate"))
			button():GetScript("OnUpdate")(button())
			wow.advance(3 * 60 * 60)
			assert.equal(1, count(wow.chat(), REMINDER))
		end)

		it("starts again at each login", function()
			wow.boot()
			wow.advance(45 * 60)
			wow.reload()
			wow.advance(45 * 60)
			assert.equal(0, count(wow.chat(), REMINDER))
			wow.advance(15 * 60)
			assert.equal(1, count(wow.chat(), REMINDER))
		end)

		it("stays quiet when the saveReminder setting is off", function()
			wow.boot({ saved = { MemoriesDB = { settings = { saveReminder = false } } } })
			wow.advance(2 * 60 * 60)
			assert.equal(0, count(wow.chat(), REMINDER))
			assert.is_falsy(button().pulsing)
		end)

		it("reads the saveReminder setting at each check", function()
			local ns = wow.boot()
			ns.Settings.Set("saveReminder", false)
			wow.advance(61 * 60)
			assert.equal(0, count(wow.chat(), REMINDER))
			ns.Settings.Set("saveReminder", true)
			wow.advance(60)
			assert.equal(1, count(wow.chat(), REMINDER))
		end)
	end)

	describe("minimap button", function()
		it("is a button on the minimap", function()
			wow.boot()
			assert.equal("Button", button().kind)
			assert.equal(Minimap, button():GetParent())
			assert.is_true(button():IsShown())
		end)

		it("saves on a left click, out of combat only", function()
			wow.boot()
			wow.combat = true
			button():GetScript("OnClick")(button(), "LeftButton")
			assert.equal(0, wow.reloads)
			assert.same({ "Memories: cannot save in combat." }, wow.chat())
			wow.combat = false
			button():GetScript("OnClick")(button(), "LeftButton")
			assert.equal(1, wow.reloads)
		end)

		it("opens the settings page on a right click", function()
			wow.boot()
			button():GetScript("OnClick")(button(), "RightButton")
			assert.equal(0, wow.reloads)
			assert.equal(wow.categories[1]:GetID(), wow.opened)
		end)

		it("shows the minutes since the last save in its tooltip", function()
			wow.boot()
			wow.advance(25 * 60 + 30)
			button():GetScript("OnEnter")(button())
			assert.same({
				"Memories",
				"25 min since the last save",
				"Left click: save (reload)",
				"Right click: settings",
			}, wow.tooltip.lines)
			assert.is_true(GameTooltip:IsShown())
			button():GetScript("OnLeave")(button())
			assert.is_false(GameTooltip:IsShown())
		end)

		it("sits at the default angle on a first login", function()
			wow.boot()
			assert.equal(225, MemoriesDB.minimap.angle)
			local point = button().point
			assert.equal("CENTER", point[1])
			assert.equal(Minimap, point[2])
			assert.is_true(math.abs(point[4] + 80 * math.sqrt(0.5)) < 1e-6)
			assert.is_true(math.abs(point[5] + 80 * math.sqrt(0.5)) < 1e-6)
		end)

		it("follows the cursor around the edge and saves the angle", function()
			wow.boot()
			-- The minimap center is (700, 500) at scale 2, so this cursor is straight above it.
			wow.cursor = { 1400, 1200 }
			button():GetScript("OnDragStart")(button())
			button():GetScript("OnUpdate")(button())
			button():GetScript("OnDragStop")(button())
			assert.is_nil(button():GetScript("OnUpdate"))
			assert.is_true(math.abs(MemoriesDB.minimap.angle - 90) < 1e-6)
			assert.is_true(math.abs(button().point[4]) < 1e-6)
			assert.is_true(math.abs(button().point[5] - 80) < 1e-6)
			wow.reload()
			assert.is_true(math.abs(MemoriesDB.minimap.angle - 90) < 1e-6)
			assert.is_true(math.abs(button().point[5] - 80) < 1e-6)
		end)

		it("keeps pulsing after a drag", function()
			wow.boot()
			wow.advance(60 * 60)
			button():GetScript("OnDragStart")(button())
			button():GetScript("OnDragStop")(button())
			assert.is_true(button().pulsing)
			assert.is_function(button():GetScript("OnUpdate"))
		end)

		it("is hidden when the minimapButton setting is off", function()
			local ns = wow.boot({ saved = { MemoriesDB = { settings = { minimapButton = false } } } })
			assert.is_false(button():IsShown())
			ns.Settings.Set("minimapButton", true)
			assert.is_true(button():IsShown())
			MemoriesDB.settings.minimapButton = false
			ns.Settings.Set("saveReminder", false)
			assert.is_true(button():IsShown())
			ns.Settings.Set("minimapButton", false)
			assert.is_false(button():IsShown())
		end)

		it("is created once, at login", function()
			local ns = wow.boot({ login = false })
			ns.MinimapButton.Pulse(true)
			assert.is_nil(MemoriesMinimapButton)
			wow.login()
			assert.equal(button(), ns.MinimapButton.Create())
		end)

		it("starts at the saved angle and never writes it when MemoriesDB is from a newer Memories", function()
			local ns = wow.boot({ saved = { MemoriesDB = { schema = 99, minimap = { angle = 90 } } } })
			assert.is_true(ns.Store.ReadOnlyAll())
			assert.is_true(math.abs(button().point[4]) < 1e-6)
			assert.is_true(math.abs(button().point[5] - 80) < 1e-6)
			wow.cursor = { 1400, 0 }
			button():GetScript("OnDragStart")(button())
			button():GetScript("OnUpdate")(button())
			button():GetScript("OnDragStop")(button())
			assert.equal(90, MemoriesDB.minimap.angle)
			assert.is_false(math.abs(button().point[5] - 80) < 1e-6)
		end)

		it("replaces a saved angle that is not a number", function()
			wow.boot({ saved = { MemoriesDB = { minimap = { angle = "up" } } } })
			assert.equal(225, MemoriesDB.minimap.angle)
		end)
	end)
end)
