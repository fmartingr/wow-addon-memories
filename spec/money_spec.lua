local wow = require("helpers.wow")

describe("money", function()
	local LINEN, SWORD, WOOL = 2589, 2488, 2592

	local ns

	local function boot(opts)
		opts = opts or {}
		opts.addons = opts.addons or { "Memories", "Memories_Economy" }
		opts.money = opts.money or 10000
		ns = wow.boot(opts)
		wow.items[LINEN] = "Paño de lino"
		wow.items[SWORD] = "Espada de fuego"
		wow.item_info[LINEN] = { quality = 1, class = 7, equipLoc = "" }
		wow.item_info[WOOL] = { quality = 1, class = 7, equipLoc = "" }
		wow.item_info[SWORD] = { quality = 2, class = 2, equipLoc = "INVTYPE_WEAPON" }
		return ns
	end

	local function journal()
		return ns.Registry.Journal("Memories_Economy").journal
	end

	-- The economy lines as "kind|fields", in journal order, without the login gear snapshot.
	local function lines(kind)
		local out = {}
		for line in journal():Lines() do
			local rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(.*)$")
			if not rest:match("^nt|") and not rest:match("^ge|") and (not kind or rest:match("^" .. kind .. "|")) then
				out[#out + 1] = rest
			end
		end
		return out
	end

	local function counts(module)
		return journal():Counts(module or "money")
	end

	local function gain(n)
		wow.set_money(wow.money + n)
	end

	local function link(id, name)
		return "|cffffffff|Hitem:" .. id .. "::::::::10:::::|h[" .. name .. "]|h|r"
	end

	describe("gold", function()
		it("writes a gain with no window as loot", function()
			boot()
			gain(35)
			assert.same({ "mn|35|loot" }, lines())
			assert.equal(35, counts()["loot+"])
			assert.equal(35, counts().earned)
			assert.equal(10035, counts().held)
			assert.equal(10035, counts().peak)
			assert.equal(10, counts().peakLevel)
		end)

		it("writes a loss with no window as other and keeps the peak", function()
			boot()
			gain(-20)
			gain(0)
			assert.same({ "mn|-20|other" }, lines())
			assert.equal(20, counts()["other-"])
			assert.equal(20, counts().spent)
			assert.equal(9980, counts().held)
			assert.equal(10000, counts().peak)
			assert.is_nil(counts().peakLevel)
		end)

		it("sets the gold on hand at login with no line", function()
			boot({ saved = { MemoriesEconomyCharDB = { counts = { money = { held = 50, peak = 20000 } } } } })
			assert.same({}, lines())
			assert.equal(10000, counts().held)
			assert.equal(20000, counts().peak)
		end)

		it("keeps the last known gold while the amount is hidden", function()
			boot()
			wow.set_money(wow.secret(12000))
			assert.same({}, lines())
			wow.set_money(10500)
			assert.same({ "mn|500|loot" }, lines())
		end)

		it("takes the first known amount as the start when the login amount was hidden", function()
			boot({ login = false })
			wow.money = wow.secret(10000)
			wow.login()
			wow.set_money(10200)
			wow.set_money(10300)
			assert.same({ "mn|100|loot" }, lines())
			assert.equal(10300, counts().held)
		end)

		it("writes no line with mn off and still counts", function()
			boot()
			ns.Settings.SetKind("mn", false)
			gain(700)
			assert.same({}, lines())
			assert.equal(700, counts()["loot+"])
			assert.equal(10700, counts().held)
		end)

		it("sets the gold on hand again after its journal is restored", function()
			boot()
			wow.money = 15000
			ns.Emit("RESTORED", "Memories")
			assert.equal(10000, counts().held)
			ns.Emit("RESTORED", "Memories_Economy")
			assert.equal(15000, counts().held)
			gain(10)
			assert.same({ "mn|10|loot" }, lines())
		end)

		it("keeps the gold of each new level 2 s after the level up", function()
			boot()
			wow.fire("PLAYER_LEVEL_UP", 20)
			wow.advance(2)
			assert.equal(10000, journal():Snap(20, "money"))
			wow.money = wow.secret(1)
			wow.fire("PLAYER_LEVEL_UP", 21)
			wow.advance(2)
			assert.is_nil(journal():Snap(21, "money"))
		end)

		it("writes nothing with a read-only journal", function()
			boot({ saved = { MemoriesEconomyCharDB = { schema = 99 } } })
			gain(5)
			assert.same({}, lines())
			assert.same({}, counts())
		end)
	end)

	describe("windows", function()
		it("names a gain at a bank, a gossip and a trainer after the window", function()
			boot()
			for _, w in ipairs({
				{ "BANKFRAME_OPENED", "bank" },
				{ "GOSSIP_SHOW", "gossip" },
				{ "TRAINER_SHOW", "trainer" },
			}) do
				wow.fire(w[1])
				gain(1)
				assert.equal("mn|1|" .. w[2], lines()[#lines()])
			end
		end)

		it("clears the label only when the closed window is the current one", function()
			boot()
			wow.fire("GOSSIP_SHOW")
			wow.fire("MERCHANT_SHOW")
			wow.fire("GOSSIP_CLOSED")
			gain(5)
			wow.fire("MERCHANT_CLOSED")
			gain(5)
			assert.same({ "mn|5|vendor", "mn|5|loot" }, lines())
		end)

		it("keeps a quest label for 1 s after the window closed", function()
			boot({ quests = { [783] = "Una amenaza interna" } })
			wow.fire("QUEST_COMPLETE")
			wow.fire("QUEST_TURNED_IN", 783, 100, 500)
			wow.fire("QUEST_FINISHED")
			wow.advance(0.8)
			gain(500)
			wow.advance(0.2)
			gain(1)
			assert.same({ "mn|500|quest|Una amenaza interna", "mn|1|loot" }, lines())
		end)

		it("names one gain only after a turn-in", function()
			boot({ quests = { [783] = "Una amenaza interna" } })
			wow.fire("QUEST_COMPLETE")
			wow.fire("QUEST_TURNED_IN", 783, 100, 500)
			gain(500)
			gain(300)
			assert.same({ "mn|500|quest|Una amenaza interna", "mn|300|quest" }, lines())
		end)

		it("leaves the quest title empty without a recent turn-in", function()
			boot()
			wow.fire("QUEST_TURNED_IN", 783)
			wow.advance(6)
			wow.fire("QUEST_COMPLETE")
			gain(500)
			assert.same({ "mn|500|quest" }, lines())
		end)

		it("names a flight fare after the flight's destination", function()
			boot({
				taxi = {
					{ name = "Ventormenta", type = "CURRENT" },
					{ name = "Villa del Lago", type = "REACHABLE", cost = 50 },
				},
			})
			wow.fire("TAXIMAP_OPENED", 1)
			TakeTaxiNode(2)
			wow.fire("TAXIMAP_CLOSED")
			wow.advance(1)
			gain(-50)
			wow.fire("TAXIMAP_OPENED", 1)
			gain(-1)
			assert.same({ "mn|-50|flight|Villa del Lago", "mn|-1|flight|Villa del Lago" }, lines())
		end)
	end)

	describe("vendor", function()
		it("names a sale after the stack sold a moment ago", function()
			boot()
			wow.fire("MERCHANT_SHOW")
			wow.bags[0] = { [1] = { itemID = WOOL, itemName = "Paño de lana", stackCount = 20 } }
			C_Container.UseContainerItem(0, 1)
			wow.advance(1)
			gain(400)
			wow.bags[0][2] = { itemID = WOOL, itemName = "Paño de lana", stackCount = 1 }
			UseContainerItem(0, 2)
			gain(20)
			wow.advance(4)
			gain(20)
			assert.same({ "mn|400|vendor|20 Paño de lana", "mn|20|vendor|Paño de lana", "mn|20|vendor" }, lines())
			assert.equal(440, counts()["vendor+"])
		end)

		it("reads no sale outside a vendor and no empty slot", function()
			boot()
			wow.bags[0] = { [1] = { itemID = WOOL, itemName = "Paño de lana", stackCount = 20 } }
			C_Container.UseContainerItem(0, 1)
			wow.fire("MERCHANT_SHOW")
			C_Container.UseContainerItem(0, 5)
			gain(400)
			assert.same({ "mn|400|vendor" }, lines())
		end)

		it("names a purchase after the item bought a moment ago", function()
			boot()
			wow.fire("MERCHANT_SHOW")
			wow.merchant[1] = { name = "Frasco vacío" }
			wow.merchant[2] = { id = LINEN }
			BuyMerchantItem(1)
			gain(-50)
			BuyMerchantItem(2, 5)
			gain(-80)
			wow.advance(3.5)
			gain(-10)
			assert.same({ "mn|-50|vendor|Frasco vacío", "mn|-80|vendor|Paño de lino", "mn|-10|vendor" }, lines())
		end)

		it("writes a repair within 2 s of RepairAllItems", function()
			boot()
			wow.fire("MERCHANT_SHOW")
			RepairAllItems()
			wow.advance(1.5)
			gain(-1200)
			RepairAllItems()
			wow.advance(2.5)
			gain(-100)
			gain(300)
			assert.same({ "mn|-1200|repair", "mn|-100|vendor", "mn|300|vendor" }, lines())
		end)

		it("writes a repair once and none for a guild bank repair", function()
			boot()
			wow.fire("MERCHANT_SHOW")
			RepairAllItems()
			gain(-1200)
			gain(-100)
			RepairAllItems(true)
			gain(-50)
			assert.same({ "mn|-1200|repair", "mn|-100|vendor", "mn|-50|vendor" }, lines())
		end)

		it("writes a respec within 3 s of ConfirmTalentWipe", function()
			boot()
			ConfirmTalentWipe()
			wow.advance(3)
			gain(-10000)
			assert.same({ "mn|-10000|respec" }, lines())
		end)
	end)

	describe("trainer", function()
		local function service(name, cost, extra)
			local s = extra or {}
			s.name, s.cost = name, cost
			return s
		end

		local function trainer(services, tradeskill)
			wow.units.npc = { name = "Maestro", guid = "Creature-0-1-0-1-198-1" }
			wow.trainer = { services = services, tradeskill = tradeskill }
			wow.fire("TRAINER_SHOW")
		end

		it("writes each paid service and the loss with their names", function()
			boot()
			trainer({ service("Bola de fuego", 100, { sub = "Rango 2" }), service("Escudo de maná", 250) })
			BuyTrainerService(1)
			BuyTrainerService(2)
			gain(-350)
			assert.same({
				"tb|class|Bola de fuego (Rango 2)|100",
				"tb|class|Escudo de maná|250",
				"mn|-350|trainer|Bola de fuego (Rango 2), Escudo de maná",
			}, lines())
			assert.equal(350, counts("trainers").class)
		end)

		it("writes no service when the clicks do not add up to the loss", function()
			boot()
			trainer({ service("Bola de fuego", 100) })
			BuyTrainerService(1)
			gain(-90)
			assert.same({ "mn|-90|trainer" }, lines())
		end)

		it("drops clicks older than 3 s and the clicks after a match", function()
			boot()
			trainer({ service("A", 100), service("B", 200), service("C", 300) })
			BuyTrainerService(1)
			wow.advance(4)
			BuyTrainerService(2)
			BuyTrainerService(3)
			gain(-200)
			gain(-300)
			assert.same({ "tb|class|B|200", "mn|-200|trainer|B", "mn|-300|trainer" }, lines())
		end)

		it("names the kind of each service from localized skill lines", function()
			boot({ skillLines = { [762] = "Equitación", [43] = "Espadas", [261] = "Adiestramiento de bestias" } })
			trainer({
				service("Equitación de aprendiz", 1000, { skill = "Equitación" }),
				service("Espadas", 10, { skill = "Espadas" }),
				service("Gruñido", 5, { skill = "Adiestramiento de bestias" }),
				service("Bendición", 1, { skill = "Paladín" }),
			})
			for i = 1, 4 do
				BuyTrainerService(i)
			end
			gain(-1016)
			local kinds = {}
			for _, line in ipairs(lines("tb")) do
				kinds[#kinds + 1] = line:match("^tb|(%a+)|")
			end
			assert.same({ "riding", "weapon", "pet", "class" }, kinds)
		end)

		it("names a profession trainer's services as profession", function()
			boot()
			trainer({ service("Minería de aprendiz", 10, { skill = "Minería" }) }, true)
			BuyTrainerService(1)
			gain(-10)
			assert.same({ "tb|profession|Minería de aprendiz|10", "mn|-10|trainer|Minería de aprendiz" }, lines())
			assert.equal(10, counts("trainers").profession)
		end)

		it("ignores the pet window, free services, headers and availability words", function()
			boot()
			wow.trainer = { services = { service("Mordisco", 0) } }
			BuyTrainerService(1)
			trainer({
				service("Hechizos", 0, { type = "header" }),
				service("Mordisco", 0),
				service("Toque", 20, { sub = "available" }),
				service("Sin precio"),
			})
			for i = 1, 4 do
				BuyTrainerService(i)
			end
			gain(-20)
			assert.same({ "tb|class|Toque|20", "mn|-20|trainer|Toque" }, lines())
		end)

		it("keeps the fuller list of the same trainer", function()
			boot()
			trainer({})
			wow.trainer.services = { service("A", 100), service("B", 200) }
			wow.advance(1)
			wow.trainer.services = { service("A", 100) }
			wow.fire("TRAINER_UPDATE")
			wow.fire("TRAINER_UPDATE")
			wow.advance(0.3)
			BuyTrainerService(2)
			gain(-200)
			assert.same({ "tb|class|B|200", "mn|-200|trainer|B" }, lines())
		end)

		it("names a click after the list on screen when a filter hides services", function()
			boot()
			trainer({ service("A", 100), service("B", 200), service("C", 300) })
			wow.trainer.services = { service("A", 100), service("C", 300) }
			wow.fire("TRAINER_UPDATE")
			wow.advance(0.3)
			BuyTrainerService(2)
			gain(-300)
			assert.same({ "tb|class|C|300", "mn|-300|trainer|C" }, lines())
		end)

		it("reads the list of another trainer again", function()
			boot()
			trainer({ service("A", 100), service("B", 200) })
			wow.units.npc = { name = "Otro" }
			wow.trainer.services = { service("C", 50) }
			wow.fire("TRAINER_SHOW")
			BuyTrainerService(1)
			gain(-50)
			assert.same({ "tb|class|C|50", "mn|-50|trainer|C" }, lines())
		end)

		it("writes no tb with tb off and still counts", function()
			boot()
			ns.Settings.SetKind("tb", false)
			trainer({ service("A", 100) })
			BuyTrainerService(1)
			gain(-100)
			assert.same({ "mn|-100|trainer|A" }, lines())
			assert.equal(100, counts("trainers").class)
		end)
	end)

	describe("auction house", function()
		local function open()
			wow.fire("AUCTION_HOUSE_SHOW")
		end

		it("writes a post with its deposit", function()
			boot()
			open()
			C_AuctionHouse.PostItem({ name = "Paño de lana" }, 1, 1, 0, 100)
			wow.advance(1)
			gain(-60)
			assert.same({ "ah|post|60|Paño de lana", "mn|-60|auction|Paño de lana" }, lines())
			assert.equal(1, counts("auction").post)
			assert.equal(60, counts("auction").postCopper)
		end)

		it("pays each deposit of posts in a row to its own post", function()
			boot()
			open()
			C_AuctionHouse.PostItem({ name = "Paño de lana" }, 1, 1)
			C_AuctionHouse.PostItem({ name = "Paño de lino" }, 1, 1)
			gain(-60)
			gain(-15)
			assert.same({
				"ah|post|60|Paño de lana",
				"mn|-60|auction|Paño de lana",
				"ah|post|15|Paño de lino",
				"mn|-15|auction|Paño de lino",
			}, lines())
		end)

		it("writes a commodity post and a legacy post", function()
			boot()
			open()
			C_AuctionHouse.PostCommodity({ name = "Paño de lino" }, 1, 20, 5)
			gain(-15)
			wow.sell_item = "Hacha"
			StartAuction(100, 200, 1)
			gain(-5)
			PostAuction(100, 200, 1, 1, 1)
			wow.advance(4)
			gain(-5)
			assert.same({
				"ah|post|15|Paño de lino",
				"mn|-15|auction|Paño de lino",
				"ah|post|5|Hacha",
				"mn|-5|auction|Hacha",
				"mn|-5|auction",
			}, lines())
		end)

		it("writes a buyout and a bid by the amount of the loss", function()
			boot()
			open()
			wow.auctions[5] = { itemLink = link(SWORD, "Espada de fuego"), buyoutAmount = 1000 }
			wow.auctions[6] = { itemKey = { itemID = LINEN }, buyoutAmount = 5000 }
			C_AuctionHouse.PlaceBid(6, 300)
			C_AuctionHouse.PlaceBid(5, 1000)
			gain(-1000)
			gain(-300)
			assert.same({
				"ah|buyout|1000|Espada de fuego",
				"mn|-1000|auction|Espada de fuego",
				"ah|bid|300|Paño de lino",
				"mn|-300|auction|Paño de lino",
			}, lines())
			assert.equal(1, counts("auction").buyout)
			assert.equal(300, counts("auction").bidCopper)
		end)

		it("writes a commodity purchase at the event and names the loss after it", function()
			boot()
			open()
			C_AuctionHouse.ConfirmCommoditiesPurchase(LINEN, 20)
			wow.fire("COMMODITY_PURCHASE_SUCCEEDED")
			gain(-400)
			gain(-1)
			assert.same({
				"ah|buyout||Paño de lino x20",
				"mn|-400|auction|Paño de lino x20",
				"mn|-1|auction",
			}, lines())
			assert.equal(1, counts("auction").buyout)
			assert.is_nil(counts("auction").buyoutCopper)
		end)

		it("takes the oldest click with no amount when no amount matches", function()
			boot()
			open()
			C_AuctionHouse.ConfirmCommoditiesPurchase(SWORD, 1)
			C_AuctionHouse.ConfirmCommoditiesPurchase(LINEN, 2)
			gain(-77)
			assert.same({ "ah|buyout|77|Espada de fuego", "mn|-77|auction|Espada de fuego" }, lines())
		end)

		it("drops the newest click when a commodity purchase fails", function()
			boot()
			open()
			C_AuctionHouse.ConfirmCommoditiesPurchase(SWORD, 1)
			C_AuctionHouse.ConfirmCommoditiesPurchase(LINEN, 2)
			wow.fire("COMMODITY_PURCHASE_FAILED")
			wow.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 1)
			wow.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 2)
			assert.same({ "ah|buyout||Espada de fuego" }, lines())
		end)

		it("keeps a newer item bid when a commodity purchase fails", function()
			boot()
			open()
			C_AuctionHouse.ConfirmCommoditiesPurchase(LINEN, 2)
			C_AuctionHouse.PlaceBid(9, 100)
			wow.fire("COMMODITY_PURCHASE_FAILED")
			gain(-100)
			assert.same({ "ah|bid|100", "mn|-100|auction" }, lines())
		end)

		it("forgets clicks after 30 s and a purchase after 10 s", function()
			boot()
			open()
			C_AuctionHouse.PlaceBid(9, 100)
			C_AuctionHouse.ConfirmCommoditiesPurchase(LINEN, 1)
			wow.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 9)
			wow.advance(31)
			gain(-100)
			assert.same({ "ah|bid|100", "mn|-100|auction" }, lines())
		end)

		it("writes a legacy bid as a buyout when it reaches the buyout", function()
			boot()
			open()
			wow.legacy_auctions[1] = { name = "Hacha", buyout = 500 }
			wow.legacy_auctions[2] = { name = "Maza", buyout = 0 }
			PlaceAuctionBid("list", 1, 500)
			PlaceAuctionBid("list", 2, 80)
			gain(-500)
			gain(-80)
			assert.same(
				{ "ah|buyout|500|Hacha", "mn|-500|auction|Hacha", "ah|bid|80|Maza", "mn|-80|auction|Maza" },
				lines()
			)
		end)

		it("keeps the auction label 3 s after the window closed", function()
			boot()
			open()
			wow.fire("AUCTION_HOUSE_CLOSED")
			wow.advance(2)
			gain(9)
			wow.advance(1)
			gain(9)
			assert.same({ "mn|9|auction", "mn|9|loot" }, lines())
		end)

		it("writes no ah with ah off and still counts", function()
			boot()
			ns.Settings.SetKind("ah", false)
			open()
			C_AuctionHouse.PostItem({ name = "Paño de lana" }, 1, 1)
			gain(-60)
			assert.same({ "mn|-60|auction|Paño de lana" }, lines())
			assert.equal(1, counts("auction").post)
		end)
	end)

	describe("mail", function()
		local function open(inbox)
			wow.inbox = inbox or {}
			wow.fire("MAIL_SHOW")
		end

		local function send(who, money, item)
			wow.send_mail = { money = money, item = item }
			SendMail(who, "Hola", "")
		end

		it("splits a send into the money sent and the postage", function()
			boot()
			open()
			send("Ann", 1000, "Paño de lino")
			wow.advance(2)
			gain(-1030)
			wow.fire("MAIL_SEND_SUCCESS")
			wow.fire("MAIL_SEND_SUCCESS")
			assert.same({ "mn|-1000|mail|Ann", "mn|-30|postage|Ann", "ma|send|Ann|1000|Paño de lino" }, lines())
			assert.equal(1, counts("mail").send)
			assert.equal(1030, counts().spent)
		end)

		it("writes the postage of a send with no money or with less loss than the money", function()
			boot()
			open()
			send("Ann", 0)
			gain(-30)
			gain(-30)
			send("Bob", 1000)
			gain(-500)
			assert.same({ "mn|-30|postage|Ann", "mn|-30|mail", "mn|-500|postage|Bob" }, lines())
		end)

		it("writes a send of only money as one line", function()
			boot()
			open()
			send("Ann", 1000)
			gain(-1000)
			assert.same({ "mn|-1000|mail|Ann" }, lines())
		end)

		it("forgets a failed send", function()
			boot()
			open()
			send("Ann", 0)
			wow.fire("MAIL_FAILED")
			wow.fire("MAIL_SEND_SUCCESS")
			gain(-30)
			assert.same({ "mn|-30|mail" }, lines())
		end)

		it("writes a seller invoice once per visit", function()
			boot()
			local mail = {
				sender = "Casa de subastas",
				subject = "Subasta ganada: Barra de cobre",
				money = 950,
				invoice = { type = "seller", item = "Barra de cobre", player = "Bob" },
			}
			open({ mail })
			TakeInboxMoney(1)
			gain(950)
			mail.days = 29.995
			TakeInboxMoney(1)
			assert.same({
				"ah|sold|950|Barra de cobre",
				"ma|invoice|Bob|950|Barra de cobre",
				"mn|950|auction|Barra de cobre",
			}, lines())
			assert.equal(1, counts("auction").sold)
			assert.equal(950, counts("auction").soldCopper)
			assert.equal(1, counts("mail").invoice)
		end)

		it("writes a buyer invoice and its item as bought", function()
			boot()
			local mail = {
				sender = "Casa de subastas",
				subject = "Subasta ganada: Espada de fuego",
				items = { [1] = { id = SWORD, name = "Espada de fuego", quality = 2 } },
				invoice = { type = "buyer", player = "Bob" },
			}
			open({ mail })
			TakeInboxItem(1, 1)
			wow.inbox = {}
			wow.advance(1)
			assert.same({ "ma|invoice|Bob||Espada de fuego", "lo|2488|2||bought|Espada de fuego|1|1" }, lines())
		end)

		it("writes a bought item as bought when its pushed line comes first", function()
			boot()
			local mail = {
				sender = "Casa de subastas",
				subject = "Subasta ganada: Espada de fuego",
				items = { [1] = { id = SWORD, name = "Espada de fuego", quality = 2 } },
				invoice = { type = "buyer", player = "Bob" },
			}
			open({ mail })
			TakeInboxItem(1, 1)
			wow.fire("CHAT_MSG_LOOT", "Recibes objeto: " .. link(SWORD, "Espada de fuego") .. ".")
			wow.inbox = {}
			wow.advance(1)
			assert.same({ "lo|2488|2||bought|Espada de fuego|1|1" }, lines("lo"))
		end)

		it("names the gold of player mail, outbid mail and other mail", function()
			boot()
			open({
				{ sender = "Ann", subject = "Hola", money = 100, canReply = true },
				{ sender = "Casa de subastas", subject = "Puja superada: Espada de fuego", money = 300 },
				{ sender = "Maestro de juego", subject = "Aviso", money = 5, canReply = true, isGM = true },
			})
			for i = 1, 3 do
				TakeInboxMoney(i)
				gain(wow.inbox[i].money)
			end
			wow.advance(16)
			gain(1)
			assert.same({
				"ma|take|Ann|100",
				"mn|100|mail|Ann",
				"ma|take|Casa de subastas|300",
				"mn|300|auction|Espada de fuego",
				"ma|take|Maestro de juego|5",
				"mn|5|other|Maestro de juego",
				"mn|1|mail",
			}, lines())
			assert.equal(3, counts("mail").take)
		end)

		it("names each gold after its own mail when takes come before the gold", function()
			boot()
			open({
				{ sender = "Ann", subject = "Hola", money = 100, canReply = true },
				{ sender = "Casa de subastas", subject = "Puja superada: Espada de fuego", money = 300 },
			})
			TakeInboxMoney(1)
			TakeInboxMoney(2)
			gain(100)
			gain(300)
			assert.same({ "mn|100|mail|Ann", "mn|300|auction|Espada de fuego" }, lines("mn"))
		end)

		it("never names gold after a take of one attachment", function()
			boot()
			open({
				{ sender = "Ann", subject = "Hola", money = 300, canReply = true, items = { [1] = { id = SWORD } } },
				{ sender = "Casa de subastas", subject = "Puja superada: Espada de fuego", money = 300 },
			})
			TakeInboxItem(1, 1)
			TakeInboxMoney(2)
			gain(300)
			assert.same({ "mn|300|auction|Espada de fuego" }, lines("mn"))
		end)

		it("writes an expired auction and its item", function()
			boot()
			open({
				{
					sender = "Casa de subastas",
					subject = "Subasta caducada: Paño de lino",
					items = { [2] = { id = LINEN, name = "Paño de lino", count = 20, quality = 1 } },
				},
			})
			AutoLootMailItem(1)
			wow.inbox = {}
			wow.advance(1)
			assert.same({
				"ah|expired||Paño de lino",
				"ma|take|Casa de subastas||Paño de lino",
				"lo|2589|1|20|other|Paño de lino||1",
			}, lines())
		end)

		it("records an attachment once, when it left its mail", function()
			boot()
			local mail = {
				sender = "Ann",
				subject = "Regalo",
				canReply = true,
				items = { [1] = { id = SWORD, name = "Espada de fuego", quality = 2 } },
			}
			open({ mail })
			TakeInboxItem(1)
			TakeInboxItem(1, 1)
			wow.advance(1)
			assert.same({ "ma|take|Ann||Espada de fuego" }, lines())
			mail.items = {}
			wow.advance(1)
			wow.advance(2)
			TakeInboxItem(1, 1)
			wow.advance(1)
			assert.same({ "ma|take|Ann||Espada de fuego", "lo|2488|2||mail|Espada de fuego|1|1" }, lines())
		end)

		it("takes an attachment moved to another slot as left", function()
			boot()
			local mail = {
				sender = "Ann",
				subject = "Regalo",
				items = { [1] = { id = SWORD, name = "Espada de fuego" }, [2] = { id = LINEN, name = "Paño de lino" } },
			}
			open({ mail })
			AutoLootMailItem(1)
			mail.items = { [1] = { id = LINEN, name = "Paño de lino" } }
			wow.advance(1)
			assert.same({ "lo|2488|2||mail|Espada de fuego|1|1", "lo|2589|1||mail|Paño de lino||1" }, lines("lo"))
		end)

		it("keeps waiting on a failed inbox read and forgets an attachment after 10 s", function()
			boot()
			open({ { sender = "Ann", subject = "Regalo", items = { [1] = { id = SWORD, name = "Espada de fuego" } } } })
			TakeInboxItem(1, 1)
			wow.inbox_fail = true
			wow.advance(1)
			wow.inbox_fail = false
			wow.inbox[2] = { subject = "Sin remitente" }
			wow.advance(1)
			wow.inbox[2] = nil
			wow.advance(10)
			wow.inbox = {}
			wow.advance(2)
			assert.same({}, lines("lo"))
		end)

		it("checks once more when the mailbox closes, then drops every wait", function()
			boot()
			local mail = {
				sender = "Ann",
				subject = "Regalo",
				items = { [1] = { id = SWORD, name = "Espada de fuego" }, [2] = { id = LINEN, name = "Paño de lino" } },
			}
			open({ mail, { sender = "Bob", subject = "Otro" } })
			TakeInboxItem(1, 1)
			TakeInboxItem(1, 2)
			mail.items[1] = nil
			wow.fire("MAIL_CLOSED")
			mail.items[2] = nil
			wow.advance(2)
			assert.same({ "lo|2488|2||mail|Espada de fuego|1|1" }, lines("lo"))
		end)

		it("drops every wait when the closed mailbox reads empty", function()
			boot()
			open({ { sender = "Ann", subject = "Regalo", items = { [1] = { id = SWORD, name = "Espada de fuego" } } } })
			TakeInboxItem(1, 1)
			wow.inbox = {}
			wow.fire("MAIL_CLOSED")
			wow.advance(2)
			assert.same({}, lines("lo"))
			wow.fire("MAIL_CLOSED")
		end)

		it("writes no item for a taken gold and ignores an unreadable mail", function()
			boot()
			open({ { sender = "Ann", subject = "Oro", money = 50 }, { sender = "Bob" } })
			TakeInboxMoney(1)
			TakeInboxItem(1, 1)
			TakeInboxMoney(2)
			wow.advance(2)
			assert.same({ "ma|take|Ann|50" }, lines())
		end)

		it("writes a pushed item and the same attachment once", function()
			boot()
			local mail =
				{ sender = "Ann", subject = "Regalo", items = { [1] = { id = SWORD, name = "Espada de fuego" } } }
			open({ mail })
			TakeInboxItem(1, 1)
			wow.fire("CHAT_MSG_LOOT", "Recibes objeto: " .. link(SWORD, "Espada de fuego") .. ".")
			mail.items = {}
			wow.advance(1)
			assert.same({ "lo|2488|2||mail|Espada de fuego|1|1" }, lines("lo"))
			assert.equal(1, counts("loot").items)
		end)

		it("writes an attachment and the same pushed item once", function()
			boot()
			local mail =
				{ sender = "Ann", subject = "Regalo", items = { [1] = { id = SWORD, name = "Espada de fuego" } } }
			open({ mail })
			TakeInboxItem(1, 1)
			mail.items = {}
			wow.advance(1)
			wow.advance(1.5)
			wow.fire("CHAT_MSG_LOOT", "Recibes objeto: " .. link(SWORD, "Espada de fuego") .. ".")
			wow.advance(1)
			wow.fire("CHAT_MSG_LOOT", "Recibes objeto: " .. link(SWORD, "Espada de fuego") .. ".")
			assert.same({ "lo|2488|2||mail|Espada de fuego|1|1", "lo|2488|2||mail|Espada de fuego|1" }, lines("lo"))
		end)

		it("writes no ma with ma off and still counts", function()
			boot()
			ns.Settings.SetKind("ma", false)
			open()
			send("Ann", 0)
			wow.fire("MAIL_SEND_SUCCESS")
			assert.same({}, lines())
			assert.equal(1, counts("mail").send)
		end)
	end)

	describe("trade", function()
		local function trade(partner)
			wow.units.NPC = { name = partner }
			wow.fire("TRADE_SHOW")
		end

		it("writes one trade and each item received when the trade completes", function()
			boot()
			trade("Bob")
			wow.trade = {
				items = {
					[1] = { id = SWORD, name = "Espada de fuego", quality = 2 },
					[3] = { id = LINEN, name = "Paño de lino", count = 5, quality = 1 },
				},
				money = 5000,
				given = 1000,
			}
			wow.fire("TRADE_TARGET_ITEM_CHANGED", 1)
			wow.fire("TRADE_ACCEPT_UPDATE", 1, 1)
			gain(4000)
			wow.fire("UI_INFO_MESSAGE", 1, "Comercio completado.")
			wow.fire("CHAT_MSG_SYSTEM", "Comercio completado.")
			wow.fire("TRADE_CLOSED")
			wow.advance(2)
			gain(1)
			assert.same({
				"mn|4000|trade|Bob",
				"tr|Bob|4000",
				"lo|2488|2||trade|Espada de fuego|1|1",
				"lo|2589|1|5|trade|Paño de lino||1",
				"mn|1|loot",
			}, lines())
			assert.equal(1, counts("trade").trades)
		end)

		it("writes a trade with a hidden partner, an even exchange and an item with no link", function()
			boot()
			trade(wow.secret("Bob"))
			wow.trade = { items = { [2] = { name = "Carta" } }, money = 100, given = 100 }
			wow.fire("TRADE_MONEY_CHANGED")
			wow.fire("CHAT_MSG_SYSTEM", "Otra cosa")
			wow.fire("CHAT_MSG_SYSTEM", "Comercio completado.")
			assert.same({ "tr|?", "lo||||trade|Carta" }, lines())
		end)

		it("names the trade gold after the last partner", function()
			boot()
			trade("Bob")
			trade(nil)
			gain(10)
			assert.same({ "mn|10|trade|Bob" }, lines())
			wow.fire("CHAT_MSG_SYSTEM", "Comercio completado.")
			wow.fire("CHAT_MSG_SYSTEM", "Comercio completado.")
			assert.same({ "mn|10|trade|Bob", "tr|?" }, lines())
		end)

		it("completes no trade without ERR_TRADE_COMPLETE or an open trade", function()
			boot({ strings = { ERR_TRADE_COMPLETE = false } })
			wow.fire("CHAT_MSG_SYSTEM", "Comercio completado.")
			wow.fire("TRADE_MONEY_CHANGED")
			trade("Bob")
			wow.fire("CHAT_MSG_SYSTEM", nil)
			assert.same({}, lines())
		end)

		it("writes a pushed item and the same traded item once", function()
			boot()
			trade("Bob")
			wow.trade =
				{ items = { [1] = { id = SWORD, name = "Espada de fuego", quality = 2 } }, money = 0, given = 0 }
			wow.fire("TRADE_ACCEPT_UPDATE", 1, 1)
			wow.fire("CHAT_MSG_LOOT", "Recibes objeto: " .. link(SWORD, "Espada de fuego") .. ".")
			wow.fire("UI_INFO_MESSAGE", 1, "Comercio completado.")
			assert.same({ "lo|2488|2||trade|Espada de fuego|1|1", "tr|Bob" }, lines())
		end)

		it("writes no tr with tr off and still counts", function()
			boot()
			ns.Settings.SetKind("tr", false)
			trade("Bob")
			wow.fire("CHAT_MSG_SYSTEM", "Comercio completado.")
			assert.same({}, lines())
			assert.equal(1, counts("trade").trades)
		end)
	end)

	describe("missing game functions", function()
		it("records gold without the optional tables", function()
			boot({ login = false })
			_G.C_AuctionHouse, _G.C_Container, _G.C_SkillInfo, _G.C_QuestLog = nil, nil, nil, nil
			_G.C_Item = nil
			wow.login()
			wow.fire("QUEST_TURNED_IN", 1)
			wow.fire("QUEST_COMPLETE")
			gain(5)
			assert.same({ "mn|5|quest" }, lines())
			assert.same({}, ns.Errors())
		end)
	end)
end)
