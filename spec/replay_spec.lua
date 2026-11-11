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
end)
