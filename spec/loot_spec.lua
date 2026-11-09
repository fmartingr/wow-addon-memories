local wow = require("helpers.wow")

describe("loot", function()
	wow.pin_locale("enUS", before_each, after_each)

	local LINEN, SWORD, RING, FLASK = 2589, 2488, 11287, 3087
	local WHITE, GREEN, BLUE = "|cffffffff", "|cff1eff00", "|cff0070dd"

	local ns, eco

	local function boot(opts)
		opts = opts or {}
		opts.addons = opts.addons or { "Memories", "Memories_Economy" }
		local all
		ns, all = wow.boot(opts)
		eco = all.Memories_Economy
		wow.item_info[LINEN] = { quality = 1, class = 7, equipLoc = "" }
		wow.item_info[SWORD] = { quality = 2, class = 2, equipLoc = "INVTYPE_WEAPON" }
		wow.item_info[RING] = { quality = 3, class = 4, equipLoc = "INVTYPE_FINGER" }
		wow.item_info[FLASK] = { quality = 1, class = 0, equipLoc = "" }
		return ns
	end

	local function journal()
		return ns.Registry.Journal("Memories_Economy").journal
	end

	-- The economy lines as "kind|fields", in journal order.
	local function lines(kind)
		local out = {}
		for line in journal():Lines() do
			local rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(.*)$")
			if not rest:match("^nt|") and (not kind or rest:match("^" .. kind .. "|")) then
				out[#out + 1] = rest
			end
		end
		return out
	end

	local function counts()
		return journal():Counts("loot")
	end

	local function link(id, name, color)
		return (color or WHITE) .. "|Hitem:" .. id .. "::::::::10:::::|h[" .. name .. "]|h|r"
	end

	local function loot(msg)
		wow.fire("CHAT_MSG_LOOT", msg)
	end

	local function history(key, text)
		return "|HlootHistory:" .. key .. "|h[Botín]|h: " .. text
	end

	local function newOnly(on)
		ns.Settings.Set("newOnly.loot", on)
	end

	local function sword()
		return link(SWORD, "Espada de fuego", GREEN)
	end

	describe("items", function()
		it("writes a looted stack with every count", function()
			boot()
			loot("Recibes botín: " .. link(LINEN, "Paño de lino") .. "x2.")
			assert.same({ "lo|2589|1|2|loot|Paño de lino||1" }, lines())
			assert.equal(2, counts().items)
			assert.equal(2, counts().q1)
			assert.equal(2, counts()["item:2589"])
		end)

		it("leaves first empty for a known item and the count empty for one", function()
			boot()
			journal():Count("loot", "item:2589", 5)
			loot("Recibes botín: " .. link(LINEN, "Paño de lino") .. ".")
			assert.same({ "lo|2589|1||loot|Paño de lino" }, lines())
			assert.equal(6, counts()["item:2589"])
		end)

		it("writes into its own saved file only", function()
			local core = boot().Store.Core()
			local before = core:LineCount()
			loot("Recibes botín: " .. sword() .. ".")
			assert.equal(before, core:LineCount())
			assert.is_table(_G.MemoriesEconomyCharDB.log)
			ns = wow.reload()
			assert.same({ "lo|2488|2||loot|Espada de fuego|1|1" }, lines("lo"))
		end)

		it("marks a made item", function()
			boot()
			loot("Creas: " .. link(FLASK, "Frasco vacío") .. "x5.")
			loot("Creas: " .. link(FLASK, "Frasco vacío") .. ".")
			assert.same({ "lo|3087|1|5|made|Frasco vacío||1", "lo|3087|1||made|Frasco vacío" }, lines())
		end)

		it("names a pushed item after Money's window", function()
			boot()
			local function push()
				loot("Recibes objeto: " .. link(FLASK, "Frasco vacío") .. ".")
			end
			push()
			for _, event in ipairs({ "MERCHANT_SHOW", "AUCTION_HOUSE_SHOW", "QUEST_COMPLETE", "BANKFRAME_OPENED" }) do
				wow.fire(event)
				push()
			end
			loot("Recibes objeto: " .. link(FLASK, "Frasco vacío") .. "x3.")
			local how = {}
			for i, line in ipairs(lines()) do
				how[i] = line:match("^lo|%d+|%d*|%d*|(%a+)|")
			end
			assert.same({ "other", "bought", "bought", "quest", "other", "other" }, how)
			assert.equal("lo|3087|1|3|other|Frasco vacío", lines()[6])
		end)

		it("reads the quality from the link when the client does not know the item", function()
			boot()
			loot("Recibes botín: " .. link(900001, "Gema rara", "|cnIQ4:") .. ".")
			loot("Recibes botín: " .. link(900002, "Hacha", "|cffA335EE") .. ".")
			loot("Recibes botín: " .. link(900003, "Raro", "|cff123456") .. ".")
			assert.same({
				"lo|900001|4||loot|Gema rara|1|1",
				"lo|900002|4||loot|Hacha|1|1",
				"lo|900003|||loot|Raro|1|1",
			}, lines())
			assert.equal(2, counts().q4)
			assert.equal(3, counts().items)
		end)

		it("marks wearable items", function()
			boot()
			wow.item_info[1] = { class = 2, equipLoc = "INVTYPE_NON_EQUIP_IGNORE" }
			wow.item_info[2] = { class = 15, equipLoc = "INVTYPE_HEAD" }
			wow.item_info[3] = { class = 15, equipLoc = "INVTYPE_NON_EQUIP_IGNORE" }
			wow.item_info[4] = { equipLoc = "INVTYPE_CHEST" }
			wow.item_info[5] = { class = 12 }
			wow.item_info[6] = { class = 4 }
			for id = 1, 6 do
				loot("Recibes botín: " .. link(id, "Cosa") .. ".")
			end
			local gear = {}
			for i, line in ipairs(lines()) do
				gear[i] = line:match("^lo|%d+|%d*|%d*|loot|Cosa|(%d*)") or ""
			end
			assert.same({ "", "1", "", "1", "", "1" }, gear)
		end)

		it("writes an item with no id and no name", function()
			boot()
			newOnly(true)
			loot("Recibes botín: |cff1eff00|Hcurrency:42|h[]|h|r.")
			loot("Recibes botín: |cff1eff00|Hcurrency:42|h[]|h|r.")
			assert.same({ "lo||2||loot|?", "lo||2||loot|?" }, lines())
			assert.equal(2, counts().items)
		end)

		it("ignores a hidden line, a line of another player and an unknown line", function()
			boot()
			loot(wow.secret("Recibes botín: " .. sword() .. "."))
			loot("Bob recibe botín: " .. sword() .. ".")
			loot(history(3, "Bob ha pasado de: " .. sword()))
			assert.same({}, lines())
			assert.is_nil(counts().items)
		end)

		it("writes no line with lo off and still counts", function()
			boot()
			ns.Settings.SetKind("lo", false)
			loot("Recibes botín: " .. link(19019, "Furia de trueno", "|cffa335ee") .. ".")
			assert.same({}, lines())
			assert.equal(1, counts().items)
			assert.equal(1, counts().q4)
			assert.equal(1, counts()["item:19019"])
		end)
	end)

	describe("new findings only", function()
		it("writes the first of an item, then only counts it", function()
			boot()
			newOnly(true)
			loot("Recibes botín: " .. link(LINEN, "Paño de lino") .. ".")
			loot("Recibes botín: " .. link(LINEN, "Paño de lino") .. "x3.")
			assert.same({ "lo|2589|1||loot|Paño de lino||1" }, lines())
			assert.equal(4, counts()["item:2589"])
			assert.equal(4, counts().items)
		end)

		it("writes a rare item again", function()
			boot()
			newOnly(true)
			journal():Count("loot", "item:11287", 2)
			loot("Recibes botín: " .. link(RING, "Anillo de plata", BLUE) .. ".")
			assert.same({ "lo|11287|3||loot|Anillo de plata|1" }, lines())
		end)

		it("writes nothing for items counted before the box was turned on", function()
			boot()
			for _ = 1, 3 do
				loot("Recibes botín: " .. link(LINEN, "Paño de lino") .. ".")
			end
			newOnly(true)
			loot("Recibes botín: " .. link(LINEN, "Paño de lino") .. ".")
			assert.equal(3, #lines())
			assert.equal(4, counts()["item:2589"])
		end)
	end)

	describe("rolls", function()
		local function needAndWin(key, roll)
			loot(history(key, "Has seleccionado Necesidad para: " .. sword()))
			loot(history(key, "Necesidad - " .. roll .. " para " .. sword() .. " por Kaelys"))
		end

		it("writes one roll and one item for a win shown three times", function()
			boot()
			needAndWin(7, 100)
			loot(history(7, "Necesidad - 12 para " .. sword() .. " por Kaelys"))
			for _ = 1, 3 do
				loot(history(7, "Has ganado: " .. sword()))
			end
			assert.same({ "rl|2488|need|100|1|Espada de fuego|2", "lo|2488|2||roll|Espada de fuego|1|1" }, lines())
			assert.equal(1, counts().perfect)
			assert.equal(1, counts()["perfect:need:2488"])
			assert.equal(1, counts().needRolls)
			assert.equal(1, counts().needWon)
		end)

		it("skips the loot line of an item won a moment ago, once", function()
			boot()
			needAndWin(7, 64)
			loot(history(7, "Has ganado: " .. sword()))
			wow.advance(2)
			loot("Recibes botín: " .. sword() .. ".")
			assert.equal(1, #lines("lo"))
			loot("Recibes botín: " .. sword() .. ".")
			assert.equal(2, #lines("lo"))
			assert.equal(2, counts()["item:2488"])
		end)

		it("writes no item for a win of an item received a moment ago", function()
			boot()
			loot("Recibes botín: " .. sword() .. ".")
			wow.advance(3)
			needAndWin(8, 30)
			loot(history(8, "Has ganado: " .. sword()))
			assert.same({ "lo|2488|2||loot|Espada de fuego|1|1", "rl|2488|need|30|1|Espada de fuego|2" }, lines())
		end)

		it("forgets a received item after 10 s", function()
			boot()
			loot("Recibes botín: " .. sword() .. ".")
			wow.advance(11)
			loot(history(1, "Has ganado: " .. sword()))
			assert.same({ "lo|2488|2||loot|Espada de fuego|1|1", "lo|2488|2||roll|Espada de fuego|1" }, lines("lo"))
		end)

		it("writes no second item for a second win within 10 s", function()
			boot()
			loot(history(1, "Has ganado: " .. sword()))
			wow.advance(6)
			loot(history(2, "Has ganado: " .. sword()))
			assert.same({ "lo|2488|2||roll|Espada de fuego|1|1" }, lines("lo"))
		end)

		it("writes each of two copies won in a row, whichever line comes first", function()
			boot()
			loot(history(1, "Has ganado: " .. sword()))
			loot("Recibes botín: " .. sword() .. ".")
			wow.advance(1)
			loot(history(2, "Has ganado: " .. sword()))
			loot("Recibes botín: " .. sword() .. ".")
			wow.advance(11)
			loot("Recibes botín: " .. sword() .. ".")
			loot(history(3, "Has ganado: " .. sword()))
			wow.advance(1)
			loot("Recibes botín: " .. sword() .. ".")
			loot(history(4, "Has ganado: " .. sword()))
			assert.equal(4, #lines("lo"))
			assert.equal(4, counts()["item:2488"])
		end)

		it("writes a lost greed roll for a win by another player", function()
			boot()
			local ring = link(RING, "Anillo de plata", BLUE)
			loot(history(9, "Has seleccionado Codicia para: " .. ring))
			loot(history(9, "Codicia - 45 para " .. ring .. " por Kaelys"))
			loot(history(9, "Codicia - 88 para " .. ring .. " por Bob Stone"))
			loot(history(9, "Bob Stone ha ganado: " .. ring))
			loot(history(9, "Bob Stone ha ganado: " .. ring))
			assert.same({ "rl|11287|greed|45|0|Anillo de plata|3" }, lines())
			assert.equal(1, counts().greedRolls)
			assert.is_nil(counts().greedWon)
		end)

		it("takes a win by name with a surname as the player's own", function()
			boot()
			loot(history(4, "Codicia - 3 para " .. sword() .. " por Kaelys Brumasol"))
			loot(history(4, "Kaelys Brumasol ha ganado: " .. sword()))
			assert.same({ "rl|2488|greed|3|1|Espada de fuego|2", "lo|2488|2||roll|Espada de fuego|1|1" }, lines())
			assert.equal(1, counts().greedWon)
		end)

		it("ignores the rolls and wins of others when the player did not roll", function()
			boot()
			loot(history(5, "Necesidad - 70 para " .. sword() .. " por Bob"))
			loot(history(5, "Kaelysa ha ganado: " .. sword()))
			assert.same({}, lines())
		end)

		it("closes a roll with no line when everyone passed", function()
			boot()
			needAndWin(6, 20)
			loot(history(6, "Todos han pasado de: " .. sword()))
			loot(history(6, "Bob ha ganado: " .. sword()))
			wow.advance(301)
			loot("Recibes botín: " .. link(LINEN, "Paño de lino") .. ".")
			assert.same({ "lo|2589|1||loot|Paño de lino||1" }, lines("[lr][ol]"))
		end)

		it("closes a roll with no result after 300 s on the next loot line", function()
			boot()
			needAndWin(3, 57)
			wow.advance(300)
			loot("Recibes botín: " .. link(LINEN, "Paño de lino") .. ".")
			assert.equal(0, #lines("rl"))
			wow.advance(1)
			loot("Recibes botín: " .. link(LINEN, "Paño de lino") .. ".")
			assert.same({ "rl|2488|need|57||Espada de fuego|2" }, lines("rl"))
			assert.is_nil(counts().needWon)
		end)

		it("writes no rl with rl off and still counts", function()
			boot()
			ns.Settings.SetKind("rl", false)
			needAndWin(7, 100)
			loot(history(7, "Has ganado: " .. sword()))
			assert.same({ "lo|2488|2||roll|Espada de fuego|1|1" }, lines())
			assert.equal(1, counts().perfect)
			assert.equal(1, counts().needWon)
		end)

		it("keys a roll by item without the loot history link", function()
			boot({
				strings = {
					LOOT_ROLL_GREED_SELF = "Has seleccionado Codicia para: %s",
					LOOT_ROLL_YOU_WON = "Has ganado: %s",
				},
			})
			loot("Has seleccionado Codicia para: " .. sword())
			loot("Has ganado: " .. sword())
			loot("Has ganado: " .. sword())
			assert.same({ "rl|2488|greed||1|Espada de fuego|2", "lo|2488|2||roll|Espada de fuego|1|1" }, lines())
		end)

		it("reads a translation that reorders the arguments", function()
			boot({
				strings = {
					LOOT_ROLL_ROLLED_NEED = "|HlootHistory:%1$d|h[Botín]|h: %4$s tira %2$d (Necesidad) por %3$s",
				},
			})
			loot(history(2, "Kaelys tira 99 (Necesidad) por " .. sword()))
			loot(history(2, "Has ganado: " .. sword()))
			assert.same("rl|2488|need|99|1|Espada de fuego|2", lines()[1])
		end)

		it("reads no roll with a hidden player name", function()
			boot()
			wow.player.name = wow.secret("Kaelys")
			needAndWin(7, 40)
			loot(history(7, "Kaelys ha ganado: " .. sword()))
			assert.same({ "rl|2488|need||0|Espada de fuego|2" }, lines())
		end)
	end)

	describe("formats", function()
		it("compiles a format into a pattern for the whole text", function()
			boot()
			local c = eco.Compile("100%% %s: %d.", { "who", "count" })
			assert.same({ who = "Bob", count = "3" }, eco.Match(c, "100% Bob: 3."))
			assert.is_nil(eco.Match(c, "100% Bob: 3. más"))
		end)

		it("refuses a format that it cannot read", function()
			boot()
			assert.is_nil(eco.Compile(nil, { "item" }))
			assert.is_nil(eco.Compile("Recibes %q", { "item" }))
			assert.is_nil(eco.Compile("Recibes %s %s", { "item" }))
			assert.is_nil(eco.Compile("Recibes botín.", { "item" }))
			assert.is_nil(eco.Compile("|HlootHistory:%d|h[Botín]|h: %1$d", { "item" }))
		end)

		it("skips a loot line whose GlobalStrings format is missing or broken", function()
			boot({ strings = { LOOT_ITEM_SELF = "Recibes botín %q" } })
			loot("Recibes botín: " .. sword() .. ".")
			loot("Recibes botín: " .. sword() .. "x2.")
			assert.same({ "lo|2488|2|2|loot|Espada de fuego|1|1" }, lines())
		end)
	end)

	describe("gear", function()
		local function wear()
			wow.gear[1] = { id = 7413, quality = 2 }
			wow.gear[5] = { id = 6129, quality = 1 }
			wow.gear[16] = { id = 2488, quality = 2 }
		end

		local IDS = "7413,0,0,0,6129,0,0,0,0,0,0,0,0,0,0,2488,0,0,0"

		it("writes a gear snapshot 4 s after login", function()
			boot({ login = false })
			wear()
			wow.login()
			wow.advance(3.9)
			assert.same({}, lines())
			wow.advance(0.1)
			assert.same({ "ge|10|" .. IDS .. "|login" }, lines())
			assert.equal(IDS, journal():Snap(10, "gear"))
		end)

		it("writes no login snapshot when the level has one", function()
			boot()
			wear()
			wow.advance(5)
			ns = wow.reload()
			wow.advance(5)
			assert.same({ "ge|10|" .. IDS .. "|login" }, lines())
		end)

		it("writes a ding snapshot 2 s after a level up", function()
			boot()
			wow.advance(5)
			wear()
			wow.fire("PLAYER_LEVEL_UP", 13)
			wow.advance(1.9)
			assert.equal(1, #lines("ge"))
			wow.advance(0.1)
			assert.same("ge|13|" .. IDS .. "|ding", lines("ge")[2])
			assert.equal(IDS, journal():Snap(13, "gear"))
		end)

		it("writes a ding snapshot after a login one at the same level", function()
			boot()
			wow.advance(5)
			wow.fire("PLAYER_LEVEL_UP", 10)
			wow.advance(2)
			assert.equal(2, #lines("ge"))
		end)

		it("writes no login snapshot with an unknown level", function()
			boot({ login = false })
			wow.player.level = wow.secret(10)
			wow.login()
			wow.advance(5)
			assert.same({}, lines())
		end)

		it("writes each changed slot after the baseline, once per burst", function()
			boot({ login = false })
			wear()
			wow.login()
			wow.advance(5)
			wow.gear[5] = nil
			wow.gear[3] = { id = 2582, quality = 3 }
			for _ = 1, 3 do
				wow.fire("PLAYER_EQUIPMENT_CHANGED", 5, false)
				wow.advance(0.2)
			end
			assert.same({}, lines("eq"))
			wow.advance(0.5)
			assert.same({ "eq|3|2582|3", "eq|5|0" }, lines("eq"))
		end)

		it("takes the first scan as the baseline", function()
			boot()
			wear()
			wow.fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
			wow.advance(1)
			assert.same({}, lines("eq"))
			wow.gear[1] = nil
			wow.fire("PLAYER_EQUIPMENT_CHANGED", 1, false)
			wow.advance(1)
			assert.same({ "eq|1|0" }, lines("eq"))
		end)

		it("never counts a hidden slot as a change", function()
			boot()
			wear()
			wow.gear[5] = { id = wow.secret(6129) }
			wow.advance(5)
			assert.same({ "ge|10|7413,0,0,0,?,0,0,0,0,0,0,0,0,0,0,2488,0,0,0|login" }, lines("ge"))
			wow.gear[5] = { id = 6129, quality = 1 }
			wow.fire("PLAYER_EQUIPMENT_CHANGED", 5, true)
			wow.advance(1)
			wow.gear[5] = { id = wow.secret(4000) }
			wow.fire("PLAYER_EQUIPMENT_CHANGED", 5, true)
			wow.advance(1)
			wow.gear[5] = { id = 6129, quality = 1 }
			wow.fire("PLAYER_EQUIPMENT_CHANGED", 5, true)
			wow.advance(1)
			assert.same({}, lines("eq"))
		end)

		it("writes no ge or eq with the kinds off and keeps the snapshot", function()
			boot()
			ns.Settings.SetKind("ge", false)
			ns.Settings.SetKind("eq", false)
			wear()
			wow.advance(5)
			wow.gear[1] = nil
			wow.fire("PLAYER_EQUIPMENT_CHANGED", 1, false)
			wow.advance(1)
			assert.same({}, lines())
			assert.equal(IDS, journal():Snap(10, "gear"))
		end)

		it("reads empty slots without the inventory functions", function()
			boot({ login = false })
			_G.GetInventoryItemID = nil
			wow.login()
			wow.advance(5)
			assert.same({ "ge|10|0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0|login" }, lines())
		end)
	end)

	describe("registration", function()
		it("registers its kinds and the new-only box", function()
			boot()
			for kind, group in pairs({ lo = "Loot", rl = "Loot", ge = "Loot", eq = "Loot", mn = "Money", tb = "Money" }) do
				local spec = ns.Kinds.Get(kind)
				assert.equal("Memories_Economy", spec.addon)
				assert.equal(group, spec.group)
			end
			for _, kind in ipairs({ "ah", "ma", "tr" }) do
				assert.equal("Money", ns.Kinds.Get(kind).group)
			end
			local box = ns.Registry.Registered()[1].boxes[1]
			assert.equal("loot", box.key)
			assert.same({ "lo" }, box.kinds)
		end)

		it("records after a registration after login", function()
			ns = wow.boot({ addons = { "Memories" } })
			eco = wow.load_addon("Memories_Economy")
			loot("Recibes botín: " .. sword() .. ".")
			assert.equal(1, #lines())
			assert.same({}, ns.Errors())
		end)

		it("stops with one line when it loads before the core", function()
			boot({ order = "reverse" })
			assert.equal("Memories_Economy: Memories is not loaded.", wow.chat()[1])
			assert.is_nil(ns.Kinds.Get("lo"))
			assert.is_nil(eco.Money)
		end)

		it("writes and counts nothing with a read-only journal", function()
			boot({ saved = { MemoriesEconomyCharDB = { schema = 99, counts = {} } } })
			loot("Recibes botín: " .. sword() .. ".")
			assert.same({}, lines())
			assert.same({}, counts())
		end)
	end)
end)
