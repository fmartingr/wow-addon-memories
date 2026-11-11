local wow = require("helpers.wow")

describe("map overlay", function()
	wow.pin_locale("enUS", before_each, after_each)

	local ns, O
	local ZONE, OTHER = 1453, 1454

	-- A fake world map: a canvas of 1000 x 500 and the provider calls of the game.
	local function fakeMap(mapID)
		local canvas = CreateFrame("Frame", "FakeCanvas")
		canvas:SetSize(1000, 500)
		local map = { providers = {}, mapID = mapID or ZONE, shown = true }
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
		function map:IsShown()
			return self.shown
		end
		_G.WorldMapFrame = map
		_G.MapCanvasDataProviderMixin = {
			GetMap = function(self)
				return self.owningMap
			end,
			OnMapChanged = function() end,
			RefreshAllData = function() end,
			RemoveAllData = function() end,
		}
		_G.CreateFromMixins = function(mixin)
			local out = {}
			for k, v in pairs(mixin) do
				out[k] = v
			end
			return out
		end
		return map
	end

	local function chunk(m, t, d)
		return { s = 1, t = t, m = m, n = 1, d = d }
	end

	local function boot(chunks, opts)
		opts = opts or {}
		_G.WorldMapFrame = nil
		_G.MapCanvasDataProviderMixin = nil
		_G.CreateFromMixins = nil
		ns = wow.boot({
			login = false,
			maps = opts.maps or { [ZONE] = { mapType = 3 }, [OTHER] = { mapType = 3 } },
			saved = { MemoriesCharDB = { trail = { v = 1, chunks = chunks or {} } } },
		})
		O = ns.Overlay
		ns.Store.Reopen()
	end

	local function attach(mapID)
		local map = fakeMap(mapID)
		assert.is_true(O.Attach())
		return map, map.providers[1]
	end

	local function rgba(color, a)
		return { color[1], color[2], color[3], a }
	end

	local function visible(list)
		local n = 0
		for _, f in ipairs(list or {}) do
			if f.shown then
				n = n + 1
			end
		end
		return n
	end

	local function container(map)
		for _, f in ipairs(wow.frames) do
			if f.parent == map:GetCanvas() and f.kind == "Frame" then
				return f
			end
		end
	end

	local function lines(map)
		return container(map).lines or {}
	end

	local function pins(map)
		local out = {}
		for _, f in ipairs(wow.frames) do
			if f.kind == "Button" and f.parent == container(map) then
				out[#out + 1] = f
			end
		end
		return out
	end

	local function journal(list)
		local j = ns.Store.Core()
		for _, l in ipairs(list) do
			j:WriteAt({ t = l.t, m = l.m, x = l.x, y = l.y }, l.kind, unpack(l.args or {}))
		end
	end

	local function flush()
		wow.advance(0.01)
	end

	it("adds one provider to the world map at login", function()
		boot()
		local map = fakeMap()
		wow.login()
		assert.equal(1, #map.providers)
		assert.is_true(O.Attach())
		assert.equal(1, #map.providers)
	end)

	it("waits for the world map when it is not there at login", function()
		boot()
		wow.login()
		assert.is_false(O.Attach())
		local map = fakeMap()
		wow.fire("ADDON_LOADED", "Blizzard_Other")
		assert.equal(0, #map.providers)
		wow.fire("ADDON_LOADED", "Blizzard_WorldMap")
		assert.equal(1, #map.providers)
	end)

	it("adds the provider again after the map refused it", function()
		boot()
		local map = fakeMap()
		local add = map.AddDataProvider
		map.AddDataProvider = function()
			error("refused")
		end
		assert.has_error(function()
			O.Attach()
		end)
		map.AddDataProvider = add
		assert.is_true(O.Attach())
		assert.equal(1, #map.providers)
	end)

	it("lets the clicks on a pin through to the map", function()
		boot()
		local map = attach()
		journal({ { t = 10, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 5 } } })
		O.Show(true)
		assert.is_false(pins(map)[1].mouseClickEnabled)
	end)

	it("tells the panel when it is turned off", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		attach()
		O.Show(true)
		flush()
		local seen
		ns.Listen("MAP_OVERLAY_DRAWN", function(_, stats)
			seen = stats
		end)
		O.Show(false)
		assert.same({ lines = 0, pins = 0, cutLines = 0, cutPins = 0, zones = 0 }, seen)
	end)

	it("draws nothing while it is off", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000") })
		local map, p = attach()
		p:OnMapChanged()
		assert.is_nil(container(map))
		assert.is_false(O.Enabled())
	end)

	it("draws a line for each step of the trail and a pin for each line of the journal", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,2000,m") })
		local map = attach()
		journal({ { t = 10, m = ZONE, x = 5000, y = 5000, kind = "lv", args = { 5 } } })
		O.Show(true)
		flush()
		local l = lines(map)
		assert.equal(2, visible(l))
		assert.same({ "TOPLEFT", container(map), 100, -50 }, { unpack(l[1].startPoint, 1, 4) })
		assert.same(rgba(O.WAY_COLOR.foot, 0.9), { unpack(l[1].color, 1, 4) })
		assert.same(rgba(O.WAY_COLOR.mounted, 0.9), { unpack(l[2].color, 1, 4) })
		local ps = pins(map)
		assert.equal(1, visible(ps))
		assert.same({ "CENTER", container(map), "TOPLEFT", 500, -250 }, { unpack(ps[1].point, 1, 5) })
		assert.equal(1, O.Stats().pins)
		assert.equal(2, O.Stats().lines)
		assert.is_true(O.Enabled())
	end)

	it("makes the pins of a death and of a level up larger", function()
		boot()
		local map = attach()
		journal({
			{ t = 10, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 5 } },
			{ t = 11, m = ZONE, x = 2000, y = 1000, kind = "de", args = { "Wolf" } },
			{ t = 12, m = ZONE, x = 3000, y = 1000, kind = "di", args = { "Elwynn" } },
		})
		O.Show(true)
		local ps = pins(map)
		assert.equal(3, #ps)
		assert.same({ O.BIG_PIN_SIZE, O.BIG_PIN_SIZE, O.PIN_SIZE }, { ps[1].size[1], ps[2].size[1], ps[3].size[1] })
	end)

	it("gives each pin the icon of its group, and a default icon to a group without one", function()
		boot()
		local map = attach()
		journal({
			{ t = 10, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 5 } },
			{ t = 11, m = ZONE, x = 2000, y = 1000, kind = "de", args = { "Wolf" } },
			{ t = 12, m = ZONE, x = 3000, y = 1000, kind = "ex", args = { "Other", "thing", "" } },
		})
		O.Show(true)
		local ps = pins(map)
		assert.equal(O.GROUP_ICON.Progress, ps[1].icon.texture)
		assert.equal(O.GROUP_ICON.Deaths, ps[2].icon.texture)
		assert.equal("Interface\\Icons\\INV_Misc_QuestionMark", ps[3].icon.texture)
	end)

	it("shows the time, the kind name and the fields in the tooltip of a pin", function()
		boot()
		local map = attach()
		journal({ { t = 86400, m = ZONE, x = 1000, y = 1000, kind = "de", args = { "Wolf" } } })
		O.Show(true)
		local pin = pins(map)[1]
		pin.scripts.OnEnter(pin)
		local text = table.concat(wow.tooltip.lines, "\n")
		assert.truthy(text:find("Died", 1, true))
		assert.truthy(text:find("1970-01-02", 1, true))
		assert.truthy(text:find("killer: Wolf", 1, true))
		assert.is_true(GameTooltip.shown)
		pin.scripts.OnLeave(pin)
		assert.is_false(GameTooltip.shown)
	end)

	it("keeps a tooltip failure out of the map", function()
		boot()
		local map = attach()
		journal({ { t = 10, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 5 } } })
		O.Show(true)
		local pin = pins(map)[1]
		pin.data.fields = nil
		pin.scripts.OnEnter(pin)
		assert.equal(1, #ns.Errors())
	end)

	it("skips the trail with Trail off and the pins of a group that is off", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map = attach()
		journal({
			{ t = 10, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 5 } },
			{ t = 11, m = ZONE, x = 2000, y = 1000, kind = "de", args = { "Wolf" } },
		})
		ns.Settings.Set("map.trail", false)
		ns.Settings.Set("map.groups.Deaths", false)
		O.Show(true)
		flush()
		assert.equal(0, visible(lines(map)))
		assert.equal(1, visible(pins(map)))
		assert.equal("lv", pins(map)[1].data.kind)
	end)

	it("draws only the chosen session, and all again with none", function()
		boot({
			{ s = 1000, t = 1000, m = ZONE, n = 2, d = "0,1000,1000;2,2000,1000" },
			{ s = 2000, t = 2000, m = ZONE, n = 3, d = "0,1000,2000;2,2000,2000;4,3000,2000" },
		})
		local map = attach()
		O.Show(true)
		flush()
		assert.equal(3, visible(lines(map)))
		O.SetSession({ start = 2000, stop = 2100 })
		flush()
		assert.equal(2, visible(lines(map)))
		assert.same({ start = 2000, stop = 2100 }, O.Session())
		O.SetSession(nil)
		flush()
		assert.equal(3, visible(lines(map)))
	end)

	it("cuts the lines and the pins at the caps and counts the cut", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000;6,4000,1000;8,5000,1000") })
		local map = attach()
		O.MAX_LINES, O.MAX_PINS = 2, 1
		journal({
			{ t = 10, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 5 } },
			{ t = 11, m = ZONE, x = 2000, y = 1000, kind = "lv", args = { 6 } },
			{ t = 12, m = ZONE, x = 3000, y = 1000, kind = "lv", args = { 7 } },
		})
		O.Show(true)
		flush()
		assert.equal(2, visible(lines(map)))
		assert.equal(1, visible(pins(map)))
		local stats = O.Stats()
		assert.equal(2, stats.cutLines)
		assert.equal(2, stats.cutPins)
	end)

	it("draws the lines in slices over several frames", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000;6,4000,1000;8,5000,1000") })
		local map = attach()
		O.SLICE = 2
		O.Show(true)
		assert.equal(2, visible(lines(map)))
		flush()
		assert.equal(4, visible(lines(map)))
		assert.equal(4, O.Stats().lines)
	end)

	it("tells the panel when a draw ends", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		attach()
		local seen = {}
		ns.Listen("MAP_OVERLAY_DRAWN", function(_, stats)
			seen[#seen + 1] = stats
		end)
		O.Show(true)
		flush()
		assert.equal(1, #seen)
		assert.equal(1, seen[1].lines)
	end)

	it("ends the draw in the slice that places the last line", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000") })
		attach()
		O.SLICE = 2
		local seen = 0
		ns.Listen("MAP_OVERLAY_DRAWN", function()
			seen = seen + 1
		end)
		O.Show(true)
		assert.equal(1, seen)
	end)

	it("tells the panel when the map clears its data or is hidden", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map, p = attach()
		O.Show(true)
		local seen
		ns.Listen("MAP_OVERLAY_DRAWN", function(_, stats)
			seen = stats
		end)
		p:RemoveAllData()
		assert.equal(0, seen.lines)
		O.Show(true)
		assert.equal(1, seen.lines)
		map.shown = false
		O.SetSession(nil)
		assert.equal(0, seen.lines)
	end)

	it("reads the lists again after a draw on a hidden map", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map, p = attach()
		O.Show(true)
		map.shown = false
		O.SetSession({ start = 5000, stop = 6000 })
		map.shown = true
		p:OnCanvasSizeChanged()
		assert.equal(0, visible(lines(map)))
	end)

	it("clears the pools and stops old slices when the map changes", function()
		boot({
			chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000;6,4000,1000"),
			chunk(OTHER, 2000, "0,1000,1000;2,2000,1000"),
		})
		local map, p = attach()
		O.SLICE = 1
		O.Show(true)
		assert.equal(1, visible(lines(map)))
		map.mapID = OTHER
		p:OnMapChanged()
		flush()
		flush()
		flush()
		assert.equal(1, visible(lines(map)))
		assert.equal(1, O.Stats().lines)
	end)

	it("clears the drawing when the map clears its data", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map, p = attach()
		O.Show(true)
		assert.equal(1, visible(lines(map)))
		p:RemoveAllData()
		assert.equal(0, visible(lines(map)))
		assert.same({ lines = 0, pins = 0, cutLines = 0, cutPins = 0, zones = 0 }, O.Stats())
	end)

	it("hides the drawing when it is turned off", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map = attach()
		O.Show(true)
		O.Show(false)
		assert.equal(0, visible(lines(map)))
		assert.is_false(container(map).shown)
		O.Show(true)
		assert.is_true(container(map).shown)
		assert.equal(1, visible(lines(map)))
	end)

	it("reuses its lines for the next draw", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map, p = attach()
		O.Show(true)
		p:OnMapChanged()
		p:RefreshAllData()
		assert.equal(1, #lines(map))
	end)

	it("counts the zones that cannot be shown", function()
		boot({ chunk(OTHER, 1000, "0,1000,1000;2,2000,1000") }, {
			maps = { [ZONE] = { mapType = 2 }, [OTHER] = { mapType = 3, parentMapID = ZONE } },
		})
		local map = attach()
		O.Show(true)
		assert.equal(0, visible(lines(map)))
		assert.equal(1, O.Stats().zones)
	end)

	it("leaves the map working when a draw fails", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map, p = attach()
		O.Show(true)
		ns.MapData.Segments = function()
			error("boom")
		end
		assert.has_no.errors(function()
			p:OnMapChanged()
		end)
		assert.equal(1, #ns.Errors())
		assert.equal(0, visible(lines(map)))
		assert.is_false(container(map).shown)
	end)

	it("keeps a failure to build a line out of the map and draws again later", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map, p = attach()
		local frame = getmetatable(CreateFrame("Frame")).__index
		local create = frame.CreateLine
		frame.CreateLine = function()
			error("no lines")
		end
		local ok = pcall(function()
			O.Show(true)
			p:RemoveAllData()
			p:OnMapChanged()
		end)
		frame.CreateLine = create
		assert.is_true(ok)
		assert.equal(0, O.Stats().lines)
		p:OnMapChanged()
		assert.equal(1, visible(lines(map)))
	end)

	it("clears the drawing when a later slice fails", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000") })
		local map = attach()
		O.SLICE = 1
		O.Show(true)
		assert.equal(1, visible(lines(map)))
		local color = O.WAY_COLOR
		O.WAY_COLOR = nil
		flush()
		O.WAY_COLOR = color
		assert.equal(1, #ns.Errors())
		assert.equal(0, visible(lines(map)))
		assert.is_false(container(map).shown)
	end)

	it("waits for the map to show before it draws", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map, p = attach()
		map.shown = false
		O.Show(true)
		assert.is_nil(container(map))
		map.shown = true
		p:RefreshAllData()
		assert.equal(1, visible(lines(map)))
	end)

	it("draws again when the canvas changes size", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map, p = attach()
		O.Show(true)
		map:GetCanvas():SetSize(2000, 1000)
		p:OnCanvasSizeChanged()
		assert.same({ "TOPLEFT", container(map), 200, -100 }, { unpack(lines(map)[1].startPoint, 1, 4) })
	end)

	it("places the lists of the last draw again when the canvas changes size", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map, p = attach()
		O.Show(true)
		local segments, reads = ns.MapData.Segments, 0
		ns.MapData.Segments = function(...)
			reads = reads + 1
			return segments(...)
		end
		p:OnCanvasSizeChanged()
		assert.equal(0, reads)
		assert.equal(1, visible(lines(map)))
		p:RemoveAllData()
		p:OnCanvasSizeChanged()
		ns.MapData.Segments = segments
		assert.equal(1, reads)
	end)

	it("puts the drawing at the level of the map's area pins", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map = attach()
		local asked
		function map:GetPinFrameLevelsManager()
			return {
				GetValidFrameLevel = function(_, kind)
					asked = kind
					return 42
				end,
			}
		end
		O.Show(true)
		assert.equal("PIN_FRAME_LEVEL_AREA_POI", asked)
		assert.equal(42, container(map).frameLevel)
	end)

	it("keeps the default level when the map has no level for its area pins", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map = attach()
		function map:GetPinFrameLevelsManager()
			return {
				GetValidFrameLevel = function()
					error("unknown level")
				end,
			}
		end
		O.Show(true)
		assert.is_nil(container(map).frameLevel)
		assert.equal(1, visible(lines(map)))
		assert.equal(0, #ns.Errors())
	end)

	it("does nothing before the provider is added", function()
		boot()
		assert.has_no.errors(function()
			O.Show(true)
			O.SetSession(nil)
		end)
	end)

	it("draws again when the journal opens again while it is on", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map = attach()
		O.Show(true)
		ns.Emit("JOURNAL_OPENED")
		assert.equal(1, visible(lines(map)))
		O.Show(false)
		ns.Emit("JOURNAL_OPENED")
		assert.equal(0, visible(lines(map)))
	end)

	it("builds a new container when the canvas changes", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
		local map, p = attach()
		O.Show(true)
		local first = container(map)
		local canvas = CreateFrame("Frame")
		canvas:SetSize(100, 100)
		map.GetCanvas = function()
			return canvas
		end
		p:OnMapChanged()
		assert.is_not.equal(first, container(map))
		assert.is_false(first.shown)
	end)
end)
