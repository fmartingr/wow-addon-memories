local wow = require("helpers.wow")
local serialize = require("helpers.serialize")

-- A Lua 5.1 chunk holds at most 262,143 unique constants; a saved file is one chunk.
describe("journal size limit", function()
	local N = 300000

	it("runs under Lua 5.1", function()
		assert.equal("Lua 5.1", _VERSION)
	end)

	it("fails to load 300,000 plain strings, so the test can detect the limit", function()
		local list = {}
		for i = 1, N do
			list[i] = "line " .. i
		end
		local loaded, err = serialize.load(serialize.file({ MemoriesCharDB = list }))
		assert.is_nil(loaded)
		assert.matches("constant table overflow", err)
	end)

	it("saves and loads 300,000 packed lines", function()
		-- Before the world loads the core recorders have written nothing yet.
		local ns = wow.boot({ login = false })
		wow.fire("PLAYER_LOGIN")
		local core = ns.Store.Core()
		for i = 1, N do
			core:WriteAt({ t = 1793560500 + i, p = i, m = 1453, x = i % 10000, y = 9999 - i % 10000 }, "lv", i)
		end
		assert.equal(N, core:LineCount())

		local saved = assert(serialize.load(serialize.file({ MemoriesCharDB = MemoriesCharDB })))
		local journal = ns.Journal.New(saved.MemoriesCharDB)
		assert.equal(N, journal:LineCount())
		local i = 0
		for line in journal:Lines() do
			i = i + 1
			if line ~= ns.Codec.EncodeLine(1793560500 + i, i, 1453, i % 10000, 9999 - i % 10000, "lv", i) then
				error("line " .. i .. " differs: " .. line)
			end
		end
		assert.equal(N, i)
	end)
end)
