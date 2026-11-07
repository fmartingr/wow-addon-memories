local wow = require("helpers.wow")

describe("social", function()
	local ALLIANCE = { "Alliance", "Alianza" }
	local OAK = { name = "Oak Guard", rank = "Miembro", index = 3 }

	local ns, units

	local function player(name, extra)
		local u = {
			name = name,
			isPlayer = true,
			class = { "Guerrero", "WARRIOR", 1 },
			race = { "Enano", "Dwarf", 3 },
			level = 12,
			faction = ALLIANCE,
		}
		for k, v in pairs(extra or {}) do
			u[k] = v
		end
		return u
	end

	local function boot(opts)
		opts = opts or {}
		opts.addons = opts.addons or { "Memories", "Memories_Social" }
		units = opts.units or {}
		opts.units = units
		ns = wow.boot(opts)
		wow.advance(11)
		return ns
	end

	local function social()
		return wow.ns.Memories_Social.Social
	end

	local function journal()
		return ns.Registry.Journal("Memories_Social").journal
	end

	-- The social lines as "kind|fields", in journal order.
	local function lines()
		local out = {}
		for line in journal():Lines() do
			local rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(.*)$")
			if not rest:match("^nt|") then
				out[#out + 1] = rest
			end
		end
		return out
	end

	local function counts()
		return journal():Counts("social")
	end

	local function roster()
		wow.fire("GROUP_ROSTER_UPDATE")
		wow.advance(1)
	end

	local function guildEvent(event)
		wow.fire(event or "PLAYER_GUILD_UPDATE")
		wow.advance(2)
	end

	describe("group", function()
		it("merges the roster events into one scan 1 s after the last one", function()
			boot()
			units.party1 = player("Ann", { surname = "Roble", guild = "Oak Guard" })
			units.party2 = player("Bob", { class = { "Maga", "MAGE", 8 }, level = 14 })
			for _ = 1, 3 do
				wow.fire("GROUP_ROSTER_UPDATE")
				wow.advance(0.25)
			end
			wow.advance(0.7)
			assert.same({}, lines())
			wow.advance(0.05)
			assert.same({ "gj|Ann Roble|Oak Guard|WARRIOR|12", "gj|Bob||MAGE|14" }, lines())
			assert.equal(2, counts().joins)
			assert.same({ "Ann Roble", "Bob" }, social().OpenMembers())
		end)

		it("counts a joiner of your own guild", function()
			boot({ guild = OAK })
			units.party1 = player("Bob", { guild = "Oak Guard" })
			units.party2 = player("Cid", { guild = "Red Fang" })
			roster()
			assert.equal(2, counts().joins)
			assert.equal(1, counts().guildmateJoins)
		end)

		it("writes the leaves after the joins, sorted by name", function()
			boot()
			units.party1 = player("Zed")
			units.party2 = player("Abe")
			roster()
			units.party1, units.party2 = player("Cid"), nil
			roster()
			assert.same(
				{ "gj|Zed||WARRIOR|12", "gj|Abe||WARRIOR|12", "gj|Cid||WARRIOR|12", "gl|Abe", "gl|Zed" },
				lines()
			)
		end)

		it("writes leaves for everyone when you leave the group", function()
			boot()
			units.party1 = player("Ann")
			roster()
			units.party1 = nil
			roster()
			assert.same({ "gj|Ann||WARRIOR|12", "gl|Ann" }, lines())
			assert.same({}, social().OpenMembers())
		end)

		it("writes only the new member after a reload", function()
			boot()
			units.party1, units.party2 = player("Ann"), player("Bob")
			roster()
			units.party2 = nil
			roster()
			units.party2 = player("Cid")
			ns = wow.reload()
			wow.advance(5)
			assert.same({ "gj|Ann||WARRIOR|12", "gj|Bob||WARRIOR|12", "gl|Bob", "gj|Cid||WARRIOR|12" }, lines())
		end)

		it("writes no leave while a member's name is unknown", function()
			boot()
			units.party1, units.party2 = player("Ann"), player("Bob")
			roster()
			units.party2 = player(wow.secret("Bob"))
			roster()
			assert.equal(2, #lines())
			units.party2 = nil
			roster()
			assert.same("gl|Bob", lines()[3])
		end)

		it("reads raid units and skips yourself", function()
			boot()
			wow.group.raid, wow.group.n = true, 3
			units.raid1 = wow.player
			units.raid2 = player("Ann")
			units.raid3 = player("Bob", { isPlayer = false })
			roster()
			assert.same({ "gj|Ann||WARRIOR|12" }, lines())
		end)

		it("scans the group 5 s after login", function()
			units = { party1 = player("Ann") }
			wow.boot({ addons = { "Memories", "Memories_Social" }, units = units })
			wow.advance(4.9)
			ns = wow.ns.Memories
			assert.same({}, lines())
			wow.advance(0.1)
			assert.same({ "gj|Ann||WARRIOR|12" }, lines())
		end)

		it("scans again when a backup restores the journal", function()
			boot()
			units.party1 = player("Ann")
			ns.Emit("RESTORED", "Memories")
			wow.advance(1)
			assert.same({}, lines())
			ns.Emit("RESTORED", "Memories_Social")
			wow.advance(1)
			assert.same({ "gj|Ann||WARRIOR|12" }, lines())
		end)

		it("writes no line with gj and gl off and still counts", function()
			boot()
			ns.Settings.SetKind("gj", false)
			ns.Settings.SetKind("gl", false)
			units.party1 = player("Ann")
			roster()
			units.party1 = nil
			roster()
			assert.same({}, lines())
			assert.equal(1, counts().joins)
			assert.same({}, social().OpenMembers())
		end)
	end)

	describe("guild", function()
		it("writes nothing with no guild and no gu ever", function()
			boot()
			assert.same({}, lines())
			assert.equal(0, wow.roster_asks)
		end)

		it("asks for the roster and writes gu 7 s after login", function()
			wow.boot({ addons = { "Memories", "Memories_Social" }, guild = OAK })
			ns = wow.ns.Memories
			assert.equal(1, wow.roster_asks)
			wow.advance(6.9)
			assert.same({}, lines())
			wow.advance(0.1)
			assert.same({ "gu|Oak Guard|Miembro" }, lines())
			assert.equal(1, counts().guildChanges)
		end)

		it("waits for a guild name, and a roster event writes it", function()
			boot({ guild = true })
			assert.same({}, lines())
			wow.guild = OAK
			guildEvent("GUILD_ROSTER_UPDATE")
			assert.same({ "gu|Oak Guard|Miembro" }, lines())
		end)

		it("writes a rank change, snaps the level and keeps the tabard", function()
			boot({ guild = OAK })
			wow.tabard = {
				backgroundColor = { r = 0.12345, g = 0.5, b = 1 },
				emblemColor = { r = 1, g = 1, b = 1 },
				emblemFileID = 131,
				emblemStyle = 4,
			}
			wow.guild = { name = "Oak Guard", rank = "Oficial", index = 1 }
			guildEvent("GUILDTABARD_UPDATE")
			assert.same({ "gu|Oak Guard|Miembro", "gu|Oak Guard|Oficial" }, lines())
			assert.equal(2, counts().guildChanges)
			local tabard = {
				background = { 0.123, 0.5, 1 },
				emblem = { 1, 1, 1 },
				file = 131,
				style = 4,
			}
			assert.same(
				{ name = "Oak Guard", rank = "Oficial", index = 1, tabard = tabard },
				journal():Snap(10, "guild")
			)
			assert.same(tabard, journal():State("tabards")["Oak Guard"])
		end)

		it("snaps a redesigned tabard without a line", function()
			boot({ guild = OAK })
			wow.tabard = { emblemFileID = 1, emblemStyle = 1 }
			guildEvent("GUILDTABARD_UPDATE")
			assert.equal(1, journal():Snap(10, "guild").tabard.file)
			wow.tabard = { emblemFileID = 2, emblemStyle = 1 }
			guildEvent("GUILDTABARD_UPDATE")
			assert.equal(2, journal():Snap(10, "guild").tabard.file)
			assert.equal(2, journal():State("tabards")["Oak Guard"].file)
			assert.same({ "gu|Oak Guard|Miembro" }, lines())
		end)

		it("compares a restored journal with the current guild", function()
			boot({ guild = OAK })
			journal():State("guild").guild = nil
			ns.Emit("RESTORED", "Memories_Social")
			wow.advance(2)
			assert.same({ "gu|Oak Guard|Miembro", "gu|Oak Guard|Miembro" }, lines())
		end)

		it("writes gu with an empty guild when you leave, with no snapshot", function()
			boot({ guild = OAK })
			wow.guild = nil
			guildEvent()
			wow.player.level = 11
			guildEvent()
			assert.same({ "gu|Oak Guard|Miembro", "gu" }, lines())
			assert.equal("Oak Guard", journal():Snap(10, "guild").name)
			assert.is_nil(journal():Snap(11, "guild"))
		end)

		it("fills the snapshot of a new level and a missing tabard without a line", function()
			boot({ guild = OAK })
			assert.is_nil(journal():Snap(10, "guild").tabard)
			wow.player.level = 11
			guildEvent()
			assert.equal("Oak Guard", journal():Snap(11, "guild").name)
			wow.logo = { 255, 0, 51, 0, 0, 0, 255, 255, 255, 1234, 2 }
			guildEvent()
			assert.equal(1, #lines())
			local tabard = {
				background = { 1, 0, 0.2 },
				border = { 0, 0, 0 },
				emblem = { 1, 1, 1 },
				file = 1234,
				style = 2,
			}
			assert.same(tabard, journal():Snap(11, "guild").tabard)
			assert.same(tabard, journal():State("tabards")["Oak Guard"])
			wow.logo = nil
			guildEvent()
			assert.same(tabard, journal():Snap(11, "guild").tabard)
		end)

		it("keeps the saved tabard on a rank change when the tabard read fails", function()
			boot({ guild = OAK })
			wow.tabard = { emblemFileID = 5, emblemStyle = 1 }
			guildEvent("GUILDTABARD_UPDATE")
			wow.tabard, wow.tabard_error = nil, "no tabard"
			wow.guild = { name = "Oak Guard", rank = "Oficial", index = 1 }
			guildEvent()
			assert.equal("Oficial", journal():Snap(10, "guild").rank)
			assert.equal(5, journal():Snap(10, "guild").tabard.file)
		end)

		it("logs a tabard read that throws and uses the logo", function()
			boot()
			wow.tabard_error = "no tabard"
			wow.logo = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 77 }
			wow.guild = OAK
			guildEvent()
			assert.equal(77, journal():Snap(10, "guild").tabard.file)
			assert.equal("Memories_Social:tabard", ns.Errors()[1].where)
			assert.matches("no tabard", ns.Errors()[1].msg)
		end)

		it("keeps the guild state with gu off", function()
			boot({ guild = OAK })
			ns.Settings.SetKind("gu", false)
			wow.guild = { name = "Red Fang", rank = "Miembro", index = 3 }
			guildEvent()
			ns.Settings.SetKind("gu", true)
			guildEvent()
			assert.same({ "gu|Oak Guard|Miembro" }, lines())
			assert.equal(2, counts().guildChanges)
			assert.equal("Red Fang", social().MyGuild())
		end)

		it("skips the snapshot while the level is unknown", function()
			boot()
			wow.player.level = wow.secret(10)
			wow.guild = OAK
			guildEvent()
			assert.same({ "gu|Oak Guard|Miembro" }, lines())
			assert.is_nil(journal():Snap(10, "guild"))
		end)
	end)

	describe("player memory", function()
		it("reads name, class, race, level, guild and the enemy flag", function()
			boot()
			units.target = player("Kor", {
				surname = "Ash",
				faction = { "Horde", "Horda" },
				class = { "Pícaro", "ROGUE", 4 },
				race = { "Orco", "Orc", 2 },
				guild = "Red Fang",
				level = -1,
			})
			local rec, late = social().Read("target", "target")
			assert.is_false(late)
			assert.same({
				name = "Kor Ash",
				first = "Kor",
				class = "ROGUE",
				race = "Orc",
				guild = "Red Fang",
				enemy = true,
				at = wow.clock,
				source = "target",
				seen = 1,
			}, rec)
		end)

		it("skips yourself, other units and unknown names", function()
			boot()
			units.target = wow.player
			assert.is_nil(social().Read("target", "target"))
			units.target = player("Lobo", { isPlayer = false })
			assert.is_nil(social().Read("target", "target"))
			units.target = player(wow.secret("Ann"))
			assert.is_nil(social().Read("target", "target"))
			units.target = player("Desconocido")
			assert.is_nil(social().Read("target", "target"))
			assert.is_nil(social().Read("focus", "target"))
		end)

		it("merges reads and reports a guild just learned", function()
			boot()
			units.target = player("Ann")
			social().Read("target", "target")
			units.target = player("Ann", { guild = "Oak Guard", level = wow.secret(13) })
			local rec, late = social().Read("target", "mouseover")
			assert.is_true(late)
			assert.equal(12, rec.level)
			assert.equal(2, rec.seen)
			assert.equal("mouseover", rec.source)
			rec, late = social().Read("target", "scan")
			assert.is_false(late)
			assert.equal(3, rec.seen)
		end)

		it("keeps a known enemy when a later read has no faction", function()
			boot()
			units.target = player("Kor", { faction = { "Horde", "Horda" } })
			assert.is_true(social().Read("target", "target").enemy)
			units.target = player("Kor", { faction = false })
			assert.is_true(social().Read("target", "target").enemy)
		end)

		it("logs only the first failed guild read and counts them all", function()
			boot()
			units.target = player("Ann", { guildError = "restricted" })
			local rec = social().Read("target", "target")
			social().Read("target", "target")
			assert.is_nil(rec.guild)
			assert.equal(2, social().guildFailures)
			assert.equal(1, #ns.Errors())
			assert.equal("Memories_Social:guild read", ns.Errors()[1].where)
		end)

		it("returns a 101st non-enemy but does not keep it", function()
			boot()
			for i = 1, 100 do
				social().Remember({ name = "P" .. i, first = "P" .. i })
			end
			local rec = social().Remember({ name = "Extra", first = "Extra" })
			assert.equal("Extra", rec.name)
			assert.is_nil(social().Find("Extra"))
			assert.is_table(social().Remember({ name = "Foe", first = "Foe", enemy = true }))
			assert.is_table(social().Find("Foe"))
		end)

		it("finds by full name, then by the first name", function()
			boot()
			social().Remember({ name = "Ivan Petrov", first = "Ivan" })
			assert.equal("Ivan Petrov", social().Find("Ivan").name)
			assert.equal("Ivan Petrov", social().Find("Ivan Petrov").name)
			assert.equal("Ivan Petrov", social().Find("Ivan Sidorov").name)
			assert.is_nil(social().Find("Olga"))
			assert.is_nil(social().Find(nil))
			assert.is_nil(social().Find("Ivan Sidorov", true))
		end)

		it("turns the first dash of a name from text into a space", function()
			boot()
			assert.equal("Immar Stone", social().NameFromText("Immar-Stone"))
			assert.equal("Ana Lu-Mar", social().NameFromText("Ana-Lu-Mar"))
			assert.is_nil(social().NameFromText(""))
		end)

		it("tells the script and the font of a name", function()
			boot()
			local s = social()
			assert.equal("latin", s.Script("Ñandú"))
			assert.equal("latin", s.Script(nil))
			assert.equal("cyrillic", s.Script("Иван"))
			assert.equal("korean", s.Script("한국"))
			assert.equal("chinese", s.Script("中文"))
			assert.equal("japanese", s.Script("ひらがな"))
			assert.is_nil(s.Font("Иван"))
			assert.equal("Fonts\\2002.TTF", s.Font("한국"))
			assert.equal("Fonts\\ARKai_T.ttf", s.Font("中文"))
			assert.equal("Fonts\\ARKai_T.ttf", s.Font("ひらがな"))
			wow.locale = "zhTW"
			assert.is_nil(s.Font("中文"))
			wow.locale = "koKR"
			assert.is_nil(s.Font("한국"))
		end)
	end)

	describe("registration", function()
		it("registers its kinds in two groups", function()
			boot()
			for _, kind in ipairs({ "gj", "gl", "gu" }) do
				assert.equal("Social", ns.Kinds.Get(kind).group)
				assert.equal("Memories_Social", ns.Kinds.Get(kind).addon)
			end
			for _, kind in ipairs({ "ep", "pk", "hk", "du", "bg", "rk" }) do
				assert.equal("PvP", ns.Kinds.Get(kind).group)
			end
		end)

		it("writes into its own saved file only", function()
			local core = boot({ guild = OAK })
			assert.is_table(_G.MemoriesSocialCharDB.log)
			assert.equal(1, #lines())
			for line in core.Store.Core():Lines() do
				assert.is_nil(line:match("|gu|"))
			end
		end)

		it("records after a registration after login", function()
			ns = wow.boot({ addons = { "Memories" }, guild = OAK })
			wow.load_addon("Memories_Social")
			wow.advance(7)
			assert.same({ "gu|Oak Guard|Miembro" }, lines())
			assert.same({}, ns.Errors())
		end)

		it("stops with one line when it loads before the core", function()
			boot({ order = "reverse" })
			assert.equal("Memories_Social: Memories is not loaded.", wow.chat()[1])
			assert.is_nil(ns.Kinds.Get("gj"))
		end)
	end)
end)
