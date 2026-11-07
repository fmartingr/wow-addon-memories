local wow = require("helpers.wow")

describe("pvp", function()
	local HORDE = { "Horde", "Horda" }
	local BG = { name = "Garganta Grito de Guerra", type = "pvp", id = 489 }
	local KOR_GUID = "Player-1234-0BBBBBB1"

	local ns, units

	local function kor(extra)
		local u = {
			guid = KOR_GUID,
			name = "Kor",
			surname = "Ash",
			isPlayer = true,
			class = { "Pícaro", "ROGUE", 4 },
			race = { "Orco", "Orc", 2 },
			level = 14,
			faction = HORDE,
		}
		for k, v in pairs(extra or {}) do
			u[k] = v
		end
		return u
	end

	local function boot(opts)
		opts = opts or {}
		opts.addons = opts.addons or { "Memories", "Memories_Social" }
		units = opts.units or {}
		opts.units = units
		ns = wow.boot(opts)
		wow.advance(11)
		return ns
	end

	local function pvp()
		return wow.ns.Memories_Social.PvP
	end

	local function journal()
		return ns.Registry.Journal("Memories_Social").journal
	end

	-- The PvP lines as "kind|fields", in journal order; the login rank line is left out.
	local function lines()
		local out = {}
		for line in journal():Lines() do
			local rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(.*)$")
			if not rest:match("^nt|") and not rest:match("^rk|") then
				out[#out + 1] = rest
			end
		end
		return out
	end

	local function rankLines()
		local out = {}
		for line in journal():Lines() do
			local rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(.*)$")
			if rest:match("^rk|") then
				out[#out + 1] = rest
			end
		end
		return out
	end

	local function counts()
		return journal():Counts("pvp")
	end

	local function target(u)
		units.target = u
		wow.fire("PLAYER_TARGET_CHANGED")
	end

	local function fightStart()
		wow.combat, wow.flags.combat = true, true
		wow.fire("PLAYER_REGEN_DISABLED")
	end

	local function fightEnd()
		wow.combat, wow.flags.combat = false, false
		wow.fire("PLAYER_REGEN_ENABLED")
	end

	local function honor(msg)
		wow.fire("CHAT_MSG_COMBAT_HONOR_GAIN", msg)
	end

	local function enterBattleground()
		wow.instance = BG
		wow.fire("ZONE_CHANGED_NEW_AREA")
	end

	local function leaveBattleground()
		wow.instance = nil
		wow.fire("ZONE_CHANGED_NEW_AREA")
	end

	describe("enemies", function()
		it("writes ep on target, again only after 30 minutes", function()
			boot()
			target(kor())
			assert.same({ "ep|Kor Ash|ROGUE|Orc|14" }, lines())
			assert.equal(1, counts().met)
			wow.advance(600)
			target(kor())
			assert.equal(1, #lines())
			wow.advance(21 * 60)
			target(kor())
			assert.equal(2, #lines())
			assert.equal(2, counts().met)
		end)

		it("writes a new ep when a plate shows the guild of a met enemy", function()
			boot()
			target(kor())
			units.nameplate2 = kor({ guild = "Red Fang" })
			wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
			assert.same({ "ep|Kor Ash|ROGUE|Orc|14", "ep|Kor Ash|ROGUE|Orc|14|Red Fang" }, lines())
		end)

		it("writes no ep for a guild learned before the first meeting or for a friend", function()
			boot()
			units.mouseover = kor()
			wow.fire("UPDATE_MOUSEOVER_UNIT")
			units.mouseover = kor({ guild = "Red Fang" })
			wow.fire("UPDATE_MOUSEOVER_UNIT")
			units.mouseover = kor({ name = "Ann", faction = { "Alliance", "Alianza" } })
			wow.fire("UPDATE_MOUSEOVER_UNIT")
			assert.same({}, lines())
			target(kor({ guild = "Red Fang" }))
			assert.same({ "ep|Kor Ash|ROGUE|Orc|14|Red Fang" }, lines())
		end)

		it("reads no unit inside a party instance", function()
			boot()
			wow.instance = { name = "Minas Muertas", type = "party" }
			target(kor())
			assert.same({}, lines())
		end)

		it("writes no line with ep off and still counts", function()
			boot()
			ns.Settings.SetKind("ep", false)
			target(kor())
			assert.same({}, lines())
			assert.equal(1, counts().met)
		end)
	end)

	describe("fights", function()
		it("writes pk won when a fought enemy's plate shows him dead, once", function()
			boot()
			fightStart()
			target(kor())
			units.target = nil
			wow.advance(12)
			units.nameplate1 = kor({ dead = true })
			wow.advance(0.5)
			assert.same({ "ep|Kor Ash|ROGUE|Orc|14", "pk|won|Kor Ash|ROGUE|14" }, lines())
			assert.equal(1, counts().won)
			wow.advance(20)
			assert.equal(2, #lines())
		end)

		it("reads an unknown plate that targets you and counts a battleground win", function()
			boot()
			target(kor({ name = "Zug", surname = nil, guid = "Player-1-02" }))
			enterBattleground()
			fightStart()
			units.nameplate4 = kor({ nameplate4target = true })
			units.nameplate4target = wow.player
			wow.advance(0.5)
			units.nameplate4 = kor({ ghost = true })
			wow.advance(0.5)
			assert.same("pk|won|Kor Ash|ROGUE|14", lines()[2])
			assert.equal(1, counts().bgWon)
		end)

		it("scans a plate first read with no faction once a target read shows an enemy", function()
			boot()
			target(kor({ name = "Zug", surname = nil, guid = "Player-1-02" }))
			units.target = nil
			fightStart()
			units.nameplate1 = kor({ faction = {} })
			wow.advance(0.5)
			target(kor())
			units.target = nil
			units.nameplate1 = kor({ dead = true })
			wow.advance(0.5)
			assert.same("pk|won|Kor Ash|ROGUE|14", lines()[#lines()])
		end)

		it("skips friends and plates in a raid instance, and stops 5 s after the fight", function()
			boot()
			fightStart()
			target(kor())
			units.target = nil
			units.nameplate1 = kor({ name = "Ann", faction = { "Alliance", "Alianza" }, dead = true })
			wow.advance(0.5)
			fightEnd()
			wow.advance(6)
			units.nameplate2 = kor({ dead = true })
			wow.advance(1)
			assert.equal(1, #lines())
			wow.instance = { name = "Molten Core", type = "raid" }
			fightStart()
			wow.advance(1)
			assert.equal(1, #lines())
			wow.instance = nil
			wow.advance(0.5)
			assert.same("pk|won|Kor Ash|ROGUE|14", lines()[2])
		end)

		it("starts the scan when the first enemy shows during a fight", function()
			boot()
			fightStart()
			wow.advance(1)
			target(kor())
			units.target = kor({ dead = true })
			wow.advance(0.5)
			assert.same("pk|won|Kor Ash|ROGUE|14", lines()[2])
		end)

		it("writes no line with pk off and still counts", function()
			boot()
			ns.Settings.SetKind("pk", false)
			fightStart()
			target(kor())
			units.target = kor({ dead = true })
			wow.advance(0.5)
			assert.same({ "ep|Kor Ash|ROGUE|Orc|14" }, lines())
			assert.equal(1, counts().won)
		end)
	end)

	describe("honor", function()
		it("writes hk for the enemy targeted 10 s ago and a won fight", function()
			boot()
			target(kor())
			wow.advance(10)
			honor("Se te han concedido 6 puntos de honor.")
			assert.same({ "ep|Kor Ash|ROGUE|Orc|14", "hk|6|Kor Ash", "pk|won|Kor Ash|ROGUE|14" }, lines())
			assert.equal(6, counts().honor)
			assert.equal(6, counts().honorWorld)
		end)

		it("reads the victim and the rank of a kill line", function()
			boot()
			honor("Zug Ash muere, muerte con honor. Rango: Sargento (Puntos de honor estimados: 1.234)")
			honor("Esto no es honor.")
			assert.same({ "hk|1234|Zug Ash|Sargento" }, lines())
			assert.is_nil(counts().won)
		end)

		it("reads the victim of a kill line with no rank", function()
			boot()
			honor("Zug Ash muere, muerte con honor (Puntos de honor estimados: 7)")
			assert.same({ "hk|7|Zug Ash" }, lines())
		end)

		it("writes one pk won per enemy in 60 s", function()
			boot()
			target(kor())
			honor("Kor Ash muere, muerte con honor. Rango: Cabo (Puntos de honor estimados: 5)")
			wow.advance(59)
			honor("Kor muere, muerte con honor. Rango: Cabo (Puntos de honor estimados: 5)")
			assert.equal(1, counts().won)
			wow.advance(1)
			honor("Kor Ash muere, muerte con honor. Rango: Cabo (Puntos de honor estimados: 5)")
			assert.equal(2, counts().won)
			assert.same("hk|5|Kor|Cabo", lines()[4])
		end)

		it("reads a victim joined to the surname with a dash", function()
			boot()
			target(kor())
			honor("Kor-Ash muere, muerte con honor. Rango: Cabo (Puntos de honor estimados: 5)")
			assert.same({ "ep|Kor Ash|ROGUE|Orc|14", "hk|5|Kor Ash|Cabo", "pk|won|Kor Ash|ROGUE|14" }, lines())
		end)

		it("reads a format with a percent sign and ignores an empty line", function()
			boot({ strings = { COMBATLOG_HONORAWARD = "Honor: %d (100%%)." } })
			honor(nil)
			honor("Honor: 8 (100%).")
			assert.same({ "hk|8" }, lines())
		end)

		it("writes hk with no victim when no enemy was seen in 30 s", function()
			boot()
			target(kor())
			wow.advance(31)
			honor("Se te han concedido 6 puntos de honor.")
			assert.same("hk|6", lines()[2])
		end)

		it("only counts honor in a battleground and adds it to the tally", function()
			boot()
			enterBattleground()
			honor("Se te han concedido 12 puntos de honor.")
			assert.same({}, lines())
			assert.equal(12, counts().honorBg)
			assert.is_nil(counts().honorWorld)
			assert.equal(12, pvp().Tally().honor)
		end)

		it("matches nothing without the GlobalStrings formats", function()
			boot({ strings = { COMBATLOG_HONORAWARD = false, COMBATLOG_HONORGAIN = "%z" } })
			honor("Se te han concedido 6 puntos de honor.")
			assert.same({}, lines())
			assert.is_nil(counts().honor)
		end)

		it("writes no line with hk off and still counts", function()
			boot()
			ns.Settings.SetKind("hk", false)
			honor("Se te han concedido 6 puntos de honor.")
			assert.same({}, lines())
			assert.equal(6, counts().honor)
		end)

		it("counts new lifetime kills in the world and in a battleground", function()
			boot({ pvp = { kills = 10 } })
			wow.pvp.kills = 12
			wow.fire("PLAYER_PVP_KILLS_CHANGED", "player")
			wow.advance(1)
			assert.equal(2, counts().hk)
			assert.equal(2, counts().hkWorld)
			enterBattleground()
			wow.pvp.kills = 15
			wow.fire("PLAYER_PVP_KILLS_CHANGED", "player")
			wow.advance(1)
			assert.equal(5, counts().hk)
			assert.equal(3, counts().hkBg)
			assert.equal(3, pvp().Tally().kills)
			wow.pvp.kills = 15
			wow.fire("PLAYER_PVP_KILLS_CHANGED", "player")
			wow.pvp.kills = wow.secret(16)
			wow.fire("PLAYER_PVP_KILLS_CHANGED", "player")
			wow.advance(1)
			assert.equal(5, counts().hk)
		end)

		it("counts nothing without a login baseline", function()
			boot({ pvp = { kills = wow.secret(3) } })
			wow.pvp.kills = 4
			wow.fire("PLAYER_PVP_KILLS_CHANGED", "player")
			wow.advance(1)
			assert.is_nil(counts().hk)
			wow.pvp.kills = 6
			wow.fire("PLAYER_PVP_KILLS_CHANGED", "player")
			wow.advance(1)
			assert.equal(2, counts().hk)
		end)
	end)

	describe("deaths", function()
		local function die(recap)
			wow.recap = recap
			wow.flags.dead = true
			wow.fire("PLAYER_DEAD")
		end

		it("writes pk lost for a death line by an enemy rogue, and nothing at the release", function()
			boot()
			units.nameplate3 = kor()
			wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
			die({ { timestamp = 7, sourceGUID = KOR_GUID, sourceName = "Kor Ash", amount = 44 } })
			wow.advance(1)
			assert.same({ "pk|lost|Kor Ash|ROGUE|14" }, lines())
			assert.equal(1, counts().lost)
			wow.advance(20)
			wow.flags.dead, wow.flags.ghost = false, true
			wow.fire("PLAYER_DEAD")
			wow.advance(10)
			assert.equal(1, #lines())
		end)

		it("judges the death with de off in the core", function()
			boot()
			ns.Settings.SetKind("de", false)
			units.target = kor()
			wow.fire("PLAYER_TARGET_CHANGED")
			units.target = nil
			die({ { timestamp = 7, sourceGUID = KOR_GUID, sourceName = "Kor Ash", amount = 44 } })
			wow.advance(1)
			assert.same({ "ep|Kor Ash|ROGUE|Orc|14", "pk|lost|Kor Ash|ROGUE|14" }, lines())
			for line in ns.Store.Core():Lines() do
				assert.is_nil(line:match("|de|"))
			end
		end)

		it("uses the line's killer, class and level for a stranger", function()
			boot()
			ns.Emit("DIED", { killer = "Zug", kclass = "WARLOCK", klevel = 20 })
			assert.same({ "pk|lost|Zug|WARLOCK|20" }, lines())
		end)

		it("never looks up a hidden killer, and takes byPlayer", function()
			boot()
			wow.ns.Memories_Social.Social.Remember({ name = "?", first = "?", enemy = true, class = "MAGE" })
			ns.Emit("DIED", { killer = "?", byPlayer = true })
			assert.same({ "pk|lost|?" }, lines())
		end)

		it("writes a second loss to another player within 15 s of a judged loss", function()
			boot()
			ns.Emit("DIED", { killer = "Zug", kclass = "WARLOCK", klevel = 20 })
			wow.advance(10)
			ns.Emit("DIED", { killer = "Kor", kclass = "ROGUE", klevel = 14 })
			assert.same({ "pk|lost|Zug|WARLOCK|20", "pk|lost|Kor|ROGUE|14" }, lines())
		end)

		it("counts a battleground loss", function()
			boot()
			enterBattleground()
			ns.Emit("DIED", { killer = "Zug", kclass = "WARLOCK" })
			assert.equal(1, counts().bgLost)
		end)

		it("writes nothing for a creature or for a killer with no player sign", function()
			boot()
			ns.Emit("DIED", { killer = "Lobo", npc = 299, kclass = "ROGUE" })
			ns.Emit("DIED", { killer = "Lobo", kclass = "normal" })
			ns.Emit("DIED", "bad")
			assert.same({}, lines())
		end)

		it("writes the fallback loss 6 s after PLAYER_DEAD when no death line came", function()
			boot()
			fightStart()
			target(kor())
			units.target = nil
			wow.advance(8)
			wow.fire("PLAYER_DEAD")
			wow.advance(5.9)
			assert.equal(1, #lines())
			wow.advance(0.1)
			assert.same("pk|lost|Kor Ash|ROGUE|14", lines()[2])
			ns.Emit("DIED", { killer = "Kor Ash", kclass = "ROGUE" })
			assert.equal(2, #lines())
		end)

		it("cancels the fallback for a creature's death line", function()
			boot()
			fightStart()
			target(kor())
			units.target = nil
			wow.advance(8)
			die({ { timestamp = 7, sourceGUID = "Creature-0-1-2-3-299-0000", sourceName = "Lobo" } })
			wow.advance(7)
			assert.same({ "ep|Kor Ash|ROGUE|Orc|14" }, lines())
		end)

		it("starts no fallback for an enemy only targeted or fought too long ago", function()
			boot()
			target(kor())
			wow.fire("PLAYER_DEAD")
			wow.advance(7)
			fightStart()
			target(kor())
			units.target = nil
			wow.advance(46)
			wow.fire("PLAYER_DEAD")
			wow.advance(7)
			assert.equal(1, #lines())
		end)

		it("drops a fallback when a newer PLAYER_DEAD replaces it", function()
			boot()
			fightStart()
			target(kor())
			wow.fire("PLAYER_DEAD")
			wow.advance(3)
			ns.Emit("DIED", { killer = "Lobo", npc = 299 })
			wow.advance(31)
			target(kor())
			wow.fire("PLAYER_DEAD")
			wow.advance(7)
			assert.same("pk|lost|Kor Ash|ROGUE|14", lines()[2])
			assert.equal(2, #lines())
		end)
	end)

	describe("duels", function()
		it("writes du lost for a Spanish duel line after a duel to the death", function()
			boot({ player = { name = "Mookz" } })
			wow.fire("DUEL_TO_THE_DEATH_REQUESTED", "Immar-Stone")
			wow.fire("CHAT_MSG_SYSTEM", "Immar Stone ha derrotado a Mookz en un duelo.")
			assert.same({ "du|lost|Immar Stone" }, lines())
			assert.equal(1, counts().duel_lost)
			assert.equal(1, counts().duelDeath)
		end)

		it("writes won with the class from memory, and fled", function()
			boot({ player = { name = "Mookz" } })
			units.target = kor({ faction = { "Alliance", "Alianza" } })
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.fire("DUEL_REQUESTED", "Kor-Ash")
			wow.fire("CHAT_MSG_SYSTEM", "Mookz Hill ha derrotado a Kor Ash en un duelo.")
			wow.fire("DUEL_REQUESTED", "Kor-Ash")
			wow.fire("CHAT_MSG_SYSTEM", "Mookz ha huido de Kor Ash en un duelo.")
			assert.same({ "du|won|Kor Ash|ROGUE", "du|fled|Kor Ash|ROGUE" }, lines())
			assert.equal(1, counts()["duel_won:ROGUE"])
			assert.equal(1, counts().duel_fled)
			assert.is_nil(counts().duelDeath)
		end)

		it("forgets a declined duel to the death, so a later duel is not one", function()
			boot({ player = { name = "Mookz" } })
			wow.fire("DUEL_TO_THE_DEATH_REQUESTED", "Kor-Ash")
			wow.fire("DUEL_FINISHED")
			wow.advance(3)
			wow.fire("CHAT_MSG_SYSTEM", "Mookz ha derrotado a Kor Ash en un duelo.")
			assert.same({ "du|won|Kor Ash" }, lines())
			assert.is_nil(counts().duelDeath)
		end)

		it("keeps the duel to the death when the end event comes before the result line", function()
			boot({ player = { name = "Mookz" } })
			wow.fire("DUEL_TO_THE_DEATH_REQUESTED", "Kor-Ash")
			wow.fire("DUEL_FINISHED")
			wow.fire("CHAT_MSG_SYSTEM", "Mookz ha derrotado a Kor Ash en un duelo.")
			wow.advance(3)
			assert.equal(1, counts().duelDeath)
		end)

		it("reads no duel line without the GlobalStrings formats", function()
			boot({
				player = { name = "Mookz" },
				strings = { DUEL_WINNER_KNOCKOUT = false, DUEL_WINNER_RETREAT = false },
			})
			wow.fire("CHAT_MSG_SYSTEM", "Mookz ha derrotado a Bob en un duelo.")
			assert.same({}, lines())
		end)

		it("ignores other people's duels and other lines", function()
			boot({ player = { name = "Mookz" } })
			wow.fire("CHAT_MSG_SYSTEM", "Ann ha derrotado a Bob en un duelo.")
			wow.fire("CHAT_MSG_SYSTEM", "Mookzer ha huido de Bob en un duelo.")
			wow.fire("CHAT_MSG_SYSTEM", "Has aprendido un nuevo hechizo: Bola de Fuego.")
			wow.fire("CHAT_MSG_SYSTEM", nil)
			assert.same({}, lines())
		end)

		it("writes no line with du off and still counts", function()
			boot({ player = { name = "Mookz" } })
			ns.Settings.SetKind("du", false)
			wow.fire("CHAT_MSG_SYSTEM", "Mookz ha derrotado a Bob en un duelo.")
			assert.same({}, lines())
			assert.equal(1, counts().duel_won)
		end)
	end)

	describe("battlegrounds", function()
		local SCORE = { honorableKills = 7, killingBlows = 3, deaths = 2, honorGained = 150 }

		it("writes bg won with the score when you leave", function()
			boot({ pvp = { score = SCORE } })
			enterBattleground()
			assert.equal(1, wow.score_asks)
			wow.advance(600.4)
			wow.fire("PVP_MATCH_COMPLETE", 1, 600)
			wow.fire("PVP_MATCH_COMPLETE", 0, 600)
			leaveBattleground()
			assert.same({ "bg|Garganta Grito de Guerra|won|600|150|7|3|2" }, lines())
			local c = counts()
			assert.equal(1, c.bg_won)
			assert.equal(600, c.bgSec)
			assert.equal(1, c["bgPlayed:Garganta Grito de Guerra"])
			assert.equal(1, c["bgWon:Garganta Grito de Guerra"])
			assert.equal(7, c.bgBest)
			assert.equal(7, c["bgBest:Garganta Grito de Guerra"])
			assert.is_nil(pvp().Tally())
		end)

		it("writes left with the tally when no winner was seen, and keeps the best", function()
			boot()
			journal():Counts("pvp").bgBest = 9
			enterBattleground()
			honor("Se te han concedido 12 puntos de honor.")
			wow.advance(60)
			leaveBattleground()
			assert.same({ "bg|Garganta Grito de Guerra|left|60|12|0" }, lines())
			assert.equal(9, counts().bgBest)
		end)

		it("takes the loser side from GetBattlefieldWinner and logs a score error", function()
			boot({ pvp = { scoreError = "secret" } })
			enterBattleground()
			wow.fire("UPDATE_BATTLEFIELD_SCORE")
			wow.pvp.winner = 0
			wow.fire("UPDATE_BATTLEFIELD_SCORE")
			leaveBattleground()
			assert.same({ "bg|Garganta Grito de Guerra|lost|0|0|0" }, lines())
			assert.equal("Memories_Social:score", ns.Errors()[1].where)
		end)

		it("keeps reading the score after the winner, since the final scoreboard can come later", function()
			boot({ pvp = { score = { honorableKills = 0 } } })
			enterBattleground()
			wow.fire("PVP_MATCH_COMPLETE", 1, 60)
			wow.pvp.score = SCORE
			wow.fire("UPDATE_BATTLEFIELD_SCORE")
			wow.pvp.scoreError = "gone"
			wow.fire("UPDATE_BATTLEFIELD_SCORE")
			leaveBattleground()
			assert.same({ "bg|Garganta Grito de Guerra|won|0|150|7|3|2" }, lines())
		end)

		it("writes left after a draw", function()
			boot()
			wow.fire("PVP_MATCH_COMPLETE", 1, 60)
			enterBattleground()
			wow.fire("PVP_MATCH_COMPLETE", 255, 60)
			wow.fire("PVP_MATCH_COMPLETE", 1, 60)
			leaveBattleground()
			assert.same({ "bg|Garganta Grito de Guerra|left|0|0|0" }, lines())
			assert.equal(1, counts().bg_left)
		end)

		it("writes the tally when the client has no score", function()
			boot()
			_G.C_PvP.GetScoreInfoByPlayerGuid = nil
			enterBattleground()
			wow.fire("PVP_MATCH_COMPLETE", 1, 60)
			leaveBattleground()
			assert.same({ "bg|Garganta Grito de Guerra|won|0|0|0" }, lines())
		end)

		it("reads the active match winner only when the match is over", function()
			boot({ player = { faction = HORDE }, pvp = { matchWinner = 0 } })
			enterBattleground()
			wow.fire("UPDATE_BATTLEFIELD_SCORE")
			assert.is_nil(pvp().Tally().won)
			wow.pvp.complete = true
			wow.fire("UPDATE_BATTLEFIELD_SCORE")
			assert.is_true(pvp().Tally().won)
		end)

		it("checks 2 s after entering the world, with an unknown name", function()
			boot()
			wow.instance = { type = "pvp" }
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			wow.advance(1.9)
			assert.is_nil(pvp().Tally())
			wow.advance(0.1)
			assert.equal("?", pvp().Tally().name)
			wow.instance = nil
			wow.fire("UPDATE_BATTLEFIELD_STATUS", 1)
			assert.same({ "bg|?|left|0|0|0" }, lines())
		end)

		it("counts the queued seconds", function()
			boot({ pvp = { queues = { "queued", "none" } } })
			wow.fire("UPDATE_BATTLEFIELD_STATUS", 1)
			wow.advance(90.4)
			wow.fire("UPDATE_BATTLEFIELD_STATUS", 1)
			wow.pvp.queues[1] = "confirm"
			wow.fire("UPDATE_BATTLEFIELD_STATUS", 1)
			assert.equal(90, counts().queueSec)
		end)

		it("ends the queue of a slot above the max battlefield id", function()
			boot({ pvp = { queues = { "none", "queued" } } })
			wow.fire("UPDATE_BATTLEFIELD_STATUS", 2)
			wow.advance(30)
			wow.pvp.queues = { "none" }
			wow.fire("UPDATE_BATTLEFIELD_STATUS", 2)
			assert.equal(30, counts().queueSec)
			wow.advance(3600)
			wow.pvp.queues = { "none", "queued" }
			wow.fire("UPDATE_BATTLEFIELD_STATUS", 2)
			wow.advance(10)
			wow.pvp.queues = { "none", "none" }
			wow.fire("UPDATE_BATTLEFIELD_STATUS", 2)
			assert.equal(40, counts().queueSec)
		end)

		it("writes no line with bg off and still counts", function()
			boot()
			ns.Settings.SetKind("bg", false)
			enterBattleground()
			leaveBattleground()
			assert.same({}, lines())
			assert.equal(1, counts().bg_left)
		end)
	end)

	describe("rank", function()
		it("writes rank 0 once at login and snaps the level", function()
			boot({ pvp = { renown = 0, points = 0, threshold = 2000, currency = { [1901] = 40 } } })
			assert.same({ "rk|0|Civil" }, rankLines())
			assert.same(
				{ rank = 0, title = "Civil", points = 0, threshold = 2000, highest = 0, kills = 0, honor = 40 },
				journal():Snap(10, "pvp")
			)
			assert.equal(0, counts().highestRank)
			ns = wow.reload()
			wow.advance(5)
			assert.equal(1, #rankLines())
		end)

		it("writes a new rank with its title and only snaps the same rank", function()
			boot({ pvp = { renown = 2, points = 100, threshold = 2000, maxRank = 8, currency = { [1792] = 5 } } })
			assert.same({ "rk|2|Cabo" }, rankLines())
			wow.pvp.points = 500
			wow.fire("UPDATE_FACTION")
			wow.advance(2)
			assert.equal(1, #rankLines())
			assert.equal(500, journal():Snap(10, "pvp").points)
			assert.equal(5, journal():Snap(10, "pvp").honor)
			assert.equal(4, counts().highestRank)
			wow.pvp.renown = 3
			wow.fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
			wow.advance(2)
			assert.same({ "rk|2|Cabo", "rk|3|Sargento" }, rankLines())
			wow.pvp.renown = 9
			wow.fire("PLAYER_PVP_KILLS_CHANGED", "player")
			wow.advance(2)
			assert.same("rk|9", rankLines()[3])
			assert.equal(9, counts().highestRank)
		end)

		it("uses the gendered title, the rank base of the client and skips an unknown level", function()
			boot({ player = { faction = HORDE, level = wow.secret(10) } })
			_G.Enum.PvPRanks = { Rank_1 = 6 }
			_G.GetText = function(token, sex)
				return token == "PVP_RANK_6_0" and "Cabo" .. (sex == 3 and "a" or "") or token
			end
			wow.pvp.renown = 1
			wow.fire("UPDATE_FACTION")
			wow.advance(2)
			assert.same({ "rk|1|Caboa" }, rankLines())
			assert.is_nil(journal():Snap(10, "pvp"))
		end)

		it("writes nothing without the rank faction", function()
			boot()
			assert.same({}, rankLines())
		end)

		it("compares a restored journal with the current rank", function()
			boot({ pvp = { renown = 2 } })
			journal():State("pvp").rank = nil
			ns.Emit("RESTORED", "Memories_Social")
			wow.advance(2)
			assert.same({ "rk|2|Cabo", "rk|2|Cabo" }, rankLines())
		end)

		it("keeps the rank with rk off", function()
			boot({ pvp = { renown = 2 } })
			ns.Settings.SetKind("rk", false)
			wow.pvp.renown = 3
			wow.fire("UPDATE_FACTION")
			wow.advance(2)
			ns.Settings.SetKind("rk", true)
			wow.fire("UPDATE_FACTION")
			wow.advance(2)
			assert.same({ "rk|2|Cabo" }, rankLines())
		end)
	end)
end)
