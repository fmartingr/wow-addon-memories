local wow = require("helpers.wow")

describe("gathering", function()
	wow.pin_locale("enUS", before_each, after_each)

	local SPELLS = {
		[2575] = "Minería",
		[2366] = "Herboristería",
		[8613] = "Desollar",
		[7620] = "Pesca",
		[921] = "Robar",
		[3365] = "Abriendo",
	}
	local VEIN = "GameObject-0-4389-0-47-1731-00002B3A5C"
	local HERB = "GameObject-0-4389-0-47-1617-00002B3A5D"
	local POOL = "GameObject-0-4389-0-47-180582-00002B3A5E"
	local CHEST = "GameObject-0-4389-0-47-2843-00002B3A5F"
	local DEFIAS = "Creature-0-4389-0-47-116-00002B3A60"
	local WOLF = "Creature-0-4389-0-47-525-00002B3A61"

	local ns

	local function boot(opts)
		opts = opts or {}
		opts.addons = opts.addons or { "Memories", "Memories_Gathering" }
		opts.spells = opts.spells or SPELLS
		ns = wow.boot(opts)
		return ns
	end

	local function journal()
		return ns.Registry.Journal("Memories_Gathering").journal
	end

	-- The gathering lines as "kind|fields", in journal order.
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
		return journal():Counts("gather")
	end

	local function newOnly(on)
		ns.Settings.Set("newOnly.gathering", on)
	end

	local function cast(spell, target)
		wow.send(spell, target)
		wow.cast(spell)
	end

	local function ore(n)
		return { item = 2770, name = "Mena de cobre", count = n, quality = 1, source = VEIN }
	end

	local function mine(slots)
		cast(2575, "Filón de cobre")
		wow.advance(1)
		wow.open_loot({ slots = slots })
	end

	local function herb(slot)
		cast(2366, "Hojaplata")
		wow.advance(1)
		wow.open_loot({ slots = { slot } })
	end

	local function fish(slots)
		wow.cast(7620)
		wow.advance(1)
		wow.open_loot({ fishing = true, slots = slots })
	end

	local function pick(slots)
		cast(921, "Bandido Defias")
		wow.advance(0.5)
		wow.open_loot({ slots = slots })
	end

	local function openChest(slots)
		cast(3365, "Cofre maltrecho")
		wow.advance(1)
		wow.open_loot({ slots = slots })
	end

	local function useBox()
		wow.items[16885] = "Caja fuerte pesada"
		wow.bags[0] = { [3] = { itemID = 16885, hasLoot = true, itemName = "Heavy Junkbox" } }
		C_Container.UseContainerItem(0, 3)
	end

	describe("gather", function()
		it("writes every gathered item with new findings only off", function()
			boot()
			journal():Count("gather", "item:Mining|2770", 5)
			mine({ ore(2) })
			assert.same({ "ga|Mining|Filón de cobre|1731|2770|1|2|Mena de cobre" }, lines())
			assert.equal(2, counts().Mining)
			assert.equal(7, counts()["item:Mining|2770"])
			assert.equal(1, counts()["cast:mined|Filón de cobre|Mining"])
		end)

		it("marks a first find and leaves the count empty for one item", function()
			boot()
			mine({ ore(1) })
			assert.same({ "ga|Mining|Filón de cobre|1731|2770|1||Mena de cobre|first" }, lines())
		end)

		it("writes the line into its own saved file only", function()
			local coreNs = boot()
			local coreLines = coreNs.Store.Core():LineCount()
			mine({ ore(1) })
			assert.equal(coreLines, coreNs.Store.Core():LineCount())
			assert.equal(1, #lines())
			assert.is_table(_G.MemoriesGatheringCharDB.log)
			ns = wow.reload()
			assert.same({ "ga|Mining|Filón de cobre|1731|2770|1||Mena de cobre|first" }, lines())
		end)

		it("writes nothing for a known item with new findings only on, but counts it", function()
			boot()
			journal():Count("gather", "item:Mining|2770", 5)
			newOnly(true)
			mine({ ore(2) })
			assert.same({}, lines())
			assert.equal(2, counts().Mining)
			assert.equal(7, counts()["item:Mining|2770"])
		end)

		it("writes a first find with new findings only on", function()
			boot()
			newOnly(true)
			herb({ item = 765, name = "Hojaplata", quality = 1, source = HERB })
			assert.same({ "ga|Herbalism|Hojaplata|1617|765|1||Hojaplata|first" }, lines())
			assert.equal(1, counts().Herbalism)
		end)

		it("writes a rare find with new findings only on, rare before first", function()
			boot()
			newOnly(true)
			journal():Count("gather", "item:Herbalism|13468", 3)
			herb({ item = 13468, name = "Loto negro", quality = 1, source = HERB })
			herb({ item = 13467, name = "Escarcharraíz", quality = 3, source = HERB })
			assert.same({
				"ga|Herbalism|Hojaplata|1617|13468|1||Loto negro|rare",
				"ga|Herbalism|Hojaplata|1617|13467|3||Escarcharraíz|rare",
			}, lines())
		end)

		it("writes one line for the same item twice with new findings only on, and counts both", function()
			boot()
			newOnly(true)
			mine({ ore(1), ore(1) })
			assert.same({ "ga|Mining|Filón de cobre|1731|2770|1||Mena de cobre|first" }, lines())
			assert.equal(2, counts()["item:Mining|2770"])
		end)

		it("writes no line for items found before new findings only was turned on", function()
			boot()
			for _ = 1, 10 do
				mine({ ore(1) })
			end
			assert.equal(10, #lines())
			newOnly(true)
			mine({ ore(1) })
			assert.equal(10, #lines())
			assert.equal(11, counts()["item:Mining|2770"])
		end)

		it("matches another spell id by its Spanish name", function()
			boot({ spells = { [2575] = "Minería", [99001] = "Minería", [99003] = "Minería" } })
			cast(99001, "Filón de estaño")
			wow.advance(1)
			wow.open_loot({ slots = { { item = 2771, name = "Mena de estaño", quality = 1, source = VEIN } } })
			cast(99003, "Filón de estaño")
			wow.advance(1)
			wow.open_loot({ slots = { { item = 2771, name = "Mena de estaño", quality = 1, source = VEIN } } })
			assert.same({
				"ga|Mining|Filón de estaño|1731|2771|1||Mena de estaño|first",
				"ga|Mining|Filón de estaño|1731|2771|1||Mena de estaño",
			}, lines())
		end)

		it("learns the names once the client answers", function()
			boot({ spells = {} })
			wow.spells[99001] = "Minería"
			cast(99001, "Filón de estaño")
			wow.advance(1)
			wow.open_loot({ slots = { ore(1) } })
			assert.same({}, lines())
			wow.spells[2575] = "Minería"
			cast(99001, "Filón de estaño")
			wow.advance(1)
			wow.open_loot({ slots = { ore(1) } })
			assert.equal(1, #lines())
		end)

		it("forgets a cast after 3 s and after one window", function()
			boot()
			cast(2575, "Filón de cobre")
			wow.advance(3.5)
			wow.open_loot({ slots = { ore(1) } })
			mine({ ore(1) })
			wow.open_loot({ slots = { ore(1) } })
			assert.equal(1, #lines())
		end)

		it("writes ? for a hidden or unmatched target and no object without a source", function()
			boot()
			cast(8613, wow.secret("Lobo"))
			wow.advance(1)
			wow.open_loot({ slots = { { item = 2318, name = "Cuero ligero", quality = 1 } } })
			wow.send(8613, "Lobo")
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-other", 8613)
			wow.advance(1)
			wow.open_loot({ slots = { { item = 2318, name = "Cuero ligero", quality = 1, source = WOLF } } })
			assert.same({
				"ga|Skinning|?||2318|1||Cuero ligero|first",
				"ga|Skinning|?||2318|1||Cuero ligero",
			}, lines())
			assert.equal(2, counts()["cast:skinned|?|Skinning"])
		end)

		it("skips money and slots without an item link", function()
			boot()
			mine({ { money = true }, { name = "Sin enlace", source = VEIN }, ore(1) })
			assert.same({ "ga|Mining|Filón de cobre|1731|2770|1||Mena de cobre|first" }, lines())
		end)

		it("ignores other units' casts and unknown spells", function()
			boot()
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-1", 2575)
			wow.cast(133)
			wow.advance(1)
			wow.open_loot({ slots = { ore(1) } })
			assert.same({}, lines())
		end)

		it("ignores a secret spell id and a source that is no object or creature", function()
			boot()
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", wow.secret(2575))
			wow.advance(1)
			wow.open_loot({ slots = { ore(1) } })
			assert.same({}, lines())
			mine({ { item = 2770, name = "Mena de cobre", quality = 1, source = "Player-1234-0ABCDEF0" } })
			assert.same({ "ga|Mining|Filón de cobre||2770|1||Mena de cobre|first" }, lines())
		end)

		it("writes nothing for a window from the other source kind than the cast's", function()
			boot()
			cast(2575, "Filón de cobre")
			wow.advance(1)
			wow.open_loot({ slots = { { item = 2589, name = "Lino", quality = 1, source = WOLF } } })
			cast(8613, "Lobo")
			wow.advance(1)
			wow.open_loot({ slots = { ore(1) } })
			assert.same({}, lines())
		end)

		it("writes no line with ga off and still counts", function()
			boot()
			ns.Settings.SetKind("ga", false)
			mine({ ore(2) })
			assert.same({}, lines())
			assert.equal(2, counts().Mining)
			assert.equal(2, counts()["item:Mining|2770"])
		end)
	end)

	describe("fishing", function()
		it("writes every catch with new findings only off", function()
			boot()
			journal():Count("gather", "item:Fishing|6303", 9)
			fish({
				{ item = 6303, name = "Pargo largo crudo", quality = 1, count = 2, source = POOL },
				{ item = 6358, name = "Pez aceitoso", quality = 1 },
			})
			assert.same({
				"fs|6303|1|2|Pargo largo crudo|180582",
				"fs|6358|1||Pez aceitoso|180582|first",
			}, lines())
			assert.equal(3, counts().Fishing)
			assert.equal(1, counts()["cast:caught|?|Fishing"])
		end)

		it("writes a green catch as rare with new findings only on", function()
			boot()
			newOnly(true)
			journal():Count("gather", "item:Fishing|6303", 9)
			journal():Count("gather", "item:Fishing|6359", 9)
			fish({
				{ item = 6303, name = "Pargo largo crudo", quality = 1 },
				{ item = 6359, name = "Pez verde", quality = 2 },
			})
			assert.same({ "fs|6359|2||Pez verde||rare" }, lines())
			assert.equal(10, counts()["item:Fishing|6303"])
		end)

		it("writes no line with fs off and still counts", function()
			boot()
			ns.Settings.SetKind("fs", false)
			fish({ { item = 6303, name = "Pargo largo crudo", quality = 1 } })
			assert.same({}, lines())
			assert.equal(1, counts().Fishing)
		end)

		it("counts a missed and an escaped fish from the localized errors", function()
			boot()
			wow.fire("UI_ERROR_MESSAGE", 1, "No has pescado nada.")
			wow.fire("UI_ERROR_MESSAGE", 1, "¡El pez se ha escapado!")
			wow.fire("UI_ERROR_MESSAGE", 1, "Fuera de alcance.")
			wow.fire("UI_ERROR_MESSAGE", 1, wow.secret("No has pescado nada."))
			assert.same({}, lines())
			assert.equal(1, counts()["fish:missed"])
			assert.equal(1, counts()["fish:escaped"])
		end)
	end)

	describe("opening", function()
		it("writes nothing for a quest crate", function()
			boot()
			openChest({ { item = 5060, name = "Suministros", quality = 1, quest = true, source = CHEST } })
			assert.same({}, lines())
			assert.is_nil(counts()["open:chest"])
		end)

		it("writes a chest with money", function()
			boot()
			openChest({ { money = true, source = CHEST } })
			assert.same({ "op|chest||Cofre maltrecho|2843" }, lines())
			assert.equal(1, counts()["open:chest"])
		end)

		it("matches the untranslated Opening - No Text spell as a chest", function()
			boot({ spells = { [3365] = "Abriendo", [99002] = "Opening - No Text" } })
			cast(99002, "Cofre maltrecho")
			wow.advance(1)
			wow.open_loot({ slots = { { money = true, source = CHEST } } })
			assert.same({ "op|chest||Cofre maltrecho|2843" }, lines())
		end)

		it("writes a chest with a quest item and another item", function()
			boot()
			openChest({
				{ item = 5060, name = "Suministros", quality = 1, quest = true },
				{ item = 858, name = "Poción", quality = 1 },
			})
			assert.same({ "op|chest||Cofre maltrecho" }, lines())
		end)

		it("writes nothing for a corpse looted after an Opening cast that opened no window", function()
			boot()
			cast(3365, "Palanca")
			wow.advance(1)
			wow.open_loot({ slots = { { money = true, source = WOLF } } })
			assert.same({}, lines())
			assert.is_nil(counts()["open:chest"])
		end)

		it("writes a used container with its id and name", function()
			boot()
			useBox()
			wow.advance(1)
			wow.open_loot({ slots = { { money = true } } }, true)
			assert.same({ "op|item|16885|Caja fuerte pesada" }, lines())
			assert.equal(1, counts()["open:item"])
		end)

		it("writes a used container without the isFromItem flag when no cast came first", function()
			boot()
			useBox()
			wow.advance(1.5)
			wow.open_loot({ slots = {} })
			assert.same({ "op|item|16885|Caja fuerte pesada" }, lines())
		end)

		it("writes nothing for a corpse looted after a used item that opened no window", function()
			boot()
			useBox()
			wow.advance(1)
			wow.open_loot({ slots = { { money = true, source = WOLF } } })
			assert.same({}, lines())
			assert.is_nil(counts()["open:item"])
		end)

		it("writes nothing for a disenchant window", function()
			boot({ spells = { [13262] = "Desencantar" } })
			cast(13262, "")
			wow.advance(1)
			wow.open_loot({ slots = { { item = 10940, name = "Polvo extraño", quality = 1 } } }, true)
			assert.same({}, lines())
			assert.is_nil(counts()["open:item"])
		end)

		it("writes ? for an item window with no known item", function()
			boot()
			wow.bags[0] = { [1] = { itemID = 858, hasLoot = false } }
			C_Container.UseContainerItem(0, 1)
			C_Container.UseContainerItem(1, 1)
			wow.open_loot({ slots = {} }, true)
			assert.same({ "op|item||?" }, lines())
		end)

		it("writes no line with op off and still counts", function()
			boot()
			ns.Settings.SetKind("op", false)
			openChest({ { money = true } })
			useBox()
			wow.open_loot({ slots = {} }, true)
			assert.same({}, lines())
			assert.equal(1, counts()["open:chest"])
			assert.equal(1, counts()["open:item"])
		end)

		it("writes every opening with new findings only on", function()
			boot()
			newOnly(true)
			openChest({ { money = true } })
			openChest({ { money = true } })
			assert.equal(2, #lines())
		end)
	end)

	describe("pick pocket", function()
		it("writes the best item, the first one on a tie", function()
			boot()
			pick({
				{ money = true },
				{ item = 2589, name = "Lino", quality = 1, source = DEFIAS },
				{ item = 5374, name = "Gema pequeña", quality = 2 },
				{ item = 5375, name = "Otra gema", quality = 2 },
			})
			assert.same({ "pp|Bandido Defias|116|5374|2|Gema pequeña" }, lines())
			assert.equal(1, counts().pickpockets)
		end)

		it("writes a grey item with new findings only off and on", function()
			boot()
			pick({ { item = 3300, name = "Pata de conejo", quality = 0, source = DEFIAS } })
			newOnly(true)
			pick({ { item = 3300, name = "Pata de conejo", quality = 0, source = DEFIAS } })
			assert.same({
				"pp|Bandido Defias|116|3300|0|Pata de conejo",
				"pp|Bandido Defias|116|3300|0|Pata de conejo",
			}, lines())
			assert.equal(2, counts().pickpockets)
		end)

		it("counts a money-only pocket without a line", function()
			boot()
			pick({ { money = true, source = DEFIAS } })
			assert.same({}, lines())
			assert.equal(1, counts().pickpockets)
		end)

		it("writes no line with pp off and still counts", function()
			boot()
			ns.Settings.SetKind("pp", false)
			pick({ { item = 3300, name = "Pata de conejo", quality = 0 } })
			assert.same({}, lines())
			assert.equal(1, counts().pickpockets)
		end)
	end)

	describe("missing game functions", function()
		it("falls back without an error", function()
			boot()
			_G.IsFishingLoot, _G.GetLootSourceInfo = nil, nil
			_G.GetLootSlotInfo = function()
				error("broken")
			end
			mine({ ore(1) })
			assert.same({ "ga|Mining|Filón de cobre||2770|||?|first" }, lines())
			assert.same({}, wow.errors)
			assert.same({}, ns.Errors())
		end)

		it("registers without C_Container", function()
			boot({ login = false })
			_G.C_Container = nil
			wow.login()
			mine({ ore(1) })
			assert.equal(1, #lines())
		end)
	end)

	describe("registration", function()
		it("registers its kinds and the new-only box", function()
			boot()
			for _, kind in ipairs({ "ga", "fs", "op", "pp" }) do
				local spec = ns.Kinds.Get(kind)
				assert.equal("Memories_Gathering", spec.addon)
				assert.equal("Gathering", spec.group)
			end
			local box = ns.Registry.Registered()[1].boxes[1]
			assert.equal("gathering", box.key)
			assert.same({ "ga", "fs" }, box.kinds)
		end)

		it("records after a registration after login", function()
			ns = wow.boot({ addons = { "Memories" }, spells = SPELLS })
			wow.load_addon("Memories_Gathering")
			mine({ ore(1) })
			assert.equal(1, #lines())
			assert.same({}, ns.Errors())
		end)

		it("stops with one line when it loads before the core", function()
			boot({ order = "reverse" })
			assert.equal("Memories_Gathering: Memories is not loaded.", wow.chat()[1])
			assert.is_nil(ns.Kinds.Get("ga"))
		end)
	end)
end)
