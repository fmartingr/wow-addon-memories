local wow = require("helpers.wow")

describe("combat", function()
	wow.pin_locale("enUS", before_each, after_each)

	local DEFIAS = "Creature-0-4389-0-47-589-00002B3A60"
	local KOBOLD = "Creature-0-4389-0-47-116-00002B3A61"
	local MORLADIM = "Creature-0-4389-0-47-522-00002B3A62"
	local RABBIT = "Creature-0-4389-0-47-721-00002B3A63"
	local MINAS = { name = "Las Minas de la Muerte", type = "party", id = 36 }

	local ns

	local function boot(opts)
		opts = opts or {}
		opts.addons = opts.addons or { "Memories", "Memories_Combat" }
		ns = wow.boot(opts)
		return ns
	end

	local function journal()
		return ns.Registry.Journal("Memories_Combat").journal
	end

	-- The combat lines as "kind|fields", in journal order.
	local function lines()
		local out = {}
		for line in journal():Lines() do
			local rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(.*)$")
			if not rest:match("^nt|") then
				out[#out + 1] = rest
			end
		end
		return out
	end

	local function kills()
		return journal():Counts("kills")
	end

	local function fights()
		return journal():Counts("fights")
	end

	local function defias(over)
		local unit = {
			guid = DEFIAS,
			name = "Saqueador Defias",
			level = 12,
			classification = "normal",
			creatureType = { "Humanoide", 7 },
			threat = 1,
			hostile = true,
		}
		for k, v in pairs(over or {}) do
			unit[k] = v
		end
		return unit
	end

	local function fightStart()
		wow.combat = true
		wow.fire("PLAYER_REGEN_DISABLED")
	end

	local function fightEnd()
		wow.combat = false
		wow.fire("PLAYER_REGEN_ENABLED")
	end

	local function xp(name, amount)
		wow.fire("CHAT_MSG_COMBAT_XP_GAIN", COMBATLOG_XPGAIN_FIRSTPERSON:format(name, amount))
	end

	-- Engages the plate in a fight scan, then lets it die in the next scan.
	local function plateDies(unit, plate)
		plate = plate or "nameplate1"
		wow.units[plate] = unit
		wow.advance(0.5)
		unit.dead = true
		wow.advance(0.5)
	end

	describe("kills", function()
		it("pairs a dead plate with the XP line of the same name", function()
			boot()
			fightStart()
			plateDies(defias())
			wow.advance(1)
			xp("Saqueador Defias", 45)
			wow.advance(3)
			assert.same({ "ki|Saqueador Defias|589|Humanoide|normal|45|12||1" }, lines())
			local c = kills()
			assert.equal(1, c.total)
			assert.equal(1, c.xp)
			assert.equal(1, c["npc:589"])
			assert.equal(1, c["t:Humanoide"])
			assert.equal(1, c["n:Saqueador Defias"])
			assert.equal(1, c["nz:Saqueador Defias@Bosque de Elwynn"])
			assert.is_nil(c.noxp)
			assert.is_nil(c.inst)
		end)

		it("writes the line into its own saved file only", function()
			local coreNs = boot()
			local coreLines = coreNs.Store.Core():LineCount()
			fightStart()
			plateDies(defias())
			wow.advance(3)
			assert.equal(coreLines, coreNs.Store.Core():LineCount())
			assert.is_table(_G.MemoriesCombatCharDB.log)
			ns = wow.reload()
			assert.same({ "ki|Saqueador Defias|589|Humanoide|normal||12||1" }, lines())
		end)

		it("pairs an XP line that comes before the plate death", function()
			boot()
			fightStart()
			local unit = defias()
			wow.units.nameplate1 = unit
			wow.advance(0.5)
			xp("Saqueador Defias", 45)
			unit.dead = true
			wow.advance(0.5)
			wow.advance(3)
			assert.same({ "ki|Saqueador Defias|589|Humanoide|normal|45|12||1" }, lines())
			assert.equal(1, kills().total)
		end)

		it("writes a kill with no XP line after 2.6 s", function()
			boot({ player = { level = 60 } })
			fightStart()
			plateDies(defias())
			wow.advance(2.5)
			assert.same({}, lines())
			wow.advance(0.2)
			assert.same({ "ki|Saqueador Defias|589|Humanoide|normal||12||1" }, lines())
			assert.equal(1, kills().noxp)
			assert.is_nil(kills().xp)
		end)

		it("keeps a plate death and an XP line apart beyond 2.5 s", function()
			boot()
			fightStart()
			plateDies(defias())
			wow.advance(2.6)
			xp("Saqueador Defias", 45)
			wow.advance(3)
			assert.same({
				"ki|Saqueador Defias|589|Humanoide|normal||12||1",
				"ki|Saqueador Defias|589|Humanoide|normal|45|12",
			}, lines())
			assert.equal(2, kills().total)
		end)

		it("pairs each plate with one XP line at most", function()
			boot()
			fightStart()
			local a, b = defias(), defias({ guid = "Creature-0-4389-0-47-589-00002B3A70" })
			wow.units.nameplate1, wow.units.nameplate2 = a, b
			wow.advance(0.5)
			a.dead, b.dead = true, true
			wow.advance(0.5)
			xp("Saqueador Defias", 45)
			wow.advance(3)
			assert.same({
				"ki|Saqueador Defias|589|Humanoide|normal|45|12||1",
				"ki|Saqueador Defias|589|Humanoide|normal||12",
			}, lines())
			assert.equal(1, kills().xp)
			assert.equal(1, kills().noxp)
		end)

		it("counts a death once when the dead plate is also removed", function()
			boot()
			fightStart()
			plateDies(defias())
			wow.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
			wow.units.target = wow.units.nameplate1
			wow.advance(3)
			assert.equal(1, #lines())
			assert.equal(1, kills().total)
		end)

		it("takes a death from a dead plate removed before a scan", function()
			boot()
			fightStart()
			local unit = defias()
			wow.units.nameplate1 = unit
			wow.advance(0.5)
			unit.dead = true
			wow.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
			wow.units.nameplate1 = nil
			wow.advance(3)
			assert.equal(1, kills().total)
		end)

		it("ignores a removed plate that is alive or never engaged", function()
			boot()
			fightStart()
			wow.units.nameplate1 = defias()
			wow.advance(0.5)
			wow.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
			wow.units.nameplate2 = defias({ guid = KOBOLD, threat = false, dead = true })
			wow.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
			wow.advance(3)
			assert.same({}, lines())
		end)

		it("writes nothing for a creature tapped by another player", function()
			boot()
			fightStart()
			plateDies(defias({ tapDenied = true, combat = true }))
			wow.advance(3)
			assert.same({}, lines())
			assert.is_nil(kills().total)
		end)

		it("drops an engaged creature that another player tagged since", function()
			boot()
			fightStart()
			local unit = defias()
			wow.units.nameplate1 = unit
			wow.advance(0.5)
			unit.threat, unit.tapDenied = false, true
			wow.advance(0.5)
			unit.dead = true
			wow.advance(3.5)
			assert.same({}, lines())
			assert.is_nil(kills().total)
		end)

		it("drops an engaged creature that another player tagged and killed between two scans", function()
			boot()
			fightStart()
			local unit = defias()
			wow.units.nameplate1 = unit
			wow.advance(0.5)
			unit.threat, unit.tapDenied, unit.dead = false, true, true
			wow.advance(3.5)
			assert.same({}, lines())
			assert.is_nil(kills().total)
		end)

		it("drops an engaged creature that another player tagged and killed before its plate went", function()
			boot()
			fightStart()
			local unit = defias()
			wow.units.nameplate1 = unit
			wow.advance(0.5)
			unit.threat, unit.tapDenied, unit.dead = false, true, true
			wow.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
			wow.units.nameplate1 = nil
			wow.advance(3.5)
			assert.same({}, lines())
			assert.is_nil(kills().total)
		end)

		it("never engages a friendly unit in a fight", function()
			boot()
			fightStart()
			plateDies(defias({ name = "Guardia", threat = false, combat = true, hostile = false }))
			wow.advance(3)
			assert.same({}, lines())
			assert.is_nil(kills().total)
		end)

		it("drops a stale engaged creature before a scan of a later fight sees it", function()
			boot()
			fightStart()
			local unit = defias()
			wow.units.nameplate1 = unit
			wow.advance(0.5)
			fightEnd()
			wow.advance(6)
			unit.threat = false
			wow.advance(200)
			fightStart()
			wow.advance(0.5)
			unit.dead = true
			wow.advance(3.5)
			assert.same({}, lines())
		end)

		it("engages by the pet's threat or by a fight with no tap", function()
			boot()
			fightStart()
			plateDies(defias({ threat = false, petThreat = 0 }), "nameplate1")
			plateDies(defias({ guid = KOBOLD, name = "Kobold", threat = false, combat = true }), "nameplate2")
			plateDies(defias({ guid = RABBIT, name = "Conejo", threat = false }), "nameplate3")
			wow.advance(3)
			assert.equal(2, kills().total)
			assert.is_nil(kills()["n:Conejo"])
		end)

		it("never engages players, their pets or a key with no GUID and no name", function()
			boot()
			fightStart()
			plateDies(defias({ isPlayer = true }), "nameplate1")
			plateDies(defias({ controlled = true }), "nameplate2")
			plateDies(defias({ guid = wow.secret(DEFIAS), name = wow.secret("Saqueador Defias") }), "nameplate3")
			wow.advance(3)
			assert.same({}, lines())
		end)

		it("keys a unit with a hidden GUID by its name", function()
			boot()
			fightStart()
			plateDies(defias({ guid = wow.secret(DEFIAS) }))
			wow.advance(3)
			assert.same({ "ki|Saqueador Defias||Humanoide|normal||12||1" }, lines())
			assert.equal(1, kills()["n:Saqueador Defias"])
		end)

		it("engages the next creature of the same name on the plate of a dead one with a hidden GUID", function()
			boot()
			fightStart()
			plateDies(defias({ guid = wow.secret(DEFIAS) }))
			wow.advance(3)
			plateDies(defias({ guid = wow.secret(DEFIAS) }))
			wow.advance(3)
			assert.equal(2, kills().total)
		end)

		it("counts once a targeted creature with a hidden GUID that also has a plate", function()
			boot()
			fightStart()
			local unit = defias({ guid = wow.secret(DEFIAS) })
			wow.units.target = unit
			plateDies(unit)
			xp("Saqueador Defias", 45)
			wow.advance(3)
			assert.same({ "ki|Saqueador Defias||Humanoide|normal|45|12||1" }, lines())
			assert.equal(1, kills().total)
		end)

		it("counts once a target with a hidden GUID engaged before its plate showed", function()
			boot()
			fightStart()
			local unit = defias({ guid = wow.secret(DEFIAS) })
			wow.units.target = unit
			wow.advance(0.5)
			wow.units.nameplate1 = unit
			wow.advance(0.5)
			unit.dead = true
			wow.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
			wow.units.nameplate1 = nil
			wow.advance(4)
			assert.equal(1, kills().total)
		end)

		it("counts a target with a hidden GUID whose plate first shows it dead", function()
			boot()
			fightStart()
			local unit = defias({ guid = wow.secret(DEFIAS) })
			wow.units.target = unit
			wow.advance(0.5)
			unit.dead = true
			wow.units.nameplate1 = unit
			wow.advance(4)
			assert.equal(1, kills().total)
		end)

		it("forgets a hidden GUID's key when its plate goes away alive", function()
			boot()
			fightStart()
			wow.units.nameplate1 = defias({ guid = wow.secret(DEFIAS) })
			wow.advance(0.5)
			wow.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
			wow.units.nameplate1 = defias({ guid = wow.secret(DEFIAS), threat = false, tapDenied = true })
			wow.advance(0.5)
			wow.units.nameplate1.dead = true
			wow.advance(4)
			assert.same({}, lines())
			assert.is_nil(kills().total)
		end)

		it("forgets a hidden GUID's target key when the target changes", function()
			boot()
			fightStart()
			wow.units.target = defias({ guid = wow.secret(DEFIAS) })
			wow.advance(0.5)
			wow.units.target = defias({ guid = wow.secret(DEFIAS), threat = false, tapDenied = true })
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.advance(0.5)
			wow.units.target.dead = true
			wow.advance(4)
			assert.same({}, lines())
			assert.is_nil(kills().total)
		end)

		it("writes ? for a hidden name and leaves hidden fields empty", function()
			boot()
			fightStart()
			plateDies(defias({
				name = wow.secret("Saqueador Defias"),
				level = wow.secret(12),
				classification = wow.secret("normal"),
				creatureType = { wow.secret("Humanoide"), wow.secret(7) },
			}))
			wow.advance(3)
			assert.same({ "ki|?|589||||||1" }, lines())
			assert.equal(1, kills()["t:?"])
			assert.is_nil(kills()["n:?"])
		end)

		it("drops an engaged unit untouched for 120 s", function()
			boot()
			fightStart()
			local unit = defias()
			wow.units.nameplate1 = unit
			wow.advance(0.5)
			wow.units.nameplate1 = nil
			wow.advance(121)
			wow.units.nameplate1 = unit
			unit.dead = true
			wow.advance(3)
			assert.same({}, lines())
		end)

		it("forgets a dead key after 600 s", function()
			boot()
			fightStart()
			local unit = defias()
			plateDies(unit)
			wow.advance(601)
			unit.dead = false
			wow.advance(0.5)
			unit.dead = true
			wow.advance(3.5)
			assert.equal(2, kills().total)
		end)

		it("counts a critter by its type id and an elite by its name", function()
			boot()
			fightStart()
			plateDies(
				defias({ guid = RABBIT, name = "Conejo", classification = "normal", creatureType = { "Alimaña", 8 } })
			)
			plateDies(defias({ classification = "elite" }), "nameplate2")
			wow.advance(3)
			assert.equal(1, kills().critter)
			assert.equal(1, kills()["t:Alimaña"])
			assert.equal(1, kills().elite)
			assert.equal(1, kills()["e:Saqueador Defias"])
		end)

		it("counts a battleground kill as an open world kill", function()
			boot({ instance = { name = "Garganta Grito de Guerra", type = "pvp", id = 489 } })
			fightStart()
			plateDies(defias())
			wow.advance(3)
			assert.equal(1, kills().total)
			assert.is_nil(kills().inst)
		end)
	end)

	describe("instances", function()
		it("writes an instance kill from the XP line alone", function()
			boot({ instance = MINAS })
			xp("Edwin VanCleef", 300)
			wow.advance(3)
			assert.same({ "ki|Edwin VanCleef||||300||party|1" }, lines())
			local c = kills()
			assert.equal(1, c.inst)
			assert.equal(1, c.total)
			assert.equal(1, c["n:Edwin VanCleef"])
			assert.is_nil(c.xp)
			assert.is_nil(c["nz:Edwin VanCleef@Bosque de Elwynn"])
		end)

		it("writes raid for a raid kill", function()
			boot({ instance = { name = "Núcleo de Magma", type = "raid", id = 409 } })
			xp("Lucifron", 3000)
			wow.advance(3)
			assert.same({ "ki|Lucifron||||3000||raid|1" }, lines())
		end)

		it("neither scans plates nor learns names inside", function()
			boot({ instance = MINAS })
			fightStart()
			wow.units.target = defias({ classification = "elite" })
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.fire("NAME_PLATE_UNIT_ADDED", "target")
			plateDies(defias())
			wow.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
			xp("Saqueador Defias", 45)
			wow.advance(3)
			assert.same({ "ki|Saqueador Defias||||45||party|1" }, lines())
			assert.equal(1, kills().total)
		end)
	end)

	describe("details", function()
		it("writes ki and ra for a rare elite targeted before its XP line", function()
			boot()
			wow.units.target = {
				guid = MORLADIM,
				name = "Mor'Ladim",
				level = 35,
				classification = "rareelite",
				creatureType = { "No-muerto", 6 },
			}
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.units.target = nil
			xp("Mor'Ladim", 900)
			wow.advance(3)
			assert.same({
				"ki|Mor'Ladim|522|No-muerto|rareelite|900|35||1",
				"ra|Mor'Ladim|522|35",
			}, lines())
			local c = kills()
			assert.equal(1, c.rare)
			assert.equal(1, c.elite)
			assert.equal(1, c["e:Mor'Ladim"])
		end)

		it("reads the current target for an XP line of a name not learned", function()
			boot()
			wow.units.target = defias()
			xp("Saqueador Defias", 45)
			wow.advance(3)
			assert.same({ "ki|Saqueador Defias|589|Humanoide|normal|45|12||1" }, lines())
		end)

		it("learns from a plate that appears, never from a player or a pet", function()
			boot()
			wow.units.nameplate1 = defias()
			wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
			wow.units.nameplate2 = defias({ guid = KOBOLD, name = "Kobold", controlled = true })
			wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
			xp("Saqueador Defias", 45)
			xp("Kobold", 30)
			wow.advance(3)
			assert.same({
				"ki|Saqueador Defias|589|Humanoide|normal|45|12||1",
				"ki|Kobold||||30|||1",
			}, lines())
		end)

		it("fills a plate's missing fields from the learned table", function()
			boot()
			wow.units.target = defias({ level = 13 })
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.units.target = nil
			fightStart()
			plateDies(defias({ level = wow.secret(12), creatureType = { wow.secret("Humanoide") } }))
			wow.advance(3)
			assert.same({ "ki|Saqueador Defias|589|Humanoide|normal||13||1" }, lines())
		end)

		it("starts the learned table over after 400 names", function()
			boot()
			wow.units.target = defias()
			wow.fire("PLAYER_TARGET_CHANGED")
			for i = 1, 400 do
				wow.units.target = { name = "Bicho " .. i, level = 1 }
				wow.fire("PLAYER_TARGET_CHANGED")
			end
			wow.units.target = nil
			xp("Saqueador Defias", 45)
			xp("Bicho 400", 1)
			wow.advance(3)
			assert.same({ "ki|Saqueador Defias||||45|||1", "ki|Bicho 400||||1|1||1" }, lines())
		end)

		it("reads a reordered translation and a thousands separator", function()
			boot({ strings = { COMBATLOG_XPGAIN_FIRSTPERSON = "Ganas %2$d p. de experiencia (%1$s muere). 100%%" } })
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Ganas 1.250 p. de experiencia (Onyxia muere). 100%")
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "otra cosa")
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", wow.secret("Ganas 5 p. de experiencia (Lobo muere). 100%"))
			wow.advance(3)
			assert.same({ "ki|Onyxia||||1250|||1" }, lines())
		end)

		it("matches nothing without the GlobalString or with a format it cannot read", function()
			boot({ strings = { COMBATLOG_XPGAIN_FIRSTPERSON = false } })
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Saqueador Defias muere, ganas 45 p. de experiencia.")
			wow.advance(3)
			assert.same({}, lines())
			boot({ strings = { COMBATLOG_XPGAIN_FIRSTPERSON = "%s muere: %i" } })
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Lobo muere: 5")
			wow.advance(3)
			assert.same({}, lines())
		end)
	end)

	describe("new findings only", function()
		local function newOnly(on)
			ns.Settings.Set("newOnly.kills", on)
		end

		it("writes the first kill of an NPC id with first = 1", function()
			boot()
			newOnly(true)
			fightStart()
			plateDies(defias())
			wow.advance(3)
			assert.same({ "ki|Saqueador Defias|589|Humanoide|normal||12||1" }, lines())
		end)

		it("writes no line for a known normal NPC and still counts", function()
			boot()
			journal():Count("kills", "npc:116", 3)
			newOnly(true)
			fightStart()
			plateDies(defias({ guid = KOBOLD, name = "Kobold" }))
			xp("Kobold", 30)
			wow.advance(3)
			assert.same({}, lines())
			assert.equal(4, kills()["npc:116"])
			assert.equal(1, kills().total)
		end)

		it("writes a known elite and a known rare, with ra", function()
			boot()
			journal():Count("kills", "npc:589", 2)
			journal():Count("kills", "npc:522", 2)
			newOnly(true)
			fightStart()
			plateDies(defias({ classification = "elite" }))
			plateDies(
				defias({ guid = MORLADIM, name = "Mor'Ladim", classification = "rare", level = 35 }),
				"nameplate2"
			)
			wow.advance(3)
			assert.same({
				"ki|Saqueador Defias|589|Humanoide|elite||12",
				"ki|Mor'Ladim|522|Humanoide|rare||35",
				"ra|Mor'Ladim|522|35",
			}, lines())
		end)

		it("always writes a kill with a hidden name and no NPC id", function()
			boot()
			newOnly(true)
			fightStart()
			plateDies(defias({ guid = "GameObject-0-4389-0-47-1731-00002B3A64", name = wow.secret("Caja") }))
			wow.advance(3)
			assert.same({ "ki|?||Humanoide|normal||12" }, lines())
		end)

		it("writes nothing for an instance kill of a known name", function()
			boot({ instance = MINAS })
			journal():Count("kills", "n:Edwin VanCleef", 1)
			newOnly(true)
			xp("Edwin VanCleef", 300)
			xp("Minero Defias", 50)
			wow.advance(3)
			assert.same({ "ki|Minero Defias||||50||party|1" }, lines())
			assert.equal(2, kills()["n:Edwin VanCleef"])
		end)
	end)

	describe("kind off", function()
		it("writes no ki with ki off and still counts", function()
			boot()
			ns.Settings.SetKind("ki", false)
			fightStart()
			plateDies(defias())
			wow.advance(3)
			assert.same({}, lines())
			assert.equal(1, kills().total)
			assert.equal(1, kills()["npc:589"])
		end)

		it("still writes ra for a rare with ki off", function()
			boot()
			ns.Settings.SetKind("ki", false)
			fightStart()
			plateDies(defias({ guid = MORLADIM, name = "Mor'Ladim", classification = "rare", level = 35 }))
			wow.advance(3)
			assert.same({ "ra|Mor'Ladim|522|35" }, lines())
			assert.equal(1, kills().rare)
		end)

		it("writes no ra with ra off and still counts", function()
			boot()
			ns.Settings.SetKind("ra", false)
			fightStart()
			plateDies(defias({ guid = MORLADIM, name = "Mor'Ladim", classification = "rare", level = 35 }))
			wow.advance(3)
			assert.same({ "ki|Mor'Ladim|522|Humanoide|rare||35||1" }, lines())
			assert.equal(1, kills().rare)
		end)

		it("writes no fi with fi off and still counts", function()
			boot()
			ns.Settings.SetKind("fi", false)
			fightStart()
			wow.advance(25)
			fightEnd()
			assert.same({}, lines())
			assert.equal(1, fights().n)
			assert.equal(25, fights().sec)
		end)
	end)

	describe("fights", function()
		it("writes a long fight with the target read 1 s after the start", function()
			boot()
			fightStart()
			wow.units.target = { name = "Lobo gris", hostile = true, classification = "normal", level = 8 }
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 133)
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 133)
			wow.advance(25)
			fightEnd()
			assert.same({ "fi|25|Lobo gris|normal|8||2" }, lines())
			local f = fights()
			assert.equal(1, f.n)
			assert.equal(25, f.sec)
			assert.equal(25, f.longest)
			assert.is_nil(f.died)
		end)

		it("writes a short fight with the low-health warning", function()
			boot()
			fightStart()
			wow.advance(6)
			ns.Emit("LOW_HEALTH", true)
			fightEnd()
			assert.same({ "fi|6|||||0" }, lines())
		end)

		it("writes a short fight where the player died", function()
			boot()
			fightStart()
			wow.advance(4)
			wow.flags.dead = true
			fightEnd()
			ns.Emit("DIED", {})
			fightStart()
			wow.advance(3)
			ns.Emit("DIED", {})
			fightEnd()
			assert.same({ "fi|4||||1|0", "fi|3||||1|0" }, lines())
			assert.equal(2, fights().died)
		end)

		it("writes no line for a short fight and keeps the longest one", function()
			boot()
			fightStart()
			wow.advance(30)
			fightEnd()
			fightStart()
			wow.advance(5)
			fightEnd()
			assert.equal(1, #lines())
			assert.equal(2, fights().n)
			assert.equal(35, fights().sec)
			assert.equal(30, fights().longest)
		end)

		it("skips a player, a friendly or a hidden target", function()
			boot()
			wow.units.target = { name = "Ana", isPlayer = true, hostile = true }
			fightStart()
			wow.advance(25)
			fightEnd()
			wow.units.target = { name = "Guardia", hostile = false }
			fightStart()
			wow.advance(25)
			fightEnd()
			wow.units.target = { name = wow.secret("Oculto"), hostile = true }
			fightStart()
			wow.advance(25)
			fightEnd()
			assert.same({ "fi|25|||||0", "fi|25|||||0", "fi|25|?||||0" }, lines())
		end)

		it("skips the target read when a new fight started meanwhile", function()
			boot()
			fightStart()
			wow.advance(0.5)
			ns.Emit("LOW_HEALTH", true)
			fightEnd()
			wow.units.target = { name = "Lobo gris", hostile = true }
			fightStart()
			wow.advance(0.6)
			ns.Emit("LOW_HEALTH", true)
			fightEnd()
			assert.same({ "fi|1|||||0", "fi|1|||||0" }, lines())
		end)

		it("writes no fi and no fight counts for a fight that was on at login", function()
			boot({ login = false })
			wow.combat = true
			wow.login(true)
			wow.advance(30)
			fightEnd()
			assert.same({}, lines())
			assert.is_nil(fights().n)
			fightStart()
			wow.advance(25)
			fightEnd()
			assert.same({ "fi|25|||||0" }, lines())
		end)

		it("follows only the next fight after a registration inside a fight", function()
			boot({ addons = { "Memories" } })
			fightStart()
			wow.load_addon("Memories_Combat")
			wow.advance(30)
			fightEnd()
			assert.same({}, lines())
			fightStart()
			wow.advance(25)
			fightEnd()
			assert.same({ "fi|25|||||0" }, lines())
		end)

		it("scans plates for 5 s after a fight ends, then stops", function()
			boot()
			fightStart()
			local a, b = defias(), defias({ guid = KOBOLD, name = "Kobold" })
			wow.units.nameplate1, wow.units.nameplate2 = a, b
			wow.advance(0.5)
			fightEnd()
			wow.advance(2)
			a.dead = true
			wow.advance(4)
			b.dead = true
			wow.advance(3)
			assert.equal(1, kills().total)
			assert.equal(1, kills()["npc:589"])
		end)
	end)

	describe("snapshots", function()
		it("keeps the kill counts at each level up", function()
			boot()
			journal():Count("kills", "total", 120)
			journal():Count("kills", "xp", 100)
			wow.fire("PLAYER_LEVEL_UP", 15)
			assert.same({ total = 120, xp = 100, inst = 0 }, journal():Snap(15, "kills"))
		end)
	end)

	describe("missing game functions", function()
		it("engages by the fight flag alone and leaves the type empty", function()
			boot()
			_G.UnitThreatSituation, _G.UnitIsTapDenied, _G.UnitPlayerControlled = nil, nil, nil
			_G.UnitCreatureType = function()
				error("broken")
			end
			_G.UnitClassification = nil
			fightStart()
			plateDies(defias({ threat = false, combat = true }))
			wow.advance(3)
			assert.same({ "ki|Saqueador Defias|589||||12||1" }, lines())
			assert.same({}, ns.Errors())
		end)
	end)

	describe("registration", function()
		it("registers its kinds and the new-only box", function()
			boot()
			for _, kind in ipairs({ "ki", "ra", "fi" }) do
				local spec = ns.Kinds.Get(kind)
				assert.equal("Memories_Combat", spec.addon)
				assert.equal("Combat", spec.group)
			end
			local box = ns.Registry.Registered()[1].boxes[1]
			assert.equal("kills", box.key)
			assert.same({ "ki" }, box.kinds)
		end)

		it("stops with one line when it loads before the core", function()
			boot({ order = "reverse" })
			assert.equal("Memories_Combat: Memories is not loaded.", wow.chat()[1])
			assert.is_nil(ns.Kinds.Get("ki"))
		end)
	end)
end)
