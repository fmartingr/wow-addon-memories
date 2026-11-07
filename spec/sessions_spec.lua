local wow = require("helpers.wow")

describe("sessions", function()
	local GUID = "Player-1234-0ABCDEF0"

	local function lines()
		local out = {}
		for line in wow.ns.Memories.Store.Core():Lines() do
			out[#out + 1] = line
		end
		return out
	end

	local function kinds(kind)
		local out = {}
		for _, line in ipairs(lines()) do
			local k, rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(%w+)|?(.*)$")
			if k == kind then
				out[#out + 1] = rest
			end
		end
		return out
	end

	local function chatFrame()
		local frame = CreateFrame("Frame", "ChatFrame1")
		frame:RegisterEvent("TIME_PLAYED_MSG")
		_G.CHAT_FRAMES = { "ChatFrame1", "ChatFrameMissing" }
		return frame
	end

	local function saved(prev, extra)
		local db = {
			MemoriesCharDB = {
				char = { guid = GUID, first = { t = 1, level = 10 } },
				sessions = { prev },
			},
		}
		for k, v in pairs(extra or {}) do
			db[k] = v
		end
		return db
	end

	describe("login and reload", function()
		it("writes in|login and pc|<id> and opens a session entry on a fresh login", function()
			local ns = wow.boot()
			local id = MemoriesDB.computer
			assert.matches("^%x%x%x%x%x%x$", id)
			assert.same({ "login" }, kinds("in"))
			assert.same({ id }, kinds("pc"))
			local entry = MemoriesCharDB.sessions[1]
			assert.equal(ns.Sessions.Current(), entry)
			assert.equal("login", entry.how)
			assert.equal(id, entry.computer)
			assert.equal(wow.wall, entry.start)
			assert.equal(wow.wall, entry.last)
			assert.is_number(entry.tz)
			assert.equal(wow.wall .. "||1453|5000|2500|in|login", lines()[1])
		end)

		it("writes out, then in|reload and no pc on a reload, with the same computer id", function()
			wow.boot()
			local id = MemoriesDB.computer
			wow.advance(30)
			wow.reload()
			assert.same({ "login", "reload" }, kinds("in"))
			assert.same({ "" }, kinds("out"))
			assert.same({ id }, kinds("pc"))
			assert.equal(id, MemoriesDB.computer)
			assert.equal(2, #MemoriesCharDB.sessions)
			assert.equal("reload", MemoriesCharDB.sessions[2].how)
			local all = lines()
			assert.matches("|out$", all[#all - 2])
			assert.matches("|in|reload$", all[#all - 1])
		end)

		it("writes nothing for a later entering-world event of the same load", function()
			wow.boot()
			local before = #lines()
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			wow.fire("PLAYER_ENTERING_WORLD", true, false)
			assert.equal(before, #lines())
			assert.equal(1, #MemoriesCharDB.sessions)
		end)

		it("stores the client clock's offset from UTC", function()
			local ns = wow.boot()
			_G.date = function(fmt)
				if fmt == "!*t" then
					return { year = 2026, yday = 311, hour = 23, min = 30 }
				end
				return { year = 2026, yday = 312, hour = 0, min = 30 }
			end
			assert.equal(3600, ns.Sessions.TimeZone(1))
			_G.date = function(fmt)
				if fmt == "!*t" then
					return { year = 2027, yday = 1, hour = 2, min = 0 }
				end
				return { year = 2026, yday = 365, hour = 21, min = 0 }
			end
			assert.equal(-5 * 3600, ns.Sessions.TimeZone(1))
		end)

		it("reads the realm rules once at login", function()
			local function rules()
				local f = MemoriesCharDB.flags
				return { hardcore = f.hardcore, selfFoundAllowed = f.selfFoundAllowed }
			end
			wow.boot({ rules = { hardcore = true, selfFound = false } })
			assert.same({ hardcore = true, selfFoundAllowed = false }, rules())
			wow.boot({ rules = { hardcore = wow.secret(true), selfFound = true } })
			assert.same({ selfFoundAllowed = true }, rules())
			wow.boot()
			assert.same({}, rules())
		end)
	end)

	describe("/played", function()
		it("asks 3 s after login, mutes the chat frames and writes pl", function()
			local ns = wow.boot()
			local frame = chatFrame()
			wow.advance(2.9)
			assert.equal(0, wow.played_asks)
			wow.advance(0.1)
			assert.equal(1, wow.played_asks)
			assert.is_false(frame:IsEventRegistered("TIME_PLAYED_MSG"))
			wow.fire("TIME_PLAYED_MSG", 7200, 600)
			assert.same({ "7200" }, kinds("pl"))
			assert.equal(7200, ns.Store.PlayedNow())
			assert.is_false(frame:IsEventRegistered("TIME_PLAYED_MSG"))
			wow.advance(0.5)
			assert.is_true(frame:IsEventRegistered("TIME_PLAYED_MSG"))
		end)

		it("listens again 10 s after the ask when no answer comes, and mutes once", function()
			local ns = wow.boot()
			local frame = chatFrame()
			wow.advance(3)
			ns.Sessions.RequestPlayed("dev")
			assert.equal(2, wow.played_asks)
			wow.advance(9.9)
			assert.is_false(frame:IsEventRegistered("TIME_PLAYED_MSG"))
			wow.advance(0.1)
			assert.is_true(frame:IsEventRegistered("TIME_PLAYED_MSG"))
		end)

		it("writes no pl for a dev ask or a typed /played, and stamps p after an answer", function()
			local ns = wow.boot()
			assert.equal("", ns.Codec.DecodeLine(lines()[1]).p or "")
			wow.fire("TIME_PLAYED_MSG", 100, 10)
			ns.Sessions.RequestPlayed("dev")
			wow.fire("TIME_PLAYED_MSG", 120, 30)
			assert.same({}, kinds("pl"))
			assert.equal(120, ns.Store.PlayedNow())
			assert.equal(120, ns.Codec.DecodeLine(ns.Store.Core():Write("ex", "a", "b")).p)
		end)

		it("sets played0 once and played1 on every answer", function()
			wow.boot()
			wow.advance(20)
			wow.fire("TIME_PLAYED_MSG", 1500, 100)
			local entry = MemoriesCharDB.sessions[1]
			assert.equal(1480, entry.played0)
			assert.equal(1500, entry.played1)
			wow.advance(10)
			wow.fire("TIME_PLAYED_MSG", 1510, 110)
			assert.equal(1480, entry.played0)
			assert.equal(1510, entry.played1)
		end)

		it("ignores a secret answer", function()
			local ns = wow.boot()
			wow.fire("TIME_PLAYED_MSG", wow.secret(100), 5)
			assert.is_nil(ns.Store.PlayedNow())
			assert.is_nil(MemoriesCharDB.sessions[1].played1)
		end)

		it("writes gp at the session start when more than 120 s are missing", function()
			local prev = { start = 1000, last = 1793000000, how = "login", played0 = 500, played1 = 1000 }
			local start = wow.wall
			wow.boot({ saved = saved(prev) })
			wow.advance(20)
			wow.fire("TIME_PLAYED_MSG", 1500, 100)
			assert.same({ "480|1793000000" }, kinds("gp"))
			local gp
			for _, line in ipairs(lines()) do
				if line:find("|gp|") then
					gp = line
				end
			end
			assert.equal(start .. "|1480|1453|5000|2500|gp|480|1793000000", gp)
			wow.fire("TIME_PLAYED_MSG", 9999, 100)
			assert.equal(1, #kinds("gp"))
		end)

		it("writes no gp for a gap of 120 s or less", function()
			local prev = { start = 1000, last = 1793000000, how = "login", played1 = 1000 }
			wow.boot({ saved = saved(prev) })
			wow.advance(2)
			wow.fire("TIME_PLAYED_MSG", 1105, 100)
			assert.same({}, kinds("gp"))
		end)

		it("writes no gp without a previous played1", function()
			wow.boot({ saved = saved({ start = 1000, last = 1500, how = "login" }) })
			wow.fire("TIME_PLAYED_MSG", 99999, 100)
			assert.same({}, kinds("gp"))
		end)
	end)

	describe("first login /played", function()
		it("keeps the wait for first.played over a reload and dates it with the wall clock", function()
			wow.boot()
			assert.is_true(MemoriesCharDB.char.first.wait)
			wow.advance(2)
			wow.reload()
			assert.is_true(MemoriesCharDB.char.first.wait)
			wow.advance(10)
			wow.fire("TIME_PLAYED_MSG", 50, 50)
			assert.equal(38, MemoriesCharDB.char.first.played)
			assert.is_nil(MemoriesCharDB.char.first.wait)
		end)

		it("stops the wait on a later login, where offline time would count", function()
			wow.boot()
			local db = { MemoriesDB = MemoriesDB, MemoriesCharDB = MemoriesCharDB }
			wow.fire("PLAYER_LOGOUT")
			wow.boot({ saved = db, wall = wow.wall + 86400 })
			assert.is_nil(MemoriesCharDB.char.first.wait)
			wow.fire("TIME_PLAYED_MSG", 50, 50)
			assert.is_nil(MemoriesCharDB.char.first.played)
		end)
	end)

	describe("logout and saves", function()
		it("writes out at a logout before the world loaded", function()
			wow.boot({ login = false })
			wow.fire("PLAYER_LOGIN")
			wow.fire("PLAYER_LOGOUT")
			assert.same({ "" }, kinds("out"))
			assert.is_nil(MemoriesCharDB.sessions[1])
		end)

		it("writes out and updates last and played1 at logout", function()
			local ns = wow.boot()
			wow.fire("TIME_PLAYED_MSG", 100, 10)
			wow.advance(45)
			wow.fire("PLAYER_LOGOUT")
			assert.same({ "" }, kinds("out"))
			local entry = ns.Sessions.Current()
			assert.equal(wow.wall, entry.last)
			assert.equal(145, entry.played1)
		end)

		it("updates last and played1 every 60 s", function()
			local ns = wow.boot()
			local start = wow.wall
			wow.advance(59)
			assert.equal(start, ns.Sessions.Current().last)
			wow.advance(1)
			assert.equal(start + 60, ns.Sessions.Current().last)
			assert.is_nil(ns.Sessions.Current().played1)
			wow.fire("TIME_PLAYED_MSG", 1000, 10)
			wow.advance(60)
			assert.equal(start + 120, ns.Sessions.Current().last)
			assert.equal(1060, ns.Sessions.Current().played1)
		end)
	end)

	describe("away", function()
		local function changes(ns)
			local seen = {}
			ns.Listen("AWAY_CHANGED", function(_, isAway, state)
				seen[#seen + 1] = { isAway, state }
			end)
			return seen
		end

		it("writes af when the AFK flag changes and tells the listeners", function()
			local ns = wow.boot()
			local seen = changes(ns)
			wow.flags.afk = true
			wow.fire("PLAYER_FLAGS_CHANGED", "party1")
			assert.same({}, kinds("af"))
			wow.fire("PLAYER_FLAGS_CHANGED", "player")
			wow.fire("PLAYER_FLAGS_CHANGED", "player")
			assert.equal("afk", ns.Sessions.Away())
			wow.flags.afk = false
			wow.fire("PLAYER_FLAGS_CHANGED", "player")
			assert.same({ "1", "0" }, kinds("af"))
			assert.is_nil(ns.Sessions.Away())
			assert.same({ { true, "afk" }, { false } }, seen)
		end)

		it("ignores a secret AFK flag", function()
			local ns = wow.boot()
			local seen = changes(ns)
			wow.flags.afk = wow.secret(true)
			wow.fire("PLAYER_FLAGS_CHANGED", "player")
			assert.same({}, kinds("af"))
			assert.is_nil(ns.Sessions.Away())
			assert.same({}, seen)
		end)

		it("turns idle after 120 s without activity and active again on a cast or a fight", function()
			local ns = wow.boot()
			local seen = changes(ns)
			wow.advance(118)
			assert.is_nil(ns.Sessions.Away())
			wow.advance(2)
			assert.equal("idle", ns.Sessions.Away())
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "target")
			assert.equal("idle", ns.Sessions.Away())
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player")
			assert.is_nil(ns.Sessions.Away())
			wow.advance(120)
			assert.equal("idle", ns.Sessions.Away())
			wow.fire("PLAYER_REGEN_DISABLED")
			assert.is_nil(ns.Sessions.Away())
			assert.same({ { true, "idle" }, { false }, { true, "idle" }, { false } }, seen)
		end)

		it("counts clearing the AFK flag as activity", function()
			local ns = wow.boot()
			wow.flags.afk = true
			wow.fire("PLAYER_FLAGS_CHANGED", "player")
			wow.advance(300)
			assert.equal("afk", ns.Sessions.Away())
			wow.flags.afk = false
			wow.fire("PLAYER_FLAGS_CHANGED", "player")
			assert.is_nil(ns.Sessions.Away())
		end)
	end)

	describe("kinds off", function()
		local function off(list)
			local kindsOff = {}
			for _, k in ipairs(list) do
				kindsOff[k] = false
			end
			return { MemoriesDB = { settings = { kinds = kindsOff } } }
		end

		it("writes no in or pc but still opens the session", function()
			wow.boot({ saved = off({ "in", "pc" }) })
			assert.same({}, kinds("in"))
			assert.same({}, kinds("pc"))
			assert.equal(1, #MemoriesCharDB.sessions)
			assert.is_string(MemoriesDB.computer)
		end)

		it("writes no out but still saves the entry", function()
			local ns = wow.boot({ saved = off({ "out" }) })
			wow.advance(5)
			wow.fire("PLAYER_LOGOUT")
			assert.same({}, kinds("out"))
			assert.equal(wow.wall, ns.Sessions.Current().last)
		end)

		it("writes no pl but still sets the estimate", function()
			local ns = wow.boot({ saved = off({ "pl" }) })
			wow.advance(3)
			wow.fire("TIME_PLAYED_MSG", 300, 10)
			assert.same({}, kinds("pl"))
			assert.equal(300, ns.Store.PlayedNow())
		end)

		it("writes no gp but still writes the catch-up levels", function()
			local prev = { start = 1000, last = 1793000000, how = "login", played1 = 1000 }
			local db = saved(prev, off({ "gp" }))
			wow.boot({ saved = db, player = { level = 11 } })
			wow.fire("TIME_PLAYED_MSG", 5000, 100)
			assert.same({}, kinds("gp"))
			assert.same({ "11" }, kinds("lv"))
		end)

		it("writes no af but still turns away", function()
			local ns = wow.boot({ saved = off({ "af" }) })
			wow.flags.afk = true
			wow.fire("PLAYER_FLAGS_CHANGED", "player")
			assert.same({}, kinds("af"))
			assert.equal("afk", ns.Sessions.Away())
		end)
	end)

	it("puts the running entry back into a restored sessions list", function()
		local ns = wow.boot({ saved = { MemoriesDB = { settings = {} } } })
		local entry = ns.Sessions.Current()
		ns.Backup.Write("Memories")
		ns.Store.Core():Write("ex", "a", "b")
		assert.is_true(ns.Backup.Restore("Memories"))
		assert.equal(1, #MemoriesCharDB.sessions)
		assert.equal(entry, MemoriesCharDB.sessions[1])

		MemoriesDB.backups[GUID].Memories = { t = 1, lines = 1, data = { log = { chunks = {}, open = { "x" } } } }
		assert.is_true(ns.Backup.Restore("Memories"))
		assert.equal(entry, MemoriesCharDB.sessions[#MemoriesCharDB.sessions])
		wow.advance(60)
		assert.equal(wow.wall, MemoriesCharDB.sessions[#MemoriesCharDB.sessions].last)
	end)
end)

describe("core recorders when the core cannot write", function()
	local function events()
		wow.advance(5)
		wow.fire("TIME_PLAYED_MSG", 100, 10)
		wow.fire("PLAYER_LEVEL_UP", 11)
		wow.fire("CHAT_MSG_COMBAT_XP_GAIN", "Ganas 50 p. de experiencia.")
		wow.fire("QUEST_TURNED_IN", 1, 50, 0)
		wow.fire("PLAYER_FLAGS_CHANGED", "player")
		wow.fire("UPDATE_EXHAUSTION")
		wow.fire("LOADING_SCREEN_ENABLED")
		wow.fire("PLAYER_LOGOUT")
		JumpOrAscendStart()
		wow.advance(30)
	end

	it("does nothing when the store failed at login", function()
		local ns = wow.boot({ login = false })
		ns.Store.Init = function()
			error("boom")
		end
		local messages = {}
		for _, msg in ipairs({ "LEVEL_UP", "AWAY_CHANGED", "TRAIL_LIVE" }) do
			ns.Listen(msg, function()
				messages[#messages + 1] = msg
			end)
		end
		wow.login()
		events()
		assert.equal(1, #MemoriesDB.errors)
		assert.equal("store", MemoriesDB.errors[1].where)
		assert.same({}, messages)
		assert.equal(0, wow.played_asks)
		assert.is_nil(MemoriesCharDB.sessions)
		assert.is_nil(MemoriesDB.computer)
	end)

	it("records nothing into read-only data", function()
		local data = { schema = 2, char = { guid = "Player-1234-0ABCDEF0" }, log = { chunks = {}, open = { "x" } } }
		local ns = wow.boot({ saved = { MemoriesCharDB = data } })
		events()
		assert.same({ "x" }, MemoriesCharDB.log.open)
		assert.is_nil(MemoriesCharDB.sessions)
		assert.is_nil(MemoriesCharDB.trail)
		assert.is_nil(MemoriesCharDB.counts)
		assert.same({}, MemoriesDB.errors)
		assert.equal(0, wow.played_asks)
		assert.is_nil(ns.Sessions.Current())
	end)
end)
