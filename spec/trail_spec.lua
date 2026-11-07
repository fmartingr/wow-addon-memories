local wow = require("helpers.wow")

describe("trail codec", function()
	local ns

	before_each(function()
		ns = wow.boot({ login = false })
	end)

	it("writes the flag letters in their fixed order, - for none", function()
		local F = ns.TrailCodec.Flags
		assert.equal("-", F({}))
		assert.equal(
			"tfmdwci",
			F({
				taxi = true,
				flying = true,
				mounted = true,
				dead = true,
				swimming = true,
				combat = true,
				instance = true,
			})
		)
		assert.equal("g", F({ ghost = true, dead = true }))
		assert.equal("mc", F({ combat = true, mounted = true }))
	end)

	it("writes flags on the first point and on each change, and decodes them back", function()
		local chunk = ns.TrailCodec.New(100, 1000, 1453)
		chunk:Add(0, 4512, 6120, "m")
		chunk:Add(2.4, 4530, 6101, "m")
		chunk:Add(3.6, 4560, 6080, "mc")
		local rec = chunk:Record()
		assert.same({ s = 100, t = 1000, m = 1453, n = 3, d = "0,4512,6120,m;2,4530,6101;4,4560,6080,mc" }, rec)
		assert.equal(1, chunk:Record(true).o)
		assert.same({
			{ t = 1000, x = 4512, y = 6120, flags = "m" },
			{ t = 1002, x = 4530, y = 6101, flags = "m" },
			{ t = 1004, x = 4560, y = 6080, flags = "mc" },
		}, ns.TrailCodec.Decode(rec))
	end)

	it("decodes nothing from a malformed record", function()
		local D = ns.TrailCodec.Decode
		assert.is_nil(D("x"))
		assert.is_nil(D({ t = 1 }))
		assert.is_nil(D({ t = 1, d = "1,2" }))
		assert.same({}, D({ t = 1, d = "" }))
	end)
end)

describe("trail", function()
	local ns

	local function counts(module)
		return ns.Store.Core():Counts(module)
	end

	local function chunks()
		return MemoriesCharDB.trail.chunks
	end

	-- Moves the player by dx, dy yards (world) and tx, ty map units, then waits one 2 s tick.
	local function step(dx, dy, tx, ty)
		if wow.world then
			wow.world.x = wow.world.x + (dx or 0)
			wow.world.y = wow.world.y + (dy or 0)
		end
		wow.map.x = wow.map.x + (tx or 0) / 10000
		wow.map.y = wow.map.y + (ty or 0) / 10000
		wow.advance(2)
	end

	local function point(x, y, flags)
		return { m = 1453, x = x, y = y, flags = flags or "-" }
	end

	before_each(function()
		ns = wow.boot()
	end)

	it("keeps only the first point while the player moves 1 yd per tick with the same flags", function()
		step()
		for i = 1, 4 do
			step(i % 2 == 1 and 1 or -1)
		end
		local open = ns.Trail.Open()
		assert.equal(1, open.n)
		assert.equal("0,5000,2500,-", open.d)
		assert.equal(1453, open.m)
		assert.equal(wow.wall - 10 + 2, open.t)
		assert.equal(ns.Sessions.Current().start, open.s)
	end)

	it("keeps a new point with flag m on a mount-up without movement", function()
		step()
		wow.flags.mounted = true
		step()
		local pts = ns.TrailCodec.Decode(ns.Trail.Open())
		assert.equal(2, #pts)
		assert.equal("m", pts[2].flags)
		assert.equal("m", ns.Trail.Flags())
	end)

	it("counts no distance for a teleport and starts a new chunk", function()
		step()
		step(1500, 0, 900, 0)
		assert.is_nil(counts("distance").foot)
		assert.equal(1, #chunks())
		assert.equal(1, chunks()[1].n)
		assert.equal(1, ns.Trail.Open().n)
		step(10, 0, 50, 0)
		assert.equal(10, counts("distance").foot)
		assert.equal(1, #chunks())
	end)

	it("files the old chunk on a map change and opens one with the new map", function()
		step()
		wow.map.id = 1429
		step()
		assert.equal(1, #chunks())
		assert.equal(1453, chunks()[1].m)
		assert.equal(1429, ns.Trail.Open().m)
	end)

	it("counts 0 s for a tick that comes long after the last", function()
		step()
		local sec = counts("move").sec
		assert.equal(2, sec)
		-- The clock jumps without running the timers, as when the client stalls.
		wow.clock = wow.clock + 30
		ns.Trail.Tick()
		assert.equal(sec, counts("move").sec)
	end)

	it("starts a new chunk for a teleport during a stalled tick", function()
		step()
		wow.clock = wow.clock + 10
		wow.world.x = wow.world.x + 5000
		ns.Trail.Tick()
		assert.is_nil(counts("distance").foot)
		assert.equal(1, #chunks())
		assert.equal(1, ns.Trail.Open().n)
	end)

	it("counts riding time and yards when mounted and moving", function()
		step()
		wow.flags.mounted = true
		step(22)
		local move, dist = counts("move"), counts("distance")
		assert.equal(2, move.moving)
		assert.equal(2, move.ride)
		assert.equal(2, move["ride:10"])
		assert.equal(22, dist.ride)
		assert.equal(22, dist["ride:10"])
		assert.equal(2, counts("activity").travel)
	end)

	it("counts dungeon time in an instance and feeds no point", function()
		wow.instance = { type = "party", name = "Las Minas de la Muerte" }
		step(30)
		step(30)
		assert.equal(4, counts("activity").dungeon)
		assert.equal(4, counts("activity")["dungeon:10"])
		assert.is_nil(ns.Trail.Open())
		assert.is_nil(ns.Trail.LastPoint())
		assert.same({ t = wow.wall }, ns.Here())
	end)

	it("counts an ascend for a jump while swimming or flying, else a jump", function()
		wow.flags.swimming = true
		JumpOrAscendStart()
		assert.equal(1, counts("travel").ascend)
		assert.is_nil(counts("travel").jumps)
		wow.flags.swimming = false
		JumpOrAscendStart()
		JumpOrAscendStart()
		assert.equal(2, counts("travel").jumps)
		assert.equal(2, counts("travel")["jumps:10"])
		assert.equal(3, wow.jumps)
	end)

	it("counts nothing for the jump key on a flight path", function()
		wow.flags.taxi = true
		JumpOrAscendStart()
		assert.is_nil(counts("travel").jumps)
		assert.is_nil(counts("travel").ascend)
	end)

	it("files the open copy left in the saved data at login and clears it", function()
		local copy = { s = 1, t = 100, m = 1453, n = 2, d = "0,1,1,-;2,9,9", o = 1 }
		wow.boot({ saved = { MemoriesCharDB = { trail = { v = 1, chunks = {}, open = copy } } } })
		assert.equal(1, #MemoriesCharDB.trail.chunks)
		assert.same(copy, MemoriesCharDB.trail.chunks[1])
		assert.is_nil(MemoriesCharDB.trail.open)
		wow.boot({ saved = { MemoriesCharDB = { trail = { chunks = {}, open = { n = 0 } } } } })
		assert.same({}, MemoriesCharDB.trail.chunks)
		assert.is_nil(MemoriesCharDB.trail.open)
	end)

	it("refreshes the open copy at most once a minute", function()
		step()
		assert.same(
			{ s = ns.Sessions.Current().start, t = wow.wall, m = 1453, n = 1, d = "0,5000,2500,-", o = 1 },
			MemoriesCharDB.trail.open
		)
		step(10, 0, 40, 0)
		assert.equal(1, MemoriesCharDB.trail.open.n)
		for _ = 1, 29 do
			step(10, 0, 40, 0)
		end
		assert.equal(31, ns.Trail.Open().n)
		assert.equal(31, MemoriesCharDB.trail.open.n)
	end)

	it("closes the chunk and clears the copy at logout", function()
		step()
		step(10, 0, 40, 0)
		wow.fire("PLAYER_LOGOUT")
		assert.equal(1, #chunks())
		assert.equal(2, chunks()[1].n)
		assert.is_nil(chunks()[1].o)
		assert.is_nil(MemoriesCharDB.trail.open)
		assert.is_nil(ns.Trail.Open())
		ns.Trail.Close()
		assert.equal(1, #chunks())
	end)

	it("pauses during a loading screen and forgets the world position", function()
		step()
		wow.fire("LOADING_SCREEN_ENABLED")
		assert.equal(1, #chunks())
		local sec = counts("move").sec
		step(5000)
		step()
		assert.equal(sec, counts("move").sec)
		assert.is_nil(ns.Trail.Open())
		wow.fire("LOADING_SCREEN_DISABLED")
		step(5)
		assert.equal(sec + 2, counts("move").sec)
		assert.is_nil(counts("distance").foot)
		step(5)
		assert.equal(5, counts("distance").foot)
		wow.fire("PLAYER_ENTERING_WORLD", false, false)
		step(5)
		assert.equal(5, counts("distance").foot)
	end)

	it("starts a new chunk after 60 s without a position, and at 2,000 points", function()
		ns.Trail.Feed(point(1, 1))
		wow.clock = wow.clock + 61
		ns.Trail.Feed(point(100, 100))
		assert.equal(1, #chunks())
		for i = 1, 2000 do
			ns.Trail.Feed(point(10 * i, 1))
		end
		assert.equal(2, #chunks())
		assert.equal(2000, chunks()[2].n)
		assert.equal(1, ns.Trail.Open().n)
	end)

	it("thins by 3 yards, or by 4 map units without yards, and keeps a flag change", function()
		assert.is_true(ns.Trail.Feed({ m = 1453, x = 10, y = 10, wx = 0, wy = 0, flags = "-" }))
		assert.is_false(ns.Trail.Feed({ m = 1453, x = 90, y = 10, wx = 2.9, wy = 0, flags = "-" }))
		assert.is_true(ns.Trail.Feed({ m = 1453, x = 10, y = 10, wx = 3, wy = 0, flags = "-" }))
		assert.is_false(ns.Trail.Feed(point(13, 10)))
		assert.is_true(ns.Trail.Feed(point(14, 10)))
		assert.is_true(ns.Trail.Feed(point(14, 10, "c")))
		assert.equal(4, ns.Trail.Open().n)
		assert.same({ m = 1453, x = 14, y = 10, t = wow.wall }, ns.Trail.LastPoint())
	end)

	it("thins by map units and counts no distance when the world position is unknown", function()
		wow.world = nil
		step()
		step(0, 0, 3, 0)
		step(0, 0, 4, 0)
		assert.equal(2, ns.Trail.Open().n)
		assert.same({}, counts("distance"))
		wow.world = { x = 0, y = 0, inst = 0 }
		_G.UnitPosition = function()
			return wow.secret(1), 0, 0, 0
		end
		step(0, 0, 10, 0)
		assert.equal(3, ns.Trail.Open().n)
	end)

	it("tells the listeners about each kept point", function()
		local seen = {}
		ns.Listen("TRAIL_LIVE", function(_, m, x, y)
			seen[#seen + 1] = { m, x, y }
		end)
		step()
		step(1)
		step(10, 0, 40, 0)
		assert.same({ { 1453, 5000, 2500 }, { 1453, 5040, 2500 } }, seen)
	end)

	it("skips world and continent maps, and keeps their place out of lines", function()
		wow.maps[947] = { mapType = 1 }
		wow.maps[1453] = { mapType = 3 }
		wow.map.id = 947
		step()
		assert.is_nil(ns.Trail.Open())
		assert.same({ t = wow.wall }, ns.Here())
		assert.is_true(ns.IsSkippedMap(947))
		assert.is_false(ns.IsSkippedMap(1453))
		assert.matches("^%d+||||", ns.Store.Core():Write("ex", "a", "b"))
		wow.maps[947] = { mapType = 3 }
		assert.is_true(ns.IsSkippedMap(947))
		wow.map.id = 1453
		assert.same({ t = wow.wall, m = 1453, x = 5000, y = 2500 }, ns.Here())
	end)

	it("counts a secret instance answer as outside", function()
		_G.IsInInstance = function()
			return wow.secret(true), "party"
		end
		step()
		assert.is_false(ns.InInstance())
		assert.equal(1, ns.Trail.Open().n)
		assert.is_nil(counts("activity").dungeon)
	end)

	it("puts each tick into the first matching activity", function()
		step()
		wow.flags.afk = true
		wow.fire("PLAYER_FLAGS_CHANGED", "player")
		wow.flags.dead = true
		step()
		wow.flags.afk = false
		wow.fire("PLAYER_FLAGS_CHANGED", "player")
		step()
		wow.flags.dead = false
		wow.combat = true
		step(5)
		wow.combat = false
		step(5)
		wow.flags.taxi = true
		step()
		wow.flags.taxi = false
		step()
		local a = counts("activity")
		assert.same({
			town = 4,
			["town:10"] = 4,
			afk = 2,
			["afk:10"] = 2,
			dead = 2,
			["dead:10"] = 2,
			combat = 2,
			["combat:10"] = 2,
			travel = 4,
			["travel:10"] = 4,
		}, a)
		assert.equal(14, counts("move").sec)
	end)

	it("puts each move into the first matching mode", function()
		step()
		wow.flags.taxi = true
		step(40)
		wow.flags.taxi = false
		wow.flags.ghost = true
		step(4)
		wow.flags.ghost = false
		wow.flags.swimming = true
		step(4)
		wow.flags.swimming = false
		step(40)
		step(4)
		wow.flags.moving = true
		step()
		local m, d = counts("move"), counts("distance")
		assert.equal(2, m.fly)
		assert.equal(40, d.fly)
		assert.equal(2, m.ghost)
		assert.equal(2, m.swim)
		assert.equal(2, m.boat)
		assert.equal(40, d.boat)
		assert.equal(4, m.foot)
		assert.equal(4, d.foot)
		assert.equal(12, m.moving)
	end)

	it("restarts the timer when the recording rate changes", function()
		step()
		local sec = counts("move").sec
		ns.Settings.Set("recordRate", 5)
		wow.advance(4.9)
		assert.equal(sec, counts("move").sec)
		wow.advance(0.1)
		assert.equal(sec + 5, counts("move").sec)
		ns.Settings.Set("saveReminder", false)
		wow.advance(5)
		assert.equal(sec + 10, counts("move").sec)
	end)

	it("counts the first tick after the rate drops from the last tick at the longer rate", function()
		ns.Settings.Set("recordRate", 10)
		wow.advance(10)
		local sec = counts("move").sec
		wow.advance(9)
		ns.Settings.Set("recordRate", 1)
		wow.advance(1)
		assert.equal(sec + 10, counts("move").sec)
	end)

	it("falls back to 2 s for a rate that is not allowed", function()
		ns.Settings.Get = function()
			return 3
		end
		ns.Emit("SETTING_CHANGED", "recordRate", 3)
		local sec = counts("move").sec or 0
		wow.advance(2)
		assert.equal(sec + 2, counts("move").sec)
	end)

	it("files a restored backup's copy and writes the running stretch's copy", function()
		step()
		ns.Backup.Write("Memories")
		local old = { s = 1, t = 5, m = 1, n = 1, d = "0,1,1,-", o = 1 }
		local rec = ns.Backup.Record("Memories")
		local data = ns.Backup.Read("Memories")
		data.trail.open = old
		rec.blob, rec.data = nil, data
		assert.is_true(ns.Backup.Restore("Memories"))
		local trail = MemoriesCharDB.trail
		assert.same(old, trail.chunks[#trail.chunks])
		assert.equal(1, trail.open.n)
		assert.equal(1453, trail.open.m)
	end)

	it("keeps 3 chunks over a reload", function()
		step()
		step(10, 0, 40, 0)
		wow.map.id = 1429
		step()
		wow.map.id = 1437
		step()
		step(10, 0, 40, 0)
		local before = {}
		for _, c in ipairs(chunks()) do
			before[#before + 1] = ns.TrailCodec.Decode(c)
		end
		before[#before + 1] = ns.TrailCodec.Decode(ns.Trail.Open())
		ns = wow.reload()
		assert.equal(3, #chunks())
		local maps = {}
		for i, c in ipairs(chunks()) do
			maps[i] = c.m
			assert.same(before[i], ns.TrailCodec.Decode(c))
		end
		assert.same({ 1453, 1429, 1437 }, maps)
		assert.is_nil(MemoriesCharDB.trail.open)
	end)
end)
