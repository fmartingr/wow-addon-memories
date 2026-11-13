local wow = require("helpers.wow")

describe("notes", function()
	local ns

	local function noteLines()
		local out = {}
		for line in ns.Store.Core():Lines() do
			local ev = ns.Codec.DecodeLine(line)
			if ev.k == "un" then
				out[#out + 1] = ev
			end
		end
		return out
	end

	it("writes one un line with the text", function()
		ns = wow.boot()
		local line = ns.Notes.Add("hello")
		assert.truthy(line)
		local all = noteLines()
		assert.equal(1, #all)
		assert.equal("hello", all[1].text)
		assert.equal(1, ns.Store.Core():Counts("notes").written)
	end)

	it("is not an always kind", function()
		ns = wow.boot()
		assert.is_false(ns.Kinds.Get("un").always)
	end)

	it("turns line breaks into spaces and trims", function()
		ns = wow.boot()
		ns.Notes.Add("  one\ntwo\r\nthree  ")
		assert.equal("one two  three", noteLines()[1].text)
	end)

	it("refuses an empty note", function()
		ns = wow.boot()
		assert.same({ nil, "empty" }, { ns.Notes.Add(" \n ") })
		assert.same({ nil, "empty" }, { ns.Notes.Add(nil) })
		assert.equal(0, #noteLines())
	end)

	it("writes nothing when the kind is off", function()
		ns = wow.boot({ saved = { MemoriesDB = { settings = { kinds = { un = false } } } } })
		assert.same({ nil, "off" }, { ns.Notes.Add("hello") })
		assert.equal(0, #noteLines())
	end)

	it("writes nothing for a journal from a newer version", function()
		ns = wow.boot({ saved = { MemoriesDB = { schema = 99 } } })
		assert.same({ nil, "read only" }, { ns.Notes.Add("hello") })
	end)

	it("cuts a long note to 400 bytes at a character edge", function()
		ns = wow.boot()
		ns.Notes.Add(string.rep("a", 399) .. "é" .. string.rep("b", 50))
		local text = noteLines()[1].text
		assert.equal(399, #text)
		assert.equal(string.rep("a", 399), text)
	end)

	it("drops a token that the cut would leave open", function()
		ns = wow.boot()
		local text = string.rep("a", 390) .. "{item:19019:Thunderfury}"
		assert.equal(string.rep("a", 390), ns.Notes.Fit(text))
		local long = string.rep("a", 380) .. "{item:19019:" .. string.rep("N", 30) .. "}"
		assert.equal(string.rep("a", 380), ns.Notes.Fit(long))
		assert.equal("short {item:1:x}", ns.Notes.Fit("short {item:1:x}"))
	end)

	describe("tokens", function()
		it("makes item and quest tokens", function()
			ns = wow.boot()
			assert.equal("{item:19019:Thunderfury}", ns.Notes.ItemToken(19019, "Thunderfury"))
			assert.equal("{quest:12:Kill them all}", ns.Notes.QuestToken(12, "Kill them all"))
		end)

		it("removes braces and control characters from a name", function()
			ns = wow.boot()
			assert.equal("{item:5:a b}", ns.Notes.ItemToken(5, "{a}\n b"))
		end)

		it("refuses a bad id", function()
			ns = wow.boot()
			for _, id in ipairs({ 0, -1, 1.5, "12", math.huge }) do
				assert.is_nil(ns.Notes.ItemToken(id, "x"))
			end
			assert.is_nil(ns.Notes.QuestToken(nil, "x"))
		end)

		it("reads a game hyperlink", function()
			ns = wow.boot()
			assert.equal(
				"{item:19019:Thunderfury}",
				ns.Notes.TokenFromLink("|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r")
			)
			assert.equal("{quest:77:A Quest}", ns.Notes.TokenFromLink("|cffffff00|Hquest:77:60|h[A Quest]|h|r"))
			assert.is_nil(ns.Notes.TokenFromLink("|Hplayer:Bob|h[Bob]|h"))
			assert.is_nil(ns.Notes.TokenFromLink(nil))
		end)

		it("keeps a token through the codec", function()
			ns = wow.boot()
			ns.Notes.Add("see {item:19019:Thunderfury} now")
			assert.equal("see {item:19019:Thunderfury} now", noteLines()[1].text)
		end)
	end)
end)
