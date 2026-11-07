local wow = require("helpers.wow")

describe("progress", function()
	local GUID = "Player-1234-0ABCDEF0"
	local ENGLISH = {
		COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience.",
		COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience.",
		COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP = "You gain %d experience. (+%d group bonus)",
		ERR_ZONE_EXPLORED = "Discovered: %s",
		ERR_ZONE_EXPLORED_XP = "Discovered %s: %d experience gained",
	}

	local ns

	local function kinds(kind)
		local out = {}
		for line in ns.Store.Core():Lines() do
			local k, rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(%w+)|?(.*)$")
			if k == kind then
				out[#out + 1] = rest
			end
		end
		return out
	end

	local function counts(module)
		return ns.Store.Core():Counts(module)
	end

	local function boot(opts)
		ns = wow.boot(opts)
		return ns
	end

	describe("experience", function()
		it("writes a named kill gain with its group bonus", function()
			boot({ strings = ENGLISH })
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 45 experience. (+9 group bonus)")
			assert.same({ "45|kill|Kobold Vermin|9" }, kinds("xp"))
			assert.same({ all = 45, kill = 45, ["kill:10"] = 45 }, counts("xp"))
		end)

		it("never reads the rested bonus as the group bonus", function()
			boot({ strings = ENGLISH })
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold dies, you gain 90 experience. (+45 exp Rested bonus)")
			wow.fire(
				"CHAT_MSG_COMBAT_XP_GAIN",
				"Kobold dies, you gain 99 experience. (+45 exp Rested bonus, +9 group bonus)"
			)
			assert.same({ "90|kill|Kobold", "99|kill|Kobold|9" }, kinds("xp"))
		end)

		it("reads Spanish lines from the client's GlobalStrings", function()
			boot()
			wow.fire(
				"CHAT_MSG_COMBAT_XP_GAIN",
				"Alimaña kóbold muere, ganas 1.250 p. de experiencia. (+9 bonif. grupo)"
			)
			assert.same({ "1250|kill|Alimaña kóbold|9" }, kinds("xp"))
		end)

		it("reads a translation that reorders its arguments", function()
			boot({ strings = { COMBATLOG_XPGAIN_FIRSTPERSON = "Ganas %2$d p. por matar a %1$s." } })
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Ganas 45 p. por matar a Lobo.")
			assert.same({ "45|kill|Lobo" }, kinds("xp"))
		end)

		it("joins a nameless gain with a turn-in that follows within 1.5 s", function()
			boot({ quests = { [783] = "Una amenaza interna" } })
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Ganas 1,250 p. de experiencia.")
			local at = wow.wall
			wow.advance(0.1)
			wow.fire("QUEST_TURNED_IN", 783, 1250, 0)
			wow.advance(5)
			assert.same({ "1250|quest|Una amenaza interna" }, kinds("xp"))
			assert.same({ "783|1250|0|Una amenaza interna" }, kinds("qt"))
			assert.equal(1250, counts("xp").quest)
			assert.equal(1, counts("progress").quests)
			for line in ns.Store.Core():Lines() do
				if line:find("|xp|") then
					assert.equal(at, ns.Codec.DecodeLine(line).t)
				end
			end
		end)

		it("joins a nameless gain with a turn-in from up to 2 s before", function()
			boot({ quests = { [783] = "Una amenaza interna" } })
			wow.fire("QUEST_TURNED_IN", 783, 1250, 0)
			wow.advance(0.5)
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Ganas 1250 p. de experiencia.")
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Ganas 1250 p. de experiencia.")
			wow.advance(2)
			assert.same({ "1250|quest|Una amenaza interna", "1250|other" }, kinds("xp"))
		end)

		it("writes other for a nameless gain with no turn-in", function()
			boot()
			wow.fire("QUEST_TURNED_IN", 1, 300, 0)
			wow.advance(2.5)
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Ganas 300 p. de experiencia.")
			wow.advance(1.4)
			assert.same({}, kinds("xp"))
			wow.advance(0.1)
			assert.same({ "300|other" }, kinds("xp"))
			assert.equal(300, counts("xp").other)
		end)

		it("counts XP in an instance as dungeon XP", function()
			boot()
			wow.instance = { type = "party", name = "Las Minas de la Muerte" }
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias muere, ganas 80 p. de experiencia.")
			assert.same({ all = 80, kill = 80, dungeon = 80, ["dungeon:10"] = 80 }, counts("xp"))
		end)

		it("ignores gains of 0 or less, lines that do not parse and secret text", function()
			boot()
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Ganas 0 p. de experiencia.")
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Algo distinto")
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", wow.secret("Ganas 5 p. de experiencia."))
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", nil)
			wow.advance(2)
			assert.same({}, kinds("xp"))
			assert.same({}, counts("xp"))
		end)

		it("reads no group bonus when the group GlobalString has no words after its number", function()
			boot({ strings = { COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP = "%d" } })
			assert.same({ 5 }, { ns.Progress.ParseXP("Ganas 5 p. de experiencia. (+1 bonif. grupo)") })
		end)

		it("parses nothing when the client lacks the GlobalStrings", function()
			boot({ strings = { COMBATLOG_XPGAIN_FIRSTPERSON = "%.1f raro", COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = 5 } })
			assert.is_nil(ns.Progress.ParseXP("Lobo muere, ganas 5 p. de experiencia."))
			assert.is_nil(ns.Progress.Compile(""))
			assert.equal("^100%%()", ns.Progress.Compile("100%%"))
		end)
	end)

	describe("quests", function()
		it("writes qt 2 s later with the title read again when it is missing", function()
			boot()
			wow.fire("QUEST_TURNED_IN", 783, 1250, 1500)
			wow.quests[783] = "Una amenaza interna"
			wow.advance(1.9)
			assert.same({}, kinds("qt"))
			wow.advance(0.1)
			assert.same({ "783|1250|1500|Una amenaza interna" }, kinds("qt"))
		end)

		it("holds the quest xp line until the title is read again", function()
			boot()
			wow.fire("QUEST_TURNED_IN", 783, 1250, 0)
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Ganas 1250 p. de experiencia.")
			wow.fire("QUEST_TURNED_IN", 784, 300, 0)
			wow.advance(0.1)
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Ganas 300 p. de experiencia.")
			wow.quests[783] = "Una amenaza interna"
			wow.quests[784] = "Otra"
			assert.same({}, kinds("xp"))
			wow.advance(2)
			assert.same({ "1250|quest|Una amenaza interna", "300|quest|Otra" }, kinds("xp"))
		end)

		it("writes qt without a title that never comes", function()
			boot()
			wow.fire("QUEST_TURNED_IN", 9, 0, 0)
			wow.advance(2)
			assert.same({ "9|0|0" }, kinds("qt"))
			wow.fire("QUEST_TURNED_IN", wow.secret(9), 0, 0)
			wow.advance(2)
			assert.equal(1, #kinds("qt"))
		end)
	end)

	describe("discoveries", function()
		it("writes di and an xp line for a discovery with XP", function()
			boot()
			wow.fire("CHAT_MSG_SYSTEM", "Has descubierto Villadorada: 100 p. de experiencia ganados")
			assert.same({ "Villadorada|100" }, kinds("di"))
			assert.same({ "100|discover|Villadorada" }, kinds("xp"))
			assert.equal(1, counts("progress").discoveries)
			wow.fire("CHAT_MSG_SYSTEM", "Otra cosa")
			wow.fire("CHAT_MSG_SYSTEM", wow.secret("Has descubierto Villadorada: 100 p. de experiencia ganados"))
			assert.equal(1, #kinds("di"))
		end)

		it("writes nothing for the message of a discovery that a line with XP recorded", function()
			boot()
			wow.fire("UI_INFO_MESSAGE", 1, "Descubierto: Villadorada.")
			wow.fire("CHAT_MSG_SYSTEM", "Has descubierto Villadorada: 100 p. de experiencia ganados")
			wow.advance(1.5)
			assert.same({ "Villadorada|100" }, kinds("di"))
		end)

		it("writes di 1.5 s after a discovery without XP", function()
			boot({ strings = ENGLISH })
			wow.fire("UI_INFO_MESSAGE", 1, "Discovered: Goldshire")
			wow.advance(1.4)
			assert.same({}, kinds("di"))
			wow.advance(0.1)
			assert.same({ "Goldshire" }, kinds("di"))
			assert.equal(1, counts("progress").discoveries)
			wow.advance(10)
			wow.fire("UI_INFO_MESSAGE", 1, "Discovered: Goldshire")
			wow.fire("UI_INFO_MESSAGE", 1, "Something else")
			wow.advance(2)
			assert.same({ "Goldshire", "Goldshire" }, kinds("di"))
		end)
	end)

	describe("levels", function()
		it("writes lv, the snapshots and asks /played with reason ding", function()
			boot({ rested = 900, zone = "Bosque de Elwynn" })
			local seen = {}
			ns.Listen("LEVEL_UP", function(_, level)
				seen[#seen + 1] = level
			end)
			local asks = wow.played_asks
			wow.player.level = 11
			wow.fire("PLAYER_LEVEL_UP", 12)
			assert.same({ "12" }, kinds("lv"))
			assert.same({ 12 }, seen)
			local j = ns.Store.Core()
			assert.equal(wow.wall, j:Snap(12, "t"))
			assert.equal("Bosque de Elwynn", j:Snap(12, "zone"))
			assert.equal(900, j:Snap(12, "rested"))
			assert.is_nil(j:Snap(12, "inst"))
			assert.equal(1, counts("progress").levels)
			assert.equal(12, MemoriesCharDB.char.level)
			assert.equal(12, ns.Progress.Level())
			assert.equal(asks + 1, wow.played_asks)
			wow.fire("TIME_PLAYED_MSG", 5000, 3)
			assert.same({ "5000" }, kinds("pl"))
			assert.equal(4997, j:Snap(12, "played"))
			wow.fire("TIME_PLAYED_MSG", 6000, 1003)
			assert.equal(4997, j:Snap(12, "played"))
			wow.fire("PLAYER_LEVEL_UP", 13)
			wow.fire("TIME_PLAYED_MSG", 7000, wow.secret(5))
			assert.is_nil(j:Snap(13, "played"))
		end)

		it("snapshots the instance name and marks level 60", function()
			boot({ player = { level = 59 } })
			wow.instance = { type = "raid", name = "Núcleo de Magma" }
			wow.fire("PLAYER_LEVEL_UP", 60)
			assert.equal("Núcleo de Magma", ns.Store.Core():Snap(60, "inst"))
			assert.equal(0, ns.Store.Core():Snap(60, "rested"))
			assert.is_true(MemoriesCharDB.char.dinged60)
		end)

		it("takes no rested snapshot when the pool is secret", function()
			boot({ rested = wow.secret(900) })
			wow.fire("PLAYER_LEVEL_UP", 12)
			assert.is_nil(ns.Store.Core():Snap(12, "rested"))
		end)

		it("takes the next level when the event's level is secret", function()
			boot()
			wow.fire("PLAYER_LEVEL_UP", wow.secret(11))
			assert.same({ "11" }, kinds("lv"))
			assert.equal(11, ns.Level())
		end)

		it("writes no level when the event's level and UnitLevel are both secret", function()
			boot()
			wow.player.level = wow.secret(10)
			wow.fire("PLAYER_LEVEL_UP", wow.secret(11))
			assert.same({}, kinds("lv"))
			assert.is_nil(ns.Store.Core():Snap(1, "t"))
		end)

		it("writes the missed levels at the first /played answer", function()
			boot({
				player = { level = 13 },
				saved = { MemoriesCharDB = { char = { guid = GUID, first = { t = 1, level = 10 } } } },
			})
			local start = wow.wall
			wow.advance(5)
			wow.fire("TIME_PLAYED_MSG", 2000, 100)
			assert.same({ "11", "12", "13" }, kinds("lv"))
			local j = ns.Store.Core()
			for l = 11, 13 do
				assert.equal(start, j:Snap(l, "t"))
				assert.equal(1, j:Snap(l, "gap"))
			end
			assert.equal(3, counts("progress").levels)
			assert.equal(13, ns.Progress.KnownLevel())
			wow.fire("TIME_PLAYED_MSG", 2010, 110)
			assert.equal(3, #kinds("lv"))
		end)

		it("takes the known level from the snapshots and catches up nothing without one", function()
			boot({
				saved = {
					MemoriesCharDB = { char = { guid = GUID, first = {} }, snap = { [12] = { t = 5 }, [20] = {} } },
				},
			})
			assert.equal(12, ns.Progress.KnownLevel())
			assert.equal(0, ns.Progress.CatchUp(12, ns.Here()))
			assert.equal(0, ns.Progress.CatchUp(nil, ns.Here()))
			MemoriesCharDB.snap = {}
			assert.equal(0, ns.Progress.CatchUp(20, ns.Here()))
		end)

		it("catches up the levels after a backup restore", function()
			boot()
			ns.Backup.Write("Memories")
			wow.player.level = 12
			assert.is_true(ns.Backup.Restore("Memories"))
			assert.same({ "11", "12" }, kinds("lv"))
		end)
	end)

	describe("rested", function()
		it("counts the XP drawn from the pool and writes rs when it ends", function()
			boot({ rested = 4000 })
			assert.same({ "4000" }, kinds("rs"))
			wow.rested = 3800
			wow.fire("PLAYER_XP_UPDATE", "player")
			wow.rested = nil
			wow.fire("UPDATE_EXHAUSTION")
			wow.fire("UPDATE_EXHAUSTION")
			assert.equal(4000, counts("xp").rested)
			assert.same({ "4000", "0" }, kinds("rs"))
			wow.rested = wow.secret(10)
			wow.fire("UPDATE_EXHAUSTION")
			wow.rested = 500
			wow.fire("UPDATE_EXHAUSTION")
			assert.equal(4000, counts("xp").rested)
		end)

		it("writes rs at each load", function()
			boot({ rested = 100 })
			wow.reload()
			ns = wow.ns.Memories
			assert.same({ "100", "100" }, kinds("rs"))
		end)

		it("writes no rs at load for a secret pool", function()
			boot({ rested = wow.secret(5) })
			assert.same({}, kinds("rs"))
		end)
	end)

	describe("kinds off", function()
		local function off(list, extra)
			local kindsOff = {}
			for _, k in ipairs(list) do
				kindsOff[k] = false
			end
			local opts = { saved = { MemoriesDB = { settings = { kinds = kindsOff } } } }
			for k, v in pairs(extra or {}) do
				opts[k] = v
			end
			return opts
		end

		it("writes no lv but still emits LEVEL_UP, snapshots and counts", function()
			boot(off({ "lv" }))
			local seen = {}
			ns.Listen("LEVEL_UP", function(_, level)
				seen[#seen + 1] = level
			end)
			wow.fire("PLAYER_LEVEL_UP", 11)
			assert.same({}, kinds("lv"))
			assert.same({ 11 }, seen)
			assert.equal(wow.wall, ns.Store.Core():Snap(11, "t"))
			assert.equal(1, counts("progress").levels)
		end)

		it("writes no xp but still counts", function()
			boot(off({ "xp" }))
			wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Lobo muere, ganas 50 p. de experiencia.")
			assert.same({}, kinds("xp"))
			assert.equal(50, counts("xp").all)
		end)

		it("writes no qt but still counts", function()
			boot(off({ "qt" }, { quests = { [1] = "Misión" } }))
			wow.fire("QUEST_TURNED_IN", 1, 10, 0)
			assert.same({}, kinds("qt"))
			assert.equal(1, counts("progress").quests)
		end)

		it("writes no di but still counts and dedupes", function()
			boot(off({ "di" }))
			wow.fire("CHAT_MSG_SYSTEM", "Has descubierto Villadorada: 100 p. de experiencia ganados")
			wow.fire("UI_INFO_MESSAGE", 1, "Descubierto: Villadorada.")
			wow.advance(2)
			assert.same({}, kinds("di"))
			assert.equal(1, counts("progress").discoveries)
		end)

		it("writes no rs but still counts the rested XP", function()
			boot(off({ "rs" }, { rested = 50 }))
			wow.rested = 0
			wow.fire("UPDATE_EXHAUSTION")
			assert.same({}, kinds("rs"))
			assert.equal(50, counts("xp").rested)
		end)
	end)
end)
