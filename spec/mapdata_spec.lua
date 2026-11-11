local wow = require("helpers.wow")

describe("map data", function()
	local ns, M

	local ZONE, OTHER, FAR, CONT, CONT2 = 1453, 1454, 1411, 12, 13
	local function chunk(m, t, d, extra)
		local rec = { s = 1, t = t, m = m, n = 1, d = d }
		for k, v in pairs(extra or {}) do
			rec[k] = v
		end
		return rec
	end

	local function boot(chunks, opts)
		opts = opts or {}
		ns = wow.boot({
			login = false,
			maps = opts.maps or {
				[CONT] = { mapType = 2 },
				[CONT2] = { mapType = 2 },
				[ZONE] = { mapType = 3, parentMapID = CONT },
				[OTHER] = { mapType = 3, parentMapID = CONT },
				[FAR] = { mapType = 3, parentMapID = CONT2 },
			},
			projections = opts.projections,
			saved = {
				MemoriesCharDB = { trail = { v = 1, chunks = chunks, open = opts.open }, sessions = opts.sessions },
			},
		})
		M = ns.MapData
		ns.Store.Reopen()
	end

	local function lines(list)
		local j = ns.Store.Core()
		for _, l in ipairs(list) do
			j:WriteAt({ t = l.t, m = l.m, x = l.x, y = l.y }, l.kind, unpack(l.args or {}))
		end
	end

	describe("Way", function()
		it("names the way of travel from the flags, the first match winning", function()
			boot({})
			assert.equal("foot", M.Way("-"))
			assert.equal("foot", M.Way("c"))
			assert.equal("mounted", M.Way("m"))
			assert.equal("mounted", M.Way("f"))
			assert.equal("taxi", M.Way("tf"))
			assert.equal("swim", M.Way("wm"))
			assert.equal("dead", M.Way("g"))
			assert.equal("dead", M.Way("dm"))
		end)
	end)

	describe("Project", function()
		it("puts a zone point on the higher map through the world position", function()
			boot({}, {
				projections = {
					[ZONE] = { continent = 1, x0 = 100, y0 = 100, x1 = 200, y1 = 200 },
					[CONT] = { continent = 1, x0 = 0, y0 = 0, x1 = 1000, y1 = 1000 },
				},
			})
			local x, y = M.Project(ZONE, 0.5, 0.25, CONT)
			assert.near(0.15, x, 1e-9)
			assert.near(0.125, y, 1e-9)
		end)

		it("gives nil without a world position, without a target position and outside the target", function()
			boot({}, {
				projections = {
					[ZONE] = { continent = 1, x0 = 100, y0 = 100, x1 = 200, y1 = 200 },
					[CONT] = { continent = 1, x0 = 0, y0 = 0, x1 = 120, y1 = 120 },
					[OTHER] = { continent = 2, x0 = 0, y0 = 0, x1 = 1, y1 = 1 },
				},
			})
			assert.is_nil(M.Project(999, 0.5, 0.5, CONT))
			assert.is_nil(M.Project(ZONE, 0.5, 0.5, 999))
			assert.is_nil(M.Project(ZONE, 0.5, 0.5, OTHER))
			assert.is_nil(M.Project(ZONE, 0.9, 0.5, CONT))
		end)

		it("gives nil when a game call is missing or fails", function()
			boot({})
			local map = _G.C_Map
			local saved = map.GetWorldPosFromMapPos
			map.GetWorldPosFromMapPos = nil
			assert.is_nil(M.Project(ZONE, 0.5, 0.5, CONT))
			map.GetWorldPosFromMapPos = function()
				error("bad map")
			end
			assert.is_nil(M.Project(ZONE, 0.5, 0.5, CONT))
			map.GetWorldPosFromMapPos = saved
			_G.C_Map = nil
			assert.is_nil(M.Project(ZONE, 0.5, 0.5, CONT))
			_G.C_Map = map
		end)

		it("gives nil when the game has no CreateVector2D", function()
			boot({}, {
				projections = {
					[ZONE] = { continent = 1, x0 = 0, y0 = 0, x1 = 1, y1 = 1 },
					[CONT] = { continent = 1, x0 = 0, y0 = 0, x1 = 1, y1 = 1 },
				},
			})
			local create = _G.CreateVector2D
			_G.CreateVector2D = nil
			local x = M.Project(ZONE, 0.3, 0.4, CONT)
			_G.CreateVector2D = create
			assert.is_nil(x)
			assert.near(0.3, M.Project(ZONE, 0.3, 0.4, CONT), 1e-9)
		end)
	end)

	describe("Segments", function()
		it("returns nothing for an empty trail", function()
			boot({})
			local segs, skipped = M.Segments(ZONE, {})
			assert.same({}, segs)
			assert.same({}, skipped)
		end)

		it("returns nothing when MemoriesCharDB has no trail", function()
			boot({})
			_G.MemoriesCharDB = nil
			assert.same({}, (M.Segments(ZONE)))
			_G.MemoriesCharDB = { trail = "x" }
			assert.same({}, (M.Segments(ZONE)))
		end)

		it("joins the points of a chunk of the map into one segment in map units", function()
			boot({ chunk(ZONE, 1000, "0,1000,2000,m;2,2000,3000;4,3000,4000") })
			local segs = M.Segments(ZONE, {})
			assert.equal(1, #segs)
			assert.equal("mounted", segs[1].way)
			assert.same({ 0.1, 0.2, 0.2, 0.3, 0.3, 0.4 }, segs[1].pts)
		end)

		it("skips a chunk of another map", function()
			boot({ chunk(OTHER, 1000, "0,1000,2000;2,2000,3000") })
			assert.same({}, (M.Segments(ZONE, {})))
		end)

		it("keeps a long stand inside a chunk as one line, and breaks the line between chunks", function()
			boot({
				chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;300,2100,1000;302,3000,1000"),
				chunk(ZONE, 2000, "0,3000,1000;2,4000,1000"),
			})
			local segs = M.Segments(ZONE, {})
			assert.equal(2, #segs)
			assert.same({ 0.1, 0.1, 0.2, 0.1, 0.21, 0.1, 0.3, 0.1 }, segs[1].pts)
			assert.same({ 0.3, 0.1, 0.4, 0.1 }, segs[2].pts)
		end)

		it("goes on into the next chunk after a full chunk, and only then", function()
			local max = 2000
			boot({
				chunk(ZONE, 1000, "0,1000,1000;2,2000,1000", { n = max }),
				chunk(ZONE, 1004, "0,3000,1000;2,4000,1000", { n = 2 }),
				chunk(ZONE, 1008, "0,5000,1000;2,6000,1000", { n = 2 }),
				chunk(OTHER, 1012, "0,1000,1000;2,2000,1000", { n = max }),
				chunk(ZONE, 1016, "0,7000,1000;2,8000,1000", { n = 2 }),
			})
			assert.equal(max, ns.Trail.MAX_POINTS)
			local segs = M.Segments(ZONE, {})
			assert.equal(3, #segs)
			assert.same({ 0.1, 0.1, 0.2, 0.1, 0.3, 0.1, 0.4, 0.1 }, segs[1].pts)
			assert.same({ 0.5, 0.1, 0.6, 0.1 }, segs[2].pts)
			assert.same({ 0.7, 0.1, 0.8, 0.1 }, segs[3].pts)
		end)

		it("starts a new segment at a change of way and keeps the line whole", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000,m;6,4000,1000") })
			local segs = M.Segments(ZONE, {})
			assert.equal(2, #segs)
			assert.equal("foot", segs[1].way)
			assert.same({ 0.1, 0.1, 0.2, 0.1 }, segs[1].pts)
			assert.equal("mounted", segs[2].way)
			assert.same({ 0.2, 0.1, 0.3, 0.1, 0.4, 0.1 }, segs[2].pts)
		end)

		it("thins points that are nearer than the step to the last kept point", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;2,1005,1000;4,1010,1000;6,1500,1000") })
			local segs = M.Segments(ZONE, {})
			assert.same({ 0.1, 0.1, 0.15, 0.1 }, segs[1].pts)
			boot({ chunk(ZONE, 1000, "0,1000,1000;50,1005,1000;100,1010,1000;102,3000,1000") })
			segs = M.Segments(ZONE, {})
			assert.equal(1, #segs)
			assert.same({ 0.1, 0.1, 0.3, 0.1 }, segs[1].pts)
		end)

		it("draws no point with the flag i, and splits the line there", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000,i;6,4000,1000,-;8,5000,1000") })
			local segs = M.Segments(ZONE, {})
			assert.equal(2, #segs)
			assert.same({ 0.1, 0.1, 0.2, 0.1 }, segs[1].pts)
			assert.same({ 0.4, 0.1, 0.5, 0.1 }, segs[2].pts)
		end)

		it("skips a point outside 0..10000, a malformed chunk and a chunk with one point", function()
			boot({
				chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,12000,1000;6,3000,1000;8,3500,1000"),
				chunk(ZONE, 2000, "garbage"),
				"not a chunk",
				chunk("x", 3000, "0,1,1"),
				chunk(ZONE, 4000, "0,1000,1000"),
			})
			local segs = M.Segments(ZONE, {})
			assert.equal(2, #segs)
			assert.same({ 0.3, 0.1, 0.35, 0.1 }, segs[2].pts)
		end)

		it("adds the open stretch", function()
			boot({})
			wow.map.x, wow.map.y = 0.5, 0.5
			ns.Trail.Feed({ m = ZONE, x = 5000, y = 5000, flags = "-" })
			ns.Trail.Feed({ m = ZONE, x = 5600, y = 5000, flags = "-" })
			local segs = M.Segments(ZONE, {})
			assert.equal(1, #segs)
			assert.same({ 0.5, 0.5, 0.56, 0.5 }, segs[1].pts)
		end)

		it("keeps a chunk of the chosen session whole, past a stop saved early", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000", { s = 1000 }) })
			local segs = M.Segments(ZONE, { session = { start = 1000, stop = 1002 } })
			assert.same({ 0.1, 0.1, 0.2, 0.1, 0.3, 0.1 }, segs[1].pts)
			assert.same({}, (M.Segments(ZONE, { session = { start = 5000 } })))
		end)

		it("cuts a chunk with no session start by the time of the session", function()
			boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000;6,4000,1000;8,5000,1000", { s = false }) })
			local segs = M.Segments(ZONE, { session = { start = 1002, stop = 1006 } })
			assert.same({ 0.2, 0.1, 0.3, 0.1, 0.4, 0.1 }, segs[1].pts)
			assert.same({}, (M.Segments(ZONE, { session = { start = 5000 } })))
			assert.same({}, (M.Segments(ZONE, { session = { start = 1, stop = 500 } })))
			assert.equal(1, #M.Segments(ZONE, { session = { start = 1000 } }))
		end)

		it("skips a chunk that is not a table with a session chosen", function()
			boot({ 5, chunk(ZONE, 1000, "0,1000,1000;2,2000,1000", { s = 1000 }) })
			assert.equal(1, #M.Segments(ZONE, { session = { start = 1000, stop = 2000 } }))
		end)

		it("skips a chunk of another session before it decodes it", function()
			boot({
				chunk(ZONE, 1000, "0,1000,1000;2,2000,1000", { s = 900 }),
				chunk(ZONE, 2000, "0,3000,1000;2,4000,1000", { s = 2000 }),
			})
			local decoded = 0
			local decode = ns.TrailCodec.Decode
			ns.TrailCodec.Decode = function(rec)
				decoded = decoded + 1
				return decode(rec)
			end
			local segs = M.Segments(ZONE, { session = { start = 2000 } })
			assert.equal(1, decoded)
			assert.same({ { way = "foot", pts = { 0.3, 0.1, 0.4, 0.1 } } }, segs)
		end)

		it("reads the saved copy of the open stretch when Trail does not record", function()
			boot({}, { open = chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") })
			assert.is_nil(ns.Trail.Open())
			local segs = M.Segments(ZONE, {})
			assert.equal(1, #segs)
			assert.same({ 0.1, 0.1, 0.2, 0.1 }, segs[1].pts)
		end)

		describe("on a continent", function()
			local projections = {
				[ZONE] = { continent = 1, x0 = 100, y0 = 100, x1 = 200, y1 = 200 },
				[CONT] = { continent = 1, x0 = 0, y0 = 0, x1 = 1000, y1 = 1000 },
			}

			it("puts the zones below it on the map through the world position", function()
				boot({ chunk(ZONE, 1000, "0,0,0;2,5000,5000;4,10000,10000") }, { projections = projections })
				local segs, skipped = M.Segments(CONT, {})
				assert.same({}, skipped)
				assert.equal(1, #segs)
				assert.near(0.1, segs[1].pts[1], 1e-9)
				assert.near(0.15, segs[1].pts[3], 1e-9)
				assert.near(0.2, segs[1].pts[5], 1e-9)
			end)

			it("skips a zone without a projection and counts it once", function()
				boot({
					chunk(OTHER, 1000, "0,1000,1000;2,2000,1000"),
					chunk(OTHER, 2000, "0,1000,1000;2,2000,1000"),
					chunk(ZONE, 3000, "0,1000,1000;2,2000,1000"),
				}, { projections = projections })
				local segs, skipped = M.Segments(CONT, {})
				assert.same({ [OTHER] = true }, skipped)
				assert.equal(1, #segs)
			end)

			it("does not count a zone of another continent", function()
				boot({ chunk(FAR, 1000, "0,1000,1000;2,2000,1000") }, { projections = projections })
				local segs, skipped = M.Segments(CONT, {})
				assert.same({}, segs)
				assert.same({}, skipped)
			end)

			it("does not project the zones for a map that is not higher", function()
				boot({ chunk(ZONE, 1000, "0,1000,1000;2,2000,1000") }, { projections = projections })
				local segs, skipped = M.Segments(OTHER, {})
				assert.same({}, segs)
				assert.same({}, skipped)
			end)

			it("breaks the line at a point outside the map and keeps the rest of the zone", function()
				boot(
					{ chunk(ZONE, 1000, "0,9000,1000;2,1000,1000;4,2000,1000;6,8000,1000;8,3000,1000;10,4000,1000") },
					{
						projections = {
							[ZONE] = { continent = 1, x0 = 100, y0 = 100, x1 = 200, y1 = 200 },
							[CONT] = { continent = 1, x0 = 0, y0 = 0, x1 = 150, y1 = 150 },
						},
					}
				)
				local segs, skipped = M.Segments(CONT, {})
				assert.same({}, skipped)
				assert.equal(2, #segs)
				assert.near(110 / 150, segs[1].pts[1], 1e-9)
				assert.near(130 / 150, segs[2].pts[1], 1e-9)
			end)

			it("thins the points in the units of the shown map", function()
				boot(
					{ chunk(ZONE, 1000, "0,1000,1000;2,1050,1000;4,1100,1000;6,1500,1000") },
					{ projections = projections }
				)
				local segs = M.Segments(CONT, {})
				assert.equal(1, #segs)
				assert.equal(4, #segs[1].pts)
				assert.near(0.11, segs[1].pts[1], 1e-9)
				assert.near(0.115, segs[1].pts[3], 1e-9)
			end)

			it("asks the game for two corners of each zone, not for each point", function()
				boot({
					chunk(ZONE, 1000, "0,1000,1000;2,2000,1000;4,3000,1000;6,4000,1000"),
					chunk(ZONE, 2000, "0,5000,1000;2,6000,1000"),
				}, { projections = projections })
				local map = _G.C_Map
				local orig = map.GetWorldPosFromMapPos
				local calls = 0
				map.GetWorldPosFromMapPos = function(...)
					calls = calls + 1
					return orig(...)
				end
				assert.equal(2, #M.Segments(CONT, {}))
				assert.equal(2, calls)
			end)
		end)
	end)

	describe("Pins", function()
		local ALL
		before_each(function()
			boot({})
			ALL = { Progress = true, Deaths = true, Travel = true, Sessions = true }
		end)

		it("returns the lines with a position on the map, with their group and fields", function()
			lines({
				{ t = 10, m = ZONE, x = 1000, y = 2000, kind = "lv", args = { 12 } },
				{ t = 20, m = OTHER, x = 1000, y = 2000, kind = "lv", args = { 13 } },
				{ t = 30, kind = "lv", args = { 14 } },
				{ t = 40, m = ZONE, x = 3000, y = 4000, kind = "de", args = { "Wolf" } },
			})
			local pins, total = M.Pins(ZONE, { groups = ALL })
			assert.equal(2, total)
			assert.equal(2, #pins)
			assert.equal("lv", pins[1].kind)
			assert.equal("Progress", pins[1].group)
			assert.equal(10, pins[1].t)
			assert.near(0.1, pins[1].x, 1e-9)
			assert.near(0.2, pins[1].y, 1e-9)
			assert.equal(12, pins[1].fields.level)
			assert.equal("Deaths", pins[2].group)
			assert.equal("Wolf", pins[2].fields.killer)
		end)

		it("keeps only the shown groups, and none without a filter", function()
			lines({
				{ t = 10, m = ZONE, x = 1000, y = 2000, kind = "lv", args = { 12 } },
				{ t = 40, m = ZONE, x = 3000, y = 4000, kind = "de", args = { "Wolf" } },
			})
			local pins = M.Pins(ZONE, { groups = { Deaths = true } })
			assert.equal(1, #pins)
			assert.equal("de", pins[1].kind)
			assert.same({}, (M.Pins(ZONE)))
		end)

		it("skips a kind this client does not know and a position out of range", function()
			local open = MemoriesCharDB.log.open
			open[#open + 1] = "10||" .. ZONE .. "|1000|2000|zz|a"
			open[#open + 1] = "11||" .. ZONE .. "|99999|2000|lv|5"
			open[#open + 1] = "garbage"
			open[#open + 1] = 42
			assert.same({}, (M.Pins(ZONE, { groups = ALL })))
		end)

		it("limits the list and still counts every match", function()
			for i = 1, 5 do
				lines({ { t = i, m = ZONE, x = i * 100, y = 100, kind = "lv", args = { i } } })
			end
			local pins, total = M.Pins(ZONE, { groups = ALL, limit = 2 })
			assert.equal(2, #pins)
			assert.equal(5, total)
		end)

		it("keeps the lines of the chosen session", function()
			lines({
				{ t = 10, m = ZONE, x = 1000, y = 2000, kind = "lv", args = { 1 } },
				{ t = 50, m = ZONE, x = 1000, y = 2000, kind = "lv", args = { 2 } },
				{ t = 90, m = ZONE, x = 1000, y = 2000, kind = "lv", args = { 3 } },
			})
			local pins = M.Pins(ZONE, { groups = ALL, session = { start = 40, stop = 60 } })
			assert.equal(1, #pins)
			assert.equal(2, pins[1].fields.level)
		end)

		it("returns nothing for an empty journal and without a core journal", function()
			assert.same({}, (M.Pins(ZONE, { groups = ALL })))
			ns.Store.Core = function() end
			local pins, total = M.Pins(ZONE, { groups = ALL })
			assert.same({}, pins)
			assert.equal(0, total)
		end)

		it("reads a read-only journal", function()
			local ro = wow.boot({
				login = false,
				saved = {
					MemoriesDB = { schema = 99 },
					MemoriesCharDB = {
						schema = 99,
						log = { chunks = {}, open = { "10||" .. ZONE .. "|1000|2000|lv|7" } },
					},
				},
			})
			ro.Store.Reopen()
			assert.is_false(ro.Store.Core():CanWrite())
			local pins = ro.MapData.Pins(ZONE, { groups = ALL })
			assert.equal(1, #pins)
			assert.equal(7, pins[1].fields.level)
		end)

		it("puts the lines of a zone on a continent map", function()
			boot({}, {
				projections = {
					[ZONE] = { continent = 1, x0 = 100, y0 = 100, x1 = 200, y1 = 200 },
					[CONT] = { continent = 1, x0 = 0, y0 = 0, x1 = 1000, y1 = 1000 },
				},
			})
			lines({
				{ t = 10, m = ZONE, x = 5000, y = 5000, kind = "lv", args = { 1 } },
				{ t = 20, m = OTHER, x = 5000, y = 5000, kind = "lv", args = { 2 } },
			})
			local pins, total, skipped = M.Pins(CONT, { groups = ALL })
			assert.equal(1, total)
			assert.same({ [OTHER] = true }, skipped)
			assert.near(0.15, pins[1].x, 1e-9)
		end)

		it("reads the journals of the sub-addons", function()
			ns = wow.boot({ addons = { "Memories", "Memories_Combat" } })
			local j = ns.Registry.Journal("Memories_Combat").journal
			j:WriteAt({ t = 10, m = ZONE, x = 1000, y = 2000 }, "ra", "Mor'Ladim", 522, 35)
			local pins = ns.MapData.Pins(ZONE, { groups = { Combat = true } })
			assert.equal(1, #pins)
			assert.equal("ra", pins[1].kind)
			assert.equal("Combat", pins[1].group)
		end)
	end)

	describe("Groups", function()
		it("lists each group once in registration order", function()
			boot({})
			local groups = M.Groups()
			assert.equal("Sessions", groups[1])
			assert.equal("Progress", groups[2])
			local seen = {}
			for _, g in ipairs(groups) do
				assert.is_nil(seen[g])
				seen[g] = true
			end
			assert.is_true(seen.Deaths)
			assert.is_true(seen.Travel)
		end)
	end)

	describe("Sessions", function()
		it("lists the saved sessions by start, the running one with no stop", function()
			boot({}, {
				sessions = {
					{ start = 300, last = 400 },
					{ start = 100, last = 200 },
					{ start = 500 },
					{ start = 600, last = 550 },
					"bad",
					{ last = 1 },
				},
			})
			assert.same({
				{ start = 100, stop = 200 },
				{ start = 300, stop = 400 },
				{ start = 500, stop = 500 },
				{ start = 600, stop = 600 },
			}, M.Sessions())
			ns.Sessions.Current = function()
				return MemoriesCharDB.sessions[1]
			end
			assert.same({ start = 300 }, M.Sessions()[2])
		end)

		it("returns nothing without saved sessions", function()
			boot({})
			assert.same({}, M.Sessions())
			_G.MemoriesCharDB = nil
			assert.same({}, M.Sessions())
		end)
	end)
end)
