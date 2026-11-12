local wow = require("helpers.wow")

describe("journey window", function()
	wow.pin_locale("enUS", before_each, after_each)

	local ns, Tab, Panel, O, W
	local ZONE, OTHER, CONT = 1453, 1454, 12

	local function boot(opts)
		opts = opts or {}
		for _, name in ipairs({ "WorldMapFrame", "QuestMapFrame", "MemoriesJourneyFrame" }) do
			_G[name] = nil
		end
		ns = wow.boot({
			login = false,
			maps = opts.maps or {
				[CONT] = { mapType = 2, name = "Continent" },
				[ZONE] = { mapType = 3, name = "Zone", parentMapID = CONT },
				[OTHER] = { mapType = 3, name = "Other", parentMapID = CONT },
			},
			art = opts.art,
			explored = opts.explored,
			zoneAt = opts.zoneAt,
			projections = opts.projections,
			saved = opts.saved or {
				MemoriesCharDB = {
					trail = {
						v = 1,
						chunks = { { s = 1, t = 1000, m = ZONE, n = 2, d = "0,1000,1000;2,2000,1000" } },
					},
				},
			},
		})
		Tab, Panel, O, W = ns.MapTab, ns.MapPanel, ns.Overlay, ns.MapWindow
		_G.UISpecialFrames = {}
		ns.Store.Reopen()
	end

	-- A fake world map with a quest log that has two tabs.
	local function fakeMap(opts)
		opts = opts or {}
		local map = CreateFrame("Frame", "WorldMapFrame")
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
		return map
	end

	local function start(opts)
		boot(opts and opts.boot)
		local map = fakeMap(opts)
		wow.login()
		return map
	end

	local function click(frame, button)
		frame.scripts.OnClick(frame, button)
	end

	local function textures(layer)
		local out = {}
		for _, f in ipairs(wow.frames) do
			if f.kind == "Texture" and f.parent == W.Canvas() and f.layer == layer and f.shown then
				out[#out + 1] = f
			end
		end
		return out
	end

	describe("the button on the world map", function()
		it("sits under the lowest shown game tab", function()
			start()
			local point = Tab.Button().point
			assert.same({ "TOP", _G.QuestMapFrame.TabButtons[2], "BOTTOM", 0, -Tab.GAP }, { unpack(point, 1, 5) })
			_G.QuestMapFrame.TabButtons[2].shown = false
			Tab.Place()
			assert.equal(_G.QuestMapFrame.TabButtons[1], Tab.Button().point[2])
		end)

		it("sits under the last game tab of the list before the game lays them out", function()
			start({ bottoms = {} })
			local log = _G.QuestMapFrame
			for i = 1, 2 do
				log.TabButtons[i] = CreateFrame("Button", nil, log)
			end
			Tab.Place()
			assert.equal(log.TabButtons[2], Tab.Button().point[2])
		end)

		it("sits on the map edge with no game tab or a hidden quest log, and moves when the map shows", function()
			start({ log = false })
			assert.same(
				{ "TOPLEFT", WorldMapFrame, "TOPRIGHT", 0, Tab.DOCK_OFFSET },
				{ unpack(Tab.Button().point, 1, 5) }
			)
			local log = CreateFrame("Frame", "QuestMapFrame")
			log.TabButtons = { CreateFrame("Button", nil, log) }
			log.shown = false
			WorldMapFrame:Show()
			assert.equal(WorldMapFrame, Tab.Button().point[2])
			log.shown = true
			WorldMapFrame:Show()
			assert.equal(log.TabButtons[1], Tab.Button().point[2])
		end)

		it("reads the named tabs of a quest log with no tab list", function()
			start()
			_G.QuestMapFrame.TabButtons = nil
			_G.QuestMapFrame.QuestsTab = CreateFrame("Button", nil, _G.QuestMapFrame)
			_G.QuestMapFrame.QuestsTab.bottom = 100
			Tab.Place()
			assert.equal(_G.QuestMapFrame.QuestsTab, Tab.Button().point[2])
		end)

		it("opens the Journey window with a click, closes it with the next one, and is lit while it is open", function()
			start()
			click(Tab.Button())
			assert.is_true(W.Shown())
			assert.is_true(O.Enabled())
			assert.is_true(Panel.Frame().shown)
			assert.is_true(Tab.Button().selected.shown)
			click(Tab.Button())
			assert.is_false(W.Shown())
			assert.is_false(O.Enabled())
			assert.is_false(Panel.Frame().shown)
			assert.is_false(Tab.Button().selected.shown)
		end)

		it("shows a tooltip", function()
			start()
			local tab = Tab.Button()
			tab.scripts.OnEnter(tab)
			assert.same({ "Journey" }, wow.tooltip.lines)
			tab.scripts.OnLeave(tab)
			assert.is_false(GameTooltip.shown)
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

		it("keeps a failed click out of the map", function()
			start()
			ns.MapWindow.Toggle = function()
				error("boom")
			end
			assert.has_no.errors(function()
				click(Tab.Button())
			end)
			assert.equal(1, #ns.Errors())
		end)
	end)

	describe("the window", function()
		it("opens on the map of the player, with its name, and closes with Escape", function()
			start()
			W.Toggle()
			assert.equal(ZONE, W.MapID())
			assert.equal("Zone", W.Frame().mapName.text)
			assert.same({ "MemoriesJourneyFrame" }, UISpecialFrames)
			assert.equal("Journey", W.Frame().TitleText and W.Frame().TitleText.text or "Journey")
		end)

		it("opens on the first map of the trail when the map of the player has no art", function()
			start({ boot = { art = { [ZONE] = false } } })
			wow.map.id = ZONE
			local saved = MemoriesCharDB.trail.chunks
			saved[#saved + 1] = { s = 1, t = 2000, m = OTHER, n = 2, d = "0,1000,1000;2,2000,1000" }
			W.Toggle()
			assert.equal(OTHER, W.MapID())
		end)

		it("opens on the nearest map above the player with art, in an instance with no trail", function()
			local DUNGEON = 999
			start({
				boot = {
					saved = { MemoriesCharDB = { trail = { v = 1, chunks = {} } } },
					maps = {
						[CONT] = { mapType = 2, name = "Continent" },
						[ZONE] = { mapType = 3, name = "Zone", parentMapID = CONT },
						[DUNGEON] = { mapType = 4, name = "Dungeon", parentMapID = ZONE },
					},
					art = { [DUNGEON] = false },
				},
			})
			wow.map.id = DUNGEON
			W.Toggle()
			assert.equal(ZONE, W.MapID())
			assert.equal("Zone", W.Frame().mapName.text)
		end)

		it("opens with no map, no name and no Up when nothing has art", function()
			start({ boot = { art = { [ZONE] = false, [CONT] = false, [OTHER] = false } } })
			wow.map.id = ZONE
			assert.has_no.errors(W.Toggle)
			assert.is_true(W.Shown())
			assert.is_nil(W.MapID())
			assert.is_false(W.Frame().up.enabled)
			assert.equal(0, #textures("BACKGROUND"))
			assert.equal(0, #ns.Errors())
		end)

		it("draws the tiles of the map art in rows, scaled to the canvas", function()
			start()
			W.Toggle()
			local tiles = textures("BACKGROUND")
			assert.equal(12, #tiles)
			local sx, sy = W.MAP_W / 1002, W.MAP_H / 668
			assert.equal(ZONE * 100 + 1, tiles[1].texture)
			assert.same({ 256 * sx, 256 * sy }, tiles[1].size)
			assert.same({ "TOPLEFT", W.Canvas(), "TOPLEFT", 0, 0 }, { unpack(tiles[1].point, 1, 5) })
			assert.same({ "TOPLEFT", W.Canvas(), "TOPLEFT", 256 * sx, -256 * sy }, { unpack(tiles[6].point, 1, 5) })
		end)

		it("draws the explored areas over the tiles, in pieces, with the last ones cut to their files", function()
			start({
				boot = {
					explored = {
						[ZONE] = {
							{
								textureWidth = 300,
								textureHeight = 100,
								offsetX = 10,
								offsetY = 20,
								fileDataIDs = { 7, 8 },
							},
							{
								textureWidth = 50,
								textureHeight = 50,
								offsetX = 0,
								offsetY = 0,
								fileDataIDs = { 9 },
								isShownByMouseOver = true,
							},
							{ textureWidth = 10, textureHeight = 256, offsetX = 0, offsetY = 0, fileDataIDs = { 11 } },
						},
					},
				},
			})
			W.Toggle()
			local pieces = textures("BORDER")
			assert.equal(3, #pieces)
			local sx, sy = W.MAP_W / 1002, W.MAP_H / 668
			assert.equal(7, pieces[1].texture)
			assert.same({ 256 * sx, 100 * sy }, pieces[1].size)
			assert.same({ 0, 1, 0, 100 / 128 }, pieces[1].texCoord)
			assert.same({ 44 * sx, 100 * sy }, pieces[2].size)
			assert.same({ 0, 44 / 64, 0, 100 / 128 }, pieces[2].texCoord)
			assert.same({ "TOPLEFT", W.Canvas(), "TOPLEFT", 266 * sx, -20 * sy }, { unpack(pieces[2].point, 1, 5) })
			-- A piece narrower than 16 sits in a file of 16, and a piece as tall as a tile fills its file.
			assert.equal(11, pieces[3].texture)
			assert.same({ 10 * sx, 256 * sy }, pieces[3].size)
			assert.same({ 0, 10 / 16, 0, 1 }, pieces[3].texCoord)
		end)

		it("hides the explored areas of the last map when it shows another one", function()
			start({
				boot = {
					explored = {
						[ZONE] = {
							{ textureWidth = 100, textureHeight = 100, offsetX = 0, offsetY = 0, fileDataIDs = { 7 } },
						},
					},
				},
			})
			W.Toggle()
			assert.equal(1, #textures("BORDER"))
			W.ShowMap(OTHER)
			assert.equal(0, #textures("BORDER"))
		end)

		it("goes up to the map that holds it with the Up button and a right click, and not past the top", function()
			start()
			W.Toggle()
			assert.is_true(W.Frame().up.enabled)
			click(W.Frame().up)
			assert.equal(CONT, W.MapID())
			assert.equal("Continent", W.Frame().mapName.text)
			assert.is_false(W.Frame().up.enabled)
			W.ShowMap(ZONE)
			W.Canvas().scripts.OnMouseUp(W.Canvas(), "RightButton")
			assert.equal(CONT, W.MapID())
			W.Up()
			assert.equal(CONT, W.MapID())
		end)

		it("opens the zone under the cursor with a left click", function()
			start({
				boot = {
					zoneAt = function(mapID, x)
						if mapID == CONT and x > 0.5 then
							return OTHER
						end
						return mapID == CONT and ZONE or nil
					end,
				},
			})
			W.Toggle()
			W.ShowMap(CONT)
			local canvas = W.Canvas()
			canvas.left, canvas.topEdge = 100, 700
			wow.cursor = { 100 + 0.75 * W.MAP_W, 700 - 0.5 * W.MAP_H }
			canvas.scripts.OnMouseUp(canvas, "LeftButton")
			assert.equal(OTHER, W.MapID())
			wow.cursor = { 0, 0 }
			canvas.scripts.OnMouseUp(canvas, "LeftButton")
			assert.equal(OTHER, W.MapID())
		end)

		it("does not change for a map with no art", function()
			start({ boot = { art = { [OTHER] = false } } })
			W.Toggle()
			assert.is_false(W.ShowMap(OTHER))
			assert.is_false(W.ShowMap("x"))
			assert.equal(ZONE, W.MapID())
		end)

		it("draws the journey on the map it shows", function()
			start()
			W.Toggle()
			assert.equal(1, O.Stats().lines)
			W.ShowMap(OTHER)
			assert.equal(0, O.Stats().lines)
		end)

		it("follows the replay into another zone on its own map", function()
			start({
				boot = {
					saved = {
						MemoriesCharDB = {
							trail = {
								v = 1,
								chunks = {
									{ s = 1, t = 1000, m = ZONE, n = 3, d = "0,1000,1000;10,2000,1000;20,3000,1000" },
									{ s = 1, t = 1040, m = OTHER, n = 3, d = "0,1000,2000;10,2000,2000;20,3000,2000" },
								},
							},
						},
					},
				},
			})
			W.Toggle()
			O.Play()
			local function frameStep(dt)
				wow.advance(dt)
				for _, f in ipairs(wow.frames) do
					if f.kind == "Frame" and f.scripts.OnUpdate and f.parent == W.Canvas() then
						f.scripts.OnUpdate(f, dt)
					end
				end
			end
			frameStep(0.001)
			frameStep(0.5)
			frameStep(0.5)
			assert.equal(OTHER, W.MapID())
			assert.equal("Other", W.Frame().mapName.text)
			assert.is_true(O.Playing())
			assert.near(40, O.Position(), 0.1)
		end)

		it("puts the panel beside the map and the player bar under it", function()
			start()
			W.Toggle()
			local view = W.Canvas():GetParent()
			assert.same(
				{ "BOTTOMLEFT", view, "BOTTOMRIGHT", W.PAD, -(W.GAP + Panel.BAR_HEIGHT) },
				{ unpack(Panel.Frame().point, 1, 5) }
			)
			assert.same({ "TOPLEFT", view, "BOTTOMLEFT", 0, -W.GAP }, { unpack(Panel.Bar().point, 1, 5) })
			assert.is_true(Panel.Bar().shown)
		end)

		it("keeps a failed show out of the game", function()
			start()
			ns.Overlay.Show = function()
				error("boom")
			end
			assert.has_no.errors(function()
				W.Toggle()
			end)
			assert.equal(1, #ns.Errors())
		end)
	end)

	describe("player bar", function()
		local function open()
			start({
				boot = {
					saved = {
						MemoriesCharDB = {
							trail = {
								v = 1,
								chunks = {
									{ s = 1, t = 1000, m = ZONE, n = 3, d = "0,1000,1000;10,2000,1000;20,3000,1000" },
								},
							},
						},
					},
				},
				shown = true,
			})
			click(Tab.Button())
			return Panel.Bar()
		end

		it("shows the clock and the play button, and plays and pauses with a click", function()
			local bar = open()
			assert.equal("Play", bar.play.text)
			assert.equal("0:20 / 0:20", bar.time.text)
			assert.equal("1x", bar.speed.text)
			assert.is_true(bar.play.enabled)
			click(bar.play)
			assert.is_true(ns.Overlay.Playing())
			assert.equal("Pause", bar.play.text)
			click(bar.play)
			assert.is_false(ns.Overlay.Playing())
			assert.equal("Play", bar.play.text)
		end)

		it("has the Follow box on, saves a click on it, and shows it again from the setting", function()
			local bar = open()
			assert.is_true(bar.follow.checked)
			assert.equal("Follow", bar.follow.label.text)
			bar.follow.checked = false
			click(bar.follow)
			assert.is_false(MemoriesDB.settings.map.follow)
			bar.follow.checked = true
			click(bar.follow)
			assert.is_true(MemoriesDB.settings.map.follow)
			ns.Settings.Set("map.follow", false)
			Panel.UpdateBar()
			assert.is_false(bar.follow.checked)
		end)

		it("cycles the speed with a click on the speed button", function()
			local bar = open()
			click(bar.speed)
			assert.equal("2x", bar.speed.text)
			assert.equal(2, ns.Overlay.Speed())
		end)

		it("gives the slider a thumb of its own size", function()
			local bar = open()
			assert.same({ 32, 32 }, bar.thumb.size)
			assert.equal("Interface\\Buttons\\UI-SliderBar-Button-Horizontal", bar.thumb.texture)
		end)

		it("moves the slider with the playhead and seeks when the player drags it", function()
			local bar = open()
			assert.same({ 0, 20 }, bar.slider.range)
			assert.equal(20, bar.slider.value)
			bar.slider.scripts.OnValueChanged(bar.slider, 5, true)
			assert.equal(5, (ns.Overlay.Position()))
			bar.slider.scripts.OnValueChanged(bar.slider, 9, false)
			assert.equal(5, (ns.Overlay.Position()))
			assert.equal("0:05 / 0:20", bar.time.text)
		end)

		it("leaves the thumb where the player holds it while the replay plays", function()
			local bar = open()
			click(bar.play)
			bar.slider.scripts.OnMouseDown(bar.slider)
			bar.slider.value = 5
			bar.slider.scripts.OnValueChanged(bar.slider, 5, true)
			ns.Emit("MAP_REPLAY_TICK", 6, 40, true)
			assert.equal(5, bar.slider.value)
			assert.equal("0:06 / 0:40", bar.time.text)
			bar.slider.scripts.OnMouseUp(bar.slider)
			ns.Emit("MAP_REPLAY_TICK", 7, 40, true)
			assert.equal(7, bar.slider.value)
		end)

		it("disables the controls with nothing to play", function()
			start({ shown = true })
			for _, group in ipairs(ns.MapData.Groups()) do
				ns.Settings.Set("map.groups." .. group, false)
			end
			ns.Settings.Set("map.trail", false)
			click(Tab.Button())
			local bar = Panel.Bar()
			assert.is_false(bar.play.enabled)
			assert.is_false(bar.speed.enabled)
			assert.is_false(bar.slider.enabled)
			assert.equal("0:00 / 0:00", bar.time.text)
		end)

		it("keeps a failed click out of the map", function()
			local bar = open()
			ns.Overlay.Toggle = function()
				error("boom")
			end
			assert.has_no.errors(function()
				click(bar.play)
			end)
			assert.equal(1, #ns.Errors())
		end)
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
			assert.is_true(byLabel("Level ups").checked)
			assert.is_false(byLabel("Deaths").checked)
			assert.equal(#ns.Overlay.GROUPS + 3, #boxes())
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
			click(Panel.Frame().sessions)
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
			click(Panel.Frame().sessions)
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
		end)

		it("cycles the colour of the trail with the colour button and draws again", function()
			start({ shown = true })
			click(Tab.Button())
			local button = Panel.Frame().color
			assert.equal("Color: Way", button.text)
			click(button)
			assert.equal("Color: Level", button.text)
			assert.equal("level", MemoriesDB.settings.map.color)
			click(button)
			assert.equal("age", MemoriesDB.settings.map.color)
			click(button)
			assert.equal("way", MemoriesDB.settings.map.color)
			assert.equal("Color: Way", button.text)
		end)

		it("saves the colourblind palette box", function()
			start({ shown = true })
			click(Tab.Button())
			local blind = byLabel("Colorblind palette")
			assert.is_false(blind.checked)
			blind.checked = true
			click(blind)
			assert.is_true(MemoriesDB.settings.map.colorblind)
			ns.Settings.Set("map.colorblind", false)
			Panel.Refresh()
			assert.is_false(blind.checked)
		end)

		describe("chapters and highlights", function()
			local TRAIL = {
				s = 1,
				t = 1000,
				m = ZONE,
				n = 5,
				d = "0,1000,1000;10,2000,1000;20,3000,1000;30,4000,1000;40,5000,1000",
			}

			local function open()
				start({
					boot = { saved = { MemoriesCharDB = { trail = { v = 1, chunks = { TRAIL } } } } },
					shown = true,
				})
				local j = ns.Store.Core()
				j:WriteAt({ t = 1015, m = ZONE, x = 5000, y = 5000 }, "lv", 12)
				j:WriteAt({ t = 1035, m = ZONE, x = 6000, y = 5000 }, "de", "Wolf")
				click(Tab.Button())
				return Panel.Frame()
			end

			local function frameStep(dt)
				wow.advance(dt)
				local c
				for _, f in ipairs(wow.frames) do
					if f.kind == "Frame" and f.scripts.OnUpdate and f.parent == ns.MapWindow.Canvas() then
						c = f
					end
				end
				if c then
					c.scripts.OnUpdate(c, dt)
				end
			end

			it(
				"lists the start and the levels as chapters by default, and marks the chapter of the playhead",
				function()
					open()
					local rows = sessionRows()
					assert.equal(2, #rows)
					assert.equal("Start", rows[1].text.text)
					assert.equal("Level 12", rows[2].text.text)
					assert.is_false(rows[1].mark.shown)
					assert.is_true(rows[2].mark.shown)
				end
			)

			it("jumps the replay to a chapter with a click", function()
				open()
				local rows = sessionRows()
				click(rows[1])
				assert.equal(0, (ns.Overlay.Position()))
				assert.is_true(rows[1].mark.shown)
				assert.is_false(rows[2].mark.shown)
				click(rows[2])
				assert.equal(15, (ns.Overlay.Position()))
				assert.is_true(rows[2].mark.shown)
			end)

			it("moves the mark when the playhead passes a chapter", function()
				open()
				local rows = sessionRows()
				click(rows[1])
				frameStep(0.001)
				ns.Overlay.Play()
				frameStep(0.2)
				assert.is_true(rows[1].mark.shown)
				frameStep(0.3)
				assert.is_true(rows[2].mark.shown)
				assert.is_false(rows[1].mark.shown)
			end)

			it("switches the list between chapters and sessions with its two buttons", function()
				local f = open()
				assert.is_false(f.chapters.enabled)
				assert.is_true(f.sessions.enabled)
				click(f.sessions)
				assert.is_true(f.chapters.enabled)
				assert.is_false(f.sessions.enabled)
				assert.equal("All", sessionRows()[1].text.text)
				click(f.chapters)
				assert.equal("Start", sessionRows()[1].text.text)
			end)

			it(
				"fills the Highlights feed as the replay passes events, newest first, and empties it on a seek back",
				function()
					local f = open()
					click(sessionRows()[1])
					frameStep(0.001)
					ns.Overlay.Play()
					frameStep(0.51)
					assert.truthy(f.feed[1].text:find("Level up: 12", 1, true))
					assert.equal("", f.feed[2].text)
					frameStep(0.5)
					assert.truthy(f.feed[1].text:find("Died: Wolf", 1, true))
					assert.truthy(f.feed[2].text:find("Level up: 12", 1, true))
					ns.Overlay.Seek(0)
					frameStep(0.001)
					assert.equal("", f.feed[1].text)
				end
			)

			it("keeps the last six events of the feed", function()
				local f = open()
				for i = 1, 8 do
					Panel.Highlight({ kind = "di", group = "Progress", fields = { area = "A" .. i } })
				end
				assert.truthy(f.feed[1].text:find("A8", 1, true))
				assert.truthy(f.feed[6].text:find("A3", 1, true))
			end)

			it("writes a feed line with the icon, the kind name and the main field", function()
				open()
				local line = Panel.HighlightText({ kind = "hs", group = "Travel", fields = { to = "Stormwind" } })
				assert.truthy(line:find("|T" .. ns.MapIcons.Get("hs") .. ":14|t", 1, true))
				assert.truthy(line:find("Hearthstone: Stormwind", 1, true))
				local zone = Panel.HighlightText({ kind = "zo", fields = {} })
				assert.truthy(zone:find("|T" .. ns.MapIcons.Get("zo"), 1, true))
				assert.truthy(zone:find("Entered a zone$"))
				local other = Panel.HighlightText({ kind = "zz", group = "Travel" })
				assert.truthy(other:find("|T" .. ns.Overlay.GROUP_ICON.Travel, 1, true))
				assert.equal("zz", Panel.HighlightText({ kind = "zz" }))
				assert.equal(zone, Panel.HighlightText({ kind = "zo" }))
			end)

			it("empties the feed when the map draws again", function()
				local f = open()
				Panel.Highlight({ kind = "di", group = "Progress", fields = { area = "A" } })
				ns.Overlay.Draw()
				assert.equal("", f.feed[1].text)
			end)

			it("has no row for chapters with nothing to play", function()
				start({ shown = true })
				for _, group in ipairs(ns.MapData.Groups()) do
					ns.Settings.Set("map.groups." .. group, false)
				end
				ns.Settings.Set("map.trail", false)
				click(Tab.Button())
				assert.equal(0, #sessionRows())
			end)
		end)

		it("shows a session that is still running up to now", function()
			start()
			assert.truthy(Panel.SessionText({ start = wow.wall - 120 }):find("2 min", 1, true))
		end)
	end)
end)
