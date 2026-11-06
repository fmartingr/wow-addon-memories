local wow = require("helpers.wow")

describe("journal", function()
	local ns, data, j

	local function collect(journal)
		local out = {}
		for line in journal:Lines() do
			out[#out + 1] = line
		end
		return out
	end

	local function writeN(n)
		for i = 1, n do
			j:WriteAt({ t = i }, "lv", i)
		end
	end

	before_each(function()
		ns = wow.boot({ login = false })
		data = {}
		j = ns.Journal.New(data, { addon = "Memories" })
	end)

	it("creates the data shape on an empty table", function()
		assert.equal(1, data.schema)
		assert.equal("Memories", data.addon)
		assert.equal("0.1.0", data.writtenBy)
		assert.same({ chunks = {}, open = {} }, data.log)
		assert.same({}, data.counts)
		assert.same({}, data.snap)
		assert.same({}, data.state)
		assert.same({}, data.char)
		assert.equal(0, data.lines)
		assert.is_true(j:CanWrite())
	end)

	it("creates a missing log in data from an older empty install", function()
		local old = { schema = 1, char = { guid = "g" }, counts = { kills = { total = 3 } } }
		local journal = ns.Journal.New(old)
		assert.same({ chunks = {}, open = {} }, old.log)
		assert.equal(3, journal:Counts("kills").total)
	end)

	it("stamps time, played and position on Write", function()
		wow.set_wall(1793560600)
		ns.Store.SetPlayed(1000)
		wow.advance(5)
		local line = j:Write("lv", 11)
		assert.equal("1793560605|1005|1453|5000|2500|lv|11", line)
	end)

	it("leaves played empty until the played base is set, and the position empty in an instance", function()
		wow.instance = { type = "party" }
		assert.equal(wow.wall .. "|||||lv|11", j:Write("lv", 11))
	end)

	it("writes the parts of at that are set", function()
		assert.equal("50|7|1|2||lv|3", j:WriteAt({ t = 50, p = 7, m = 1, x = 2 }, "lv", 3))
		assert.equal(wow.wall .. "|||||gh", j:WriteAt({}, "gh"))
	end)

	for _, case in ipairs({ { 200, 1, 0 }, { 201, 1, 1 }, { 400, 2, 0 }, { 199, 0, 199 } }) do
		local n, chunks, open = case[1], case[2], case[3]
		it("packs " .. n .. " lines into " .. chunks .. " chunks and " .. open .. " open lines", function()
			writeN(n)
			assert.equal(chunks, #data.log.chunks)
			assert.equal(open, #data.log.open)
			assert.equal(n, j:LineCount())
			assert.equal(n, data.lines)
			local lines = collect(j)
			assert.equal(n, #lines)
			for i = 1, n do
				assert.equal(i .. "|||||lv|" .. i, lines[i])
			end
		end)
	end

	it("returns no lines for an empty journal", function()
		assert.same({}, collect(j))
	end)

	it("recounts data.lines that does not match and packs a full open list at load", function()
		writeN(150)
		local open = data.log.open
		for i = 151, 450 do
			open[#open + 1] = i .. "|||||lv|" .. i
		end
		data.lines = 7
		local again = ns.Journal.New(data)
		assert.equal(450, data.lines)
		assert.equal(2, #data.log.chunks)
		assert.equal(50, #data.log.open)
		local lines = collect(again)
		assert.equal(450, #lines)
		assert.equal("450|||||lv|450", lines[450])
	end)

	it("packs an open list far past the unpack limit at load", function()
		local open = {}
		for i = 1, 20050 do
			open[i] = i .. "|||||lv|" .. i
		end
		local big = { log = { chunks = {}, open = open } }
		local journal = ns.Journal.New(big)
		assert.equal(100, #big.log.chunks)
		assert.equal(50, #big.log.open)
		assert.equal(20050, journal:LineCount())
		local lines = collect(journal)
		assert.equal("20050|||||lv|20050", lines[20050])
	end)

	it("yields each line once when a write packs a chunk during the loop", function()
		writeN(199)
		local seen = 0
		for _ in j:Lines() do
			seen = seen + 1
			if seen == 1 then
				j:WriteAt({ t = 1 }, "lv", 200)
			end
		end
		assert.equal(199, seen)
		assert.equal(200, j:LineCount())
	end)

	it("returns the old value from Count and adds n", function()
		assert.is_true(j:IsFirst("kills", 448))
		assert.equal(0, j:Count("kills", 448))
		assert.is_false(j:IsFirst("kills", 448))
		assert.equal(1, j:Count("kills", 448, 4))
		assert.equal(5, j:Counts("kills")[448])
		assert.same({ kills = { [448] = 5 } }, data.counts)
	end)

	it("treats a zero count as first", function()
		j:Counts("loot")[2589] = 0
		assert.is_true(j:IsFirst("loot", 2589))
	end)

	it("sets and gets snapshots by level", function()
		assert.is_nil(j:Snap(10, "money"))
		j:Snap(10, "money", 1234)
		assert.equal(1234, j:Snap(10, "money"))
		assert.same({ [10] = { money = 1234 } }, data.snap)
	end)

	it("emits LINE_WRITTEN with the addon, kind and line", function()
		local got
		ns.Listen("LINE_WRITTEN", function(_, ...)
			got = { ... }
		end)
		local line = j:WriteAt({ t = 1 }, "lv", 2)
		assert.same({ "Memories", "lv", line }, got)
	end)

	it("asserts on an unregistered kind", function()
		assert.has_error(function()
			j:Write("qq")
		end)
		assert.equal(0, j:LineCount())
	end)

	it("refuses a kind that the gate turns off, and still counts", function()
		ns.KindOn = function(kind)
			return kind ~= "lv"
		end
		local line, why = j:Write("lv", 2)
		assert.is_nil(line)
		assert.equal("off", why)
		assert.equal(0, j:Count("progress", "levels"))
		assert.equal(1, j:Counts("progress").levels)
		assert.equal(0, j:LineCount())
		assert.truthy(j:Write("gh"))
	end)

	it("never gates nt", function()
		ns.KindOn = function()
			return false
		end
		assert.truthy(j:Write("nt", "new character", "Player-1"))
	end)

	describe("read only", function()
		local frozen, ro

		before_each(function()
			frozen = { schema = 2, log = { chunks = {}, open = { "1|||||lv|2" } }, counts = { kills = { a = 1 } } }
			ro = ns.Journal.New(frozen, { addon = "Memories", readOnly = true })
		end)

		it("refuses writes and leaves the data as it is", function()
			local line, why = ro:Write("lv", 3)
			assert.is_nil(line)
			assert.equal("read only", why)
			assert.is_false(ro:CanWrite())
			assert.equal(1, ro:Count("kills", "a"))
			assert.equal(0, ro:Count("kills", "b"))
			ro:Snap(1, "k", "v")
			assert.is_nil(ro:Snap(1, "k"))
			assert.same(
				{ schema = 2, log = { chunks = {}, open = { "1|||||lv|2" } }, counts = { kills = { a = 1 } } },
				frozen
			)
		end)

		it("still reads lines and counts", function()
			assert.same({ "1|||||lv|2" }, collect(ro))
			assert.equal(1, ro:LineCount())
			assert.is_false(ro:IsFirst("kills", "a"))
			assert.same({}, ro:Counts("other"))
		end)

		it("gives a copy of the counts, so a caller cannot change them", function()
			ro:Counts("kills").a = 99
			assert.equal(1, frozen.counts.kills.a)
			assert.is_false(ro:IsFirst("kills", "a"))
		end)

		it("reads a data table with no log", function()
			local empty = ns.Journal.New({}, { readOnly = true })
			assert.equal(0, empty:LineCount())
			assert.same({}, collect(empty))
		end)
	end)
end)

describe("kinds", function()
	local Kinds

	before_each(function()
		Kinds = wow.boot({ login = false }).Kinds
	end)

	it("registers the core kinds in catalog order with their numeric fields", function()
		local all = Kinds.All()
		assert.equal("in", all[1].kind)
		assert.equal("nt", all[#all].kind)
		local de = Kinds.Get("de")
		assert.equal("Deaths", de.group)
		assert.equal("Died", de.name)
		assert.equal("npc", de.names[2])
		assert.is_true(de.numeric[2])
		assert.is_false(de.numeric[1])
		assert.is_true(Kinds.Get("nt").always)
	end)

	it("registers a kind of another addon and describes it", function()
		Kinds.Register("zz", { addon = "Memories_Test", group = "Test", name = "Test", fields = { "a", "#b" } })
		assert.equal("Memories_Test;Test;a,#b", Kinds.Describe().zz)
	end)

	it("asserts on a duplicate kind, a bad kind name and a bad field", function()
		assert.has_error(function()
			Kinds.Register("lv", { addon = "Memories_Test" })
		end, "duplicate kind lv")
		assert.has_error(function()
			Kinds.Register("a|b", { addon = "Memories_Test" })
		end)
		assert.has_error(function()
			Kinds.Register("zq", { addon = "Memories_Test", fields = { "a b" } })
		end)
		assert.has_error(function()
			Kinds.Register("zr", {})
		end)
		assert.is_nil(Kinds.Get("zq"))
	end)

	it("asserts on a field name that decoding uses for a fixed column", function()
		for _, field in ipairs({ "t", "#p", "k", "raw" }) do
			assert.has_error(function()
				Kinds.Register("zs", { addon = "Memories_Test", fields = { field } })
			end)
		end
		assert.is_nil(Kinds.Get("zs"))
	end)
end)
