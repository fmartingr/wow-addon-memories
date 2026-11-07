local wow = require("helpers.wow")

describe("public API", function()
	local FILE = "WoWScrnShot_110626_140309.jpg"

	local ns

	local function boot(opts)
		ns = wow.boot(opts)
		return ns
	end

	-- The fields of each ex and sn line, in journal order.
	local function lines()
		local out = {}
		for line in ns.Store.Core():Lines() do
			local k, rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(%w+)|?(.*)$")
			if k == "ex" or k == "sn" then
				out[#out + 1] = k .. "|" .. rest
			end
		end
		return out
	end

	local function event(...)
		return { Memories.RecordEvent(...) }
	end

	local function note(...)
		return { Memories.RecordScreenshot(...) }
	end

	it("records an event and a screenshot note", function()
		boot()
		assert.same({ true }, event("Test", "hello", "world"))
		assert.same({ true }, note("Paparazzi", "Level up, Boss kill", FILE))
		assert.same({ "ex|Test|hello|world", "sn|Paparazzi|Level up, Boss kill|" .. FILE }, lines())
		local ev = ns.Codec.DecodeLine(MemoriesCharDB.log.open[#MemoriesCharDB.log.open])
		assert.same({ "Paparazzi", "Level up, Boss kill", FILE }, { ev.source, ev.note, ev.file })
		assert.same({ 1453, 5000, 2500 }, { ev.m, ev.x, ev.y })
	end)

	it("leaves out the optional detail and file", function()
		boot()
		assert.same({ true }, event("Test", "hello"))
		assert.same({ true }, note("Paparazzi", "Level up", "  "))
		assert.same({ "ex|Test|hello", "sn|Paparazzi|Level up" }, lines())
	end)

	it("turns numbers into text and trims every value", function()
		boot()
		assert.same({ true }, event(42, "  hello \t", 1.5))
		assert.same({ "ex|42|hello|1.5" }, lines())
	end)

	describe("refusals", function()
		it("is not ready before PLAYER_LOGIN", function()
			boot({ login = false })
			assert.same({ false, "not ready" }, event("Test", "hello"))
			assert.same({ false, "not ready" }, note("Test", "hello"))
		end)

		it("is not ready when the core stopped at login", function()
			boot({ login = false })
			ns.Store.Init = function()
				error("broken store")
			end
			wow.login()
			assert.same({ false, "not ready" }, event("Test", "hello"))
		end)

		it("is read only with data from a newer Memories", function()
			boot({ saved = { MemoriesDB = { schema = 99 } } })
			assert.same({ false, "read only" }, event("Test", "hello"))
			assert.same({ false, "read only" }, note("Test", "hello"))
		end)

		it("is off when the kind is off", function()
			boot()
			ns.Settings.SetKind("ex", false)
			assert.same({ false, "off" }, event("Test", "hello"))
			assert.same({ true }, note("Test", "hello"))
			ns.Settings.SetKind("sn", false)
			assert.same({ false, "off" }, note("Test", "hello"))
			assert.same({ "sn|Test|hello" }, lines())
		end)

		it("refuses each bad argument by name", function()
			boot()
			local bad = { false, true, {}, print, wow.secret("x") }
			for _, v in ipairs(bad) do
				assert.same({ false, "bad source" }, event(v, "hello"))
				assert.same({ false, "bad what" }, event("Test", v))
				assert.same({ false, "bad detail" }, event("Test", "hello", v))
				assert.same({ false, "bad source" }, note(v, "hello"))
				assert.same({ false, "bad note" }, note("Test", v))
				assert.same({ false, "bad file" }, note("Test", "hello", v))
			end
			assert.same({}, lines())
		end)

		it("needs a source, a what and a note", function()
			boot()
			for _, v in ipairs({ "", " \n ", "\1\127" }) do
				assert.same({ false, "bad source" }, event(v, "hello"))
				assert.same({ false, "bad what" }, event("Test", v))
				assert.same({ false, "bad note" }, note("Test", v))
			end
			assert.same({ false, "bad source" }, event(nil, "hello"))
			assert.same({ false, "bad what" }, event("Test"))
			assert.same({ false, "bad note" }, note("Test"))
		end)

		it("refuses a file that is not a screenshot name", function()
			boot()
			for _, file in ipairs({
				"shot.jpg",
				"WoWScrnShot_110626_140309",
				"WoWScrnShot_110626_140309.jpegs",
				"WoWScrnShot_1106_140309.jpg",
				"../WoWScrnShot_110626_140309.jpg",
				"WoWScrnShot_110626_140309.jpg|x",
			}) do
				assert.same({ false, "bad file" }, note("Test", "hello", file))
			end
			assert.same({ true }, note("Test", "hello", "WoWScrnShot_110626_140309.tga"))
			assert.same({ true }, note("Test", "hello", "WoWScrnShot_110626_140309.jpeg"))
		end)
	end)

	describe("text", function()
		it("cuts each field to its byte limit", function()
			boot()
			local long = string.rep("a", 300)
			assert.same({ true }, event(long, long, long))
			assert.same({ true }, note(long, long))
			local out = lines()
			assert.equal("ex|" .. long:sub(1, 40) .. "|" .. long:sub(1, 100) .. "|" .. long:sub(1, 200), out[1])
			assert.equal("sn|" .. long:sub(1, 40) .. "|" .. long:sub(1, 200), out[2])
		end)

		it("never cuts a 4-byte character in half", function()
			boot()
			local emoji = "\240\159\152\128"
			assert.same({ true }, event(string.rep("a", 38) .. emoji, "hello"))
			assert.same({ "ex|" .. string.rep("a", 38) .. "|hello" }, lines())
		end)

		it("replaces | and line breaks in the stored line", function()
			boot()
			assert.same({ true }, note("Pap|arazzi", "Boss|kill\nnext\rline", FILE))
			assert.same({ "sn|Pap/arazzi|Boss/kill next line|" .. FILE }, lines())
			local ev = ns.Codec.DecodeLine(MemoriesCharDB.log.open[#MemoriesCharDB.log.open])
			assert.equal(FILE, ev.file)
		end)

		it("handles a long run of spaces quickly", function()
			boot()
			local spaces = string.rep(" ", 200000)
			assert.same({ true }, event(spaces .. "Test" .. spaces, "a" .. spaces .. "b"))
			assert.same({ "ex|Test|a" }, lines())
		end)
	end)

	describe("rate limit", function()
		it("accepts 30 calls a minute from one source and resets in the next minute", function()
			boot()
			for _ = 1, 30 do
				assert.same({ true }, event("Spam", "hello"))
			end
			assert.same({ false, "rate limit" }, event("Spam", "hello"))
			assert.same({ false, "rate limit" }, note("Spam", "hello"))
			assert.same({ true }, event("Other", "hello"))
			wow.advance(60)
			assert.same({ true }, event("Spam", "hello"))
		end)

		it("keeps two sources at the limit apart", function()
			boot()
			for _ = 1, 30 do
				assert.same({ true }, event("A", "hello"))
				assert.same({ true }, note("B", "hello"))
			end
			assert.same({ false, "rate limit" }, event("A", "hello"))
			assert.same({ false, "rate limit" }, note("B", "hello"))
			assert.equal(60, #lines())
		end)

		it("counts only accepted calls", function()
			boot()
			for _ = 1, 40 do
				event("Spam", nil)
			end
			ns.Settings.SetKind("ex", false)
			for _ = 1, 40 do
				event("Spam", "hello")
			end
			ns.Settings.SetKind("ex", true)
			assert.same({ true }, event("Spam", "hello"))
		end)

		it("drops buckets older than 2 minutes", function()
			boot()
			event("A", "hello")
			event("B", "hello")
			assert.equal(2, ns.Api.Sources())
			wow.advance(60)
			event("C", "hello")
			assert.equal(3, ns.Api.Sources())
			wow.advance(60)
			event("C", "hello")
			assert.equal(1, ns.Api.Sources())
		end)

		it("refuses a new source when too many sources hold a bucket", function()
			boot()
			for i = 1, ns.Api.MAX_SOURCES do
				assert.same({ true }, event("S" .. i, "hello"))
			end
			assert.same({ false, "rate limit" }, event("New", "hello"))
			assert.same({ true }, event("S1", "hello"))
			wow.advance(120)
			assert.same({ true }, event("New", "hello"))
		end)
	end)

	describe("errors", function()
		it("returns error and logs it when the call fails inside", function()
			boot()
			ns.Store.Core().Write = function()
				error("broken journal")
			end
			assert.same({ false, "error" }, event("Test", "hello"))
			assert.same({ false, "error" }, note("Test", "hello"))
			assert.equal("api:RecordEvent", MemoriesDB.errors[1].where)
			assert.equal("api:RecordScreenshot", MemoriesDB.errors[2].where)
		end)

		it("refuses a call from an error handler that the call itself triggered", function()
			boot()
			local inner = {}
			_G.geterrorhandler = function()
				return function()
					inner[#inner + 1] = { Memories.RecordEvent("Handler", "hello") }
				end
			end
			ns.Store.Core().Write = function()
				error("broken journal")
			end
			assert.same({ false, "error" }, event("Test", "hello"))
			assert.same({ { false, "error" } }, inner)
		end)

		it("works from inside the caller's own error handler", function()
			boot()
			local result
			xpcall(function()
				error("caller error")
			end, function()
				result = { Memories.RecordEvent("Test", "from handler") }
			end)
			assert.same({ true }, result)
			assert.same({ "ex|Test|from handler" }, lines())
		end)
	end)
end)
