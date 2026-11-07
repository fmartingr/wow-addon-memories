local wow = require("helpers.wow")

describe("character", function()
	local SPELLS = {
		[133] = "Bola de Fuego",
		[430] = "Beber",
		[458] = "Caballo marrón",
		[768] = "Forma felina",
		[1515] = "Domesticar bestia",
		[2550] = "Cocina",
		[2575] = "Minería",
		[3273] = "Primeros auxilios",
		[6603] = "Atacar",
		[7620] = "Pesca",
		[13262] = "Desencantar",
	}
	local TRADE = { [186] = "Minería", [129] = "Primeros auxilios", [185] = "Cocina" }
	local MOUNTS = { [6] = { name = "Caballo marrón", spell = 458 } }
	local WATER, BREAD, BANDAGE, POTION, CLOTH = 5350, 4540, 1251, 118, 2589
	local ITEMS = {
		[WATER] = { class = 0, sub = 5 },
		[BREAD] = { class = 0, sub = 5 },
		[BANDAGE] = { class = 0, sub = 7 },
		[POTION] = { class = 0, sub = 1 },
		[159] = { class = 0, sub = 5 },
		[CLOTH] = { class = 7, sub = 5 },
	}

	local ns

	local function boot(opts)
		opts = opts or {}
		opts.addons = opts.addons or { "Memories", "Memories_Character" }
		opts.spells = opts.spells or SPELLS
		opts.tradeSkills = opts.tradeSkills or TRADE
		opts.mounts = opts.mounts or MOUNTS
		ns = wow.boot(opts)
		for id, info in pairs(ITEMS) do
			wow.item_info[id] = info
		end
		wow.advance(11)
		return ns
	end

	local function journal()
		return ns.Registry.Journal("Memories_Character").journal
	end

	-- The character lines as "kind|fields", in journal order.
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

	local function counts(module)
		return journal():Counts(module)
	end

	local function snap(key, level)
		return journal():Snap(level or 10, key)
	end

	local function setSkills(rows)
		wow.skills = rows
		wow.fire("SKILL_LINES_CHANGED")
		wow.advance(3)
	end

	local function stateOf(module)
		return journal():State(module)
	end

	describe("skills", function()
		local MINING = { name = "Minería", id = 186, rank = 50, max = 75 }

		local function professions(mining, firstAid, swords)
			return {
				{ name = "Profesiones", header = true },
				mining,
				{ name = "Habilidades secundarias", header = true },
				firstAid or { name = "Primeros auxilios", id = 129, rank = 1, max = 75 },
				{ name = "Armas", header = true },
				swords or { name = "Espadas", id = 43, rank = 20, max = 50 },
			}
		end

		it("writes a profession's rank change and updates the skills snapshot", function()
			boot({ skills = professions(MINING) })
			assert.same({ "sk|Espadas|20|50", "sk|Minería|50|75", "sk|Primeros auxilios|1|75" }, lines())
			setSkills(professions({ name = "Minería", id = 186, rank = 51, max = 75 }))
			assert.equal("sk|Minería|51|75", lines()[4])
			assert.equal(4, #lines())
			assert.equal(
				"Armas:Espadas=20/50;Profesiones:Minería=51/75;Habilidades secundarias:Primeros auxilios=1/75",
				snap("skills")
			)
		end)

		it("matches a Spanish profession name with no skill line id", function()
			boot({ skills = professions({ name = "Minería", rank = 50, max = 75 }) })
			setSkills(professions({ name = "Minería", rank = 52, max = 75 }))
			assert.equal("sk|Minería|52|75", lines()[4])
		end)

		it("matches a profession name that only the skill line gives", function()
			local herbs = { name = "Herboristería", rank = 10, max = 75 }
			boot({ skills = professions(herbs), tradeSkills = {}, skillLines = { [182] = "Herboristería" } })
			setSkills(professions({ name = "Herboristería", rank = 11, max = 75 }))
			assert.equal("sk|Herboristería|11|75", lines()[4])
		end)

		it("matches Primeros auxilios through its skill line id", function()
			boot({ skills = professions(MINING), tradeSkills = {} })
			setSkills(professions(MINING, { name = "Primeros auxilios", id = 129, rank = 2, max = 75 }))
			assert.equal("sk|Primeros auxilios|2|75", lines()[4])
		end)

		it("writes a weapon skill only when its cap changes", function()
			boot({ skills = professions(MINING) })
			setSkills(professions(MINING, nil, { name = "Espadas", id = 43, rank = 21, max = 50 }))
			assert.equal(3, #lines())
			setSkills(professions(MINING, nil, { name = "Espadas", id = 43, rank = 21, max = 75 }))
			assert.equal("sk|Espadas|21|75", lines()[4])
		end)

		it("keeps a skill under a collapsed header and writes no snapshot", function()
			boot({ skills = professions(MINING) })
			local before = snap("skills")
			setSkills({
				{ name = "Profesiones", header = true },
				{ name = "Minería", id = 186, rank = 51, max = 75 },
				{ name = "Habilidades secundarias", header = true, collapsed = true },
				{ name = "Armas", header = true },
				{ name = "Espadas", id = 43, rank = 20, max = 50 },
			})
			assert.same({ "sk|Minería|51|75" }, { lines()[4] })
			assert.equal(4, #lines())
			assert.equal(before, snap("skills"))
			assert.is_table(stateOf("skills")["Primeros auxilios"])
		end)

		it("keeps a skill when a row has no readable name", function()
			boot({ skills = professions(MINING) })
			setSkills({ { name = "Profesiones", header = true }, MINING, { name = wow.secret("Primeros auxilios") } })
			assert.equal(3, #lines())
			assert.is_table(stateOf("skills")["Primeros auxilios"])
		end)

		it("writes a dropped skill as rank 0 and max 0 on a full read", function()
			boot({ skills = professions(MINING) })
			setSkills({ { name = "Profesiones", header = true }, MINING, { name = "Espadas", rank = 20, max = 50 } })
			assert.same({ "sk|Primeros auxilios|0|0" }, { lines()[4] })
			assert.is_nil(stateOf("skills")["Primeros auxilios"])
			assert.equal("Profesiones:Espadas=20/50;Profesiones:Minería=50/75", snap("skills"))
		end)

		it("writes nothing for an empty read", function()
			boot({ skills = professions(MINING) })
			setSkills({})
			assert.equal(3, #lines())
		end)

		it("keeps the first of a name seen twice and writes ? for a hidden number", function()
			boot({
				skills = {
					{ name = "Espadas", rank = 20, max = 50 },
					{ name = "Espadas", rank = 99, max = 99 },
					{ name = "Hachas", rank = wow.secret(5), max = 50 },
				},
			})
			assert.same({ "sk|Espadas|20|50" }, lines())
			assert.equal(":Espadas=20/50;:Hachas=?/50", snap("skills"))
		end)

		it("treats a name as no profession while the client gives no localized name", function()
			boot({ skills = { { name = "Minería", rank = 50, max = 75 } }, tradeSkills = {}, spells = {} })
			setSkills({ { name = "Minería", rank = 51, max = 75 } })
			assert.same({ "sk|Minería|50|75" }, lines())
		end)

		it("skips a row the client cannot read", function()
			boot({ login = false })
			wow.skills = { { name = "Espadas", rank = 20, max = 50 } }
			_G.C_SkillInfo.GetNumSkillLines = function()
				return 2
			end
			wow.login()
			wow.advance(11)
			assert.same({ "sk|Espadas|20|50" }, lines())
		end)

		it("keeps the known skills over a reload", function()
			boot({ skills = professions(MINING) })
			ns = wow.reload()
			wow.advance(11)
			assert.equal(3, #lines())
		end)

		it("writes no line with sk off and still keeps the known skills", function()
			boot({ skills = professions(MINING), login = false })
			ns.Settings.SetKind("sk", false)
			wow.login()
			wow.advance(11)
			assert.same({}, lines())
			assert.same({ 50, 75 }, stateOf("skills")["Minería"])
		end)

		it("reads the legacy skill functions without C_SkillInfo.GetSkillLineInfo", function()
			boot({ login = false })
			_G.C_SkillInfo.GetNumSkillLines, _G.C_SkillInfo.GetSkillLineInfo = nil, nil
			local rows = {
				{ "Profesiones", true, true },
				{ "Minería", false, nil, 50, 0, 0, 75 },
				{ "Secundarias", true, false },
				{ "Primeros auxilios", false, nil, 1, 0, 0, 75 },
			}
			_G.GetNumSkillLines = function()
				return #rows
			end
			_G.GetSkillLineInfo = function(i)
				return unpack(rows[i], 1, 7)
			end
			wow.login()
			wow.advance(11)
			assert.same({ "sk|Minería|50|75", "sk|Primeros auxilios|1|75" }, lines())
			assert.is_nil(snap("skills"))
		end)
	end)

	describe("learned spells and recipes", function()
		local LINK = "|cff71d5ff|Hspell:7620:0|h[Pesca]|h|r"

		it("writes one lr for the event and the chat line of one spell", function()
			boot()
			wow.fire("LEARNED_SPELL_IN_SKILL_LINE", 7620, 1, false)
			wow.advance(0.3)
			wow.fire("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: " .. LINK .. ".")
			assert.same({ "lr|Pesca|7620" }, lines())
			assert.equal(1, counts("character").learned)
		end)

		it("writes the same name again after 10 s", function()
			boot()
			wow.fire("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: " .. LINK .. ".")
			wow.advance(10)
			wow.fire("CHAT_MSG_SKILL", "Has aprendido una nueva facultad: " .. LINK .. ".")
			assert.same({ "lr|Pesca|7620", "lr|Pesca|7620" }, lines())
		end)

		it("writes two ranks of one spell learned within 10 s", function()
			boot()
			wow.spells[7621] = "Pesca"
			wow.fire("LEARNED_SPELL_IN_SKILL_LINE", 7620, 1, false)
			wow.fire("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: Pesca.")
			wow.fire("LEARNED_SPELL_IN_SKILL_LINE", 7621, 1, false)
			assert.same({ "lr|Pesca|7620", "lr|Pesca|7621" }, lines())
		end)

		it("takes the plain text without the period when the line has no link", function()
			boot({ strings = { ERR_LEARN_SPELL_S = "Has aprendido un nuevo hechizo: %s" } })
			wow.fire("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: Escudo de hielo.")
			assert.same({ "lr|Escudo de hielo" }, lines())
		end)

		it("writes lr and rc for a recipe, once for the chat line and the event", function()
			boot()
			wow.fire(
				"CHAT_MSG_SYSTEM",
				"Has aprendido a crear un nuevo objeto: |cffffffff|Hspell:3275:0|h[Venda de lino]|h|r."
			)
			wow.spells[3275] = "Venda de lino"
			wow.fire("NEW_RECIPE_LEARNED", 3275)
			assert.same({ "lr|Venda de lino|3275", "rc|Venda de lino|3275" }, lines())
			assert.equal(1, counts("character").recipes)
			assert.equal(1, counts("character").learned)
		end)

		it("builds its patterns from reordered and escaped formats", function()
			boot({
				strings = {
					ERR_LEARN_SPELL_S = "Al 100%%: %1$s.",
					ERR_LEARN_ABILITY_S = "Roto %q %s",
					ERR_LEARN_RECIPE_S = false,
				},
			})
			wow.fire("CHAT_MSG_SYSTEM", "Al 100%: " .. LINK .. ".")
			assert.same({ "lr|Pesca|7620" }, lines())
		end)

		it("ignores other system lines", function()
			boot()
			wow.fire("CHAT_MSG_SYSTEM", "Bienvenido a World of Warcraft.")
			wow.fire("CHAT_MSG_SYSTEM", wow.secret("x"))
			assert.same({}, lines())
		end)

		it("writes no line with lr and rc off and still counts", function()
			boot()
			ns.Settings.SetKind("lr", false)
			ns.Settings.SetKind("rc", false)
			wow.spells[3275] = "Venda de lino"
			wow.fire("NEW_RECIPE_LEARNED", 3275)
			assert.same({}, lines())
			assert.equal(1, counts("character").learned)
			assert.equal(1, counts("character").recipes)
		end)
	end)

	describe("talents", function()
		local function talents(nodes, unspent)
			return {
				config = 7,
				spec = 1,
				specs = { 62, 63 },
				trees = { [62] = { tree = 1, nodes = nodes }, [63] = { tree = 2, nodes = { 0, 0 } } },
				unspent = unspent,
			}
		end

		local function setTalents(t)
			wow.talents = t
			wow.fire("PLAYER_TALENT_UPDATE")
			wow.advance(1)
		end

		it("writes the spent and unspent points and counts a respec", function()
			boot({ talents = talents({ 5, 5 }, 0) })
			assert.same({ "ta|10|0" }, lines())
			assert.equal(10, snap("talents"))
			setTalents(talents({ 0, 0 }, 10))
			assert.same({ "ta|10|0", "ta|0|10" }, lines())
			assert.equal(1, counts("character").respecs)
			assert.equal(0, snap("talents"))
		end)

		it("reads a tree that two specs share once", function()
			local nodes = { 5, 5 }
			boot({
				talents = {
					config = 7,
					specs = { 62, 64 },
					trees = { [62] = { tree = 1, nodes = nodes }, [64] = { tree = 1, nodes = nodes } },
					unspent = 0,
				},
			})
			assert.same({ "ta|10|0" }, lines())
		end)

		it("writes nothing when the points stay the same", function()
			boot({ talents = talents({ 5, 5 }, 0) })
			setTalents(talents({ 5, 5 }, 0))
			assert.equal(1, #lines())
		end)

		it("writes nothing with no active config", function()
			boot({ talents = { specs = { 62 } } })
			assert.same({}, lines())
		end)

		it("writes no line with ta off and still keeps the last points", function()
			boot({ talents = talents({ 5, 5 }, 0), login = false })
			ns.Settings.SetKind("ta", false)
			wow.login()
			wow.advance(11)
			assert.same({}, lines())
			assert.same({ spent = 10, unspent = 0 }, stateOf("talents"))
		end)
	end)

	describe("casts", function()
		it("counts a cast in and out of combat by name", function()
			boot()
			wow.cast(133)
			wow.combat = true
			wow.cast(133)
			local c = counts("spells")
			assert.equal(2, c.total)
			assert.equal(1, c.calm)
			assert.equal(1, c.combat)
			assert.equal(1, c["o:Bola de Fuego"])
			assert.equal(1, c["c:Bola de Fuego"])
		end)

		it("never counts Attack, a mount or a spell with no name", function()
			boot()
			wow.cast(6603)
			wow.cast(458)
			wow.cast(99999)
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-1", 133)
			assert.is_nil(counts("spells").total)
		end)

		it("adds the cast time rounded to 0.1 s", function()
			boot()
			wow.fire("UNIT_SPELLCAST_START", "player", "Cast-1", 133)
			wow.advance(1.53)
			wow.fire("UNIT_SPELLCAST_STOP", "player", "Cast-1", 133)
			wow.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-2", 133)
			wow.advance(2)
			wow.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-2", 133)
			wow.fire("UNIT_SPELLCAST_START", "player", "Cast-3", 6603)
			wow.fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-3", 6603)
			assert.equal(3.5, counts("spells").castTime)
		end)

		it("keeps the cast running through a failed attempt of another cast", function()
			boot()
			wow.fire("UNIT_SPELLCAST_START", "player", "Cast-1", 133)
			wow.advance(1)
			wow.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2", 133)
			wow.advance(1)
			wow.fire("UNIT_SPELLCAST_STOP", "player", "Cast-1", 133)
			assert.equal(2, counts("spells").castTime)
		end)

		it("ends a channel with no GUID only on its own stop", function()
			boot()
			wow.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "", 133)
			wow.advance(1)
			wow.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2", 133)
			wow.fire("UNIT_SPELLCAST_STOP", "player", "Cast-2", 133)
			wow.advance(1)
			wow.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "", 133)
			assert.equal(2, counts("spells").castTime)
		end)

		it("keeps the fight with the most casts of the level", function()
			boot()
			wow.fire("PLAYER_REGEN_DISABLED")
			wow.cast(133)
			wow.cast(133)
			wow.advance(10.4)
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal(10, counts("spells").combatSec)
			local best = snap("bestFight")
			assert.equal(2, best.n)
			assert.equal(10, best.sec)
			assert.equal("Bosque de Elwynn", best.place)
			wow.fire("PLAYER_REGEN_DISABLED")
			wow.cast(133)
			wow.advance(3)
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal(13, counts("spells").combatSec)
			assert.equal(2, snap("bestFight").n)
		end)

		it("names the instance as the place of a fight inside one", function()
			boot({ instance = { name = "Las Minas de la Muerte", type = "party" } })
			wow.fire("PLAYER_REGEN_DISABLED")
			wow.cast(133)
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal("Las Minas de la Muerte", snap("bestFight").place)
		end)

		it("counts a disenchant with its target", function()
			boot()
			wow.send(13262, "Espada larga")
			wow.cast(13262)
			assert.equal(1, counts("prof")["disenchanted|Espada larga|Enchanting"])
		end)
	end)

	describe("consumables", function()
		local function bag(id, count, name)
			wow.bags[0] = { [1] = { itemID = id, stackCount = count, itemName = name } }
			wow.fire("BAG_UPDATE", 0)
			wow.advance(0.2)
		end

		local function newOnly(on)
			ns.Settings.Set("newOnly.consumables", on)
		end

		it("writes a drink paired with the Drink cast", function()
			boot()
			bag(WATER, 5, "Agua conjurada")
			wow.cast(430)
			wow.advance(0.1)
			bag(WATER, 4, "Agua conjurada")
			assert.same({ "cu|5350|drink|Agua conjurada" }, lines())
			assert.equal(1, counts("items")["k:drink"])
			assert.equal(1, counts("items")["o:5350"])
			assert.equal(1, counts("items").total)
		end)

		it("credits a held drop to a cast within 1.5 s and drops it after 2 s", function()
			boot()
			bag(BANDAGE, 5, "Venda de lino")
			bag(BANDAGE, 4, "Venda de lino")
			wow.advance(0.8)
			wow.combat = true
			wow.cast(3273)
			assert.same({ "cu|1251|bandage|Venda de lino|1" }, lines())
			assert.equal(1, counts("items")["c:1251"])
			bag(BANDAGE, 3, "Venda de lino")
			wow.advance(2.3)
			wow.cast(3273)
			assert.equal(1, #lines())
		end)

		it("writes food for another cast and one line per unit used", function()
			boot()
			bag(BREAD, 5, "Pan")
			wow.cast(133)
			bag(BREAD, 3, "Pan")
			assert.same({ "cu|4540|food|Pan", "cu|4540|food|Pan" }, lines())
			assert.equal(2, counts("items").total)
		end)

		it("ignores a drop of more than 3, a growing stack and items that are no consumable", function()
			boot()
			bag(POTION, 10, "Poción")
			wow.cast(133)
			bag(POTION, 5, "Poción")
			bag(POTION, 8, "Poción")
			bag(CLOTH, 3, "Paño de lino")
			wow.cast(133)
			bag(CLOTH, 2, "Paño de lino")
			bag(777, 3, "Desconocido")
			wow.cast(133)
			bag(777, 2, "Desconocido")
			assert.same({}, lines())
		end)

		it("writes one line for a first use with new findings only on", function()
			boot()
			newOnly(true)
			bag(159, 5, "Agua refrescante")
			wow.cast(430)
			bag(159, 4, "Agua refrescante")
			wow.cast(430)
			bag(159, 3, "Agua refrescante")
			assert.same({ "cu|159|drink|Agua refrescante" }, lines())
			assert.equal(2, counts("items").total)
		end)

		it("writes one line for three units used at once with new findings only on", function()
			boot()
			newOnly(true)
			bag(POTION, 5, "Poción")
			wow.cast(133)
			bag(POTION, 2, "Poción")
			assert.same({ "cu|118|potion|Poción" }, lines())
			assert.equal(3, counts("items").total)
		end)

		it("writes no line with cu off and still counts", function()
			boot()
			ns.Settings.SetKind("cu", false)
			bag(POTION, 5, "Poción")
			wow.cast(133)
			bag(POTION, 4, "Poción")
			assert.same({}, lines())
			assert.equal(1, counts("items")["k:potion"])
		end)

		it("asks the item name when the bag gives none", function()
			boot()
			wow.items[POTION] = "Poción menor"
			bag(POTION, 5)
			wow.cast(133)
			bag(POTION, 4)
			assert.same({ "cu|118|potion|Poción menor" }, lines())
		end)
	end)

	describe("buffs", function()
		local function aura(name, spellId, source)
			return { name = name, spellId = spellId, sourceUnit = source }
		end

		local function setAuras(list)
			wow.auras = list
			wow.fire("UNIT_AURA", "player")
			wow.advance(1)
		end

		it("counts gained buffs, the ones from others and the special ones", function()
			boot({ units = { party1 = { name = "Lyra", isPlayer = true } } })
			setAuras({ aura("Intelecto Arcano", 1459, "player") })
			assert.equal(1, counts("character").buffs)
			setAuras({
				aura("Intelecto Arcano", 1459, "player"),
				aura("Poder de la fe", 1243, "party1"),
				aura("Aventurero autosuficiente", 431567),
			})
			local c = counts("character")
			assert.equal(3, c.buffs)
			assert.equal(1, c.buffsFromOthers)
			assert.equal(1, c["special:Self-Found"])
			assert.equal("Self-Found", snap("buffs"))
			setAuras({})
			assert.equal("", snap("buffs"))
		end)

		it("skips the scan while the auras are secret and scans again 5 s later", function()
			boot()
			wow.auras_secret = true
			setAuras({ aura("Intelecto Arcano", 1459, "player") })
			assert.is_nil(counts("character").buffs)
			assert.equal(1, wow.ns.Memories_Character.Character.secretAuras.skipped)
			wow.auras_secret = false
			wow.advance(4.9)
			assert.is_nil(counts("character").buffs)
			wow.advance(0.1)
			assert.equal(1, counts("character").buffs)
		end)

		it("drops a half-read scan that hit a secret aura", function()
			boot()
			wow.aura_error = "Aura field cannot be accessed when secret"
			setAuras({ aura("Intelecto Arcano", 1459, "player") })
			local skipped = wow.ns.Memories_Character.Character.secretAuras
			assert.equal(1, skipped.skipped)
			assert.equal("Aura field cannot be accessed when secret", skipped.reason)
			assert.is_nil(counts("character").buffs)
			assert.same({}, ns.Errors())
		end)

		it("drops a scan that reads a secret aura, so the known buffs stay", function()
			boot()
			setAuras({ aura("Intelecto Arcano", 1459, "player"), aura("Poder de la fe", 1243, "player") })
			assert.equal(2, counts("character").buffs)
			setAuras({ wow.secret(aura("Intelecto Arcano", 1459, "player")), aura("Poder de la fe", 1243, "player") })
			assert.equal(1, wow.ns.Memories_Character.Character.secretAuras.skipped)
			setAuras({ aura("Intelecto Arcano", 1459, "player"), aura("Poder de la fe", 1243, "player") })
			assert.equal(2, counts("character").buffs)
		end)

		it("logs any other aura error", function()
			boot()
			wow.aura_error = "broken"
			setAuras({})
			assert.equal(1, #ns.Errors())
		end)
	end)

	describe("forms, totems and pets", function()
		it("counts a form change after the baseline, never leaving a form", function()
			boot()
			wow.forms[1] = 768
			wow.form = 1
			wow.fire("UPDATE_SHAPESHIFT_FORM")
			wow.form = 0
			wow.fire("UPDATE_SHAPESHIFT_FORM")
			wow.form = 2
			wow.fire("UPDATE_SHAPESHIFT_FORM")
			assert.equal(1, counts("character")["form:Forma felina"])
			assert.equal(1, counts("character")["form:form 2"])
		end)

		it("counts a placed totem", function()
			boot()
			wow.totems[1] = "Tótem de piel de piedra"
			wow.fire("PLAYER_TOTEM_UPDATE", 1)
			wow.totems[1] = nil
			wow.fire("PLAYER_TOTEM_UPDATE", 1)
			assert.equal(1, counts("character")["totem:Tótem de piel de piedra"])
		end)

		it("writes pt for a tamed beast and counts a pet once", function()
			boot()
			wow.cast(1515)
			wow.advance(12)
			wow.units.pet = { name = "Colmillo", family = "Lobo", level = 9 }
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			assert.same({ "pt|Lobo|Colmillo|9" }, lines())
			local c = counts("character")
			assert.equal(1, c.tames)
			assert.equal(1, c["pet:Lobo"])
			assert.equal(1, c["petn:Lobo|Colmillo"])
			wow.units.pet = nil
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			wow.units.pet = { name = "Colmillo", family = "Lobo", level = 9 }
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			assert.equal(1, counts("character")["pet:Lobo"])
			assert.equal(1, #lines())
		end)

		it("writes pt for a second tame with a family and name seen before", function()
			boot()
			wow.units.pet = { name = "Lobo", family = "Lobo", level = 9 }
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			wow.units.pet = nil
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			wow.cast(1515)
			wow.units.pet = { name = "Lobo", family = "Lobo", level = 12 }
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			assert.same({ "pt|Lobo|Lobo|12" }, lines())
			assert.equal(1, counts("character").tames)
			assert.equal(1, counts("character")["pet:Lobo"])
		end)

		it("writes no pt for a pet called after an interrupted Tame Beast", function()
			boot()
			wow.cast(1515)
			wow.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-3-0-0-0-1515-0", 1515, "Creature-0-0-0-0-1-0")
			wow.advance(5)
			wow.units.pet = { name = "Colmillo", family = "Lobo", level = 9 }
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			assert.same({}, lines())
			assert.is_nil(counts("character").tames)
		end)

		it("writes no pt for a pet called after a Tame Beast the player cancelled", function()
			boot()
			wow.channel = { spell = 1515, start = wow.clock, stop = wow.clock + 20 }
			wow.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-3-0-0-0-1515-0", 1515)
			wow.cast(1515)
			wow.advance(3)
			wow.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-3-0-0-0-1515-0", 1515)
			wow.channel = nil
			wow.advance(2)
			wow.units.pet = { name = "Colmillo", family = "Lobo", level = 9 }
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			assert.same({}, lines())
		end)

		it("writes pt for a pet after a Tame Beast channel that ran to its end", function()
			boot()
			wow.channel = { spell = 1515, start = wow.clock, stop = wow.clock + 20 }
			wow.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-3-0-0-0-1515-0", 1515)
			wow.cast(1515)
			wow.advance(20)
			wow.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-3-0-0-0-1515-0", 1515)
			wow.channel = nil
			wow.units.pet = { name = "Lobo", family = "Lobo", level = 12 }
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			assert.same({ "pt|Lobo|Lobo|12" }, lines())
		end)

		it("counts a pet with no recent tame without a line, and skips a pet with no family", function()
			boot()
			wow.units.pet = { name = "Diablillo", creatureType = { "Demonio", 3 } }
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			assert.equal(1, counts("character")["pet:Demonio"])
			wow.units.pet = { name = "Nada" }
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			assert.same({}, lines())
		end)

		it("writes no line with pt off and still counts", function()
			boot()
			ns.Settings.SetKind("pt", false)
			wow.cast(1515)
			wow.units.pet = { name = "Colmillo", family = "Lobo", level = 9 }
			wow.fire("UNIT_PET", "player")
			wow.advance(0.5)
			assert.same({}, lines())
			assert.equal(1, counts("character").tames)
		end)
	end)

	describe("crafting", function()
		local BREAD_LINK = "|cffffffff|Hitem:2683::::::::10:::::|h[Pan de especias]|h|r"

		it("counts made items with the open profession's verb", function()
			boot()
			wow.trade_open = "Cocina"
			wow.fire("TRADE_SKILL_SHOW")
			wow.fire("CHAT_MSG_LOOT", "Creas: " .. BREAD_LINK .. "x3.")
			wow.fire("TRADE_SKILL_CLOSE")
			wow.fire("CHAT_MSG_LOOT", "Creas: " .. BREAD_LINK .. ".")
			wow.fire("CHAT_MSG_LOOT", "Recibes botín: " .. BREAD_LINK .. ".")
			wow.fire("CHAT_MSG_LOOT", wow.secret("Creas: " .. BREAD_LINK .. "."))
			local c = counts("prof")
			assert.equal(3, c["cooked|Pan de especias|Cooking"])
			assert.equal(1, c["made|Pan de especias|?"])
		end)

		it("keeps a profession name it cannot match", function()
			boot()
			wow.trade_open = "Joyería"
			wow.fire("TRADE_SKILL_SHOW")
			wow.fire("CHAT_MSG_LOOT", "Creas: " .. BREAD_LINK .. ".")
			assert.equal(1, counts("prof")["made|Pan de especias|Joyería"])
		end)
	end)

	describe("statistics", function()
		local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
		local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"

		it("keeps the first read of a level as stats and the latest as statsNow", function()
			boot({
				stats = {
					{ 130, { { 60, "12" }, { 98, "3 " .. GOLD .. " 4 " .. SILVER }, { 97, "--" }, { 96, "0" } } },
					{ 141, { { 112, "|cffffffffA;B=C|r" }, { 113, "|TInterface\\Icons\\x:0|t" }, { 114 } } },
				},
			})
			assert.equal("60=12;98=3 g 4 s;112=ABC", snap("stats"))
			assert.equal(snap("stats"), snap("statsNow"))
		end)

		it("writes nothing for an empty pane", function()
			boot({ stats = { { 130, {} } } })
			assert.is_nil(snap("stats"))
		end)
	end)

	describe("level up", function()
		it("snapshots the casts now, the stats at +4 s and the skills and talents at +6 s", function()
			boot({ stats = { { 130, { { 60, "12" } } } } })
			wow.cast(133)
			wow.player.level = 11
			wow.fire("PLAYER_LEVEL_UP", 11)
			assert.equal(1, snap("casts", 11))
			wow.stats[1][2][1][2] = "13"
			wow.advance(3.9)
			assert.is_nil(snap("stats", 11))
			wow.advance(0.1)
			assert.equal("60=13", snap("stats", 11))
			wow.skills = { { name = "Espadas", rank = 55, max = 55 } }
			wow.talents = { config = 7, specs = { 62 }, trees = { [62] = { tree = 1, nodes = { 1 } } }, unspent = 0 }
			wow.advance(2)
			assert.same({ "sk|Espadas|55|55", "ta|1|0" }, lines())
		end)
	end)

	describe("missing game functions", function()
		it("starts and reads without the optional tables", function()
			boot({ login = false })
			for _, name in ipairs({
				"C_SkillInfo",
				"C_TradeSkillUI",
				"C_ClassTalents",
				"C_SpecializationInfo",
				"C_Traits",
				"C_UnitAuras",
				"C_Secrets",
				"C_MountJournal",
				"C_Container",
				"GetShapeshiftForm",
			}) do
				_G[name] = nil
			end
			wow.login()
			wow.advance(11)
			wow.cast(133)
			wow.fire("UNIT_AURA", "player")
			wow.fire("BAG_UPDATE", 0)
			wow.fire("UPDATE_SHAPESHIFT_FORM")
			wow.advance(1)
			assert.equal(1, counts("spells").total)
			assert.same({}, ns.Errors())
		end)
	end)

	describe("registration", function()
		it("registers its kinds in two groups and the new-only box", function()
			boot()
			for _, kind in ipairs({ "sk", "lr", "rc", "ta", "cu", "pt" }) do
				assert.equal("Character", ns.Kinds.Get(kind).group)
				assert.equal("Memories_Character", ns.Kinds.Get(kind).addon)
			end
			for _, kind in ipairs({ "rp", "qa", "hb", "fp", "bk" }) do
				assert.equal("Milestones", ns.Kinds.Get(kind).group)
			end
			local box = ns.Registry.Registered()[1].boxes[1]
			assert.equal("consumables", box.key)
			assert.same({ "cu" }, box.kinds)
		end)

		it("writes into its own saved file only", function()
			local core = boot()
			local coreLines = core.Store.Core():LineCount()
			wow.fire("LEARNED_SPELL_IN_SKILL_LINE", 7620)
			assert.equal(coreLines, core.Store.Core():LineCount())
			assert.is_table(_G.MemoriesCharacterCharDB.log)
		end)

		it("records after a registration after login", function()
			ns = wow.boot({ addons = { "Memories" }, spells = SPELLS })
			wow.load_addon("Memories_Character")
			wow.fire("LEARNED_SPELL_IN_SKILL_LINE", 7620)
			assert.same({ "lr|Pesca|7620" }, lines())
			assert.same({}, ns.Errors())
		end)

		it("stops with one line when it loads before the core", function()
			boot({ order = "reverse" })
			assert.equal("Memories_Character: Memories is not loaded.", wow.chat()[1])
			assert.is_nil(ns.Kinds.Get("sk"))
		end)
	end)
end)
