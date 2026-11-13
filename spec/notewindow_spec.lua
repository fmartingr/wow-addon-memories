local wow = require("helpers.wow")

describe("note window", function()
	wow.pin_locale("enUS", before_each, after_each)

	local ns
	local chat

	local function install()
		chat = { active = nil, deactivated = 0 }
		_G.UISpecialFrames = {}
		_G.ChatEdit_GetActiveWindow = function()
			return chat.active
		end
		_G.ChatEdit_DeactivateChat = function(box)
			chat.deactivated = chat.deactivated + 1
			if chat.active == box then
				chat.active = nil
			end
		end
		-- As the game does: with no chat box active, a link opens the chat box, which takes the focus.
		_G.ChatEdit_InsertLink = function(link)
			if not chat.active then
				chat.active = {
					text = link,
					GetText = function(self)
						return self.text
					end,
					SetText = function(self, text)
						self.text = text
					end,
				}
				chat.opened = chat.active
				for _, f in ipairs(wow.frames) do
					if f.kind == "EditBox" and f.focused then
						f:ClearFocus()
					end
				end
			end
			return true
		end
		_G.GetCursorInfo = function()
			return nil
		end
		_G.ClearCursor = function()
			chat.cleared = (chat.cleared or 0) + 1
		end
	end

	after_each(function()
		for _, name in ipairs({
			"UISpecialFrames",
			"ChatEdit_GetActiveWindow",
			"ChatEdit_DeactivateChat",
			"ChatEdit_InsertLink",
			"GetCursorInfo",
			"ClearCursor",
		}) do
			_G[name] = nil
		end
	end)

	local function boot(opts)
		opts = opts or {}
		opts.login = false
		ns = wow.boot(opts)
		install()
		wow.login()
		return ns
	end

	local function box()
		for i = #wow.frames, 1, -1 do
			local f = wow.frames[i]
			if f.kind == "EditBox" and f.scripts.OnTextChanged then
				return f
			end
		end
	end

	local function button(text)
		for _, f in ipairs(wow.frames) do
			if f.kind == "Button" and f.text == text then
				return f
			end
		end
	end

	local function type_text(text)
		box():SetText(text)
		box().scripts.OnTextChanged(box(), true)
	end

	local function notes()
		local out = {}
		for line in ns.Store.Core():Lines() do
			local ev = ns.Codec.DecodeLine(line)
			if ev.k == "un" then
				out[#out + 1] = ev.text
			end
		end
		return out
	end

	it("opens one frame with the focus in the box, and Escape closes it", function()
		boot()
		ns.NoteWindow.Open()
		local frame = _G.MemoriesNoteFrame
		assert.is_true(frame:IsShown())
		assert.is_true(box().focused)
		assert.equal(400, box().maxBytes)
		assert.same({ "MemoriesNoteFrame" }, _G.UISpecialFrames)
		box().scripts.OnEscapePressed()
		assert.is_false(frame:IsShown())
	end)

	it("keeps the draft on a second open, clears it after a close, and makes no second frame", function()
		boot()
		ns.NoteWindow.Open()
		type_text("first")
		ns.NoteWindow.Open()
		assert.equal("first", box():GetText())
		assert.is_true(box().focused)
		ns.NoteWindow.Open("second")
		assert.equal("second", box():GetText())
		button("Cancel").scripts.OnClick()
		ns.NoteWindow.Open()
		assert.equal("", box():GetText())
		assert.equal(1, #_G.UISpecialFrames)
	end)

	it("shows the byte counter and keeps Save off for white space only", function()
		boot()
		ns.NoteWindow.Open()
		assert.is_false(button("Save").enabled)
		type_text("   ")
		assert.is_false(button("Save").enabled)
		type_text("hello")
		assert.is_true(button("Save").enabled)
		local function counter(text)
			for _, f in ipairs(wow.frames) do
				if f.kind == "FontString" and f.text == text then
					return f
				end
			end
		end
		assert.equal(1, counter("5 / 400").textColor[2])
		type_text(string.rep("a", 400))
		assert.equal(0.2, counter("400 / 400").textColor[2])
	end)

	it("saves one un line, closes, and prints one line", function()
		boot()
		ns.NoteWindow.Open()
		type_text("a note")
		button("Save").scripts.OnClick()
		assert.same({ "a note" }, notes())
		assert.is_false(_G.MemoriesNoteFrame:IsShown())
		assert.equal("Memories: note saved.", wow.chat()[#wow.chat()])
	end)

	it("saves in combat", function()
		boot()
		wow.combat = true
		ns.NoteWindow.Open()
		type_text("in a fight")
		button("Save").scripts.OnClick()
		assert.same({ "in a fight" }, notes())
	end)

	it("keeps the window and the text when the kind is off", function()
		boot({ saved = { MemoriesDB = { settings = { kinds = { un = false } } } } })
		ns.NoteWindow.Open()
		type_text("hello")
		button("Save").scripts.OnClick()
		assert.same({}, notes())
		assert.is_true(_G.MemoriesNoteFrame:IsShown())
		assert.equal("hello", box():GetText())
		assert.equal("Memories: notes are off in the settings.", wow.chat()[#wow.chat()])
	end)

	it("keeps the window for a read-only journal", function()
		boot({ saved = { MemoriesDB = { schema = 99 } } })
		ns.NoteWindow.Open("hello")
		button("Save").scripts.OnClick()
		assert.is_true(_G.MemoriesNoteFrame:IsShown())
		assert.equal("Memories: the journal is read only; the note was not saved.", wow.chat()[#wow.chat()])
	end)

	it("closes with Cancel and writes nothing", function()
		boot()
		ns.NoteWindow.Open("hello")
		button("Cancel").scripts.OnClick()
		assert.is_false(_G.MemoriesNoteFrame:IsShown())
		assert.same({}, notes())
	end)

	describe("links", function()
		local ITEM = "|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
		local QUEST = "|cffffff00|Hquest:77:60|h[A Quest]|h|r"

		it("a shift-click while the box has the focus adds the token and closes the chat box", function()
			boot()
			ns.NoteWindow.Open("see ")
			ChatEdit_InsertLink(ITEM)
			assert.equal("see {item:19019:Thunderfury}", box():GetText())
			assert.equal(1, chat.deactivated)
			assert.is_true(box().focused)
			ChatEdit_InsertLink(QUEST)
			assert.equal("see {item:19019:Thunderfury}{quest:77:A Quest}", box():GetText())
		end)

		it("empties the chat box that the shift-click filled with the link", function()
			boot()
			ns.NoteWindow.Open()
			ChatEdit_InsertLink(ITEM)
			assert.equal("", chat.opened.text)
		end)

		it("does nothing when the box has not the focus, or the window is closed", function()
			boot()
			ChatEdit_InsertLink(ITEM)
			assert.is_nil(_G.MemoriesNoteFrame)
			ns.NoteWindow.Open()
			box():ClearFocus()
			wow.advance(1)
			ChatEdit_InsertLink(ITEM)
			assert.equal("", box():GetText())
			assert.equal(0, chat.deactivated)
		end)

		it("ignores a link that is not an item or a quest", function()
			boot()
			ns.NoteWindow.Open()
			ChatEdit_InsertLink("|Hplayer:Bob|h[Bob]|h")
			assert.equal("", box():GetText())
		end)

		it("prints one message and adds nothing when the token does not fit", function()
			boot()
			ns.NoteWindow.Open(string.rep("a", 395))
			ChatEdit_InsertLink(ITEM)
			assert.equal(string.rep("a", 395), box():GetText())
			assert.equal("Memories: the link does not fit in the note.", wow.chat()[#wow.chat()])
		end)

		it("a drop of an item adds the token and clears the cursor", function()
			boot()
			ns.NoteWindow.Open()
			_G.GetCursorInfo = function()
				return "item", 19019, ITEM
			end
			box().scripts.OnReceiveDrag()
			assert.equal("{item:19019:Thunderfury}", box():GetText())
			assert.equal(1, chat.cleared)
		end)

		it("a drop of a spell does nothing", function()
			boot()
			ns.NoteWindow.Open()
			_G.GetCursorInfo = function()
				return "spell", 1, 2
			end
			box().scripts.OnReceiveDrag()
			assert.equal("", box():GetText())
			assert.is_nil(chat.cleared)
		end)
	end)

	describe("/memories note", function()
		it("opens the window with the text of the command", function()
			boot()
			SlashCmdList.MEMORIES("note remember this")
			assert.is_true(_G.MemoriesNoteFrame:IsShown())
			assert.equal("remember this", box():GetText())
		end)

		it("turns a link of the command into a token", function()
			boot()
			SlashCmdList.MEMORIES("note buy |cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r now")
			assert.equal("buy {item:19019:Thunderfury} now", box():GetText())
		end)

		it("turns a link with a named colour, or with no colour, into a token", function()
			boot()
			SlashCmdList.MEMORIES(
				"note |cnIQ4:|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r and |Hquest:77:60|h[A Quest]|h"
			)
			assert.equal("{item:19019:Thunderfury} and {quest:77:A Quest}", box():GetText())
		end)

		it("opens an empty window with no text", function()
			boot()
			SlashCmdList.MEMORIES("note")
			assert.equal("", box():GetText())
		end)
	end)
end)
