local wow = require("helpers.wow")

describe("deaths", function()
	local WOLF = "Creature-0-4389-0-47-525-00002B3A5C"
	local KOBOLD = "Creature-0-4389-0-47-6-00002B3A5D"
	local DEATH_KINDS = { de = true, gh = true, al = true, cc = true, lh = true, hc = true }

	local ns
	local died, alive, low

	-- Each line of the death kinds as "kind|fields", in journal order.
	local function lines()
		local out = {}
		for line in ns.Store.Core():Lines() do
			local k, rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(%w+)|?(.*)$")
			if DEATH_KINDS[k] then
				out[#out + 1] = rest == "" and k or k .. "|" .. rest
			end
		end
		return out
	end

	local function decoded(kind)
		for line in ns.Store.Core():Lines() do
			local ev = ns.Codec.DecodeLine(line)
			if ev.k == kind then
				return ev
			end
		end
	end

	local function counts()
		return ns.Store.Core():Counts("deaths")
	end

	local function state()
		return MemoriesCharDB.state.deaths
	end

	local function listen()
		died, alive, low = {}, {}, {}
		ns.Listen("DIED", function(_, info)
			died[#died + 1] = info
		end)
		ns.Listen("ALIVE", function(_, how)
			alive[#alive + 1] = how
		end)
		ns.Listen("LOW_HEALTH", function(_, combat)
			low[#low + 1] = combat
		end)
	end

	local function boot(opts)
		ns = wow.boot(opts)
		listen()
		return ns
	end

	local function die(recap)
		wow.recap = recap
		wow.flags.dead = true
		wow.fire("PLAYER_DEAD")
	end

	local function release()
		wow.flags.dead, wow.flags.ghost = false, true
		wow.fire("PLAYER_ALIVE")
	end

	local function back()
		wow.flags.dead, wow.flags.ghost = false, false
	end

	describe("death line", function()
		it("takes the killer of the last recap entry and its learned plain name", function()
			boot({ units = { target = { guid = WOLF, name = "Lobo sarnoso", level = 8, classification = "normal" } } })
			wow.fire("PLAYER_TARGET_CHANGED")
			die({
				{ timestamp = 10, sourceGUID = KOBOLD, sourceName = "Kóbold", amount = 5 },
				{ timestamp = 12, sourceGUID = WOLF, sourceName = "Lobo sarnoso Herrero", amount = 30 },
			})
			wow.advance(0.9)
			assert.same({}, lines())
			wow.advance(0.1)
			assert.same({ "de|Lobo sarnoso|525|||world||8|normal|30" }, lines())
			local ev = decoded("de")
			assert.same({ 1453, 5000, 2500 }, { ev.m, ev.x, ev.y })
			assert.equal(1, counts().total)
			assert.equal(1, counts().world)
			assert.equal(30, counts().hardest)
			assert.is_true(state().open)
			assert.equal(12, state().lastRecap)
			assert.same({
				{
					killer = "Lobo sarnoso",
					npc = 525,
					place = "world",
					boss = false,
					klevel = 8,
					kclass = "normal",
					amount = 30,
					byPlayer = false,
				},
			}, died)
		end)

		it("gives a tie of timestamps to the later entry and keeps the hardest blow as a maximum", function()
			boot()
			die({
				{ timestamp = 12, sourceGUID = KOBOLD, sourceName = "Kóbold", amount = 50 },
				{ timestamp = 12, sourceGUID = WOLF, sourceName = "Lobo", spellName = "Mordisco", amount = 20 },
			})
			wow.advance(1)
			assert.same({ "de|Lobo|525|Mordisco||world||||20" }, lines())
			back()
			wow.fire("PLAYER_ALIVE")
			die({ { timestamp = 40, sourceGUID = KOBOLD, sourceName = "Kóbold", amount = 10 } })
			wow.advance(1)
			assert.equal(20, counts().hardest)
			assert.equal(2, counts().total)
		end)

		it("writes no second line for the same recap", function()
			boot()
			die({ { timestamp = 50, sourceGUID = WOLF, sourceName = "Lobo", amount = 9 } })
			wow.advance(1)
			back()
			wow.fire("PLAYER_ALIVE")
			die(wow.recap)
			wow.advance(1)
			assert.same({ "de|Lobo|525|||world||||9", "al|res" }, lines())
			assert.equal(1, counts().total)
			assert.equal(1, #died)
			assert.is_true(state().open)
		end)

		it("still writes gh for a released ghost of a deduped death", function()
			boot()
			die({ { timestamp = 50, sourceGUID = WOLF, sourceName = "Lobo", amount = 9 } })
			wow.advance(1)
			back()
			wow.fire("PLAYER_ALIVE")
			die(wow.recap)
			wow.advance(0.5)
			release()
			wow.advance(1)
			assert.same({ "de|Lobo|525|||world||||9", "al|res", "gh" }, lines())
		end)

		it("writes a bare line without a recap", function()
			boot()
			die(nil)
			wow.advance(1)
			assert.same({ "de|||||world" }, lines())
		end)

		it("writes ? for a secret killer name and skips secret values", function()
			boot()
			die({ { timestamp = wow.secret(5), sourceGUID = wow.secret(WOLF), sourceName = wow.secret("Lobo") } })
			wow.advance(1)
			assert.same({ "de|?||||world" }, lines())
		end)

		it("ignores a recap that is secret or fails", function()
			boot()
			wow.recap = { { timestamp = 5, sourceName = "Lobo" } }
			C_DeathRecap.GetRecapEvents = function()
				return wow.secret({})
			end
			die(wow.recap)
			wow.advance(1)
			back()
			wow.fire("PLAYER_ALIVE")
			C_DeathRecap.GetRecapEvents = function()
				error("no recap")
			end
			die(wow.recap)
			wow.advance(1)
			_G.C_DeathRecap = nil
			back()
			wow.fire("PLAYER_ALIVE")
			die(wow.recap)
			wow.advance(1)
			assert.same({ "de|||||world", "al|res", "de|||||world", "al|res", "de|||||world" }, lines())
		end)

		it("names the environment in lower case and counts it", function()
			boot()
			die({ { timestamp = 3, environmentalType = "Falling", amount = 120 } })
			wow.advance(1)
			assert.same({ "de||||falling|world||||120" }, lines())
			assert.equal(1, counts()["env.falling"])
		end)

		it("marks another player as the killer with the level and class learned from a nameplate", function()
			local rogue = "Player-1234-0BBBBBB1"
			boot({
				units = { nameplate3 = { guid = rogue, name = "Kor", level = 12, class = { "Pícaro", "ROGUE", 4 } } },
			})
			wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
			die({ { timestamp = 7, sourceGUID = rogue, sourceName = "Kor", spellName = "Puñalada", amount = 44 } })
			wow.advance(1)
			assert.same({ "de|Kor||Puñalada||world||12|ROGUE|44|1" }, lines())
			assert.equal(1, counts().player)
			assert.is_true(died[1].byPlayer)
		end)

		it("never takes the player's own GUID for a player killer", function()
			boot()
			die({ { timestamp = 7, sourceGUID = wow.player.guid, sourceName = "Kaelys", amount = 3 } })
			wow.advance(1)
			assert.same({ "de|Kaelys||||world||||3" }, lines())
			assert.is_nil(counts().player)
		end)

		it("marks a boss fight, which a loading screen ends", function()
			boot()
			wow.fire("ENCOUNTER_START", 1, "Jefe", 1, 5)
			die(nil)
			wow.advance(1)
			back()
			wow.fire("PLAYER_ALIVE")
			wow.fire("LOADING_SCREEN_ENABLED")
			die(nil)
			wow.advance(1)
			back()
			wow.fire("PLAYER_ALIVE")
			wow.fire("ENCOUNTER_START", 1, "Jefe", 1, 5)
			wow.fire("ENCOUNTER_END", 1, "Jefe", 1, 5, 1)
			die(nil)
			wow.advance(1)
			assert.same({ "de|||||world|1", "al|res", "de|||||world", "al|res", "de|||||world" }, lines())
			assert.equal(1, counts().boss)
		end)

		it("marks a world boss killer as a boss", function()
			local guid = "Creature-0-4389-0-47-6109-00002B3A5C"
			boot({ units = { target = { guid = guid, name = "Azuregos", level = 63, classification = "worldboss" } } })
			wow.fire("PLAYER_TARGET_CHANGED")
			die({ { timestamp = 9, sourceGUID = guid, sourceName = "Azuregos", amount = 900 } })
			wow.advance(1)
			assert.same({ "de|Azuregos|6109|||world|1|63|worldboss|900" }, lines())
		end)

		it("names the instance, leaves the position empty and counts a dungeon death", function()
			boot()
			wow.instance = { type = "party", name = "Las Minas de la Muerte", id = 36 }
			die(nil)
			wow.advance(1)
			assert.same({ "de|||||Las Minas de la Muerte" }, lines())
			assert.is_nil(decoded("de").m)
			assert.equal(1, counts().dungeon)
		end)

		it("marks a battleground death as pvp", function()
			boot()
			wow.instance = { type = "pvp", name = "Garganta Grito de Guerra" }
			die(nil)
			wow.advance(1)
			assert.same({ "de|||||Garganta Grito de Guerra||||||pvp" }, lines())
			assert.equal(1, counts().battleground)
		end)

		it("takes the last trail point outdoors without a map position", function()
			boot()
			wow.advance(2)
			wow.map.x, wow.map.y = nil, nil
			die(nil)
			wow.advance(1)
			local ev = decoded("de")
			assert.same({ 1453, 5000, 2500 }, { ev.m, ev.x, ev.y })
		end)

		it("waits 1 s for a death that the client reports late, then writes it at once", function()
			boot()
			wow.fire("PLAYER_DEAD")
			wow.flags.dead = true
			wow.advance(1)
			assert.same({ "de|||||world" }, lines())
			wow.flags.dead = false
			wow.fire("PLAYER_DEAD")
			wow.advance(1)
			assert.same({ "de|||||world" }, lines())
		end)

		it("writes gh for a release during the wait for a late death", function()
			boot()
			wow.fire("PLAYER_DEAD")
			release()
			wow.advance(1)
			assert.same({ "de|||||world", "gh" }, lines())
			assert.same({ dead = true, ghost = true }, ns.Deaths.State())
		end)

		it("ignores PLAYER_DEAD while already dead", function()
			boot()
			die(nil)
			wow.fire("PLAYER_DEAD")
			wow.advance(1)
			wow.fire("PLAYER_DEAD")
			wow.advance(1)
			assert.same({ "de|||||world" }, lines())
		end)

		it("drops a death that the client takes back before the recap read", function()
			boot()
			die(nil)
			wow.flags.dead = false
			wow.advance(1)
			assert.same({}, lines())
			assert.is_nil(counts().total)
			die(nil)
			wow.advance(1)
			assert.same({ "de|||||world" }, lines())
		end)

		it("writes hc after de on a Hardcore character", function()
			boot({ rules = { hardcore = true } })
			die({ { timestamp = 4, sourceGUID = WOLF, sourceName = "Lobo", amount = 9 } })
			wow.advance(1)
			assert.same({ "de|Lobo|525|||world||||9", "hc|Lobo" }, lines())
		end)
	end)

	describe("release and revive", function()
		it("does nothing on PLAYER_ALIVE or PLAYER_UNGHOST while alive", function()
			boot()
			wow.fire("PLAYER_ALIVE")
			wow.fire("PLAYER_UNGHOST")
			assert.same({}, lines())
			assert.same({}, alive)
		end)

		it("writes al|corpse for a ghost without a world position", function()
			boot()
			wow.world = nil
			die(nil)
			wow.advance(1)
			release()
			back()
			wow.fire("PLAYER_UNGHOST")
			assert.same({ "de|||||world", "gh", "al|corpse" }, lines())
		end)

		it("does nothing on PLAYER_ALIVE while still dead and not a ghost", function()
			boot()
			die(nil)
			wow.advance(1)
			wow.fire("PLAYER_ALIVE")
			assert.same({ "de|||||world" }, lines())
			assert.same({ dead = true, ghost = false }, ns.Deaths.State())
		end)

		it("writes al|res with the name of the player who offered", function()
			boot()
			die(nil)
			wow.advance(1)
			wow.fire("RESURRECT_REQUEST", "Anna")
			back()
			wow.fire("PLAYER_ALIVE")
			assert.same({ "de|||||world", "al|res|Anna" }, lines())
			assert.equal(1, counts()["revive.res"])
			assert.same({ "res" }, alive)
			assert.is_false(state().open)
			assert.same({ dead = false, ghost = false }, ns.Deaths.State())
		end)

		it("writes al|spirit for a ghost 200 yd from the body in the same world instance", function()
			boot()
			die(nil)
			wow.advance(1)
			release()
			wow.world = { x = 200, y = 0, inst = 0 }
			back()
			wow.fire("PLAYER_UNGHOST")
			assert.same({ "de|||||world", "gh", "al|spirit" }, lines())
			assert.equal(1, counts()["revive.spirit"])
		end)

		it("writes al|corpse for a ghost near the body or in another world instance", function()
			boot()
			die(nil)
			wow.advance(1)
			release()
			wow.world = { x = 30, y = 0, inst = 0 }
			back()
			wow.fire("PLAYER_UNGHOST")
			die(nil)
			wow.advance(1)
			release()
			wow.world = { x = 3000, y = 0, inst = 1 }
			back()
			wow.fire("PLAYER_UNGHOST")
			assert.same({ "de|||||world", "gh", "al|corpse", "de|||||world", "gh", "al|corpse" }, lines())
		end)

		it("reads the revive marks in their order and windows", function()
			boot()
			local function revive(fn)
				die(nil)
				wow.advance(1)
				release()
				fn()
				back()
				wow.fire("PLAYER_UNGHOST")
			end
			revive(function()
				C_DeathInfo.UseSelfResurrectOption(1, 1)
				AcceptResurrect()
			end)
			revive(function()
				AcceptResurrect()
				wow.advance(15)
			end)
			revive(function()
				wow.fire("RESURRECT_REQUEST", "Anna")
				wow.advance(91)
				wow.fire("CONFIRM_XP_LOSS")
			end)
			revive(function()
				RetrieveCorpse()
				wow.advance(30)
			end)
			revive(function()
				RetrieveCorpse()
				wow.advance(31)
				wow.world = { x = 61, y = 0, inst = 0 }
			end)
			local how = {}
			for _, line in ipairs(lines()) do
				if line:match("^al") then
					how[#how + 1] = line
				end
			end
			assert.same({ "al|soulstone", "al|res", "al|spirit", "al|corpse", "al|spirit" }, how)
			assert.same({ "soulstone", "res", "spirit", "corpse", "spirit" }, alive)
			assert.equal(1, wow.res.self)
		end)

		it("gives an offer the revive over a later corpse click", function()
			boot()
			die(nil)
			wow.advance(1)
			release()
			wow.fire("RESURRECT_REQUEST", "Anna")
			wow.fire("CONFIRM_XP_LOSS")
			RetrieveCorpse()
			back()
			wow.fire("PLAYER_UNGHOST")
			assert.same({ "res" }, alive)
		end)

		it("writes de then gh when the ghost step comes before the recap read", function()
			boot()
			die(nil)
			wow.advance(0.5)
			release()
			assert.same({}, lines())
			wow.advance(1)
			assert.same({ "de|||||world", "gh" }, lines())
			assert.is_true(state().ghost)
		end)

		it("writes the pending de before al", function()
			boot()
			die(nil)
			wow.advance(0.5)
			back()
			wow.fire("PLAYER_ALIVE")
			wow.advance(1)
			assert.same({ "de|||||world", "al|res" }, lines())
		end)

		it("writes gh once per death", function()
			boot()
			die(nil)
			wow.advance(1)
			release()
			wow.fire("PLAYER_ALIVE")
			assert.same({ "de|||||world", "gh" }, lines())
		end)
	end)

	describe("login", function()
		local TRAIL = { v = 1, chunks = { { s = 1, t = 100, m = 1429, n = 2, d = "0,3900,5900,-;2,4000,6000" } } }

		it("writes a bare de at the last saved trail point, then gh, for a ghost with no open death", function()
			boot({ flags = { ghost = true }, saved = { MemoriesCharDB = { trail = TRAIL } } })
			assert.same({ "de|||||world", "gh" }, lines())
			local ev = decoded("de")
			assert.same({ 1429, 4000, 6000 }, { ev.m, ev.x, ev.y })
			assert.is_true(state().open)
			assert.equal(1, counts().total)
		end)

		it("keeps the map position at login when the trail has no point", function()
			boot({ flags = { ghost = true } })
			assert.same({ "de|||||world", "gh" }, lines())
			local ev = decoded("de")
			assert.same({ 1453, 5000, 2500 }, { ev.m, ev.x, ev.y })
		end)

		it("writes the recap death at login and leaves the position empty inside an instance", function()
			ns =
				wow.boot({ flags = { dead = true }, login = false, recap = { { timestamp = 8, sourceName = "Lobo" } } })
			wow.instance = { type = "party", name = "Las Minas de la Muerte" }
			wow.login()
			assert.same({ "de|Lobo||||Las Minas de la Muerte" }, lines())
			assert.is_nil(decoded("de").m)
		end)

		it("writes nothing new after a reload while the death is open", function()
			boot()
			die(nil)
			wow.advance(1)
			release()
			wow.opts.flags = { ghost = true }
			ns = wow.reload()
			listen()
			assert.same({ "de|||||world", "gh" }, lines())
			assert.same({ dead = true, ghost = true }, ns.Deaths.State())
			back()
			wow.fire("PLAYER_UNGHOST")
			assert.same({ "de|||||world", "gh", "al|corpse" }, lines())
		end)

		it("writes gh at login for a ghost whose gh is missing", function()
			boot()
			die(nil)
			wow.advance(1)
			wow.opts.flags = { ghost = true }
			ns = wow.reload()
			assert.same({ "de|||||world", "gh" }, lines())
		end)

		it("closes an open death at a login while alive", function()
			boot({ saved = { MemoriesCharDB = { state = { deaths = { open = true } } } } })
			assert.is_false(state().open)
			assert.same({}, lines())
		end)

		it("records nothing with a read-only journal", function()
			boot({ flags = { dead = true }, saved = { MemoriesCharDB = { schema = 99 } } })
			wow.fire("PLAYER_DEAD")
			wow.advance(1)
			assert.is_nil(MemoriesCharDB.state)
			assert.same({ dead = false, ghost = false }, ns.Deaths.State())
			ns.Deaths.StartVisit()
			assert.equal(0, ns.Deaths.VisitDeaths())
			assert.equal(0, ns.Deaths.EndVisit())
			assert.is_nil(MemoriesCharDB.state)
		end)
	end)

	describe("names", function()
		it("keeps the shortest creature name with its level and class", function()
			boot({ units = { mouseover = { guid = WOLF, name = "Lobo sarnoso Herrero", level = 7 } } })
			wow.fire("UPDATE_MOUSEOVER_UNIT")
			wow.units.mouseover = { guid = WOLF, name = "Lobo sarnoso", level = 8, classification = "elite" }
			wow.fire("UPDATE_MOUSEOVER_UNIT")
			wow.units.mouseover = { guid = WOLF, name = "Lobo sarnoso largo", level = 9 }
			wow.fire("UPDATE_MOUSEOVER_UNIT")
			die({ { timestamp = 1, sourceGUID = WOLF, sourceName = "Lobo sarnoso Herrero" } })
			wow.advance(1)
			assert.same({ "de|Lobo sarnoso|525|||world||9|elite" }, lines())
		end)

		it("learns no name inside an instance, nor of a unit without a GUID or a name", function()
			boot({ units = { target = { guid = WOLF, name = "Lobo" } } })
			wow.instance = { type = "party", name = "Las Minas de la Muerte" }
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.instance = nil
			wow.units.target = { name = "Lobo" }
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.units.target = { guid = WOLF }
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.fire("NAME_PLATE_UNIT_ADDED", nil)
			die({ { timestamp = 1, sourceGUID = WOLF, sourceName = "Lobo Herrero" } })
			wow.advance(1)
			assert.same({ "de|Lobo Herrero|525|||world" }, lines())
		end)

		it("ignores new creatures once the cache is full", function()
			boot()
			ns.Deaths.MAX_CREATURES = 1
			wow.units.target = { guid = KOBOLD, name = "Kóbold" }
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.units.target = { guid = WOLF, name = "Lobo" }
			wow.fire("PLAYER_TARGET_CHANGED")
			die({ { timestamp = 1, sourceGUID = WOLF, sourceName = "Lobo Herrero" } })
			wow.advance(1)
			assert.same({ "de|Lobo Herrero|525|||world" }, lines())
		end)

		it("keeps a learned player level and class over a later secret read", function()
			boot()
			wow.units.target = { guid = "Player-1-01", name = "Ana", level = 5, class = { "Maga", "MAGE", 8 } }
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.units.target = { guid = "Player-1-01", name = "Ana", level = wow.secret(5) }
			wow.fire("PLAYER_TARGET_CHANGED")
			die({ { timestamp = 1, sourceGUID = "Player-1-01", sourceName = "Ana" } })
			wow.advance(1)
			assert.same({ "de|Ana||||world||5|MAGE||1" }, lines())
		end)

		it("clears the player cache once it is full", function()
			boot()
			ns.Deaths.MAX_PLAYERS = 1
			wow.units.target = { guid = "Player-1-01", name = "Ana", level = 5, class = { "Maga", "MAGE", 8 } }
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.units.target = { guid = "Player-1-02", name = "Bea", level = 6, class = { "Maga", "MAGE", 8 } }
			wow.fire("PLAYER_TARGET_CHANGED")
			die({ { timestamp = 1, sourceGUID = "Player-1-01", sourceName = "Ana" } })
			wow.advance(1)
			back()
			wow.fire("PLAYER_ALIVE")
			die({ { timestamp = 2, sourceGUID = "Player-1-02", sourceName = "Bea" } })
			wow.advance(1)
			assert.same({ "de|Ana||||world|||||1", "al|res", "de|Bea||||world||6|MAGE||1" }, lines())
		end)

		it("counts a UnitGUID error silently", function()
			boot()
			local real = UnitGUID
			_G.UnitGUID = function(u)
				if u == "nameplate1" then
					error("restricted unit")
				end
				return real(u)
			end
			wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
			assert.equal(1, ns.Deaths.GuidErrors())
			assert.same({}, wow.errors)
			assert.same({}, MemoriesDB.errors)
		end)
	end)

	describe("close calls", function()
		local function flash(seconds)
			LowHealthFrame:Show()
			wow.advance(seconds)
			LowHealthFrame:Hide()
		end

		it("writes lh at the show and cc after the flash ends and 3 s pass alive", function()
			boot()
			flash(2.4)
			assert.same({ "lh|0" }, lines())
			wow.advance(2.9)
			assert.same({ "lh|0" }, lines())
			wow.advance(0.2)
			assert.same({ "lh|0", "cc|2|0" }, lines())
			assert.same({ false }, low)
			assert.equal(1, counts().lowHealth)
			assert.equal(1, counts().closeCalls)
		end)

		it("adds each show of one episode and writes cc at the start position", function()
			boot()
			wow.combat = true
			flash(1)
			wow.map.x = 0.6
			wow.combat = false
			flash(0.2)
			wow.advance(3)
			assert.same({ "lh|1", "lh|0", "cc|1|1" }, lines())
			local cc = decoded("cc")
			assert.equal(5000, cc.x)
			assert.same({ true, false }, low)
		end)

		it("writes no cc when the player dies within 3 s", function()
			boot()
			flash(1)
			wow.advance(1)
			wow.fire("PLAYER_DEAD")
			wow.flags.dead = false
			wow.advance(5)
			assert.same({ "lh|0" }, lines())
		end)

		it("waits for the end of combat", function()
			boot()
			wow.combat = true
			flash(1)
			wow.advance(3)
			assert.same({ "lh|1" }, lines())
			wow.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			wow.advance(3)
			assert.same({ "lh|1", "cc|1|1" }, lines())
		end)

		it("does not settle while the flash still shows", function()
			boot()
			flash(1)
			LowHealthFrame.shown = true
			wow.advance(3)
			assert.same({ "lh|0" }, lines())
		end)

		it("counts UnitAffectingCombat as combat", function()
			boot({ flags = { combat = true } })
			flash(1)
			assert.same({ "lh|1" }, lines())
		end)

		it("skips a show while dead or with a fullscreen panel", function()
			boot()
			wow.panels.fullscreen = {}
			flash(1)
			wow.panels.fullscreen = nil
			wow.flags.dead = true
			flash(1)
			wow.advance(5)
			assert.same({}, lines())
			assert.same({}, low)
		end)

		it("drops the close call when the journal changed", function()
			boot()
			flash(1)
			ns.Store.Reopen()
			wow.advance(3)
			assert.same({ "lh|0" }, lines())
			assert.is_nil(counts().closeCalls)
		end)

		it("hooks a LowHealthFrame that appears within 3 s of login", function()
			boot({ lowHealthFrame = false })
			CreateFrame("Frame", "LowHealthFrame")
			wow.advance(3)
			flash(1)
			assert.same({ "lh|0" }, lines())
		end)

		it("records no flash when LowHealthFrame never appears", function()
			boot({ lowHealthFrame = false })
			wow.advance(10)
			assert.same({}, lines())
		end)
	end)

	describe("dungeon visit", function()
		it("counts the deaths of an open visit, also with de off", function()
			boot()
			ns.Settings.SetKind("de", false)
			die(nil)
			wow.advance(1)
			assert.equal(0, ns.Deaths.VisitDeaths())
			back()
			wow.fire("PLAYER_ALIVE")
			ns.Deaths.StartVisit()
			die(nil)
			wow.advance(1)
			assert.equal(1, ns.Deaths.VisitDeaths())
			assert.equal(1, state().visit)
			assert.equal(1, ns.Deaths.EndVisit())
			assert.is_nil(state().visit)
			assert.equal(0, ns.Deaths.EndVisit())
		end)

		it("writes the death over a damaged saved visit count and hardest blow", function()
			boot()
			ns.Deaths.StartVisit()
			state().visit = {}
			ns.Store.Core():Counts("deaths").hardest = "x"
			die({ { timestamp = 3, sourceGUID = WOLF, sourceName = "Lobo", amount = 4 } })
			wow.advance(1)
			assert.equal(1, #died)
			assert.equal(4, counts().hardest)
			assert.equal(1, ns.Deaths.VisitDeaths())
		end)
	end)

	describe("low-health flag", function()
		it("mirrors the CVar at login and on CVAR_UPDATE", function()
			boot({ cvars = { doNotFlashLowHealthWarning = "1" } })
			assert.is_false(MemoriesCharDB.flags.lowHealthFlash)
			SetCVar("doNotFlashLowHealthWarning", "0")
			assert.is_true(MemoriesCharDB.flags.lowHealthFlash)
			wow.cvars.doNotFlashLowHealthWarning = "1"
			wow.fire("CVAR_UPDATE", "otherCVar", "1")
			assert.is_true(MemoriesCharDB.flags.lowHealthFlash)
		end)
	end)

	describe("kinds off", function()
		it("de off: no line, the counts, the open death and DIED go on", function()
			boot()
			ns.Settings.SetKind("de", false)
			die({ { timestamp = 3, sourceGUID = WOLF, sourceName = "Lobo", amount = 4 } })
			wow.advance(1)
			assert.same({}, lines())
			assert.equal(1, counts().total)
			assert.is_true(state().open)
			assert.equal(1, #died)
			assert.equal("Lobo", died[1].killer)
		end)

		it("gh off: no line, and the saved ghost step stops a second gh after a reload", function()
			boot()
			ns.Settings.SetKind("gh", false)
			die(nil)
			wow.advance(1)
			release()
			assert.is_true(state().ghost)
			ns.Settings.SetKind("gh", true)
			wow.opts.flags = { ghost = true }
			ns = wow.reload()
			assert.same({ "de|||||world" }, lines())
		end)

		it("al off: no line, the revive count, the closed death and ALIVE go on", function()
			boot()
			ns.Settings.SetKind("al", false)
			die(nil)
			wow.advance(1)
			back()
			wow.fire("PLAYER_ALIVE")
			assert.same({ "de|||||world" }, lines())
			assert.equal(1, counts()["revive.res"])
			assert.is_false(state().open)
			assert.same({ "res" }, alive)
		end)

		it("lh off: no line, the count and LOW_HEALTH go on", function()
			boot()
			ns.Settings.SetKind("lh", false)
			LowHealthFrame:Show()
			assert.same({}, lines())
			assert.equal(1, counts().lowHealth)
			assert.same({ false }, low)
		end)

		it("cc off: no line, the count goes on", function()
			boot()
			ns.Settings.SetKind("cc", false)
			LowHealthFrame:Show()
			wow.advance(2)
			LowHealthFrame:Hide()
			wow.advance(3)
			assert.same({ "lh|0" }, lines())
			assert.equal(1, counts().closeCalls)
		end)

		it("hc off: no line", function()
			boot({ rules = { hardcore = true } })
			ns.Settings.SetKind("hc", false)
			die(nil)
			wow.advance(1)
			assert.same({ "de|||||world" }, lines())
		end)
	end)
end)
