local wow = require("helpers.wow")

describe("map journey tab", function()
	wow.pin_locale("enUS", before_each, after_each)

	local ns, Tab, Panel, O
	local ZONE = 1453

	local function boot(opts)
		opts = opts or {}
		for _, name in ipairs({
			"WorldMapFrame",
			"QuestMapFrame",
			"EventRegistry",
			"MapCanvasDataProviderMixin",
			"CreateFromMixins",
		}) do
			_G[name] = nil
		end
		ns = wow.boot({
			login = false,
			maps = { [ZONE] = { mapType = 3 } },
			saved = opts.saved or {
				MemoriesCharDB = {
					trail = {
						v = 1,
						chunks = { { s = 1, t = 1000, m = ZONE, n = 2, d = "0,1000,1000;2,2000,1000" } },
					},
				},
			},
		})
		Tab, Panel, O = ns.MapTab, ns.MapPanel, ns.Overlay
		ns.Store.Reopen()
	end

	-- A fake world map with a quest log that has two tabs.
	local function fakeMap(opts)
		opts = opts or {}
		local canvas = CreateFrame("Frame")
		canvas.canvasWidth, canvas.canvasHeight = 1000, 500
		local map = CreateFrame("Frame", "WorldMapFrame")
		map.providers = {}
		map.mapID = ZONE
		function map:AddDataProvider(p)
			self.providers[#self.providers + 1] = p
			p.owningMap = self
		end
		function map:GetMapID()
			return self.mapID
		end
		function map:GetCanvas()
			return canvas
		end
		_G.MapCanvasDataProviderMixin = {
			GetMap = function(self)
				return self.owningMap
			end,
		}
		_G.CreateFromMixins = function(mixin)
			local out = {}
			for k, v in pairs(mixin) do
				out[k] = v
			end
			return out
		end
		map.shown = opts.shown == true
		if opts.log ~= false then
			local log = CreateFrame("Frame", "QuestMapFrame")
			log.TabButtons = {}
			for i, bottom in ipairs(opts.bottoms or { 300, 250 }) do
				local tab = CreateFrame("Button", "GameTab" .. i, log)
				tab.bottom = bottom
				log.TabButtons[i] = tab
			end
			log.shown = opts.logShown ~= false
		end
		if opts.registry ~= false then
			local registry = { callbacks = {} }
			function registry:RegisterCallback(event, fn, owner)
				self.callbacks[event] = { fn = fn, owner = owner }
			end
			function registry:Fire(event, ...)
				self.callbacks[event].fn(...)
			end
			_G.EventRegistry = registry
		end
		return map
	end

	local function start(opts)
		boot(opts and opts.boot)
		local map = fakeMap(opts)
		wow.login()
		return map
	end

	local function click(frame)
		frame.scripts.OnClick(frame)
	end

	it("puts the tab under the lowest shown game tab", function()
		start()
		local point = Tab.Button().point
		assert.same({ "TOP", _G.QuestMapFrame.TabButtons[2], "BOTTOM", 0, -Tab.GAP }, { unpack(point, 1, 5) })
		_G.QuestMapFrame.TabButtons[2].shown = false
		Tab.Place()
		assert.equal(_G.QuestMapFrame.TabButtons[1], Tab.Button().point[2])
	end)

	it("puts the tab under the last game tab of the list before the game lays them out", function()
		start({ bottoms = {} })
		local log = _G.QuestMapFrame
		for i = 1, 2 do
			log.TabButtons[i] = CreateFrame("Button", nil, log)
		end
		Tab.Place()
		assert.equal(log.TabButtons[2], Tab.Button().point[2])
	end)

	it("follows the quest log when it hides and shows with the map open", function()
		start({ shown = true })
		click(Tab.Button())
		QuestMapFrame:Hide()
		assert.same({ "TOPLEFT", WorldMapFrame, "TOPRIGHT", 0, Tab.DOCK_OFFSET }, { unpack(Tab.Button().point, 1, 5) })
		assert.same(
			{ "BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", Tab.SIZE + Tab.GAP, 0 },
			{ unpack(Panel.Frame().point, 1, 5) }
		)
		QuestMapFrame:Show()
		assert.equal(_G.QuestMapFrame.TabButtons[2], Tab.Button().point[2])
		assert.equal(0, #ns.Errors())
	end)

	it("docks the open panel again when the quest log changed while the map was closed", function()
		start({ shown = true })
		click(Tab.Button())
		WorldMapFrame:Hide()
		_G.QuestMapFrame.shown = false
		WorldMapFrame:Show()
		assert.same(
			{ "BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", Tab.SIZE + Tab.GAP, 0 },
			{ unpack(Panel.Frame().point, 1, 5) }
		)
	end)

	it("follows a quest log that comes after the map", function()
		boot()
		fakeMap()
		local log = _G.QuestMapFrame
		_G.QuestMapFrame = nil
		wow.login()
		_G.QuestMapFrame = log
		WorldMapFrame:Show()
		assert.equal(log.TabButtons[2], Tab.Button().point[2])
		log:Hide()
		assert.same({ "TOPLEFT", WorldMapFrame, "TOPRIGHT", 0, Tab.DOCK_OFFSET }, { unpack(Tab.Button().point, 1, 5) })
	end)

	it("puts the tab on the map edge when no game tab is shown", function()
		start({ log = false })
		assert.same({ "TOPLEFT", WorldMapFrame, "TOPRIGHT", 0, Tab.DOCK_OFFSET }, { unpack(Tab.Button().point, 1, 5) })
	end)

	it("reads the named tabs of a quest log with no tab list", function()
		start()
		_G.QuestMapFrame.TabButtons = nil
		_G.QuestMapFrame.QuestsTab = CreateFrame("Button", nil, QuestMapFrame)
		_G.QuestMapFrame.QuestsTab.bottom = 100
		Tab.Place()
		assert.equal(_G.QuestMapFrame.QuestsTab, Tab.Button().point[2])
	end)

	it("shows the panel and turns the overlay on with a click, and off with the next one", function()
		start()
		click(Tab.Button())
		assert.is_true(Tab.Selected())
		assert.is_true(O.Enabled())
		assert.is_true(Panel.Frame().shown)
		assert.is_true(Tab.Button().selected.shown)
		assert.equal("journey", MemoriesDB.settings.map.tab)
		click(Tab.Button())
		assert.is_false(Tab.Selected())
		assert.is_false(O.Enabled())
		assert.is_false(Panel.Frame().shown)
		assert.equal("quest", MemoriesDB.settings.map.tab)
	end)

	it("takes the place of the quest log, or docks beside the map without it", function()
		start()
		_G.QuestMapFrame:SetFrameLevel(5)
		click(Tab.Button())
		assert.equal(_G.QuestMapFrame, Panel.Frame().allPoints)
		assert.equal(5 + Tab.LEVEL_ABOVE_LOG, Panel.Frame():GetFrameLevel())
		click(Tab.Button())
		_G.QuestMapFrame.shown = false
		click(Tab.Button())
		assert.same(
			{ "BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", Tab.SIZE + Tab.GAP, 0 },
			{ unpack(Panel.Frame().point, 1, 5) }
		)
	end)

	it("turns the overlay off with a click on a game tab", function()
		start()
		click(Tab.Button())
		_G.QuestMapFrame.TabButtons[1].scripts.OnClick(_G.QuestMapFrame.TabButtons[1])
		assert.is_false(Tab.Selected())
		assert.is_false(O.Enabled())
		assert.is_false(Panel.Frame().shown)
		assert.equal("quest", MemoriesDB.settings.map.tab)
	end)

	it("turns the overlay off when the quest log changes its display mode", function()
		start()
		click(Tab.Button())
		EventRegistry:Fire("QuestLog.SetDisplayMode", 1)
		assert.is_false(O.Enabled())
		assert.is_false(Panel.Frame().shown)
		EventRegistry:Fire("QuestLog.SetDisplayMode", 1)
		assert.is_false(Tab.Selected())
		assert.equal("journey", MemoriesDB.settings.map.tab)
	end)

	it("saves the quest log as the last tab when a game tab click follows a display mode change", function()
		start()
		click(Tab.Button())
		EventRegistry:Fire("QuestLog.SetDisplayMode", 1)
		_G.QuestMapFrame.TabButtons[1].scripts.OnClick(_G.QuestMapFrame.TabButtons[1])
		assert.is_false(Tab.Selected())
		assert.equal("quest", MemoriesDB.settings.map.tab)
	end)

	it("opens the map on the tab used last", function()
		start({ boot = { saved = { MemoriesDB = { settings = { map = { tab = "journey" } } } } } })
		assert.is_false(Tab.Selected())
		WorldMapFrame:Show()
		assert.is_true(Tab.Selected())
		assert.is_true(O.Enabled())
		assert.is_true(Panel.Frame().shown)
		assert.equal("journey", MemoriesDB.settings.map.tab)
	end)

	it("restores at once when the map is already shown", function()
		start({ shown = true, boot = { saved = { MemoriesDB = { settings = { map = { tab = "journey" } } } } } })
		assert.is_true(Tab.Selected())
	end)

	it("stays on the quest log when that was the last tab", function()
		start()
		WorldMapFrame:Show()
		assert.is_false(Tab.Selected())
		assert.is_nil(Panel.Frame())
	end)

	it("hooks each game tab once", function()
		start()
		WorldMapFrame:Hide()
		WorldMapFrame:Show()
		WorldMapFrame:Show()
		click(Tab.Button())
		local writes = 0
		local set = ns.Settings.Set
		ns.Settings.Set = function(path, ...)
			if path == "map.tab" then
				writes = writes + 1
			end
			return set(path, ...)
		end
		_G.QuestMapFrame.TabButtons[1].scripts.OnClick(_G.QuestMapFrame.TabButtons[1])
		ns.Settings.Set = set
		assert.equal(1, writes)
		assert.is_false(Tab.Selected())
		assert.equal(0, #ns.Errors())
	end)

	it("leaves Journey on a left mouse up inside a game tab that is a plain frame", function()
		start()
		local tab = CreateFrame("Frame", nil, QuestMapFrame)
		_G.QuestMapFrame.TabButtons[3] = tab
		click(Tab.Button())
		assert.is_nil(tab.scripts.OnClick)
		tab.scripts.OnMouseUp(tab, "RightButton", true)
		tab.scripts.OnMouseUp(tab, "LeftButton", false)
		assert.is_true(Tab.Selected())
		tab.scripts.OnMouseUp(tab, "LeftButton", true)
		assert.is_false(Tab.Selected())
		assert.equal("quest", MemoriesDB.settings.map.tab)
		assert.equal(0, #ns.Errors())
	end)

	it("works with no EventRegistry", function()
		start({ registry = false })
		click(Tab.Button())
		assert.is_true(Tab.Selected())
	end)

	it("waits for the world map when it is not there at login", function()
		boot()
		wow.login()
		assert.is_false(Tab.Attach())
		fakeMap()
		wow.fire("ADDON_LOADED", "Blizzard_Other")
		assert.is_nil(Tab.Button())
		wow.fire("ADDON_LOADED", "Blizzard_WorldMap")
		assert.is_not_nil(Tab.Button())
		assert.is_true(Tab.Attach())
	end)

	it("shows a tooltip on the tab", function()
		start()
		local tab = Tab.Button()
		tab.scripts.OnEnter(tab)
		assert.same({ "Journey" }, wow.tooltip.lines)
		tab.scripts.OnLeave(tab)
		assert.is_false(GameTooltip.shown)
	end)

	it("stays off and builds the panel again after a failed build", function()
		start()
		local create = CreateFrame
		_G.CreateFrame = function(kind, ...)
			if kind == "ScrollFrame" then
				error("no template")
			end
			return create(kind, ...)
		end
		click(Tab.Button())
		_G.CreateFrame = create
		assert.is_false(Tab.Selected())
		assert.is_nil(Panel.Frame())
		assert.equal(1, #ns.Errors())
		click(Tab.Button())
		assert.is_true(Tab.Selected())
		assert.is_true(Panel.Frame().shown)
	end)

	it("keeps a failed click out of the map", function()
		start()
		ns.Overlay.Show = function()
			error("boom")
		end
		assert.has_no.errors(function()
			click(Tab.Button())
		end)
		assert.equal(1, #ns.Errors())
	end)

	describe("panel", function()
		local function boxes()
			local out = {}
			for _, f in ipairs(wow.frames) do
				if f.kind == "CheckButton" then
					out[#out + 1] = f
				end
			end
			return out
		end

		local function byLabel(text)
			for _, f in ipairs(boxes()) do
				if f.label and f.label.text == text then
					return f
				end
			end
		end

		local function sessionRows()
			local content = Panel.Frame().content
			local out = {}
			for _, f in ipairs(wow.frames) do
				if f.kind == "Button" and f.parent == content then
					out[#out + 1] = f
				end
			end
			return out
		end

		it("has a box for the trail and for each group, set from the settings", function()
			start()
			ns.Settings.Set("map.groups.Deaths", false)
			click(Tab.Button())
			assert.is_true(byLabel("Trail").checked)
			assert.is_true(byLabel("Progress").checked)
			assert.is_false(byLabel("Deaths").checked)
			assert.equal(#ns.MapData.Groups() + 1, #boxes())
		end)

		it("saves a group box and draws again", function()
			start()
			click(Tab.Button())
			local drawn = 0
			ns.Listen("MAP_OVERLAY_DRAWN", function()
				drawn = drawn + 1
			end)
			local deaths = byLabel("Deaths")
			deaths.checked = false
			click(deaths)
			assert.is_false(MemoriesDB.settings.map.groups.Deaths)
			assert.is_true(drawn > 0)
			deaths.checked = true
			click(deaths)
			assert.is_true(MemoriesDB.settings.map.groups.Deaths)
		end)

		it("saves the trail box and draws no line with it off", function()
			start({ shown = true })
			click(Tab.Button())
			wow.advance(0.01)
			assert.equal(1, O.Stats().lines)
			local trail = byLabel("Trail")
			trail.checked = false
			click(trail)
			assert.is_false(MemoriesDB.settings.map.trail)
			assert.equal(0, O.Stats().lines)
		end)

		it("lists All and the sessions, the newest first, and chooses one", function()
			start({
				boot = {
					saved = {
						MemoriesCharDB = {
							sessions = {
								{ start = 1000, last = 1100 },
								{ start = 2000, last = 5600 },
							},
						},
					},
				},
			})
			click(Tab.Button())
			local rows = sessionRows()
			assert.equal(4, #rows)
			assert.equal("All", rows[1].text.text)
			assert.truthy(rows[2].text.text:find("0 s", 1, true))
			assert.truthy(rows[3].text.text:find("1 h", 1, true))
			assert.truthy(rows[4].text.text:find("1 min", 1, true))
			click(rows[3])
			assert.same({ start = 2000, stop = 5600 }, O.Session())
			assert.is_true(rows[3].mark.shown)
			assert.is_false(rows[4].mark.shown)
			click(rows[1])
			assert.is_nil(O.Session())
			assert.is_true(rows[1].mark.shown)
		end)

		it("makes rows only for the sessions in view and moves them with the scroll", function()
			local list = {}
			for i = 1, 200 do
				list[i] = { start = i * 1000, last = i * 1000 + 60 }
			end
			start({ boot = { saved = { MemoriesCharDB = { sessions = list } } } })
			click(Tab.Button())
			local rows = sessionRows
			assert.equal(Panel.VISIBLE, #rows())
			assert.equal("All", rows()[1].text.text)
			Panel.Frame().scroll:SetVerticalScroll(10 * Panel.ROW)
			assert.equal(Panel.VISIBLE, #rows())
			local top = rows()[1]
			assert.same({ "TOPLEFT", 0, -10 * Panel.ROW }, { unpack(top.point, 1, 3) })
			click(top)
			local sessions = ns.MapData.Sessions()
			assert.same(sessions[#sessions - 9], O.Session())
			assert.is_true(top.mark.shown)
		end)

		it("shows the counts, the cap note and the zones that are not shown", function()
			start()
			click(Tab.Button())
			assert.equal(
				"0 lines, 0 pins",
				Panel.CountText({ lines = 0, pins = 0, cutLines = 0, cutPins = 0, zones = 0 })
			)
			local text = Panel.CountText({ lines = 5, pins = 2, cutLines = 1, cutPins = 0, zones = 3 })
			assert.truthy(text:find("5 lines, 2 pins", 1, true))
			assert.truthy(text:find("Cut at 3000 lines and 500 pins.", 1, true))
			assert.truthy(text:find("3 zones not shown", 1, true))
			ns.Emit("MAP_OVERLAY_DRAWN", { lines = 7, pins = 1, cutLines = 0, cutPins = 0, zones = 0 })
			assert.equal("7 lines, 1 pins", Panel.Frame().count.text)
		end)

		it("keeps the choices for the session when all of Memories is read-only", function()
			start({ boot = { saved = { MemoriesDB = { schema = 99 } } } })
			click(Tab.Button())
			local deaths = byLabel("Deaths")
			deaths.checked = false
			click(deaths)
			assert.is_nil(MemoriesDB.settings)
			assert.is_false(ns.Settings.Get("map.groups.Deaths"))
			assert.equal("journey", ns.Settings.Get("map.tab"))
		end)

		it("names a kind group with no group Other, and an unknown group by its token", function()
			start()
			ns.Kinds.Register("zq", { addon = "Memories", name = "Zq" })
			ns.Kinds.Register("zr", { addon = "Memories", group = "Mystery", name = "Zr" })
			click(Tab.Button())
			assert.is_not_nil(byLabel("Other"))
			assert.is_not_nil(byLabel("Mystery"))
		end)

		it("shows a session that is still running up to now", function()
			start()
			assert.truthy(Panel.SessionText({ start = wow.wall - 120 }):find("2 min", 1, true))
		end)
	end)
end)
