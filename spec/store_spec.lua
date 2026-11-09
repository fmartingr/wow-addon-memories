local wow = require("helpers.wow")

describe("store", function()
	wow.pin_locale("enUS", before_each, after_each)

	local NEWER = "Memories: saved data from a newer version; this addon will not write"

	local function lines(journal)
		local out = {}
		for line in journal:Lines() do
			out[#out + 1] = line
		end
		return out
	end

	local function count(list, text)
		local n = 0
		for _, v in ipairs(list) do
			if v == text then
				n = n + 1
			end
		end
		return n
	end

	it("opens MemoriesCharDB as the core journal at login, before the modules' OnLogin", function()
		local ns = wow.boot({ login = false })
		local seen
		ns.Module("Probe").OnLogin = function()
			seen = ns.Store.Core()
		end
		wow.login()
		assert.equal(ns.Store.Core(), seen)
		assert.equal(MemoriesCharDB, seen.data)
		assert.equal("Memories", seen.addon)
		assert.is_true(seen:CanWrite())
	end)

	it("fills the core character data on a first login", function()
		wow.boot()
		local char = MemoriesCharDB.char
		assert.equal("Player-1234-0ABCDEF0", char.guid)
		assert.equal("Kaelys", char.name)
		assert.equal("Brumamar", char.realm)
		assert.equal("MAGE", char.class)
		assert.equal("Human", char.race)
		assert.equal(3, char.sex)
		assert.equal("Alliance", char.faction)
		assert.equal(10, char.level)
		assert.same({ t = wow.wall, level = 10, m = 1453, x = 5000, y = 2500, wait = true }, char.first)
		assert.equal(1, #MemoriesCharDB.sessions)
		assert.same({ v = 1, chunks = {} }, MemoriesCharDB.trail)
		assert.same({ lowHealthFlash = true }, MemoriesCharDB.flags)
		assert.equal(1, MemoriesDB.schema)
	end)

	it("records the client locale in the core character data", function()
		wow.boot({ locale = "deDE" })
		assert.equal("deDE", MemoriesCharDB.char.locale)
	end)

	it("updates the locale when the client language changes", function()
		wow.boot({ locale = "deDE" })
		wow.reload()
		assert.equal("deDE", MemoriesCharDB.char.locale)
		wow.opts.locale = "frFR"
		wow.reload()
		assert.equal("frFR", MemoriesCharDB.char.locale)
	end)

	it("writes no locale when GetLocale is missing or returns no usable text", function()
		for _, value in ipairs({ false, 5, "", "toolonglocale" }) do
			wow.boot({ login = false })
			wow.locale = value
			wow.login()
			assert.is_nil(MemoriesCharDB.char.locale)
		end
		wow.boot({ login = false })
		local saved = _G.GetLocale
		_G.GetLocale = nil
		wow.login()
		_G.GetLocale = saved
		assert.is_nil(MemoriesCharDB.char.locale)
	end)

	it("keeps an older character without a locale working", function()
		local saved = { MemoriesCharDB = { char = { guid = "Player-1234-0ABCDEF0", name = "Kaelys" } } }
		wow.boot({ saved = saved, locale = "itIT" })
		assert.equal("itIT", MemoriesCharDB.char.locale)
	end)

	it("keeps first and updates the level on a later login", function()
		wow.boot()
		local first = MemoriesCharDB.char.first
		wow.player.level = 12
		wow.advance(60)
		wow.reload()
		assert.same(first, MemoriesCharDB.char.first)
		assert.equal(12, MemoriesCharDB.char.level)
	end)

	it("fills first.played from the first /played answer of the first login", function()
		local ns = wow.boot()
		assert.is_nil(MemoriesCharDB.char.first.played)
		wow.advance(4)
		ns.Store.SetPlayed(10)
		assert.equal(6, MemoriesCharDB.char.first.played)
		ns.Store.SetPlayed(500)
		assert.equal(6, MemoriesCharDB.char.first.played)
	end)

	it("follows a rename of the same character", function()
		wow.boot()
		wow.player.name = "Kaelyss"
		wow.reload()
		assert.equal("Kaelyss", MemoriesCharDB.char.name)
		assert.is_nil(MemoriesDB.orphans)
	end)

	it("keeps a stored value when the game gives a secret one", function()
		local char = { guid = "Player-1234-0ABCDEF0", level = 10 }
		wow.boot({ saved = { MemoriesDB = {}, MemoriesCharDB = { char = char } }, login = false })
		wow.player.level = wow.secret(12)
		wow.login()
		assert.equal(10, MemoriesCharDB.char.level)
	end)

	it("writes the core kinds to MemoriesDB.kinds at login", function()
		wow.boot()
		local kinds = MemoriesDB.kinds
		assert.equal("Memories;Sessions;how", kinds["in"])
		assert.equal("Memories;Sessions;", kinds.out)
		assert.equal("Memories;Deaths;killer,#npc,spell,env,place,boss,#klevel,kclass,#amount,#byPlayer,inst", kinds.de)
		assert.equal("Memories;Other addons;source,what,detail", kinds.ex)
		assert.equal("Memories;;what,detail", kinds.nt)
		local n = 0
		for _ in pairs(kinds) do
			n = n + 1
		end
		assert.equal(39, n)
	end)

	it("moves the data of an old character with the same name to the orphans", function()
		local old = {
			schema = 1,
			char = { guid = "Player-1234-OLD", name = "Kaelys", realm = "Brumamar", level = 60 },
			log = { chunks = {}, open = { "1|||||lv|60" } },
			counts = { kills = { total = 900 } },
		}
		local ns = wow.boot({ saved = { MemoriesDB = {}, MemoriesCharDB = old } })
		local orphan = MemoriesDB.orphans[1]
		assert.equal("Player-1234-OLD", orphan.guid)
		assert.equal("Kaelys", orphan.name)
		assert.equal("Memories", orphan.addon)
		assert.equal(wow.wall, orphan.t)
		assert.same({ "1|||||lv|60" }, orphan.data.log.open)
		assert.equal(900, orphan.data.counts.kills.total)
		assert.equal(60, orphan.data.char.level)
		assert.equal("Player-1234-0ABCDEF0", MemoriesCharDB.char.guid)
		assert.equal(10, MemoriesCharDB.char.level)
		assert.same({}, MemoriesCharDB.counts)
		assert.equal(wow.wall .. "||1453|5000|2500|nt|new character|Player-1234-OLD", lines(ns.Store.Core())[1])
	end)

	it("adds to existing orphans", function()
		local saved = {
			MemoriesDB = { orphans = { { guid = "Player-1" } } },
			MemoriesCharDB = { char = { guid = "Player-2" } },
		}
		wow.boot({ saved = saved })
		assert.equal(2, #MemoriesDB.orphans)
		assert.equal("Player-2", MemoriesDB.orphans[2].guid)
	end)

	it("makes the core journal read-only when its data comes from a newer version", function()
		local data = { schema = 2, char = { guid = "Player-1234-0ABCDEF0" }, log = { chunks = {}, open = { "x" } } }
		local ns = wow.boot({ saved = { MemoriesDB = {}, MemoriesCharDB = data } })
		local core = ns.Store.Core()
		assert.is_false(core:CanWrite())
		assert.same({ nil, "read only" }, { core:Write("lv", 2) })
		assert.equal(1, count(wow.chat(), NEWER))
		assert.is_nil(MemoriesCharDB.writtenBy)
		assert.is_nil(MemoriesCharDB.sessions)
		assert.same({ "x" }, lines(core))
		assert.equal(1, MemoriesDB.schema)
	end)

	it("makes all of Memories read-only when MemoriesDB comes from a newer version", function()
		local saved = {
			MemoriesDB = { schema = 2, kinds = { zz = "x" } },
			MemoriesCharDB = { schema = 1, char = { guid = "Player-OTHER" } },
		}
		local ns = wow.boot({ saved = saved })
		assert.is_true(ns.Store.ReadOnlyAll())
		assert.is_false(ns.Store.Core():CanWrite())
		assert.is_nil(MemoriesDB.orphans)
		assert.same({ zz = "x" }, MemoriesDB.kinds)
		assert.equal("Player-OTHER", MemoriesCharDB.char.guid)
		assert.equal(1, count(wow.chat(), NEWER))
	end)

	it("keeps all lines across a reload", function()
		local ns = wow.boot()
		for i = 1, 450 do
			ns.Store.Core():Write("lv", i)
		end
		local before = lines(ns.Store.Core())
		ns = wow.reload()
		local core = ns.Store.Core()
		local after = lines(core)
		-- The reload adds out, in and rs.
		assert.equal(#before + 3, core:LineCount())
		assert.equal(#before + 3, MemoriesCharDB.lines)
		assert.same(before, { unpack(after, 1, #before) })
		assert.equal(0, #wow.chat())
	end)

	it("counts played time from the base", function()
		local ns = wow.boot()
		assert.is_nil(ns.Store.PlayedNow())
		ns.Store.SetPlayed(3600)
		wow.advance(90.7)
		assert.equal(3690, ns.Store.PlayedNow())
		assert.equal(3690, ns.Codec.DecodeLine(ns.Store.Core():Write("gh")).p)
	end)
end)

describe("store failure", function()
	wow.pin_locale("enUS", before_each, after_each)

	it("keeps the modules off when the store cannot open", function()
		local ns = wow.boot({ login = false })
		local calls = {}
		local probe = ns.Module("Probe")
		probe.OnLogin = function()
			calls[#calls + 1] = "login"
		end
		probe.OnEnterWorld = function()
			calls[#calls + 1] = "world"
		end
		ns.Store.Init = function()
			error("boom")
		end
		wow.login()
		assert.same({}, calls)
		assert.is_nil(ns.loggedIn)
		assert.equal("store", MemoriesDB.errors[1].where)
	end)
end)
