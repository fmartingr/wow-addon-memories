local wow = require("helpers.wow")

describe("map overlay", function()
	wow.pin_locale("enUS", before_each, after_each)

	local ns, O
	local ZONE, OTHER, CONT = 1453, 1454, 12

	-- A fake world map: a canvas of 1000 x 500 and the provider calls of the game.
	local function fakeMap(mapID)
		local canvas = CreateFrame("Frame", "FakeCanvas")
		canvas:SetSize(1000, 500)
		local map = { providers = {}, mapID = mapID or ZONE, shown = true, scale = 1 }
		function map:GetCanvasScale()
			return self.scale
		end
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
		-- SetMapID changes the map and draws it again before it returns, as the game does. refuse makes it raise an
		-- error before the change; broken takes the id first and then raises, as the game does for a map with no art.
		map.set = {}
		function map:SetMapID(id)
			if self.mapID == id then
				return
			end
			self.set[#self.set + 1] = id
			if self.refuse then
				error("no such map")
			end
			self.mapID = id
			if self.broken and self.broken[id] then
				error("attempt to index a nil value")
			end
			self.providers[1]:OnMapChanged()
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
			projections = opts.projections,
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

	-- A trail of 4 steps, 10 s apart, with a level up in the middle and a death near the end.
	local TRAIL = chunk(ZONE, 1000, "0,1000,1000;10,2000,1000;20,3000,1000;30,4000,1000;40,5000,1000")

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

	-- One frame of the overlay: the clock moves by dt and the container runs its OnUpdate, if it has one.
	local function step(map, dt)
		dt = dt or 0.01
		wow.advance(dt)
		local c = container(map)
		if c and c.scripts.OnUpdate then
			c.scripts.OnUpdate(c, dt)
		end
	end

	local function frames(map, n, dt)
		for _ = 1, n or 1 do
			step(map, dt)
		end
	end

	local function head(map)
		for _, f in ipairs(wow.frames) do
			if f.kind == "Frame" and f.parent == container(map) then
				return f
			end
		end
	end

	local function idle(map)
		return container(map).scripts.OnUpdate == nil
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
		step(map)
		assert.is_false(pins(map)[1].mouseClickEnabled)
	end)

	it("draws nothing while it is off", function()
		boot({ TRAIL })
		local map, p = attach()
		p:OnMapChanged()
		assert.is_nil(container(map))
		assert.is_false(O.Enabled())
	end)

	it("shows the whole journey when no replay runs, a slice of lines for each frame", function()
		boot({ TRAIL })
		local map = attach()
		journal({
			{ t = 1015, m = ZONE, x = 5000, y = 5000, kind = "lv", args = { 5 } },
			{ t = 1035, m = ZONE, x = 6000, y = 5000, kind = "de", args = { "Wolf" } },
		})
		O.SLICE = 3
		O.Show(true)
		assert.equal(0, visible(lines(map)))
		step(map)
		assert.equal(3, visible(lines(map)))
		assert.is_false(idle(map))
		step(map)
		assert.equal(4, visible(lines(map)))
		assert.equal(2, visible(pins(map)))
		assert.is_true(idle(map))
		assert.is_false(O.Playing())
		assert.same({ 40, 40 }, { O.Position(), select(2, O.Position()) })
		assert.is_false(head(map).shown)
		assert.same({ lines = 4, pins = 2, cutLines = 0, cutPins = 0, zones = 0 }, O.Stats())
	end)

	it("places a line in canvas units with the colour of its way of travel", function()
		boot({ chunk(ZONE, 1000, "0,1000,1000;10,2000,1000,m") })
		local map = attach()
		O.Show(true)
		step(map)
		local line = lines(map)[1]
		assert.same({ "TOPLEFT", container(map), 100, -50 }, { unpack(line.startPoint, 1, 4) })
		assert.same({ "TOPLEFT", container(map), 200, -50 }, { unpack(line.endPoint, 1, 4) })
		assert.same(rgba(O.WAY_COLOR.mounted, 0.9), { unpack(line.color, 1, 4) })
		assert.equal(O.LINE_WIDTH, line.thickness)
	end)

	it("gives each pin the icon and the colour of its group, and a larger size to a death and a level up", function()
		boot()
		local map = attach()
		journal({
			{ t = 10, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 5 } },
			{ t = 11, m = ZONE, x = 2000, y = 1000, kind = "de", args = { "Wolf" } },
			{ t = 12, m = ZONE, x = 3000, y = 1000, kind = "di", args = { "Elwynn" } },
		})
		O.Show(true)
		step(map)
		local ps = pins(map)
		assert.equal(3, #ps)
		assert.equal(O.GROUP_ICON.Progress, ps[1].icon.texture)
		assert.equal(O.GROUP_ICON.Deaths, ps[2].icon.texture)
		assert.same({ O.BIG_PIN_SIZE, O.BIG_PIN_SIZE }, ps[1].size)
		assert.same({ O.BIG_PIN_SIZE, O.BIG_PIN_SIZE }, ps[2].size)
		assert.same({ O.PIN_SIZE, O.PIN_SIZE }, ps[3].size)
		assert.same({ "CENTER", container(map), "TOPLEFT", 300, -50 }, { unpack(ps[3].point, 1, 5) })
		assert.same({ O.PIN_SIZE, O.PIN_SIZE }, ps[3].border.size)
		assert.is_true(ps[3].icon.size[1] < O.PIN_SIZE)
	end)

	it("shows the pins at a smaller size on a continent, where a whole journey packs together", function()
		boot(nil, { maps = { [ZONE] = { mapType = 2 }, [OTHER] = { mapType = 3 } } })
		local map = attach()
		journal({
			{ t = 10, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 5 } },
			{ t = 12, m = ZONE, x = 3000, y = 1000, kind = "di", args = { "Elwynn" } },
		})
		O.Show(true)
		step(map)
		local ps = pins(map)
		local small = O.PIN_SIZE * O.HIGH_MAP_PIN
		assert.same({ O.BIG_PIN_SIZE * O.HIGH_MAP_PIN, O.BIG_PIN_SIZE * O.HIGH_MAP_PIN }, ps[1].size)
		assert.same({ small, small }, ps[2].size)
		assert.is_true(ps[2].icon.size[1] > 0 and ps[2].icon.size[1] < small)
	end)

	it("uses a question mark for a group without an icon", function()
		boot()
		local map = attach()
		ns.Kinds.Register("zq", { addon = "Memories", name = "Zq" })
		journal({ { t = 10, m = ZONE, x = 1000, y = 1000, kind = "zq" } })
		ns.Settings.Set("map.groups.", true)
		O.Show(true)
		step(map)
		assert.truthy(pins(map)[1].icon.texture:find("QuestionMark", 1, true))
	end)

	it("shows the time, the kind name and the fields in the tooltip of a pin", function()
		boot()
		local map = attach()
		journal({ { t = 86400, m = ZONE, x = 1000, y = 1000, kind = "de", args = { "Wolf" } } })
		O.Show(true)
		step(map)
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
		step(map)
		local pin = pins(map)[1]
		pin.data.fields = nil
		pin.scripts.OnEnter(pin)
		assert.equal(1, #ns.Errors())
	end)

	it("skips the trail with Trail off and the pins of a group that is off", function()
		boot({ TRAIL })
		local map = attach()
		journal({
			{ t = 1010, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 5 } },
			{ t = 1011, m = ZONE, x = 2000, y = 1000, kind = "de", args = { "Wolf" } },
		})
		ns.Settings.Set("map.trail", false)
		ns.Settings.Set("map.groups.Deaths", false)
		O.Show(true)
		frames(map, 3)
		assert.equal(0, visible(lines(map)))
		assert.equal(1, visible(pins(map)))
		assert.equal("lv", pins(map)[1].data.kind)
	end)

	it("draws only the chosen session, and all again with none", function()
		boot({
			{ s = 1000, t = 1000, m = ZONE, n = 2, d = "0,1000,1000;10,2000,1000" },
			{ s = 2000, t = 2000, m = ZONE, n = 3, d = "0,1000,2000;10,2000,2000;20,3000,2000" },
		})
		local map = attach()
		O.Show(true)
		frames(map, 2)
		assert.equal(3, visible(lines(map)))
		O.SetSession({ start = 2000, stop = 2100 })
		frames(map, 2)
		assert.equal(2, visible(lines(map)))
		assert.same({ start = 2000, stop = 2100 }, O.Session())
		O.SetSession(nil)
		frames(map, 2)
		assert.equal(3, visible(lines(map)))
	end)

	it("cuts the lines and the pins at the caps and counts the cut", function()
		boot({ TRAIL })
		local map = attach()
		O.MAX_LINES, O.MAX_PINS = 2, 1
		journal({
			{ t = 1001, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 5 } },
			{ t = 1002, m = ZONE, x = 2000, y = 1000, kind = "lv", args = { 6 } },
			{ t = 1003, m = ZONE, x = 3000, y = 1000, kind = "lv", args = { 7 } },
		})
		O.Show(true)
		frames(map, 3)
		assert.equal(2, visible(lines(map)))
		assert.equal(1, visible(pins(map)))
		assert.equal(2, O.Stats().cutLines)
		assert.equal(2, O.Stats().cutPins)
	end)

	describe("replay", function()
		local function setup(extra)
			boot({ TRAIL })
			local map = attach()
			journal(extra or {
				{ t = 1015, m = ZONE, x = 5000, y = 5000, kind = "lv", args = { 5 } },
				{ t = 1035, m = ZONE, x = 6000, y = 5000, kind = "de", args = { "Wolf" } },
			})
			O.Show(true)
			frames(map, 2)
			return map
		end

		it("starts from the beginning and shows what the playhead passes", function()
			local map = setup()
			O.Play()
			assert.is_true(O.Playing())
			step(map, 0.001)
			assert.equal(0, visible(lines(map)))
			assert.equal(0, visible(pins(map)))
			assert.is_true(head(map).shown)
			step(map, 0.3)
			assert.equal(1, visible(lines(map)))
			assert.equal(0, visible(pins(map)))
			step(map, 0.25)
			assert.equal(2, visible(lines(map)))
			assert.equal(1, visible(pins(map)))
		end)

		it("moves the head along the trail", function()
			local map = setup()
			O.Play()
			step(map, 0.125)
			local point = head(map).point
			assert.same({ "CENTER", container(map), "TOPLEFT" }, { unpack(point, 1, 3) })
			assert.near(150, point[4], 1e-6)
			assert.near(-50, point[5], 1e-6)
		end)

		it("pops a new pin in with an animation that ends by itself", function()
			local map = setup()
			O.Play()
			step(map, 0.001)
			step(map, 0.51)
			local pin = pins(map)[1]
			assert.is_true(pin.shown)
			assert.is_not_nil(pin.popAt)
			assert.is_true(pin.size[1] < O.BIG_PIN_SIZE)
			step(map, 0.1)
			assert.is_true(pin.size[1] > 0)
			step(map, O.POP + 0.01)
			assert.is_nil(pin.popAt)
			assert.same({ O.BIG_PIN_SIZE, O.BIG_PIN_SIZE }, pin.size)
		end)

		it("pulses a new pin while it is new in played time", function()
			local map = setup()
			O.Play()
			step(map, 0.001)
			step(map, 0.51)
			local pin = pins(map)[1]
			assert.is_true(pin.glow.alpha > 0)
			O.Seek(0)
			step(map, 0.01)
			O.Pause()
			step(map, 0.01)
			assert.is_false(pin.shown)
		end)

		it("stops at the end and tells the panel", function()
			local map = setup()
			local changes = 0
			ns.Listen("MAP_REPLAY_CHANGED", function()
				changes = changes + 1
			end)
			O.Play()
			frames(map, 40, 0.1)
			assert.is_false(O.Playing())
			assert.equal(4, visible(lines(map)))
			assert.equal(2, visible(pins(map)))
			assert.is_false(head(map).shown)
			assert.is_true(changes >= 2)
			frames(map, 40, O.POP)
			assert.is_true(idle(map))
		end)

		it("pauses and goes on from the same place", function()
			local map = setup()
			O.Play()
			step(map, 0.3)
			O.Pause()
			local at = O.Position()
			step(map, 0.5)
			assert.equal(at, (O.Position()))
			assert.is_false(O.Playing())
			O.Play()
			step(map, 0.1)
			assert.is_true(O.Position() > at)
		end)

		it("restarts when it plays at the end", function()
			local map = setup()
			O.Play()
			assert.equal(0, (O.Position()))
			step(map, 0.01)
			assert.equal(0, visible(lines(map)))
		end)

		it("goes faster at a higher speed, and cycles the speeds", function()
			local map = setup()
			assert.equal(1, O.Speed())
			O.CycleSpeed()
			assert.equal(2, O.Speed())
			O.SetSpeed(5)
			assert.equal(2, O.Speed())
			O.SetSpeed(16)
			O.CycleSpeed()
			assert.equal(1, O.Speed())
			O.Play()
			O.SetSpeed(4)
			step(map, 0.1)
			assert.equal(16, (O.Position()))
		end)

		it("seeks: back hides what the playhead left, forward shows what it passes", function()
			local map = setup()
			O.Seek(15)
			step(map)
			assert.equal(1, visible(lines(map)))
			assert.equal(1, visible(pins(map)))
			O.Seek(0)
			step(map)
			assert.equal(0, visible(lines(map)))
			assert.equal(0, visible(pins(map)))
			O.Seek(999)
			step(map)
			assert.equal(4, visible(lines(map)))
			assert.equal(2, visible(pins(map)))
			assert.is_false(O.Playing())
			O.Seek("x")
			assert.equal(40, (O.Position()))
		end)

		it("does nothing with no journey to play", function()
			boot()
			local map = attach()
			O.Show(true)
			step(map)
			O.Play()
			O.Seek(3)
			assert.is_false(O.Playing())
			assert.same({ 0, 0 }, { O.Position(), select(2, O.Position()) })
		end)

		it("does nothing before the overlay is on", function()
			boot({ TRAIL })
			attach()
			O.Play()
			O.Toggle()
			assert.is_false(O.Playing())
		end)

		it("toggles between play and pause", function()
			setup()
			O.Toggle()
			assert.is_true(O.Playing())
			O.Toggle()
			assert.is_false(O.Playing())
		end)

		it("reports the playhead on each frame", function()
			local map = setup()
			local seen
			ns.Listen("MAP_REPLAY_TICK", function(_, at, total, now)
				seen = { at, total, now }
			end)
			O.Play()
			step(map, 0.25)
			assert.same({ 10, 40, true }, seen)
		end)

		it("pops no more than a few pins at a seek forward", function()
			local list = {}
			for i = 1, 20 do
				list[#list + 1] = { t = 1000 + i, m = ZONE, x = 1000 + i * 10, y = 1000, kind = "di", args = { "a" } }
			end
			local map = setup(list)
			O.Seek(0)
			step(map)
			O.Play()
			step(map, 0.5)
			local popping = 0
			for _, pin in ipairs(pins(map)) do
				if pin.shown and pin.popAt then
					popping = popping + 1
				end
			end
			assert.equal(0, popping)
		end)
	end)

	describe("zoom", function()
		it("keeps pins and lines at a screen size, at the zoom of the map", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;10,2000,1000") })
			local map, p = attach()
			map.scale = 0.5
			journal({ { t = 1005, m = ZONE, x = 1000, y = 1000, kind = "di", args = { "a" } } })
			O.Show(true)
			step(map)
			assert.same({ O.PIN_SIZE * 2, O.PIN_SIZE * 2 }, pins(map)[1].size)
			assert.equal(O.LINE_WIDTH * 2, lines(map)[1].thickness)
			map.scale = 4
			p:OnCanvasScaleChanged()
			assert.same({ O.PIN_SIZE / 4, O.PIN_SIZE / 4 }, pins(map)[1].size)
			assert.equal(O.LINE_WIDTH / 4, lines(map)[1].thickness)
		end)

		it("clamps a scale that is out of range, and reads the canvas scale without a map call", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;10,2000,1000") })
			local map, p = attach()
			map.scale = 0
			O.Show(true)
			step(map)
			assert.equal(O.LINE_WIDTH * 10, lines(map)[1].thickness)
			map.GetCanvasScale = nil
			map:GetCanvas().GetScale = function()
				return 2
			end
			p:OnCanvasScaleChanged()
			assert.equal(O.LINE_WIDTH / 2, lines(map)[1].thickness)
			map:GetCanvas().GetScale = function()
				return "x"
			end
			p:OnCanvasScaleChanged()
			assert.equal(O.LINE_WIDTH, lines(map)[1].thickness)
		end)

		it("places the lines again when the canvas size changes, and keeps the playhead", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;10,2000,1000;20,3000,1000") })
			local map, p = attach()
			O.Show(true)
			step(map)
			O.Seek(10)
			step(map)
			assert.equal(1, visible(lines(map)))
			map:GetCanvas():SetSize(2000, 1000)
			p:OnCanvasSizeChanged()
			assert.same({ "TOPLEFT", container(map), 200, -100 }, { unpack(lines(map)[1].startPoint, 1, 4) })
			assert.equal(10, (O.Position()))
			assert.equal(1, visible(lines(map)))
		end)

		it("waits for a canvas that has no size yet", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;10,2000,1000") })
			local map, p = attach()
			map:GetCanvas():SetSize(0, 0)
			O.Show(true)
			assert.equal(0, #lines(map))
			assert.is_true(idle(map))
			p:OnCanvasSizeChanged()
			assert.equal(0, #lines(map))
			map:GetCanvas():SetSize(1000, 500)
			p:OnCanvasSizeChanged()
			step(map)
			assert.equal(1, visible(lines(map)))
		end)

		it("ignores a size change while the overlay is off", function()
			boot({ TRAIL })
			local _, p = attach()
			assert.has_no.errors(function()
				p:OnCanvasSizeChanged()
				p:OnCanvasScaleChanged()
			end)
		end)
	end)

	describe("map events", function()
		it("clears the pools and starts again when the map changes", function()
			boot({ TRAIL, chunk(OTHER, 2000, "0,1000,1000;10,2000,1000") })
			local map, p = attach()
			O.Show(true)
			frames(map, 2)
			assert.equal(4, visible(lines(map)))
			map.mapID = OTHER
			p:OnMapChanged()
			frames(map, 2)
			assert.equal(1, visible(lines(map)))
			assert.equal(1, O.Stats().lines)
		end)

		it("clears the drawing when the map clears its data", function()
			boot({ TRAIL })
			local map, p = attach()
			O.Show(true)
			frames(map, 2)
			p:RemoveAllData()
			assert.equal(0, visible(lines(map)))
			assert.same({ lines = 0, pins = 0, cutLines = 0, cutPins = 0, zones = 0 }, O.Stats())
			assert.same({ 0, 0 }, { O.Position(), select(2, O.Position()) })
		end)

		it("hides the drawing when it is turned off, and shows it again when it is turned on", function()
			boot({ TRAIL })
			local map = attach()
			O.Show(true)
			frames(map, 2)
			O.Show(false)
			assert.equal(0, visible(lines(map)))
			assert.is_false(container(map).shown)
			assert.is_false(O.Playing())
			O.Show(true)
			frames(map, 2)
			assert.is_true(container(map).shown)
			assert.equal(4, visible(lines(map)))
		end)

		it("only clears while the map is hidden", function()
			boot({ TRAIL })
			local map, p = attach()
			O.Show(true)
			frames(map, 2)
			map.shown = false
			p:RefreshAllData()
			assert.equal(0, visible(lines(map)))
			map.shown = true
			p:RefreshAllData()
			frames(map, 2)
			assert.equal(4, visible(lines(map)))
		end)

		it("reuses its lines for the next draw", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;10,2000,1000") })
			local map, p = attach()
			O.Show(true)
			step(map)
			p:OnMapChanged()
			step(map)
			p:RefreshAllData()
			step(map)
			assert.equal(1, #lines(map))
		end)

		it("counts the zones that cannot be shown", function()
			boot({ chunk(OTHER, 1000, "0,1000,1000;10,2000,1000") }, {
				maps = { [ZONE] = { mapType = 2 }, [OTHER] = { mapType = 3, parentMapID = ZONE } },
			})
			local map = attach()
			O.Show(true)
			step(map)
			assert.equal(0, visible(lines(map)))
			assert.equal(1, O.Stats().zones)
		end)

		it("draws again when the journal opens again while it is on", function()
			boot({ TRAIL })
			local map = attach()
			O.Show(true)
			frames(map, 2)
			ns.Emit("JOURNAL_OPENED")
			frames(map, 2)
			assert.equal(4, visible(lines(map)))
			O.Show(false)
			ns.Emit("JOURNAL_OPENED")
			assert.equal(0, visible(lines(map)))
		end)

		it("builds a new container when the canvas changes", function()
			boot({ TRAIL })
			local map, p = attach()
			O.Show(true)
			step(map)
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

		it("takes the frame level of the area pins of the map", function()
			boot({ TRAIL })
			local map = attach()
			map.GetPinFrameLevelsManager = function()
				return {
					GetValidFrameLevel = function(_, name)
						assert.equal("PIN_FRAME_LEVEL_AREA_POI", name)
						return 77
					end,
				}
			end
			O.Show(true)
			assert.equal(77, container(map):GetFrameLevel())
		end)

		it("keeps the default level when the level manager fails", function()
			boot({ TRAIL })
			local map = attach()
			map.GetPinFrameLevelsManager = function()
				error("no manager")
			end
			assert.has_no.errors(function()
				O.Show(true)
			end)
			assert.is_true(container(map).shown)
		end)
	end)

	describe("failures", function()
		it("leaves the map working when a draw fails", function()
			boot({ TRAIL })
			local map, p = attach()
			O.Show(true)
			frames(map, 2)
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

		it("clears the drawing and stops when a frame fails", function()
			boot({ TRAIL })
			local map = attach()
			O.Show(true)
			step(map)
			O.Play()
			ns.Replay.Counts = function()
				error("boom")
			end
			assert.has_no.errors(function()
				step(map)
			end)
			assert.equal(1, #ns.Errors())
			assert.equal(0, visible(lines(map)))
			assert.is_true(idle(map))
		end)

		it("does nothing before the provider is added", function()
			boot()
			assert.has_no.errors(function()
				O.Show(true)
				O.SetSession(nil)
				O.Relayout()
			end)
		end)
	end)

	describe("trail look", function()
		it("turns the arrow of the head along the step it is on", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;10,2000,1000;20,2000,2000") })
			local map = attach()
			O.Show(true)
			frames(map, 2)
			O.Play()
			step(map, 0.001)
			step(map, 0.125)
			local arrow = head(map).arrow
			assert.equal("Interface\\Minimap\\ROTATING-MINIMAPARROW", arrow.texture)
			assert.near(math.atan2(-1, -0), arrow.rotation, 1e-6)
			step(map, 0.25)
			assert.near(math.atan2(-0, -1), arrow.rotation, 1e-6)
		end)

		it("keeps the last turn on a step of no length", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;10,2000,1000;20,2000,1000") })
			local map = attach()
			O.Show(true)
			frames(map, 2)
			O.Play()
			step(map, 0.001)
			step(map, 0.125)
			local turn = head(map).arrow.rotation
			step(map, 0.01)
			assert.equal(turn, head(map).arrow.rotation)
		end)

		it("colours the lines by level in the level mode", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;10,2000,1000;20,3000,1000") })
			local map = attach()
			journal({ { t = 1015, kind = "lv", args = { 30 } } })
			ns.Settings.Set("map.color", "level")
			O.Show(true)
			frames(map, 2)
			local ls = lines(map)
			local a = { unpack(ls[1].color, 1, 4) }
			local b = { unpack(ls[2].color, 1, 4) }
			assert.same({ ns.Replay.Color({ level = 29 }, "level") }, a)
			assert.same({ ns.Replay.Color({ level = 30 }, "level") }, b)
		end)

		it("colours the lines by age, and with the colourblind palette", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;10,2000,1000;20,3000,1000") })
			local map = attach()
			ns.Settings.Set("map.color", "age")
			O.Show(true)
			frames(map, 2)
			assert.same({ ns.Replay.Color({ age = 0.5 }, "age", false) }, { unpack(lines(map)[1].color, 1, 4) })
			ns.Settings.Set("map.colorblind", true)
			ns.Settings.Set("map.color", "way")
			O.Draw()
			frames(map, 2)
			assert.same({ ns.Replay.Color({ way = "foot" }, "way", true) }, { unpack(lines(map)[1].color, 1, 4) })
		end)

		it("draws the arc of a trip between two chunks with the arc colour", function()
			boot({
				chunk(ZONE, 1000, "0,1000,1000;10,2000,1000"),
				chunk(ZONE, 1040, "0,8000,6000;10,8500,6000"),
			})
			local map = attach()
			O.Show(true)
			frames(map, 3)
			assert.equal(2 + ns.Replay.ARC_STEPS, visible(lines(map)))
			local arc = 0
			for _, line in ipairs(lines(map)) do
				local c = ns.Replay.WAY_COLOR.arc
				if line.shown and line.color[1] == c[1] and line.color[2] == c[2] then
					arc = arc + 1
				end
			end
			assert.equal(ns.Replay.ARC_STEPS, arc)
		end)
	end)

	describe("highlights", function()
		local function bursts(map)
			local out = {}
			for _, f in ipairs(wow.frames) do
				if f.kind == "Frame" and f.parent == container(map) and f.ring then
					out[#out + 1] = f
				end
			end
			return out
		end

		local function setup(list)
			boot({ TRAIL })
			local map = attach()
			journal(list)
			O.Show(true)
			frames(map, 2)
			return map
		end

		local EVENTS = {
			{ t = 1015, m = ZONE, x = 5000, y = 5000, kind = "lv", args = { 12 } },
			{ t = 1035, m = ZONE, x = 6000, y = 5000, kind = "de", args = { "Wolf" } },
		}

		it("plays a burst at a level up with the level as its label, and tells the panel", function()
			local map = setup(EVENTS)
			local seen = {}
			ns.Listen("MAP_REPLAY_EVENT", function(_, pin)
				seen[#seen + 1] = pin.kind
			end)
			O.Play()
			step(map, 0.001)
			step(map, 0.51)
			local list = bursts(map)
			assert.equal(1, #list)
			assert.equal("Level 12", list[1].label.text)
			assert.same({ unpack(O.BURST.lv, 1, 3) }, { unpack(list[1].ring.vertexColor or O.BURST.lv, 1, 3) })
			assert.is_true(list[1].shown)
			assert.same({ "lv" }, seen)
		end)

		it("labels a death with the name of the kind and a flight with its own colour", function()
			local map = setup({
				{ t = 1015, m = ZONE, x = 5000, y = 5000, kind = "de", args = { "Wolf" } },
				{ t = 1035, m = ZONE, x = 6000, y = 5000, kind = "tx", args = { "A", "B" } },
			})
			O.Play()
			step(map, 0.001)
			step(map, 0.51)
			assert.equal("Died", bursts(map)[1].label.text)
			step(map, 0.5)
			assert.equal(2, #bursts(map))
			assert.equal("Took a flight", bursts(map)[2].label.text)
		end)

		it("plays no burst for a kind that has none", function()
			local map = setup({ { t = 1015, m = ZONE, x = 5000, y = 5000, kind = "di", args = { "Elwynn" } } })
			O.Play()
			step(map, 0.001)
			step(map, 0.51)
			assert.equal(0, #bursts(map))
		end)

		it("grows the ring and fades the burst, which ends by itself and goes back to the pool", function()
			local map = setup(EVENTS)
			O.Play()
			step(map, 0.001)
			step(map, 0.51)
			local burst = bursts(map)[1]
			local early = burst.ring.size[1]
			step(map, 0.4)
			assert.is_true(burst.ring.size[1] > early)
			assert.is_true(burst.label.alpha < 1)
			step(map, O.BURST_TIME)
			assert.is_nil(burst.startAt)
			assert.is_false(burst.shown)
			O.Seek(0)
			step(map, 0.001)
			O.Play()
			step(map, 0.51)
			assert.equal(2, #bursts(map))
			assert.is_not_nil(burst.startAt)
		end)

		it("scales a burst to the screen and anchors it at its pin", function()
			local map = setup(EVENTS)
			map.scale = 0.5
			O.Show(true)
			frames(map, 2)
			O.Play()
			step(map, 0.001)
			step(map, 0.51)
			local burst = bursts(map)[1]
			assert.equal(2, burst.scale)
			assert.same({ "CENTER", container(map), "TOPLEFT" }, { unpack(burst.point, 1, 3) })
			assert.near(500 / 2, burst.point[4], 1e-6)
			assert.near(-250 / 2, burst.point[5], 1e-6)
		end)

		it("plays at most a few bursts at once", function()
			local list = {}
			for i = 1, 6 do
				list[i] = { t = 1010 + i, m = ZONE, x = 1000 * i, y = 5000, kind = "lv", args = { 10 + i } }
			end
			local map = setup(list)
			O.Play()
			step(map, 0.001)
			step(map, 0.51)
			local playing = 0
			for _, b in ipairs(bursts(map)) do
				if b.startAt then
					playing = playing + 1
				end
			end
			assert.equal(O.MAX_BURSTS, playing)
			assert.equal(O.MAX_BURSTS, #bursts(map))
		end)

		it("plays no burst and sends no event when the playhead jumps over many events", function()
			local list = {}
			for i = 1, 12 do
				list[i] = { t = 1010 + i, m = ZONE, x = 500 * i, y = 5000, kind = "lv", args = { 10 + i } }
			end
			local map = setup(list)
			local events = 0
			ns.Listen("MAP_REPLAY_EVENT", function()
				events = events + 1
			end)
			O.Seek(0)
			step(map, 0.001)
			O.Seek(999)
			step(map)
			assert.equal(0, #bursts(map))
			assert.equal(0, events)
		end)

		it("plays no burst on a seek, and tells the panel to empty its feed on a seek back", function()
			local map = setup(EVENTS)
			local resets = 0
			ns.Listen("MAP_REPLAY_RESET", function()
				resets = resets + 1
			end)
			O.Seek(25)
			step(map)
			assert.equal(0, #bursts(map))
			O.Seek(0)
			step(map)
			assert.is_true(resets > 0)
		end)

		it("hides the bursts when the map clears its data", function()
			local map = setup(EVENTS)
			O.Play()
			step(map, 0.001)
			step(map, 0.51)
			local burst = bursts(map)[1]
			O.Show(false)
			assert.is_false(burst.shown)
			assert.is_nil(burst.startAt)
		end)

		it("gives the chapters of the replay, empty with nothing to play", function()
			local map = setup({ { t = 1015, kind = "lv", args = { 12 } } })
			local chapters = O.Chapters()
			assert.equal(2, #chapters)
			assert.equal(12, chapters[2].level)
			assert.equal(15, chapters[2].c)
			O.Show(false)
			assert.same({}, O.Chapters())
			assert.is_not_nil(map)
		end)
	end)

	describe("follow", function()
		local TWO = {
			chunk(ZONE, 1000, "0,1000,1000;10,2000,1000;20,3000,1000"),
			chunk(OTHER, 1040, "0,1000,2000;10,2000,2000;20,3000,2000"),
		}

		local function play(chunks, opts)
			boot(chunks, opts)
			local map, p = attach()
			O.Show(true)
			frames(map, 2)
			O.Play()
			step(map, 0.001)
			return map, p
		end

		it("shows the map of the playhead, keeps the playhead and waits before it goes on", function()
			local map = play(TWO)
			assert.equal(60, select(2, O.Position()))
			step(map, 0.5)
			assert.same({}, map.set)
			step(map, 0.5)
			assert.same({ OTHER }, map.set)
			assert.equal(OTHER, map:GetMapID())
			assert.near(40, O.Position(), 0.1)
			assert.is_true(O.Playing())
			local held = O.Position()
			step(map, 0.5)
			assert.equal(held, (O.Position()))
			step(map, 0.5)
			assert.equal(held, (O.Position()))
			step(map, 0.5)
			assert.near(60, O.Position(), 0.001)
			assert.equal(2, visible(lines(map)))
		end)

		it("shows the pins of the new map that the playhead passed, with no pop, burst or feed event", function()
			boot(TWO)
			journal({ { t = 1040, m = OTHER, x = 2000, y = 2000, kind = "lv", args = { 5 } } })
			local map = attach()
			O.Show(true)
			frames(map, 2)
			O.Play()
			step(map, 0.001)
			local events = 0
			ns.Listen("MAP_REPLAY_EVENT", function()
				events = events + 1
			end)
			step(map, 0.5)
			step(map, 0.5)
			assert.same({ OTHER }, map.set)
			step(map, 0.01)
			local shown = pins(map)
			assert.equal(1, visible(shown))
			assert.is_nil(shown[1].popAt)
			assert.equal(0, events)
		end)

		it("stays on a map that shows the zone of the playhead", function()
			local projections = {
				[ZONE] = { continent = 1, x0 = 100, y0 = 100, x1 = 200, y1 = 200 },
				[OTHER] = { continent = 1, x0 = 500, y0 = 500, x1 = 600, y1 = 600 },
				[CONT] = { continent = 1, x0 = 0, y0 = 0, x1 = 1000, y1 = 1000 },
			}
			boot(TWO, {
				maps = { [CONT] = { mapType = 2 }, [ZONE] = { mapType = 3 }, [OTHER] = { mapType = 3 } },
				projections = projections,
			})
			local map = attach(CONT)
			O.Show(true)
			frames(map, 2)
			O.Play()
			step(map, 0.001)
			frames(map, 6, 0.5)
			assert.same({}, map.set)
			assert.equal(CONT, map:GetMapID())
			assert.equal(60, (O.Position()))
		end)

		it("stops following when the player changes the map during the replay, until the next Play", function()
			local map, p = play(TWO)
			step(map, 0.2)
			map.mapID = OTHER
			p:OnMapChanged()
			assert.is_true(O.Playing())
			frames(map, 3, 0.1)
			assert.same({}, map.set)
			O.Pause()
			O.Play()
			step(map, 0.1)
			assert.same({ ZONE }, map.set)
		end)

		it("stops following after a seek and after a change of the box too, and starts again with them", function()
			local map, p = play(TWO)
			step(map, 0.2)
			map.mapID = OTHER
			p:OnMapChanged()
			O.Seek(10)
			step(map, 0.01)
			assert.same({ ZONE }, map.set)
		end)

		it("leaves following off for a map that cannot be shown, and asks once", function()
			local map = play(TWO)
			map.refuse = true
			frames(map, 5, 0.5)
			assert.same({ OTHER }, map.set)
			assert.equal(ZONE, map:GetMapID())
			assert.equal(60, (O.Position()))
			assert.equal(1, #ns.Errors())
		end)

		it("leaves following off when the map has no SetMapID", function()
			local map = play(TWO)
			map.SetMapID = nil
			frames(map, 5, 0.5)
			assert.equal(ZONE, map:GetMapID())
			assert.equal(60, (O.Position()))
		end)

		it("puts the map back and stops following when SetMapID takes the id and then raises", function()
			local map = play(TWO)
			map.broken = { [OTHER] = true }
			frames(map, 5, 0.5)
			assert.same({ OTHER, ZONE }, map.set)
			assert.equal(ZONE, map:GetMapID())
			assert.near(60, O.Position(), 0.001)
			assert.equal(1, #ns.Errors())
		end)

		it("does not ask for a map that has no art", function()
			local map = play(TWO)
			_G.C_Map.GetMapArtLayers = function(id)
				return id == OTHER and {} or { { layerWidth = 1000, layerHeight = 500 } }
			end
			frames(map, 5, 0.5)
			_G.C_Map.GetMapArtLayers = nil
			assert.same({}, map.set)
			assert.equal(60, (O.Position()))
			assert.equal(1, #ns.Errors())
		end)

		it("plays on the clock of the map shown when no trail is saved, and keeps no playhead across maps", function()
			boot({})
			journal({
				{ t = 1000, m = ZONE, x = 1000, y = 1000, kind = "lv", args = { 2 } },
				{ t = 1010, m = ZONE, x = 2000, y = 1000, kind = "lv", args = { 3 } },
			})
			local map, p = attach()
			O.Show(true)
			frames(map, 2)
			assert.equal(10, select(2, O.Position()))
			assert.equal(2, visible(pins(map)))
			O.Play()
			step(map, 0.1)
			assert.is_true(O.Playing())
			map.mapID = OTHER
			p:OnMapChanged()
			assert.is_false(O.Playing())
		end)

		it("plays the map shown only with Follow off, on the clock of that map", function()
			boot(TWO)
			ns.Settings.Set("map.follow", false)
			local map = attach()
			O.Show(true)
			frames(map, 2)
			assert.equal(20, select(2, O.Position()))
			O.Play()
			step(map, 0.001)
			frames(map, 4, 0.5)
			assert.same({}, map.set)
		end)

		it("draws again on the other clock when Follow changes, and saves the choice", function()
			boot(TWO)
			local map = attach()
			O.Show(true)
			frames(map, 2)
			assert.equal(60, select(2, O.Position()))
			O.SetFollow(false)
			assert.is_false(MemoriesDB.settings.map.follow)
			assert.equal(20, select(2, O.Position()))
			O.SetFollow(true)
			assert.is_true(MemoriesDB.settings.map.follow)
			assert.equal(60, select(2, O.Position()))
		end)

		it("has nothing to play when nothing is shown", function()
			boot(TWO)
			for _, group in ipairs(ns.MapData.Groups()) do
				ns.Settings.Set("map.groups." .. group, false)
			end
			ns.Settings.Set("map.trail", false)
			local map = attach()
			O.Show(true)
			step(map)
			assert.equal(0, select(2, O.Position()))
		end)

		it("keeps the playhead through a filter change during the replay", function()
			local map = play(TWO)
			step(map, 0.2)
			local at = O.Position()
			ns.Settings.Set("map.color", "age")
			O.Draw()
			assert.equal(at, (O.Position()))
			assert.is_true(O.Playing())
			assert.same({}, map.set)
		end)

		it("keeps the feed of the panel through a map change of Follow", function()
			local map = play(TWO)
			local resets = 0
			ns.Listen("MAP_REPLAY_RESET", function()
				resets = resets + 1
			end)
			step(map, 0.5)
			step(map, 0.5)
			assert.same({ OTHER }, map.set)
			assert.equal(0, resets)
		end)

		it("does not keep a playhead read on another clock", function()
			local map = play(TWO)
			step(map, 0.2)
			O.SetSession({ start = 1040 })
			assert.is_false(O.Playing())
			local at, total = O.Position()
			assert.equal(total, at)
			O.SetSession(nil)
			O.SetFollow(false)
			O.Play()
			step(map, 0.2)
			O.SetFollow(true)
			assert.is_false(O.Playing())
		end)

		it("keeps the chapters on the clock of the whole journey", function()
			boot(TWO)
			local map = attach()
			journal({ { t = 1050, kind = "lv", args = { 12 } } })
			O.Show(true)
			frames(map, 2)
			local chapters = O.Chapters()
			assert.equal(2, #chapters)
			assert.equal(50, chapters[2].c)
		end)
	end)
end)
