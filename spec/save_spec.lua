local wow = require("helpers.wow")

describe("save reminder and minimap button", function()
	wow.pin_locale("enUS", before_each, after_each)

	local REMINDER = "Memories: 1 hour since the last save. Shift-click the minimap button to save (reloads the UI)."

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
		return _G.LibDBIcon10_Memories
	end

	local function glow()
		return button().memoriesGlow
	end

	describe("save reminder", function()
		it("prints once after 60 minutes without a save and makes the button pulse", function()
			wow.boot()
			assert.is_nil(glow())
			wow.advance(59 * 60)
			assert.equal(0, count(wow.chat(), REMINDER))
			wow.advance(60)
			assert.equal(1, count(wow.chat(), REMINDER))
			assert.is_true(glow():IsShown())
			assert.is_true(glow().pulse:IsPlaying())
			assert.is_nil(button():GetScript("OnUpdate"))
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
			assert.is_nil(glow())
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
		it("is a LibDBIcon button on the minimap and an addon compartment entry", function()
			wow.boot()
			assert.equal(Minimap, button():GetParent())
			assert.is_true(button():IsShown())
			assert.equal("launcher", wow.ldb.Memories.type)
			assert.equal("Interface\\AddOns\\Memories\\assets\\icon", wow.ldb.Memories.icon)
			assert.equal(MemoriesDB.minimap, button().db)
			assert.is_function(wow.compartment.Memories)
		end)

		it("opens the Note window on a left click and does not reload", function()
			wow.boot()
			button():GetScript("OnClick")(button(), "LeftButton")
			assert.equal(0, wow.reloads)
			assert.is_true(_G.MemoriesNoteFrame:IsShown())
		end)

		it("opens the Note window again on a left click while it is shown, and keeps one frame", function()
			wow.boot()
			button():GetScript("OnClick")(button(), "LeftButton")
			local frame = _G.MemoriesNoteFrame
			button():GetScript("OnClick")(button(), "LeftButton")
			assert.equal(frame, _G.MemoriesNoteFrame)
			assert.is_true(frame:IsShown())
		end)

		it("saves on a shift + left click, out of combat only", function()
			wow.boot()
			wow.shift = true
			wow.combat = true
			button():GetScript("OnClick")(button(), "LeftButton")
			assert.equal(0, wow.reloads)
			assert.same({ "Memories: cannot save in combat." }, wow.chat())
			wow.combat = false
			button():GetScript("OnClick")(button(), "LeftButton")
			assert.equal(1, wow.reloads)
			assert.is_nil(_G.MemoriesNoteFrame)
		end)

		it("does not open the Note window on a right click", function()
			wow.boot()
			button():GetScript("OnClick")(button(), "RightButton")
			assert.is_nil(_G.MemoriesNoteFrame)
		end)

		it("gives the addon compartment entry the same clicks", function()
			wow.boot()
			wow.compartment.Memories("LeftButton")
			assert.is_true(_G.MemoriesNoteFrame:IsShown())
			wow.compartment.Memories("RightButton")
			assert.equal(wow.categories[1]:GetID(), wow.opened)
			wow.shift = true
			wow.compartment.Memories("LeftButton")
			assert.equal(1, wow.reloads)
		end)

		it("opens the settings page on a right click", function()
			wow.boot()
			button():GetScript("OnClick")(button(), "RightButton")
			assert.equal(0, wow.reloads)
			assert.equal(wow.categories[1]:GetID(), wow.opened)
		end)

		it("logs an error of a click and keeps the button", function()
			local ns = wow.boot()
			ns.NoteWindow.Open = function()
				error("note broke")
			end
			button():GetScript("OnClick")(button(), "LeftButton")
			local errors = ns.Errors()
			assert.equal("minimap:click", errors[#errors].where)
		end)

		it("shows the minutes since the last save in its tooltip", function()
			wow.boot()
			wow.advance(25 * 60 + 30)
			button():GetScript("OnEnter")(button())
			assert.same({
				"Memories",
				"25 min since the last save",
				"Left click: write a note",
				"Shift + left click: save (reload)",
				"Right click: settings",
				"Drag: move the button",
			}, wow.tooltip.lines)
			assert.is_true(GameTooltip:IsShown())
			button():GetScript("OnLeave")(button())
			assert.is_false(GameTooltip:IsShown())
		end)

		it("lets LibDBIcon use its default position on a first login", function()
			wow.boot()
			assert.is_nil(MemoriesDB.minimap.minimapPos)
			assert.is_false(MemoriesDB.minimap.hide)
		end)

		it("moves the angle of the hand-written button to minimapPos", function()
			wow.boot({ saved = { MemoriesDB = { minimap = { angle = 90 } } } })
			assert.equal(90, MemoriesDB.minimap.minimapPos)
			assert.is_nil(MemoriesDB.minimap.angle)
		end)

		it("keeps a saved minimapPos and drops one that is not a number", function()
			wow.boot({ saved = { MemoriesDB = { minimap = { minimapPos = 10, angle = 90 } } } })
			assert.equal(10, MemoriesDB.minimap.minimapPos)
			wow.boot({ saved = { MemoriesDB = { minimap = { minimapPos = "up" } } } })
			assert.is_nil(MemoriesDB.minimap.minimapPos)
		end)

		it("is hidden when the minimapButton setting is off", function()
			local ns = wow.boot({ saved = { MemoriesDB = { settings = { minimapButton = false } } } })
			assert.is_false(button():IsShown())
			assert.is_true(MemoriesDB.minimap.hide)
			ns.Settings.Set("minimapButton", true)
			assert.is_true(button():IsShown())
			assert.is_false(MemoriesDB.minimap.hide)
			ns.Settings.Set("saveReminder", false)
			assert.is_true(button():IsShown())
			ns.Settings.Set("minimapButton", false)
			assert.is_false(button():IsShown())
		end)

		it("shows and hides with /memories minimap", function()
			wow.boot()
			SlashCmdList.MEMORIES("minimap")
			assert.is_false(button():IsShown())
			assert.is_false(MemoriesDB.settings.minimapButton)
			SlashCmdList.MEMORIES("minimap")
			assert.is_true(button():IsShown())
			assert.same({ "Memories: Minimap button hidden.", "Memories: Minimap button shown." }, wow.chat())
		end)

		it("is registered once, at login", function()
			local ns = wow.boot({ login = false })
			ns.Minimap.Pulse(true)
			assert.is_nil(button())
			wow.login()
			assert.is_truthy(button())
		end)

		it("does nothing without the libraries", function()
			local ns = wow.boot({ login = false })
			_G.LibStub = nil
			wow.login()
			assert.is_nil(ns.Minimap.Button())
			ns.Minimap.Pulse(true)
			ns.Minimap.Apply(false)
			assert.is_false(ns.Minimap.Register())
		end)

		it("hands LibDBIcon a session copy when MemoriesDB is from a newer Memories", function()
			local ns = wow.boot({ saved = { MemoriesDB = { schema = 99, minimap = { angle = 90 } } } })
			assert.is_true(ns.Store.ReadOnlyAll())
			assert.equal(90, button().db.minimapPos)
			button().db.minimapPos = 10
			ns.Settings.Set("minimapButton", false)
			assert.same({ angle = 90 }, MemoriesDB.minimap)
		end)
	end)
end)
