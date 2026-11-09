local wow = require("helpers.wow")

describe("data guard", function()
	wow.pin_locale("enUS", before_each, after_each)

	local GUID = "Player-1234-0ABCDEF0"
	local ADDONS = { "Memories", "Memories_Test" }

	local function lines(journal)
		local out = {}
		for line in journal:Lines() do
			out[#out + 1] = line
		end
		return out
	end

	local function record(addon)
		return MemoriesDB.backups[GUID][addon]
	end

	local function guards()
		local out = {}
		for _, p in ipairs(wow.popups) do
			if p.which == "MEMORIES_GUARD" then
				out[#out + 1] = p
			end
		end
		return out
	end

	-- The session and zone lines are off, so the core journal holds only the lines that a test writes.
	local QUIET = { ["in"] = false, pc = false, out = false, rs = false, zo = false }

	-- Boots once, writes n lines into the core (and m into the test addon), backs them up and returns MemoriesDB.
	local function withBackup(n, m)
		local ns, all = wow.boot({ addons = ADDONS, saved = { MemoriesDB = { settings = { kinds = QUIET } } } })
		for i = 1, n do
			ns.Store.Core():Write("ex", "test", "line", i)
		end
		ns.Backup.Write("Memories")
		for i = 1, m or 0 do
			all.Memories_Test.handle:Write("zz", "line", i)
		end
		if m then
			ns.Backup.Write("Memories_Test")
		end
		return MemoriesDB
	end

	-- "restore" clicks the first button; any other value is the reason that OnCancel gets.
	local function click(popup, how)
		if how == "restore" then
			popup.info.OnAccept(popup, popup.data)
		else
			popup.info.OnCancel(popup, popup.data, how)
		end
		wow.advance(0)
	end

	it("holds an empty core journal with a backup and asks the player", function()
		local db = withBackup(3)
		local backup = wow.ns.Memories.Backup.Record("Memories")
		local ns = wow.boot({ addons = ADDONS, saved = { MemoriesDB = db } })
		assert.equal(1, #guards())
		local popup = guards()[1]
		local stamp = os.date("%Y-%m-%d %H:%M", backup.t)
		assert.equal("Memories: Memories came back empty. A backup from " .. stamp .. " has 3 lines.", popup.text1)
		assert.equal("Memories", popup.data)
		assert.equal("Restore", popup.info.button1)
		assert.equal("Start fresh", popup.info.button2)
		assert.is_true(record("Memories").hold)
		ns.Store.Core():Write("ex", "test", "new", 1)
		wow.advance(15 * 60)
		assert.equal(backup.blob, record("Memories").blob)
		assert.equal(3, record("Memories").lines)
	end)

	it("restores the lines, writes nt and asks for a reload", function()
		local ns = wow.boot({ addons = ADDONS, saved = { MemoriesDB = withBackup(3) } })
		click(guards()[1], "restore")
		local got = lines(ns.Store.Core())
		assert.equal(4, #got)
		assert.matches("|ex|test|line|3$", got[3])
		assert.matches("|nt|restored backup|3$", got[4])
		assert.is_nil(record("Memories").hold)
		local reload = wow.popups[#wow.popups]
		assert.equal("MEMORIES_RELOAD", reload.which)
		reload.info.OnAccept(reload)
		assert.equal(1, wow.reloads)
	end)

	it("keeps the lines after the reload that follows a restore", function()
		wow.boot({ addons = ADDONS, saved = { MemoriesDB = withBackup(3) } })
		click(guards()[1], "restore")
		local ns = wow.reload()
		assert.equal(4, ns.Store.Core():LineCount())
		assert.equal(0, #guards())
	end)

	it("starts fresh: the hold ends and the next backup replaces the old one", function()
		local ns = wow.boot({ addons = ADDONS, saved = { MemoriesDB = withBackup(3) } })
		click(guards()[1], "clicked")
		assert.is_nil(record("Memories").hold)
		local got = lines(ns.Store.Core())
		assert.equal(1, #got)
		assert.matches("|nt|started fresh|3$", got[1])
		assert.equal(1, #wow.popups)
		ns.Backup.Run()
		assert.equal(1, record("Memories").lines)
	end)

	it("keeps the hold when another popup replaces it", function()
		local ns = wow.boot({ addons = ADDONS, saved = { MemoriesDB = withBackup(3) } })
		click(guards()[1], "override")
		assert.is_true(record("Memories").hold)
		assert.equal(0, ns.Store.Core():LineCount())
	end)

	it("keeps a hold that is still on at logout, with its backup", function()
		local db = withBackup(3)
		local ns = wow.boot({ addons = ADDONS, saved = { MemoriesDB = db } })
		local blob = record("Memories").blob
		ns.Store.Core():Write("ex", "test", "held session", 1)
		ns = wow.reload()
		assert.equal(1, ns.Store.Core():LineCount())
		assert.is_true(record("Memories").hold)
		assert.equal(blob, record("Memories").blob)
		assert.equal(1, #guards())
		click(guards()[1], "restore")
		assert.equal(4, ns.Store.Core():LineCount())
		assert.matches("|held session|1$", lines(ns.Journal.New(MemoriesDB.orphans[1].data, { readOnly = true }))[1])
	end)

	it("asks for each held addon, one at a time", function()
		local ns = wow.boot({ addons = ADDONS, saved = { MemoriesDB = withBackup(2, 4) } })
		assert.equal(1, #guards())
		assert.equal("Memories", guards()[1].data)
		click(guards()[1], "restore")
		assert.equal(2, #guards())
		local second = guards()[2]
		assert.equal("Memories_Test", second.data)
		assert.matches("has 4 lines%.$", second.text1)
		assert.equal("MEMORIES_GUARD", wow.popups[#wow.popups].which)
		click(second, "restore")
		assert.equal(5, MemoriesTestCharDB.lines)
		assert.equal(3, ns.Store.Core():LineCount())
		assert.equal("MEMORIES_RELOAD", wow.popups[#wow.popups].which)
	end)

	it("moves on when another addon hides the popup, but not when the UI hides around it", function()
		wow.boot({ addons = ADDONS, saved = { MemoriesDB = withBackup(2, 4) } })
		local first = guards()[1]
		local shown = true
		local dialog = {
			IsShown = function()
				return shown
			end,
		}
		first.info.OnHide(dialog, first.data)
		wow.advance(0)
		assert.equal(1, #guards())
		shown = false
		first.info.OnHide(dialog, first.data)
		wow.advance(0)
		assert.equal(2, #guards())
		assert.equal("Memories_Test", guards()[2].data)
		assert.is_true(record("Memories").hold)
		first.info.OnHide(dialog, first.data)
		wow.advance(0)
		assert.equal(2, #guards())
	end)

	-- cancels: the client form, which calls OnCancel before it returns nil.
	local function refuseGuard(addon, cancels)
		local show = _G.StaticPopup_Show
		_G.StaticPopup_Show = function(which, text1, text2, data)
			if data ~= addon then
				return show(which, text1, text2, data)
			end
			if cancels then
				StaticPopupDialogs[which].OnCancel(nil, data)
			end
		end
	end

	for _, cancels in ipairs({ false, true }) do
		it(
			"keeps every hold and still asks for the reload when no guard popup can show, cancels " .. tostring(cancels),
			function()
				local db = withBackup(2, 4)
				local ns = wow.boot({ addons = ADDONS, saved = { MemoriesDB = db }, login = false })
				refuseGuard("Memories_Test", cancels)
				wow.login()
				assert.equal(1, #guards())
				click(guards()[1], "restore")
				assert.equal(3, ns.Store.Core():LineCount())
				assert.equal(1, #guards())
				assert.is_true(record("Memories_Test").hold)
				local reloads = 0
				for _, p in ipairs(wow.popups) do
					reloads = reloads + (p.which == "MEMORIES_RELOAD" and 1 or 0)
				end
				assert.equal(1, reloads)
			end
		)
	end

	it("asks for a sub-addon that registers after login", function()
		local db = withBackup(0)
		db.backups = { [GUID] = { Memories_Other = { t = 1, lines = 7, data = { log = { chunks = {}, open = {} } } } } }
		wow.boot({ saved = { MemoriesDB = db } })
		assert.equal(0, #guards())
		Memories.RegisterModule({ addon = "Memories_Other", api = 1, saved = "MemoriesOtherCharDB" })
		assert.equal(1, #guards())
		assert.equal("Memories_Other", guards()[1].data)
		assert.is_true(record("Memories_Other").hold)
	end)

	it("waits for the open popup before it asks for a late sub-addon", function()
		local db = withBackup(2)
		db.backups[GUID].Memories_Other = { t = 1, lines = 7, data = { log = { chunks = {}, open = { "a" } } } }
		db.backups[GUID].Memories_Third = { lines = 2, data = { log = { chunks = {}, open = { "b", "c" } } } }
		local ns = wow.boot({ saved = { MemoriesDB = db } })
		Memories.RegisterModule({ addon = "Memories_Other", api = 1, saved = "MemoriesOtherCharDB" })
		Memories.RegisterModule({ addon = "Memories_Third", api = 1, saved = "MemoriesThirdCharDB" })
		assert.equal(1, #guards())
		assert.equal("Memories", guards()[1].data)
		-- A restore outside the popup ends the hold, so that addon needs no question.
		assert.is_true(ns.Backup.Restore("Memories_Other"))
		click(guards()[1], "clicked")
		assert.equal(2, #guards())
		assert.equal("Memories_Third", guards()[2].data)
		assert.equal(
			"Memories: Memories_Third came back empty. A backup from an unknown date has 2 lines.",
			guards()[2].text1
		)
	end)

	it("starts fresh only for a held addon", function()
		local ns = wow.boot({ addons = ADDONS, saved = { MemoriesDB = withBackup(3) } })
		ns.Guard.StartFresh("Memories_Test")
		assert.equal(0, MemoriesTestCharDB.lines)
	end)

	it("stays quiet for a journal with lines, a backup without lines or a read-only journal", function()
		local db = withBackup(2)
		wow.boot({ addons = ADDONS, saved = { MemoriesDB = db, MemoriesCharDB = MemoriesCharDB } })
		assert.equal(0, #guards())

		db = withBackup(0)
		db.backups = { [GUID] = { Memories = { t = 1, lines = 0, data = {} } } }
		wow.boot({ saved = { MemoriesDB = db } })
		assert.equal(0, #guards())

		db.backups = { [GUID] = { Memories = { t = 1, lines = 5, data = {} } } }
		db.schema = 2
		wow.boot({ saved = { MemoriesDB = db } })
		assert.equal(0, #guards())
		assert.is_nil(db.backups[GUID].Memories.hold)
	end)

	it("prints why a restore failed and keeps the hold", function()
		local db = withBackup(1)
		db.backups[GUID].Memories = { t = 1, lines = 9, blob = "@@@@" }
		local ns = wow.boot({ saved = { MemoriesDB = db } })
		local stamp = os.date("%Y-%m-%d %H:%M", 1)
		assert.equal(
			"Memories: Memories came back empty. A backup from " .. stamp .. " has 9 lines.",
			guards()[1].text1
		)
		click(guards()[1], "restore")
		assert.is_true(record("Memories").hold)
		assert.equal(0, ns.Store.Core():LineCount())
		local chat = wow.chat()
		assert.matches("^Memories: Memories: the backup was not restored %(bad backup", chat[#chat])
		assert.equal("MEMORIES_GUARD", wow.popups[#wow.popups].which)
	end)
end)
