local wow = require("helpers.wow")

describe("travel", function()
	local TRAVEL = {
		zo = true,
		sz = true,
		ld = true,
		le = true,
		tx = true,
		tl = true,
		bt = true,
		hs = true,
		so = true,
		su = true,
		po = true,
		jp = true,
		mo = true,
		ml = true,
	}
	local ELWYNN, TRAM = 1429, 369

	local ns

	-- An error inside a handler goes to the error log, never to the test.
	after_each(function()
		assert.same({}, type(MemoriesDB) == "table" and MemoriesDB.errors or {})
	end)

	-- Each line of the travel kinds as "kind|fields", in journal order.
	local function lines()
		local out = {}
		for line in ns.Store.Core():Lines() do
			local k, rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(%w+)|?(.*)$")
			if TRAVEL[k] then
				out[#out + 1] = rest == "" and k or k .. "|" .. rest
			end
		end
		return out
	end

	local function decoded(kind)
		local found
		for line in ns.Store.Core():Lines() do
			local ev = ns.Codec.DecodeLine(line)
			if ev.k == kind then
				found = ev
			end
		end
		return found
	end

	local function counts(module)
		return ns.Store.Core():Counts(module or "travel")
	end

	local function state()
		return MemoriesCharDB.state.travel
	end

	-- Without map coordinates the trail feeds no point, so only sample() feeds Travel; coords keeps them.
	local function boot(opts)
		opts = opts or {}
		ns = wow.boot(opts)
		if not opts.coords then
			wow.map.x, wow.map.y = nil, nil
		end
		return ns
	end

	local function sample(x, y, inst)
		wow.world = { x = x, y = y, inst = inst or wow.world.inst }
		ns.Emit("TRAIL_LIVE", wow.map.id, 5000, 2500)
	end

	local function feed(x, wx)
		wow.world = { x = wx, y = 0, inst = wow.world.inst }
		ns.Trail.Feed({ m = wow.map.id, x = x, y = 2500, flags = 0 })
	end

	local function loadingScreen(after)
		wow.fire("LOADING_SCREEN_ENABLED")
		after()
		wow.fire("LOADING_SCREEN_DISABLED")
	end

	local function newLines(before)
		local all = lines()
		local out = {}
		for i = before + 1, #all do
			out[#out + 1] = all[i]
		end
		return out
	end

	describe("zones", function()
		it("writes the zone once, also across a reload", function()
			boot()
			assert.same({ "zo|Bosque de Elwynn" }, lines())
			wow.fire("ZONE_CHANGED_NEW_AREA")
			wow.reload()
			ns = wow.ns.Memories
			assert.same({ "zo|Bosque de Elwynn" }, lines())
			assert.equal("Bosque de Elwynn", state().zone)
		end)

		it("confirms an inn at login only with the zone that the map names, in Spanish", function()
			boot({
				zone = "Posada de Villa del Lago",
				maps = { [1453] = { name = "Montañas Crestagrana", mapType = 3 } },
			})
			wow.zone = "Villa del Lago"
			wow.fire("ZONE_CHANGED")
			assert.same({ "zo|Posada de Villa del Lago" }, lines())
			wow.zone = "Montañas Crestagrana"
			wow.fire("ZONE_CHANGED")
			assert.same({ "zo|Posada de Villa del Lago", "zo|Montañas Crestagrana" }, lines())
			wow.zone = "Villa del Lago"
			wow.fire("ZONE_CHANGED_INDOORS")
			assert.same({ "zo|Posada de Villa del Lago", "zo|Montañas Crestagrana" }, lines())
		end)

		it("ends the check when the map has the name of the loaded zone", function()
			boot({ zone = "Ventormenta", maps = { [1453] = { name = "Ventormenta", mapType = 3 } } })
			wow.fire("ZONE_CHANGED")
			wow.maps[1453].name = "Distrito de los Enanos"
			wow.zone = "Distrito de los Enanos"
			wow.fire("ZONE_CHANGED")
			assert.same({ "zo|Ventormenta" }, lines())
		end)

		it("ends the check on a new area and writes its zone", function()
			boot({ zone = "Posada", maps = { [1453] = { name = "Montañas Crestagrana", mapType = 3 } } })
			wow.zone = "Bosque del Ocaso"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			wow.zone = "Montañas Crestagrana"
			wow.fire("ZONE_CHANGED")
			assert.same({ "zo|Posada", "zo|Bosque del Ocaso" }, lines())
		end)

		it("writes a new subzone outside instances; a new zone clears the last one", function()
			boot({ subzone = "Villadorada" })
			wow.fire("ZONE_CHANGED")
			wow.subzone = "Mina de la Garra"
			wow.fire("ZONE_CHANGED_INDOORS")
			wow.subzone = ""
			wow.fire("ZONE_CHANGED")
			wow.zone, wow.subzone = "Páramos de Poniente", "Mina de la Garra"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			wow.instance = { name = "Minas de la Muerte", type = "party", id = 36 }
			wow.subzone = "Cala de los Mástiles"
			wow.fire("ZONE_CHANGED")
			assert.same({
				"zo|Bosque de Elwynn",
				"sz|Villadorada",
				"sz|Mina de la Garra",
				"zo|Páramos de Poniente",
				"sz|Mina de la Garra",
			}, lines())
		end)

		it("reads GetZoneText when the real zone text is empty, and skips a secret zone", function()
			boot({ zone = "" })
			assert.same({}, lines())
			_G.GetZoneText = function()
				return "Bosque de Elwynn"
			end
			wow.fire("ZONE_CHANGED_NEW_AREA")
			assert.same({ "zo|Bosque de Elwynn" }, lines())
			wow.zone = wow.secret("Ventormenta")
			_G.GetZoneText = nil
			wow.fire("ZONE_CHANGED_NEW_AREA")
			assert.same({ "zo|Bosque de Elwynn" }, lines())
		end)
	end)

	describe("trips", function()
		it("writes a hearthstone across a loading screen (Appendix B, case 3)", function()
			boot({ bind = "Villadorada", world = { x = 100, y = 100, inst = 0 } })
			wow.cast(8690)
			loadingScreen(function()
				wow.map.id = ELWYNN
				wow.world = { x = 400, y = 500, inst = 0 }
			end)
			assert.same({ "zo|Bosque de Elwynn", "ld|8690", "le" }, lines())
			wow.advance(2)
			assert.same({ "zo|Bosque de Elwynn", "ld|8690", "le", "hs|1453|1429|Villadorada|500" }, lines())
			assert.equal(1, counts().hearths)
			assert.equal(500, counts("distance").hearth)
		end)

		it("waits for the end of a second loading screen that starts within the settle time", function()
			boot({ bind = "Villadorada", world = { x = 100, y = 100, inst = 0 } })
			wow.cast(8690)
			loadingScreen(function() end)
			wow.advance(1)
			wow.fire("LOADING_SCREEN_ENABLED")
			wow.advance(1.5)
			assert.same({ "zo|Bosque de Elwynn", "ld|8690", "le", "ld|8690" }, lines())
			wow.map.id = ELWYNN
			wow.world = { x = 400, y = 500, inst = 0 }
			wow.fire("LOADING_SCREEN_DISABLED")
			wow.advance(2)
			assert.same(
				{ "zo|Bosque de Elwynn", "ld|8690", "le", "ld|8690", "le", "hs|1453|1429|Villadorada|500" },
				lines()
			)
		end)

		it("writes a hearthstone without a loading screen, named by the place after", function()
			boot({ subzone = "Villadorada" })
			sample(0, 0)
			wow.cast(556)
			wow.advance(0.25)
			assert.same({ "zo|Bosque de Elwynn", "sz|Villadorada" }, lines())
			wow.world = { x = 3, y = 4, inst = 0 }
			wow.advance(0.25)
			assert.same("hs|1453|1453|Villadorada|5", lines()[3])
		end)

		it("writes no jp for the move of a trip without a loading screen", function()
			boot()
			sample(0, 0)
			wow.cast(8690)
			wow.world = { x = 500, y = 0, inst = 0 }
			wow.advance(2)
			sample(500, 0)
			assert.same({ "zo|Bosque de Elwynn", "hs|1453|1453|Bosque de Elwynn|500" }, lines())
		end)

		it("drops a trip with no move after 15 s and stops reading", function()
			boot()
			sample(0, 0)
			wow.cast(8690)
			wow.advance(16)
			wow.world = { x = 500, y = 0, inst = 0 }
			wow.advance(1)
			assert.same({ "zo|Bosque de Elwynn" }, lines())
		end)

		it("writes a teleport with its spell and the zone after", function()
			boot()
			sample(0, 0)
			wow.cast(3561)
			loadingScreen(function()
				wow.zone = "Ventormenta"
				wow.world = { x = 0, y = 0, inst = 1 }
			end)
			wow.advance(2)
			assert.equal("po|Ventormenta|1453|1453|3561", newLines(1)[3])
			assert.equal(1, counts().portals)
			assert.equal(0, counts("distance").portal)
		end)

		it("offers and arrives at a summon (Appendix B, case 4)", function()
			boot()
			sample(0, 0)
			wow.summon = { who = "Zed", area = "Bosque del Ocaso" }
			wow.fire("CONFIRM_SUMMON", 1, false)
			wow.summon = {}
			C_SummonInfo.ConfirmSummon()
			assert.equal(1, wow.summons)
			wow.world = { x = 24, y = 32, inst = 0 }
			wow.advance(0.25)
			assert.same({ "so|Zed|Bosque del Ocaso", "su|Zed|Bosque del Ocaso|1453|1453|40" }, newLines(1))
			assert.equal(1, counts().offers)
			assert.equal(1, counts().summons)
			assert.equal(40, counts("distance").portal)
		end)

		it("writes no summon without a move in 15 s (Appendix B, case 5)", function()
			boot()
			sample(0, 0)
			wow.summon = { who = wow.secret("Zed"), area = "Bosque del Ocaso" }
			wow.fire("CONFIRM_SUMMON", 1, false)
			C_SummonInfo.ConfirmSummon()
			wow.advance(16)
			assert.same({ "so|?|Bosque del Ocaso" }, newLines(1))
		end)

		it("starts no summon trip after the offer was cancelled", function()
			boot()
			wow.fire("CANCEL_SUMMON")
			C_SummonInfo.ConfirmSummon()
			wow.summon = { who = "Zed", area = "Bosque del Ocaso" }
			wow.fire("CONFIRM_SUMMON", 1, false)
			wow.fire("CANCEL_SUMMON")
			C_SummonInfo.ConfirmSummon()
			wow.world = { x = 400, y = 0, inst = 0 }
			wow.advance(1)
			assert.same({ "so|Zed|Bosque del Ocaso" }, newLines(1))
		end)

		it("writes a boat after fast moves and a world instance change (Appendix B, case 6)", function()
			boot({ zone = "Tanaris", subzone = "Bahía del Botín" })
			sample(0, 0)
			wow.advance(1)
			sample(26, 0)
			wow.advance(3)
			loadingScreen(function()
				wow.zone, wow.subzone = "Vega de Tuercespina", nil
				wow.map.id = 1434
				wow.world = { x = 0, y = 0, inst = 1 }
			end)
			wow.advance(2)
			assert.same({ "ld", "le", "bt|1453|1434|Bahía del Botín|Vega de Tuercespina" }, newLines(2))
			assert.equal(1, counts().boats)
		end)

		it("writes a boat when the fast move comes again within 30 s", function()
			boot()
			sample(0, 0)
			wow.advance(1)
			sample(20, 0)
			loadingScreen(function()
				wow.world = { x = 1000, y = 0, inst = 0 }
			end)
			wow.advance(5)
			sample(1000, 0)
			wow.advance(1)
			sample(1015, 0)
			assert.equal("bt|1453|1453|Bosque de Elwynn|Bosque de Elwynn", newLines(1)[3])
			wow.advance(30)
			assert.equal(3, #newLines(1))
		end)

		it("takes a fast move between the loading end and the arrival as the second one", function()
			boot()
			sample(0, 0)
			wow.advance(1)
			sample(20, 0)
			loadingScreen(function()
				wow.world = { x = 1000, y = 0, inst = 0 }
			end)
			sample(1000, 0)
			wow.advance(1)
			sample(1015, 0)
			wow.advance(1)
			assert.equal("bt|1453|1453|Bosque de Elwynn|Bosque de Elwynn", newLines(1)[3])
		end)

		it("writes a portal from another mage after a fast move with no second one (Appendix B, case 7)", function()
			boot()
			sample(0, 0)
			wow.advance(1)
			sample(20, 0)
			loadingScreen(function()
				wow.zone = "Ventormenta"
				wow.world = { x = 1000, y = 0, inst = 0 }
			end)
			wow.advance(31)
			assert.same({ "ld", "le" }, newLines(1))
			wow.advance(1)
			assert.same({ "ld", "le", "po|Ventormenta|1453|1453||980" }, newLines(1))
			assert.equal(1, counts().portals)
		end)

		it("writes jp other after a fast move when a cast came within 15 s", function()
			boot()
			sample(0, 0)
			wow.advance(1)
			sample(20, 0)
			wow.cast(133)
			loadingScreen(function()
				wow.world = { x = 1000, y = 0, inst = 0 }
			end)
			wow.advance(32)
			assert.same({ "ld|133", "le", "jp|1453|1453|980|other" }, newLines(1))
			assert.equal(1, counts().teleports)
		end)

		it("writes no travel line for a loading screen right after a revive (Appendix B, case 8)", function()
			boot({ clock = 100 })
			sample(0, 0)
			ns.Emit("ALIVE", "spirit")
			wow.advance(2)
			loadingScreen(function()
				wow.world = { x = 1000, y = 0, inst = 0 }
			end)
			wow.advance(3)
			assert.same({ "ld", "le" }, newLines(1))
		end)

		it("names a jump of a ghost spirit, of a release death and else other (Appendix B, case 9)", function()
			boot()
			wow.flags.ghost = true
			sample(0, 0)
			wow.advance(0.6)
			sample(300, 0)
			assert.same({ "jp|1453|1453|300|spirit" }, newLines(1))
			wow.flags.ghost, wow.flags.dead = false, true
			wow.advance(1)
			sample(300, 0)
			wow.advance(1)
			wow.flags.dead, wow.flags.ghost = false, true
			sample(600, 0)
			wow.flags.ghost = false
			sample(600, 0)
			wow.advance(1)
			sample(900, 0)
			wow.flags.taxi = true
			wow.advance(1)
			sample(1200, 0)
			assert.same({ "jp|1453|1453|300|spirit", "jp|1453|1453|300|death", "jp|1453|1453|300|other" }, newLines(1))
			assert.equal(3, counts().teleports)
		end)

		it("writes jp death for a release long after the death", function()
			boot()
			wow.flags.dead = true
			feed(5000, 0)
			wow.advance(18)
			feed(5000, 0)
			wow.advance(2)
			wow.flags.dead, wow.flags.ghost = false, true
			feed(7000, 400)
			assert.same({ "jp|1453|1453|400|death" }, newLines(1))
		end)

		it("writes no jp for a move across a stretch with no readable position", function()
			boot()
			feed(5000, 0)
			wow.advance(20)
			feed(7000, 160)
			assert.same({}, newLines(1))
		end)

		it("writes jp for a loading screen of a dead player, a ghost and the tram", function()
			boot()
			sample(0, 0)
			wow.flags.dead = true
			loadingScreen(function()
				wow.flags.dead, wow.flags.ghost = false, true
			end)
			wow.advance(2)
			loadingScreen(function() end)
			wow.advance(2)
			wow.flags.ghost = false
			loadingScreen(function()
				wow.world = { x = 10, y = 0, inst = TRAM }
			end)
			wow.advance(2)
			local jp = {}
			for _, line in ipairs(lines()) do
				if line:match("^jp") then
					jp[#jp + 1] = line
				end
			end
			assert.same({ "jp|1453|1453|0|death", "jp|1453|1453|0|spirit", "jp|1453|1453||tram" }, jp)
		end)

		it("writes jp other without positions this session or without a map", function()
			boot()
			loadingScreen(function() end)
			wow.advance(2)
			assert.equal("jp|1453|1453|0|other", newLines(1)[3])
			sample(0, 0)
			loadingScreen(function()
				wow.map.id = nil
			end)
			wow.advance(2)
			assert.equal("jp|1453||0|other", newLines(1)[6])
		end)

		it("takes the last position as the start when the map is missing at the loading screen", function()
			boot()
			sample(0, 0)
			wow.map.id = nil
			loadingScreen(function()
				wow.map.id = ELWYNN
				wow.zone = "Ventormenta"
			end)
			wow.advance(2)
			assert.same({ "ld", "le", "po|Ventormenta|1453|1429||0" }, newLines(1))
		end)

		it("writes nothing for a loading screen into an instance or from a taxi", function()
			boot()
			sample(0, 0)
			loadingScreen(function()
				wow.instance = { name = "Minas de la Muerte", type = "party", id = 36 }
			end)
			wow.advance(2)
			wow.instance = nil
			wow.flags.taxi = true
			loadingScreen(function()
				wow.flags.taxi = false
			end)
			wow.advance(2)
			assert.same({ "ld", "le", "ld||1", "le" }, newLines(1))
		end)

		it("places ld at the last position when the map has none", function()
			boot({ coords = true })
			sample(0, 0)
			wow.map.x = nil
			wow.fire("LOADING_SCREEN_ENABLED")
			local ev = decoded("ld")
			assert.same({ 1453, 5000, 2500 }, { ev.m, ev.x, ev.y })
		end)

		it("writes le only after an ld, and keeps the last 8 casts", function()
			boot()
			wow.fire("LOADING_SCREEN_DISABLED")
			wow.cast(wow.secret(8690))
			for i = 1, 9 do
				wow.cast(i)
			end
			wow.fire("LOADING_SCREEN_ENABLED")
			assert.same({ "ld|9" }, newLines(1))
		end)

		it("classifies with the pure classifier", function()
			local C = wow.boot({ login = false }).Travel.Classify
			local here = { m = 1, world = { x = 0, y = 0, inst = 0 } }
			assert.equal("su", C({ kind = "summon" }, here, here))
			assert.is_nil(C({ kind = "loading", loading = true, revive = true }, here, here))
			assert.is_nil(C({ kind = "jump", revive = true }, here, here))
			assert.equal("wait", C({ kind = "loading", loading = true, fast = true }, here, here))
			assert.equal("po", C({ kind = "loading", loading = true, fast = true, waited = true }, here, here))
		end)
	end)

	describe("flights", function()
		local NODES = {
			{ name = "Ventormenta", type = "CURRENT" },
			{ name = "Villa del Lago", type = "REACHABLE", cost = 50 },
		}

		it("writes the flight and lands only 5 s after take-off (Appendix B, case 10)", function()
			boot({ taxi = NODES })
			wow.fire("TAXIMAP_OPENED", 1)
			TakeTaxiNode(2)
			assert.same({ 2 }, wow.taken)
			assert.same({ "tx|Ventormenta|Villa del Lago|50" }, newLines(1))
			assert.same({ from = "Ventormenta", to = "Villa del Lago", cost = 50, t = wow.wall }, ns.Travel.Flight())
			wow.flags.taxi = true
			wow.advance(3)
			wow.flags.taxi = false
			wow.fire("PLAYER_CONTROL_GAINED")
			assert.equal(1, #newLines(1))
			wow.advance(57)
			wow.fire("PLAYER_CONTROL_GAINED")
			assert.same({ "tx|Ventormenta|Villa del Lago|50", "tl|Villa del Lago" }, newLines(1))
			assert.is_nil(ns.Travel.Flight())
			assert.equal(1, counts().flights)
		end)

		it("lands on a position off the taxi", function()
			boot({ taxi = NODES })
			wow.fire("TAXIMAP_OPENED", 1)
			TakeTaxiNode(2)
			wow.flags.taxi = true
			wow.advance(10)
			sample(0, 0)
			wow.flags.taxi = false
			sample(0, 0)
			assert.same({ "tx|Ventormenta|Villa del Lago|50", "tl|Villa del Lago" }, newLines(1))
		end)

		it("lands at a mount-up of a player who stood still off the taxi", function()
			boot({ taxi = NODES })
			wow.fire("TAXIMAP_OPENED", 1)
			TakeTaxiNode(2)
			wow.flags.taxi = true
			wow.advance(3)
			wow.flags.taxi = false
			wow.fire("PLAYER_CONTROL_GAINED")
			wow.advance(10)
			wow.cast(458)
			wow.flags.mounted = true
			wow.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
			assert.same({ "tx|Ventormenta|Villa del Lago|50", "tl|Villa del Lago", "mo|1|458" }, newLines(1))
			assert.equal(1, counts().mountUps)
		end)

		it("finds the current node through C_TaxiMap, else names it ?", function()
			boot({ taxi = { { type = "REACHABLE" } } })
			_G.NumTaxiNodes = nil
			wow.taxi_map = { "bad", { name = "Ventormenta", state = 1 }, { name = "Forjaz", state = 0 } }
			wow.fire("TAXIMAP_OPENED", 1)
			TakeTaxiNode(1)
			_G.C_TaxiMap = nil
			wow.fire("TAXIMAP_OPENED", 1)
			TakeTaxiNode(1)
			assert.same({ "tx|Forjaz|?", "tx|?|?" }, newLines(1))
		end)

		it("takes no flight for a click on the current node", function()
			boot({ taxi = NODES })
			wow.fire("TAXIMAP_OPENED", 1)
			TakeTaxiNode(1)
			assert.is_nil(ns.Travel.Flight())
			assert.same({}, newLines(1))
		end)

		it("opens a flight with unknown nodes after a reload in the air", function()
			boot()
			wow.opts.flags = { taxi = true }
			wow.reload()
			ns = wow.ns.Memories
			assert.same({ t = wow.wall - 10 }, ns.Travel.Flight())
			wow.flags.taxi = false
			wow.fire("PLAYER_CONTROL_GAINED")
			assert.same({ "tl" }, newLines(1))
		end)

		it("shows the flight to a sub-addon", function()
			local _, all = wow.boot({ addons = { "Memories", "Memories_Test" }, taxi = NODES })
			wow.fire("TAXIMAP_OPENED", 1)
			TakeTaxiNode(2)
			assert.equal("Villa del Lago", all.Memories_Test.handle:Flight().to)
		end)
	end)

	describe("mounts", function()
		local MOUNTS = {
			[101] = { name = "Caballo bayo", spell = 458 },
			[102] = { name = "Lobo pardo", spell = 6654 },
		}

		local function mountUp()
			wow.flags.mounted = true
			wow.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
		end

		local function mountDown()
			wow.flags.mounted = false
			wow.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
		end

		it("writes the first use of each mount and counts every mount-up (Appendix B, case 11)", function()
			boot({ mounts = MOUNTS })
			for _ = 1, 2 do
				wow.cast(458)
				mountUp()
				mountUp()
				mountDown()
			end
			assert.same({ "mo|1|458|Caballo bayo" }, newLines(1))
			assert.equal(2, counts().mountUps)
			assert.equal(2, counts()["mount:458"])
		end)

		it("takes the active mount, else the cast's spell name", function()
			boot({ mounts = MOUNTS, spells = { [580] = "Lobo del Invierno" } })
			MOUNTS[102].active = true
			mountUp()
			mountDown()
			MOUNTS[102].active = nil
			_G.C_MountJournal = nil
			wow.cast(580)
			mountUp()
			assert.same({ "mo|1|6654|Lobo pardo", "mo|1|580|Lobo del Invierno" }, newLines(1))
		end)

		it("counts a mount-up with no known mount, and none on a taxi", function()
			boot({ mounts = MOUNTS })
			wow.cast(458)
			wow.advance(6)
			_G.C_MountJournal.GetMountFromSpell = nil
			mountUp()
			mountDown()
			wow.flags.taxi = true
			mountUp()
			assert.same({}, newLines(1))
			assert.equal(1, counts().mountUps)
		end)

		it("writes a learned mount once within 120 s", function()
			boot({ mounts = MOUNTS })
			wow.fire("NEW_MOUNT_ADDED", 101)
			wow.fire("NEW_MOUNT_ADDED", 101)
			wow.fire("NEW_MOUNT_ADDED", 999)
			state().learned.bad = "x"
			wow.advance(121)
			wow.fire("NEW_MOUNT_ADDED", 101)
			assert.same({ "ml|Caballo bayo|458", "ml|?", "ml|Caballo bayo|458" }, newLines(1))
			assert.is_nil(state().learned.bad)
		end)

		it("ignores a learned mount without the mount journal", function()
			boot({ mounts = MOUNTS })
			_G.C_MountJournal.GetMountInfoByID = nil
			wow.fire("NEW_MOUNT_ADDED", 101)
			assert.same({}, newLines(1))
		end)

		it("writes learned riding from the skill line or the riding spell names, in Spanish", function()
			boot({ spells = { [824] = "Equitación de caballos" } })
			wow.fire("CHAT_MSG_SKILL", "Has aprendido la habilidad Equitación.")
			wow.skill_lines[762] = "Equitación"
			wow.fire("CHAT_MSG_SKILL", "Has aprendido la habilidad Equitación.")
			wow.fire("CHAT_MSG_SYSTEM", "Has aprendido la habilidad Equitación de caballos.")
			wow.fire("CHAT_MSG_SKILL", "Has aprendido la habilidad Minería.")
			wow.fire("CHAT_MSG_SKILL", wow.secret("Has aprendido la habilidad Equitación."))
			wow.fire("CHAT_MSG_SKILL", "You have gained the Riding skill.")
			assert.same({ "ml|Equitación de caballos|824" }, newLines(1))
		end)

		it("retries the riding names while none could be read", function()
			boot()
			wow.fire("CHAT_MSG_SKILL", "Has aprendido la habilidad Equitación.")
			wow.skill_lines[762] = "Equitación"
			wow.fire("CHAT_MSG_SKILL", "Has aprendido la habilidad Equitación.")
			_G.C_SkillInfo = nil
			wow.advance(121)
			wow.fire("CHAT_MSG_SKILL", "Has aprendido la habilidad Equitación.")
			assert.same({ "ml|Equitación", "ml|Equitación" }, newLines(1))
		end)
	end)

	describe("distance", function()
		it("takes the setting, then the region, then the client language (Appendix B, case 12)", function()
			boot({ region = 110, locale = "deDE" })
			local U = ns.Travel.DistanceUnit
			assert.equal("meters", U())
			wow.locale = "enUS"
			assert.equal("yards", U())
			wow.locale = nil
			assert.equal("yards", U())
			wow.region = 1
			wow.locale = "deDE"
			assert.equal("yards", U())
			wow.region = 3
			assert.equal("meters", U())
			ns.Settings.Set("distanceUnit", "yards")
			assert.equal("yards", U())
			ns.Settings.Set("distanceUnit", "meters")
			wow.region = 1
			assert.equal("meters", U())
		end)

		it("measures yards only inside one world instance", function()
			local Y = wow.boot({ login = false }).Travel.Yards
			assert.equal(5, Y({ x = 0, y = 0, inst = 0 }, { x = 3, y = 4.5, inst = 0 }))
			assert.is_nil(Y({ x = 0, y = 0, inst = 0 }, { x = 3, y = 4, inst = 1 }))
			assert.is_nil(Y(nil, { x = 3, y = 4, inst = 1 }))
		end)

		it("keeps the last outdoor point", function()
			boot({ coords = true })
			assert.is_nil(ns.Travel.LastOutdoor())
			sample(0, 0)
			assert.same({ m = 1453, x = 5000, y = 2500, t = wow.wall }, ns.Travel.LastOutdoor())
			sample(5, 0, 1)
		end)
	end)

	describe("kinds off", function()
		local function off(kind)
			ns.Settings.SetKind(kind, false)
		end

		it("keeps the zone and subzone state with zo and sz off", function()
			boot({
				saved = { MemoriesDB = { settings = { kinds = { zo = false, sz = false } } } },
				subzone = "Villadorada",
			})
			assert.same({}, lines())
			assert.equal("Bosque de Elwynn", state().zone)
			assert.equal("Villadorada", state().sub)
			ns.Settings.SetKind("zo", true)
			wow.fire("ZONE_CHANGED_NEW_AREA")
			assert.same({}, lines())
		end)

		it("writes no ld, le, hs with those kinds off and still counts", function()
			boot({ bind = "Villadorada" })
			off("ld")
			off("hs")
			wow.cast(8690)
			wow.fire("LOADING_SCREEN_ENABLED")
			off("le")
			wow.fire("LOADING_SCREEN_DISABLED")
			wow.advance(2)
			assert.same({}, newLines(1))
			assert.equal(1, counts().hearths)
		end)

		it("writes no tx, tl, so, su, po with those kinds off and still counts", function()
			boot({ taxi = { { name = "Ventormenta", type = "REACHABLE" } } })
			for _, k in ipairs({ "tx", "tl", "so", "su", "po" }) do
				off(k)
			end
			TakeTaxiNode(1)
			wow.advance(6)
			wow.fire("PLAYER_CONTROL_GAINED")
			assert.is_nil(ns.Travel.Flight())
			sample(0, 0)
			wow.fire("CONFIRM_SUMMON", 1, false)
			C_SummonInfo.ConfirmSummon()
			wow.world = { x = 40, y = 0, inst = 0 }
			wow.advance(0.25)
			wow.cast(3561)
			wow.world = { x = 80, y = 0, inst = 0 }
			wow.advance(0.25)
			assert.same({}, newLines(1))
			assert.same({ 1, 1, 1, 1 }, { counts().flights, counts().offers, counts().summons, counts().portals })
		end)

		it("writes no bt, jp with those kinds off and still counts", function()
			boot()
			off("bt")
			off("jp")
			sample(0, 0)
			wow.advance(0.5)
			sample(300, 0)
			wow.advance(1)
			sample(320, 0)
			loadingScreen(function()
				wow.world = { x = 0, y = 0, inst = 1 }
			end)
			wow.advance(2)
			assert.same({ "ld", "le" }, newLines(1))
			assert.equal(1, counts().teleports)
			assert.equal(1, counts().boats)
		end)

		it("writes no mo, ml with those kinds off; the counts and the dedupe still run", function()
			boot({ mounts = { [101] = { name = "Caballo bayo", spell = 458 } } })
			off("mo")
			off("ml")
			wow.cast(458)
			wow.flags.mounted = true
			wow.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
			wow.fire("NEW_MOUNT_ADDED", 101)
			ns.Settings.SetKind("mo", true)
			ns.Settings.SetKind("ml", true)
			wow.fire("NEW_MOUNT_ADDED", 101)
			wow.flags.mounted = false
			wow.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
			wow.cast(458)
			wow.flags.mounted = true
			wow.fire("PLAYER_MOUNT_DISPLAY_CHANGED")
			assert.same({}, newLines(1))
			assert.equal(2, counts()["mount:458"])
		end)
	end)

	it("records nothing when the core cannot write", function()
		boot({ saved = { MemoriesCharDB = { schema = 99 } } })
		wow.fire("ZONE_CHANGED_NEW_AREA")
		wow.cast(8690)
		assert.same({}, lines())
	end)
end)
