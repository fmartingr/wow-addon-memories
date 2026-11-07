local wow = require("helpers.wow")

describe("backups", function()
	local GUID = "Player-1234-0ABCDEF0"

	local function lines(journal)
		local out = {}
		for line in journal:Lines() do
			out[#out + 1] = line
		end
		return out
	end

	local function fill(journal, n, what)
		for i = 1, n do
			journal:Write("ex", "test", what or "line", i)
		end
	end

	local function record(addon)
		return MemoriesDB.backups and MemoriesDB.backups[GUID] and MemoriesDB.backups[GUID][addon]
	end

	local function bootTest(opts)
		opts = opts or {}
		opts.addons = { "Memories", "Memories_Test" }
		local ns, all = wow.boot(opts)
		return ns, all.Memories_Test.handle
	end

	it("writes a packed backup that reads back as the same data", function()
		local ns = wow.boot()
		local core = ns.Store.Core()
		local base = core:LineCount()
		fill(core, 250)
		assert.is_true(ns.Backup.Write("Memories"))
		local rec = record("Memories")
		assert.equal(wow.wall, rec.t)
		assert.equal(10, rec.level)
		assert.equal(base + 250, rec.lines)
		assert.is_string(rec.blob)
		assert.is_nil(rec.data)
		assert.same(MemoriesCharDB, ns.Backup.Read("Memories", GUID))
	end)

	it("compresses with Deflate at the speed level", function()
		local ns = wow.boot()
		fill(ns.Store.Core(), 1)
		local args
		local compress = C_EncodingUtil.CompressString
		C_EncodingUtil.CompressString = function(...)
			args = { select(2, ...) }
			return compress(...)
		end
		ns.Backup.Write("Memories")
		assert.same({ Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSpeed }, args)
		Enum.CompressionLevel = nil
		ns.Backup.Write("Memories")
		assert.same({ Enum.CompressionMethod.Deflate }, args)
		_G.Enum = nil
		ns.Backup.Write("Memories")
		assert.same({}, args)
		assert.same(MemoriesCharDB, ns.Backup.Read("Memories", GUID))
	end)

	it("keeps a plain copy when C_EncodingUtil is missing", function()
		local ns = wow.boot()
		fill(ns.Store.Core(), 3)
		_G.C_EncodingUtil = nil
		assert.is_true(ns.Backup.Write("Memories"))
		local rec = record("Memories")
		assert.is_nil(rec.blob)
		assert.same(MemoriesCharDB, rec.data)
		assert.are_not.equal(MemoriesCharDB, rec.data)
		assert.same(MemoriesCharDB, ns.Backup.Read("Memories", GUID))
	end)

	it("keeps a plain copy when the encoder fails", function()
		local ns = wow.boot()
		fill(ns.Store.Core(), 3)
		C_EncodingUtil.SerializeCBOR = function()
			error("cbor broke")
		end
		assert.is_true(ns.Backup.Write("Memories"))
		assert.same(MemoriesCharDB, record("Memories").data)
		assert.same({}, MemoriesDB.errors)
	end)

	it("skips a journal that is empty, read-only, held or unknown", function()
		-- Before the world loads the core recorders have written nothing yet.
		local ns = wow.boot({ login = false })
		wow.fire("PLAYER_LOGIN")
		assert.same({ false, "empty" }, { ns.Backup.Write("Memories") })
		assert.same({ false, "unknown" }, { ns.Backup.Write("Memories_Nope") })
		fill(ns.Store.Core(), 2)
		ns.Backup.Write("Memories")
		record("Memories").hold = true
		fill(ns.Store.Core(), 2)
		assert.same({ false, "held" }, { ns.Backup.Write("Memories") })
		assert.equal(2, record("Memories").lines)

		wow.boot({
			saved = { MemoriesCharDB = { schema = 2, char = { guid = GUID }, log = { chunks = {}, open = { "x" } } } },
		})
		ns = wow.ns.Memories
		assert.same({ false, "read only" }, { ns.Backup.Write("Memories") })
		assert.is_nil(MemoriesDB.backups)
	end)

	it("skips when the player GUID is unknown", function()
		local ns = wow.boot()
		fill(ns.Store.Core(), 1)
		wow.player.guid = wow.secret(GUID)
		assert.same({ false, "no guid" }, { ns.Backup.Write("Memories") })
		assert.is_nil(ns.Backup.Record("Memories"))
	end)

	it("reads nothing for a missing or broken record", function()
		local ns = wow.boot()
		assert.same({ nil, "no backup" }, { ns.Backup.Read("Memories", GUID) })
		MemoriesDB.backups = { [GUID] = { Memories = { t = 1, lines = 3 } } }
		assert.same({ nil, "no backup" }, { ns.Backup.Read("Memories", GUID) })
		MemoriesDB.backups = { [GUID] = { Memories = { t = 1, lines = 3, blob = "@@@@" } } }
		local data, err = ns.Backup.Read("Memories", GUID)
		assert.is_nil(data)
		assert.matches("^bad backup", err)
		MemoriesDB.backups = { [GUID] = "junk" }
		assert.is_nil(ns.Backup.Record("Memories"))
		MemoriesDB.backups = { [GUID] = { Memories = { lines = 1, blob = "x" } } }
		_G.C_EncodingUtil = nil
		assert.same({ nil, "no decoder" }, { ns.Backup.Read("Memories", GUID) })
	end)

	it("restores the backup and moves the current data to the orphans", function()
		local ns = wow.boot()
		local core = ns.Store.Core()
		fill(core, 3, "kept")
		ns.Backup.Write("Memories")
		local before = lines(core)
		local n = #before
		fill(core, 2, "after")
		local current = lines(core)
		local restored = {}
		ns.Listen("RESTORED", function(_, addon)
			restored[#restored + 1] = addon
		end)
		assert.is_true(ns.Backup.Restore("Memories"))
		local now = ns.Store.Core()
		assert.are_not.equal(core, now)
		assert.equal(MemoriesCharDB, now.data)
		local got = lines(now)
		assert.equal(n + 1, #got)
		for i = 1, n do
			assert.equal(before[i], got[i])
		end
		assert.matches("|nt|restored backup|" .. n .. "$", got[n + 1])
		local orphan = MemoriesDB.orphans[1]
		assert.equal("restored backup", orphan.why)
		assert.equal("Memories", orphan.addon)
		assert.equal(GUID, orphan.guid)
		assert.equal("Kaelys", orphan.name)
		assert.same(current, lines(ns.Journal.New(orphan.data, { readOnly = true })))
		assert.same({ "Memories" }, restored)
		assert.is_string(MemoriesCharDB.char.first and MemoriesCharDB.char.class)
	end)

	it("keeps the current data when the backup does not decode", function()
		local ns = wow.boot()
		local core = ns.Store.Core()
		local base = core:LineCount()
		fill(core, 2)
		MemoriesDB.backups = { [GUID] = { Memories = { t = 1, lines = 9, blob = "@@@@" } } }
		local ok, err = ns.Backup.Restore("Memories")
		assert.is_false(ok)
		assert.matches("^bad backup", err)
		assert.equal(core, ns.Store.Core())
		assert.equal(base + 2, core:LineCount())
		assert.is_nil(MemoriesDB.orphans)
		assert.equal("backup:Memories", MemoriesDB.errors[1].where)
	end)

	it("refuses to restore a read-only or unknown journal", function()
		local data = { schema = 2, char = { guid = GUID }, log = { chunks = {}, open = { "x" } } }
		local ns = wow.boot({ saved = { MemoriesCharDB = data } })
		MemoriesDB.backups = { [GUID] = { Memories = { t = 1, lines = 1, data = { log = {} } } } }
		assert.same({ false, "read only" }, { ns.Backup.Restore("Memories") })
		assert.same({ "x" }, MemoriesCharDB.log.open)
		assert.same({ false, "unknown" }, { ns.Backup.Restore("Memories_Nope") })
	end)

	it("restores a sub-addon into its own saved global", function()
		local ns, h = bootTest()
		local coreLines = ns.Store.Core():LineCount()
		h:Write("zz", "one", 1)
		h:Write("zz", "two", 2)
		ns.Backup.Write("Memories_Test")
		h:Write("zy", "lost")
		assert.is_true(ns.Backup.Restore("Memories_Test"))
		assert.equal(3, MemoriesTestCharDB.lines)
		h:Write("zy", "after")
		local journal = ns.Registry.Journal("Memories_Test").journal
		assert.equal(MemoriesTestCharDB, journal.data)
		local got = lines(journal)
		assert.matches("|zz|two|2$", got[2])
		assert.matches("|nt|restored backup|2$", got[3])
		assert.matches("|zy|after$", got[4])
		assert.equal(coreLines, ns.Store.Core():LineCount())
		assert.equal("Memories_Test", MemoriesDB.orphans[1].addon)
	end)

	describe("schedule", function()
		it("writes one addon per frame", function()
			local ns, h = bootTest()
			fill(ns.Store.Core(), 1)
			h:Write("zz", "one", 1)
			ns.Backup.Run()
			assert.is_table(record("Memories"))
			assert.is_nil(record("Memories_Test"))
			ns.Backup.Run()
			assert.is_nil(record("Memories_Test"))
			wow.advance(0)
			assert.is_table(record("Memories_Test"))
		end)

		it("runs once more after a run when a request came during it", function()
			local ns, h = bootTest()
			local base = ns.Store.Core():LineCount()
			fill(ns.Store.Core(), 1)
			h:Write("zz", "one", 1)
			ns.Backup.Run()
			assert.equal(base + 1, record("Memories").lines)
			fill(ns.Store.Core(), 1)
			ns.Backup.Run()
			assert.equal(base + 1, record("Memories").lines)
			wow.advance(0)
			wow.advance(0)
			assert.equal(base + 2, record("Memories").lines)
			fill(ns.Store.Core(), 1)
			wow.advance(0)
			wow.advance(0)
			assert.equal(base + 2, record("Memories").lines)
		end)

		it("waits for the end of combat", function()
			local ns, h = bootTest()
			fill(ns.Store.Core(), 1)
			h:Write("zz", "one", 1)
			wow.combat = true
			ns.Backup.Run()
			assert.is_nil(record("Memories"))
			wow.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.is_table(record("Memories"))
			wow.combat = true
			wow.advance(0)
			assert.is_nil(record("Memories_Test"))
			wow.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.is_table(record("Memories_Test"))
		end)

		it("runs 5 s after login, every 15 minutes and on a level-up", function()
			local ns = wow.boot()
			local base = ns.Store.Core():LineCount()
			fill(ns.Store.Core(), 1)
			wow.advance(4)
			assert.is_nil(record("Memories"))
			wow.advance(1)
			assert.equal(base + 1, record("Memories").lines)
			fill(ns.Store.Core(), 1)
			wow.advance(15 * 60 - 5)
			assert.equal(base + 2, record("Memories").lines)
			fill(ns.Store.Core(), 1)
			ns.Emit("LEVEL_UP", 11)
			assert.equal(base + 3, record("Memories").lines)
		end)

		it("leaves the backup of a sub-addon that is not loaded", function()
			local other = { t = 1, lines = 5, blob = "kept" }
			local ns = wow.boot({ saved = { MemoriesDB = { backups = { [GUID] = { Memories_Combat = other } } } } })
			fill(ns.Store.Core(), 1)
			wow.advance(5)
			wow.reload()
			assert.same(other, record("Memories_Combat"))
			assert.is_table(record("Memories"))
		end)
	end)
end)
