local wow = require("helpers.wow")

describe("replay timeline", function()
	local ns, R

	before_each(function()
		ns = wow.boot({ login = false })
		R = ns.Replay
	end)

	local function seg(way, pts, ts)
		return { way = way, pts = pts, ts = ts }
	end

	it("builds the edges in time order with a clock that caps each pause", function()
		local tl = R.Build({
			segments = {
				seg("foot", { 0.1, 0.1, 0.2, 0.1 }, { 1000, 1010 }),
				seg("mounted", { 0.5, 0.5, 0.6, 0.5 }, { 5000, 5004 }),
			},
		})
		assert.equal(2, #tl.edges)
		assert.equal(0, tl.edges[1].c0)
		assert.equal(10, tl.edges[1].c)
		assert.equal(10 + R.GAP, tl.edges[2].c0)
		assert.equal(10 + R.GAP + 4, tl.edges[2].c)
		assert.equal(tl.edges[2].c, tl.total)
	end)

	it("sorts the edges of segments that were read out of order", function()
		local tl = R.Build({
			segments = {
				seg("mounted", { 0.5, 0.5, 0.6, 0.5 }, { 5000, 5004 }),
				seg("foot", { 0.1, 0.1, 0.2, 0.1 }, { 1000, 1010 }),
			},
		})
		assert.equal("foot", tl.edges[1].way)
		assert.equal("mounted", tl.edges[2].way)
	end)

	it("keeps the oldest edges at the cap", function()
		local tl = R.Build({ segments = { seg("foot", { 0, 0, 1, 0, 2, 0, 3, 0 }, { 1, 2, 3, 4 }) } }, 2)
		assert.equal(2, #tl.edges)
		assert.equal(2, tl.total)
	end)

	it("skips an edge with no time", function()
		local tl = R.Build({ segments = { seg("foot", { 0, 0, 1, 0 }, {}), { way = "foot", pts = { 0, 0, 1, 0 } } } })
		assert.equal(0, #tl.edges)
		assert.equal(0, tl.total)
	end)

	it("gives each pin a clock inside the trail clock, pins in clock order", function()
		local tl = R.Build({
			segments = { seg("foot", { 0.1, 0.1, 0.2, 0.1 }, { 1000, 1010 }) },
			pins = {
				{ t = 1008, kind = "de" },
				{ t = 1002, kind = "lv" },
				{ t = "x", kind = "zz" },
				{ t = 1000, kind = "lv" },
			},
		})
		assert.equal(3, #tl.pins)
		assert.equal("lv", tl.pins[1].kind)
		assert.equal(0, tl.pins[1].c)
		assert.equal(2, tl.pins[2].c)
		assert.equal(8, tl.pins[3].c)
		assert.equal(10, tl.total)
	end)

	it("plays a journey that has pins and no trail", function()
		local tl = R.Build({ pins = { { t = 100 }, { t = 105 } } })
		assert.equal(5, tl.total)
		assert.equal(0, #tl.edges)
		assert.is_nil(R.Head(tl, 3))
	end)

	it("is empty with no data", function()
		local tl = R.Build({})
		assert.equal(0, tl.total)
		assert.same({ 0, 0 }, { R.Counts(tl, 5) })
	end)

	it("advances at the base rate times the speed and stops at the end", function()
		local c, playing = R.Advance(0, 0.5, 1, 100)
		assert.equal(20, c)
		assert.is_true(playing)
		c, playing = R.Advance(c, 0.5, 4, 100)
		assert.equal(100, c)
		assert.is_false(playing)
		assert.equal(10, (R.Advance(10, -3, 1, 100)))
	end)

	it("counts the edges and the pins that show at a clock", function()
		local tl = R.Build({
			segments = { seg("foot", { 0, 0, 0.1, 0, 0.2, 0 }, { 1000, 1010, 1020 }) },
			pins = { { t = 1005 }, { t = 1015 } },
		})
		assert.same({ 0, 0 }, { R.Counts(tl, 4) })
		assert.same({ 0, 1 }, { R.Counts(tl, 5) })
		assert.same({ 1, 1 }, { R.Counts(tl, 10) })
		assert.same({ 2, 2 }, { R.Counts(tl, 99) })
	end)

	it("glides the head along the step it is on and rests between steps", function()
		local tl = R.Build({
			segments = {
				seg("foot", { 0, 0, 1, 0 }, { 1000, 1010 }),
				seg("mounted", { 1, 1, 1, 2 }, { 1100, 1110 }),
			},
		})
		local x, y, way = R.Head(tl, 0)
		assert.same({ 0, 0, "foot" }, { x, y, way })
		x, y = R.Head(tl, 5)
		assert.same({ 0.5, 0 }, { x, y })
		x, y, way = R.Head(tl, 10)
		assert.same({ 1, 0, "foot" }, { x, y, way })
		x, y, way = R.Head(tl, 20)
		assert.same({ 1, 0, "foot" }, { x, y, way })
		x, y, way = R.Head(tl, 35)
		assert.same({ 1, 1.5, "mounted" }, { x, y, way })
		x, y, way = R.Head(tl, 999)
		assert.same({ 1, 2, "mounted" }, { x, y, way })
	end)

	it("puts the head on the end of an instant step", function()
		local tl = R.Build({ segments = { seg("foot", { 0, 0, 1, 1 }, { 5, 5 }) } })
		local x, y = R.Head(tl, 0)
		assert.same({ 1, 1 }, { x, y })
	end)

	it("writes the clock as m:ss, or h:mm:ss from one hour", function()
		assert.equal("0:00", R.ClockText(-5))
		assert.equal("1:05", R.ClockText(65.9))
		assert.equal("1:00:00", R.ClockText(3600))
		assert.equal("2:03:09", R.ClockText(7389))
	end)

	describe("trip arcs", function()
		local jump = { x1 = 0.1, y1 = 0.5, t0 = 1000, x2 = 0.9, y2 = 0.5, t1 = 1030 }

		it("cuts a trip into the steps of a curve that joins its two points in its time", function()
			local tl = R.Build({ jumps = { jump } })
			assert.equal(R.ARC_STEPS, #tl.edges)
			local first, last = tl.edges[1], tl.edges[#tl.edges]
			assert.same({ 0.1, 0.5, "arc", 1000 }, { first.x1, first.y1, first.way, first.t0 })
			assert.near(0.9, last.x2, 1e-9)
			assert.near(0.5, last.y2, 1e-9)
			assert.near(1030, last.t, 1e-9)
			for i = 2, #tl.edges do
				assert.near(tl.edges[i - 1].x2, tl.edges[i].x1, 1e-9)
				assert.near(tl.edges[i - 1].y2, tl.edges[i].y1, 1e-9)
			end
			assert.equal(tl.total, last.c)
		end)

		it("bows the curve to the north, whichever way the trip goes", function()
			for _, j in ipairs({ jump, { x1 = 0.9, y1 = 0.5, t0 = 1, x2 = 0.1, y2 = 0.5, t1 = 31 } }) do
				local tl = R.Build({ jumps = { j } })
				local highest = 1
				for _, e in ipairs(tl.edges) do
					highest = math.min(highest, e.y2)
				end
				assert.is_true(highest < 0.5)
			end
		end)

		it("is a straight line for a trip of no length", function()
			local tl = R.Build({ jumps = { { x1 = 0.5, y1 = 0.5, t0 = 1, x2 = 0.5, y2 = 0.5, t1 = 11 } } })
			assert.equal(R.ARC_STEPS, #tl.edges)
			assert.near(0.5, tl.edges[5].y2, 1e-9)
		end)

		it("plays in time order with the trail", function()
			local tl = R.Build({
				segments = { seg("foot", { 0, 0, 0.1, 0 }, { 990, 1000 }) },
				jumps = { jump },
			})
			assert.equal("foot", tl.edges[1].way)
			assert.equal("arc", tl.edges[2].way)
		end)
	end)

	describe("levels and ages", function()
		local levels = { { t = 100, level = 10 }, { t = 200, level = 11 } }
		local function edgeAt(t0, t1, data)
			data = data or {}
			data.segments = { seg("foot", { 0, 0, 1, 0 }, { t0, t1 }) }
			return R.Build(data).edges[1]
		end

		it("gives each step the level of the character at its end", function()
			assert.equal(9, edgeAt(10, 50, { levels = levels }).level)
			assert.equal(10, edgeAt(150, 160, { levels = levels }).level)
			assert.equal(11, edgeAt(250, 260, { levels = levels }).level)
			assert.equal(1, edgeAt(10, 50, { levels = { { t = 100, level = 1 } } }).level)
			assert.is_nil(edgeAt(10, 50).level)
			assert.is_nil(edgeAt(10, 50, { levels = {} }).level)
		end)

		it("gives the oldest step age 0 and the newest age 1", function()
			local tl = R.Build({
				segments = { seg("foot", { 0, 0, 1, 0, 2, 0, 3, 0 }, { 100, 110, 120, 140 }) },
			})
			assert.equal(0.25, tl.edges[1].age)
			assert.equal(0.5, tl.edges[2].age)
			assert.equal(1, tl.edges[3].age)
			assert.equal(1, edgeAt(5, 5).age)
		end)
	end)

	describe("colour", function()
		local function rgba(...)
			return { ... }
		end

		it("uses the colour of the way, a palette for each way and one for the colourblind", function()
			for way, color in pairs(R.WAY_COLOR) do
				assert.same(rgba(color[1], color[2], color[3], 0.9), rgba(R.Color({ way = way }, "way", false)))
			end
			for way, color in pairs(R.BLIND_WAY_COLOR) do
				assert.same(rgba(color[1], color[2], color[3], 0.9), rgba(R.Color({ way = way }, "way", true)))
			end
			assert.same(
				rgba(R.WAY_COLOR.foot[1], R.WAY_COLOR.foot[2], R.WAY_COLOR.foot[3], 0.9),
				rgba(R.Color({ way = "x" }, "way"))
			)
			assert.is_not.same(
				rgba(R.Color({ way = "foot" }, "way", false)),
				rgba(R.Color({ way = "foot" }, "way", true))
			)
		end)

		it("keeps the five ways of the colourblind palette apart", function()
			local seen = {}
			for _, color in pairs(R.BLIND_WAY_COLOR) do
				local key = ("%.2f,%.2f,%.2f"):format(color[1], color[2], color[3])
				assert.is_nil(seen[key])
				seen[key] = true
			end
		end)

		it("colours a step by its level along a ramp from level 1 to the last level", function()
			local low = rgba(R.Color({ way = "foot", level = 1 }, "level"))
			local high = rgba(R.Color({ way = "foot", level = R.MAX_LEVEL }, "level"))
			local mid = rgba(R.Color({ way = "foot", level = 30 }, "level"))
			assert.is_not.same(low, high)
			assert.is_not.same(low, mid)
			assert.equal(0.9, low[4])
			assert.same(high, rgba(R.Color({ way = "foot", level = 99 }, "level")))
			assert.same(low, rgba(R.Color({ way = "foot", level = -5 }, "level")))
			assert.is_not.same(
				rgba(R.Color({ level = 30 }, "level", false)),
				rgba(R.Color({ level = 30 }, "level", true))
			)
		end)

		it("falls back to the way for a step with no level or no age", function()
			local foot = rgba(R.Color({ way = "foot" }, "way"))
			assert.same(foot, rgba(R.Color({ way = "foot" }, "level")))
			assert.same(foot, rgba(R.Color({ way = "foot" }, "age")))
		end)

		it("makes an older step cooler and dimmer than a newer one", function()
			local old = rgba(R.Color({ age = 0 }, "age"))
			local new = rgba(R.Color({ age = 1 }, "age"))
			assert.is_true(old[4] < new[4])
			assert.is_true(old[3] > new[3])
			assert.equal(0.4, old[4])
			assert.equal(0.9, new[4])
		end)
	end)

	describe("the clock of a time and the direction of the head", function()
		it("gives the clock of a unix time from the timeline", function()
			local tl = R.Build({ segments = { seg("foot", { 0, 0, 1, 0 }, { 1000, 1010 }) } })
			assert.equal(5, tl.clockAt(1005))
			assert.equal(0, tl.clockAt(1))
			assert.equal(10, tl.clockAt(9999))
		end)

		it("gives the direction of the step the head is on", function()
			local tl = R.Build({ segments = { seg("foot", { 0, 0, 1, 0, 1, 2 }, { 1000, 1010, 1020 }) } })
			local _, _, _, dx, dy = R.Head(tl, 5)
			assert.same({ 1, 0 }, { dx, dy })
			_, _, _, dx, dy = R.Head(tl, 15)
			assert.same({ 0, 2 }, { dx, dy })
			_, _, _, dx, dy = R.Head(tl, 99)
			assert.same({ 0, 2 }, { dx, dy })
			_, _, _, dx, dy = R.Head(R.Build({ segments = { seg("foot", { 0, 0, 3, 3 }, { 1000, 1000 }) } }), 0)
			assert.same({ 3, 3 }, { dx, dy })
		end)
	end)

	describe("chapters", function()
		local tl
		before_each(function()
			tl = R.Build({ segments = { seg("foot", { 0, 0, 1, 0, 2, 0 }, { 1000, 1010, 1020 }) } })
		end)

		it("lists the start and each level up inside the timeline, with its clock", function()
			local chapters = R.Chapters(tl, {
				{ t = 900, level = 9 },
				{ t = 1005, level = 10 },
				{ t = 1015, level = 11 },
				{ t = 5000, level = 12 },
			})
			assert.same({ { c = 0 }, { level = 10, t = 1005, c = 5 }, { level = 11, t = 1015, c = 15 } }, chapters)
		end)

		it("has only the start with no level up, and none with nothing to play", function()
			assert.same({ { c = 0 } }, R.Chapters(tl, {}))
			assert.same({ { c = 0 } }, R.Chapters(tl))
			assert.same({}, R.Chapters(R.Build({}), { { t = 1, level = 2 } }))
		end)

		it("gives the first and the last time of the timeline", function()
			assert.same({ 1000, 1020 }, { tl.first, tl.last })
		end)
	end)

	describe("the clock of the whole journey", function()
		local visits = {
			{ m = 1, t0 = 1000, t1 = 1020 },
			{ m = 2, t0 = 5000, t1 = 5030 },
			{ m = 1, t0 = 5030, t1 = 5040 },
		}

		it("counts the real time inside a visit and at most the gap between two visits", function()
			local clock = R.Clock(visits)
			assert.equal(20 + R.GAP + 30 + 10, clock.total)
			assert.equal(0, clock.at(1000))
			assert.equal(20, clock.at(1020))
			assert.equal(20 + R.GAP, clock.at(5000))
			assert.equal(20 + R.GAP + 30, clock.at(5030))
			assert.equal(clock.total, clock.at(99999))
			assert.equal(0, clock.at(1))
		end)

		it("puts a time inside a gap in between, and counts overlapping visits once", function()
			local clock = R.Clock({ { t0 = 0, t1 = 100 }, { t0 = 50, t1 = 120 }, { t0 = 1000, t1 = 1000 } })
			assert.equal(120 + R.GAP, clock.total)
			assert.equal(120 + R.GAP / 2, clock.at(560))
		end)

		it("is empty with no visit", function()
			local clock = R.Clock({})
			assert.equal(0, clock.total)
			assert.equal(0, clock.at(5))
		end)

		it("gives each visit the clock of its start and end, and the map of the playhead", function()
			local clock = R.Clock(visits)
			local route = R.Route(visits, clock)
			assert.same({ m = 2, c0 = 20 + R.GAP, c1 = 20 + R.GAP + 30 }, route[2])
			assert.is_nil(R.MapAt(route, -1))
			assert.equal(1, R.MapAt(route, 0))
			assert.equal(1, R.MapAt(route, 30))
			assert.equal(2, R.MapAt(route, 20 + R.GAP))
			assert.equal(2, R.MapAt(route, 60))
			assert.equal(1, R.MapAt(route, 20 + R.GAP + 30))
			assert.equal(1, R.MapAt(route, 9999))
			assert.is_nil(R.MapAt({}, 5))
		end)

		it("builds a timeline on the clock of the journey, with its total and its times", function()
			local clock = R.Clock(visits)
			local tl = R.Build({ segments = { seg("foot", { 0, 0, 1, 0 }, { 5000, 5010 }) } }, nil, clock)
			assert.equal(clock.total, tl.total)
			assert.equal(20 + R.GAP, tl.edges[1].c0)
			assert.equal(20 + R.GAP + 10, tl.edges[1].c)
			assert.same({ 1000, 5040 }, { tl.first, tl.last })
			assert.equal(20, tl.clockAt(1020))
		end)

		it("leaves out a pin that is far outside the journey, and keeps one near its edge", function()
			local clock = R.Clock(visits)
			local tl = R.Build({
				pins = {
					{ t = 100 },
					{ t = 1000 - R.GAP },
					{ t = 5040 + R.GAP + 1 },
					{ t = 3000 },
					{ t = 5040 + R.GAP },
				},
			}, nil, clock)
			assert.equal(3, #tl.pins)
			assert.equal(0, tl.pins[1].c)
			assert.equal(clock.total, tl.pins[3].c)
		end)

		it("falls back to the clock of the map when the journey has no visit", function()
			local tl = R.Build({ segments = { seg("foot", { 0, 0, 1, 0 }, { 1000, 1010 }) } }, nil, R.Clock({}))
			assert.equal(10, tl.total)
			assert.equal(1, #tl.edges)
		end)
	end)
end)
