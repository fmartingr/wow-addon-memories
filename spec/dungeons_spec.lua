local wow = require("helpers.wow")

describe("bosses", function()
	local ns

	before_each(function()
		ns = wow.boot({ login = false })
	end)

	it("has the 43 last bosses with their places", function()
		local n = 0
		for _ in pairs(ns.Bosses.All()) do
			n = n + 1
		end
		assert.equal(43, n)
		assert.equal("Deadmines", ns.Bosses.Place("Edwin VanCleef"))
		assert.equal("Naxxramas", ns.Bosses.Place("Kel'Thuzad"))
		assert.is_nil(ns.Bosses.Place("Hogger"))
		assert.is_nil(ns.Bosses.Place(nil))
		ns.Bosses.All()["Hogger"] = "Elwynn Forest"
		assert.is_nil(ns.Bosses.Place("Hogger"))
	end)

	it("matches a place in lower case, before a colon, trimmed and without a leading the", function()
		assert.equal("deadmines", ns.Bosses.Normalize("  The Deadmines: Mast Room "))
		assert.is_true(ns.Bosses.KnownPlace("The Deadmines"))
		assert.is_true(ns.Bosses.KnownPlace("excavation site"))
		assert.is_false(ns.Bosses.KnownPlace("Elwynn Forest"))
		assert.is_false(ns.Bosses.KnownPlace(nil))
	end)
end)

describe("dungeons", function()
	local KINDS = { dn = true, dx = true, bo = true, wb = true }
	local DEADMINES = { name = "Minas de la Muerte", type = "party", id = 36, difficulty = 1, size = 5 }
	local AZUREGOS = "Creature-0-4389-0-47-6109-00002B3A5C"

	local ns

	after_each(function()
		assert.same({}, type(MemoriesDB) == "table" and MemoriesDB.errors or {})
	end)

	local function lines()
		local out = {}
		for line in ns.Store.Core():Lines() do
			local k, rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(%w+)|?(.*)$")
			if KINDS[k] then
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

	local function counts()
		return ns.Store.Core():Counts("dungeons")
	end

	local function state()
		return MemoriesCharDB.state.dungeons
	end

	local function boot(opts)
		ns = wow.boot(opts)
		return ns
	end

	local function enter(instance)
		wow.instance = instance
		wow.fire("PLAYER_ENTERING_WORLD", false, false)
		wow.advance(1)
	end

	local function leave()
		wow.instance = nil
		wow.fire("ZONE_CHANGED_NEW_AREA")
		wow.advance(1)
	end

	local function die()
		wow.flags.dead = true
		wow.fire("PLAYER_DEAD")
		wow.advance(1)
		wow.flags.dead = false
		wow.fire("PLAYER_ALIVE")
	end

	describe("visits", function()
		it("writes dn at the last outdoor point (Appendix B, case 1)", function()
			boot({ map = { id = 1415, x = 0.4, y = 0.6 } })
			wow.advance(2)
			enter(DEADMINES)
			assert.same({ "dn|Minas de la Muerte|36|party|1|5" }, lines())
			local ev = decoded("dn")
			assert.same({ 1415, 4000, 6000 }, { ev.m, ev.x, ev.y })
			assert.equal(1, counts().visits)
			assert.same(
				{ name = "Minas de la Muerte", instance = 36, itype = "party", t = wow.wall },
				ns.Dungeons.Visit()
			)
			assert.equal(0, ns.Deaths.VisitDeaths())
		end)

		it("takes Travel's last outdoor point when the trail has none", function()
			boot({ map = { id = 1415, x = 0.4, y = 0.6 } })
			ns.Emit("TRAIL_LIVE", 1415, 4000, 6000)
			enter(DEADMINES)
			local ev = decoded("dn")
			assert.same({ 1415, 4000, 6000 }, { ev.m, ev.x, ev.y })
		end)

		it("writes nothing for a reload inside the same instance (Appendix B, case 2)", function()
			boot()
			enter(DEADMINES)
			wow.opts.instance = DEADMINES
			wow.reload()
			ns = wow.ns.Memories
			wow.advance(1)
			wow.fire("ZONE_CHANGED_NEW_AREA")
			wow.advance(1)
			assert.same({ "dn|Minas de la Muerte|36|party|1|5" }, lines())
		end)

		it("writes dx with the visit length and its deaths (Appendix B, case 3)", function()
			boot()
			enter(DEADMINES)
			wow.advance(499)
			die()
			wow.advance(1299)
			leave()
			assert.same({ "dn|Minas de la Muerte|36|party|1|5", "dx|Minas de la Muerte|36|1800|1" }, lines())
			assert.equal(1800, counts().seconds)
			assert.is_nil(ns.Dungeons.Visit())
			assert.equal(0, ns.Deaths.VisitDeaths())
		end)

		it("keeps the visit open over a release and the corpse run back inside", function()
			boot()
			enter(DEADMINES)
			wow.flags.ghost = true
			leave()
			assert.same({ "dn|Minas de la Muerte|36|party|1|5" }, lines())
			enter(DEADMINES)
			wow.flags.ghost = false
			assert.same({ "dn|Minas de la Muerte|36|party|1|5" }, lines())
			assert.equal(1, counts().visits)
		end)

		it("ends the visit at the revive of a ghost that stayed outside", function()
			boot()
			enter(DEADMINES)
			wow.flags.ghost = true
			leave()
			wow.flags.ghost = false
			ns.Emit("ALIVE", "spirit")
			wow.advance(1)
			assert.same({ "dn|Minas de la Muerte|36|party|1|5", "dx|Minas de la Muerte|36|2|0" }, lines())
		end)

		it("ends a visit at the logout when the next login is outside (Appendix B, case 4)", function()
			boot()
			enter(DEADMINES)
			wow.advance(300)
			local out = wow.wall
			wow.reload()
			ns = wow.ns.Memories
			wow.advance(600)
			leave()
			assert.same({ "dn|Minas de la Muerte|36|party|1|5", "dx|Minas de la Muerte|36|300|0" }, lines())
			assert.equal(out, decoded("dx").t)
		end)

		it("forgets an older logout once the next login is back inside", function()
			boot()
			enter(DEADMINES)
			wow.opts.instance = DEADMINES
			wow.reload()
			ns = wow.ns.Memories
			wow.advance(1)
			assert.is_nil(ns.Store.Core().data.state.dungeons.visit.out)
		end)

		it("writes dx then dn from one instance to another (Appendix B, case 5)", function()
			boot()
			enter(DEADMINES)
			enter({ name = "Cuevas de los Lamentos", type = "party", id = 43, difficulty = 1, size = 5 })
			assert.same({
				"dn|Minas de la Muerte|36|party|1|5",
				"dx|Minas de la Muerte|36|1|0",
				"dn|Cuevas de los Lamentos|43|party|1|5",
			}, lines())
			assert.equal(2, counts().visits)
		end)

		it("keeps raid counts apart", function()
			boot()
			enter({ name = "Núcleo de Magma", type = "raid", id = 409, difficulty = 9, size = 40 })
			wow.advance(9)
			leave()
			assert.equal(1, counts().raidVisits)
			assert.equal(10, counts().raidSeconds)
			assert.is_nil(counts().visits)
		end)

		it("names a secret instance ?", function()
			boot()
			enter({ name = wow.secret("Minas de la Muerte"), type = "party", id = 36 })
			assert.same({ "dn|?|36|party|1|5" }, lines())
		end)

		it("opens no visit in a battleground", function()
			boot()
			enter({ name = "Garganta Grito de Guerra", type = "pvp", id = 489 })
			assert.same({}, lines())
		end)
	end)

	describe("bosses", function()
		local function fight(id, name, success, seconds)
			wow.fire("ENCOUNTER_START", id, name, 1, 5)
			wow.advance(seconds)
			wow.fire("ENCOUNTER_END", id, name, 1, 5, success, {})
		end

		it("writes a last boss kill and asks for a screenshot 1 s later (Appendix B, case 6)", function()
			boot()
			ns.Settings.Set("shots.lastBoss", true)
			enter(DEADMINES)
			fight(1, "Edwin VanCleef", 1, 85)
			assert.equal("bo|Edwin VanCleef|1|1|1|Minas de la Muerte|85", lines()[2])
			assert.same({ 1, 1, 1, 85 }, {
				counts().bosses,
				counts().clears,
				counts()["kills:Edwin VanCleef"],
				counts()["longest:Edwin VanCleef"],
			})
			assert.equal(0, wow.shots)
			wow.advance(1)
			assert.equal(1, wow.shots)
			wow.screenshot(true)
			local ss
			for line in ns.Store.Core():Lines() do
				ss = line:match("|ss|(.*)$") or ss
			end
			assert.matches("^last boss Edwin VanCleef|ok|", ss)
		end)

		it("takes no screenshot with shots.lastBoss off, or when the journal changed", function()
			boot()
			enter(DEADMINES)
			fight(1, "Edwin VanCleef", 1, 85)
			wow.advance(1)
			assert.equal(0, wow.shots)
			ns.Settings.Set("shots.lastBoss", true)
			fight(1, "Edwin VanCleef", 1, 60)
			ns.Store.Reopen()
			wow.advance(1)
			assert.equal(0, wow.shots)
			assert.equal(85, counts()["longest:Edwin VanCleef"])
		end)

		it("writes a wipe with no last flag and no screenshot (Appendix B, case 7)", function()
			boot()
			ns.Settings.Set("shots.lastBoss", true)
			enter(DEADMINES)
			fight(1, "Edwin VanCleef", 0, 40)
			wow.advance(1)
			assert.equal("bo|Edwin VanCleef|1|0||Minas de la Muerte|40", lines()[2])
			assert.equal(1, counts().wipes)
			assert.equal(0, wow.shots)
		end)

		it("writes a boss with no length after a reload mid-fight, and a secret name as ?", function()
			boot()
			enter({ name = "Núcleo de Magma", type = "raid", id = 409, difficulty = 9, size = 40 })
			wow.fire("ENCOUNTER_START", wow.secret(663), "Lucifron", 9, 40)
			wow.fire("ENCOUNTER_END", 663, wow.secret("Lucifron"), 9, 40, true, {})
			fight(672, "Ragnaros", 1, 300)
			assert.same({ "bo|?|663|1||Núcleo de Magma", "bo|Ragnaros|672|1|1|Núcleo de Magma|300" }, {
				lines()[2],
				lines()[3],
			})
			assert.same({ 2, 1, 300 }, { counts().raidBosses, counts().raidClears, counts()["raidLongest:Ragnaros"] })
			fight(672, "Ragnaros", 0, 10)
			assert.equal(1, counts().raidWipes)
		end)

		it("writes no bo and no wb for an encounter in a battleground (Appendix B, case 9)", function()
			boot()
			enter({ name = "Valle de Alterac", type = "pvp", id = 30 })
			fight(1, "Vanndar Pico Tormenta", 1, 10)
			assert.same({}, lines())
		end)

		it("writes a world boss of an outdoor encounter, path A", function()
			boot()
			fight(1, "Kazzak", 1, 10)
			fight(1, "Kazzak", 0, 10)
			assert.same({ "wb|Kazzak" }, lines())
			assert.equal(1, counts().worldBosses)
		end)
	end)

	describe("world bosses", function()
		local function target(unit)
			wow.units.target = unit
			wow.fire("PLAYER_REGEN_ENABLED")
		end

		it("writes a dead world boss target once in 600 s (Appendix B, case 8)", function()
			boot()
			local unit = { name = "Azuregos", guid = AZUREGOS, classification = "worldboss", dead = true }
			target(unit)
			wow.advance(300)
			target(unit)
			assert.same({ "wb|Azuregos|6109" }, lines())
			wow.advance(301)
			target(unit)
			assert.same({ "wb|Azuregos|6109", "wb|Azuregos|6109" }, lines())
			assert.equal(2, counts().worldBosses)
		end)

		it("takes a listed name of any classification and keeps the last 6", function()
			boot()
			for i = 1, 7 do
				target({ name = "Jefe " .. i, classification = "worldboss", dead = true })
			end
			target({ name = "Ysondre", classification = "elite", dead = true })
			assert.equal(6, #state().worldBosses)
			assert.equal("wb|Ysondre", lines()[8])
			state().worldBosses[1] = "bad"
			target({ name = wow.secret("Taerar"), classification = "worldboss", dead = true })
			assert.equal("wb|?", lines()[9])
		end)

		it("skips a live, player, plain or missing target and any target inside a dungeon", function()
			boot()
			target(nil)
			target({ name = "Azuregos", classification = "worldboss" })
			target({ name = "Azuregos", classification = "worldboss", dead = true, isPlayer = true })
			target({ name = "Hogger", classification = "elite", dead = true })
			enter(DEADMINES)
			target({ name = "Azuregos", classification = "worldboss", dead = true })
			assert.same({ "dn|Minas de la Muerte|36|party|1|5" }, lines())
		end)

		it("skips a world boss target in a battleground", function()
			boot()
			enter({ name = "Valle de Alterac", type = "pvp", id = 30 })
			target({ name = "Drek'Thar", classification = "worldboss", dead = true })
			assert.same({}, lines())
		end)
	end)

	describe("kinds off", function()
		it("keeps the visit, its deaths and the counts with dn and dx off", function()
			boot({ saved = { MemoriesDB = { settings = { kinds = { dn = false, dx = false } } } } })
			enter(DEADMINES)
			die()
			assert.equal(36, ns.Dungeons.Visit().instance)
			assert.equal(1, ns.Deaths.VisitDeaths())
			ns.Settings.SetKind("dx", true)
			wow.advance(8)
			leave()
			assert.same({ "dx|Minas de la Muerte|36|10|1" }, lines())
			assert.equal(1, counts().visits)
		end)

		it("counts bosses and keeps the world boss dedupe with bo and wb off", function()
			boot({ saved = { MemoriesDB = { settings = { kinds = { bo = false, wb = false } } } } })
			enter(DEADMINES)
			wow.fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1, {})
			leave()
			local unit = { name = "Azuregos", guid = AZUREGOS, classification = "worldboss", dead = true }
			wow.units.target = unit
			wow.fire("PLAYER_REGEN_ENABLED")
			ns.Settings.SetKind("wb", true)
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.same({ "dn|Minas de la Muerte|36|party|1|5", "dx|Minas de la Muerte|36|1|0" }, lines())
			assert.same({ 1, 1, 1 }, { counts().bosses, counts().clears, counts().worldBosses })
		end)
	end)

	it("records nothing when the core cannot write", function()
		boot({ saved = { MemoriesCharDB = { schema = 99 } } })
		enter(DEADMINES)
		assert.is_nil(ns.Dungeons.Visit())
		assert.same({}, lines())
	end)
end)
