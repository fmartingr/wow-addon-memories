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

	it("writes a pipe as a slash", function()
		ns = wow.boot()
		ns.Notes.Add("a | b || c")
		assert.equal("a / b / c", noteLines()[1].text)
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
		assert.equal(string.rep("a", 395), ns.Notes.Fit(string.rep("a", 395) .. " {item:19019:Thunderfury}"))
		assert.equal(string.rep("a", 397), ns.Notes.Fit(string.rep("a", 397) .. "{it" .. string.rep("b", 50)))
	end)

	it("keeps the text after a brace that is not a token", function()
		ns = wow.boot()
		local text = "a { b " .. string.rep("c", 450)
		assert.equal(text:sub(1, 400), ns.Notes.Fit(text))
		local named = string.rep("a", 390) .. "{note:12 " .. string.rep("b", 50)
		assert.equal(named:sub(1, 400), ns.Notes.Fit(named))
	end)

	it("refuses a note that the cut leaves empty", function()
		ns = wow.boot()
		assert.same({ nil, "empty" }, { ns.Notes.Add("{item:1:" .. string.rep("N", 450)) })
		assert.equal(0, #noteLines())
	end)

	it("keeps one pipe for an escaped pipe of an edit box", function()
		ns = wow.boot()
		assert.equal("a | b", ns.Notes.Clean("a || b"))
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

		it("removes escapes and pipes from a name", function()
			ns = wow.boot()
			local name = "|cffa335eeSword|r |A:Professions-ChatIcon-Quality-Tier3:17:17::1|a|T123:0|t x|y"
			assert.equal("{item:5:Sword xy}", ns.Notes.ItemToken(5, name))
			assert.equal("{item:5:Sword}", ns.Notes.ItemToken(5, "|cnIQ4:Sword|r"))
			assert.equal("{quest:5:One Two}", ns.Notes.QuestToken(5, "One|nTwo"))
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
