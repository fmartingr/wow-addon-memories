local wow = require("helpers.wow")

describe("map overlay", function()
	wow.pin_locale("enUS", before_each, after_each)

	local ns, O
	local ZONE, OTHER = 1453, 1454

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
end)
