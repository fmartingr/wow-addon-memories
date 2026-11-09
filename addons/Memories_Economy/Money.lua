local ADDON, ns = ...
local L = ns.L

-- Loot.lua stops before it fills ns when the core is missing, and it has said why.
if not ns.Loot then
	return
end

local Money = {}
ns.Money = Money

local call, api, text, number = ns.Call, ns.Api, ns.Text, ns.Number
local abs = math.abs

local REPAIR = 2
local RESPEC = 3
local TRAINER_CLICK = 3
local POST = 3
local AUCTION_CLICK = 30
local PURCHASE = 10
local MAIL = 15
local VENDOR = 3
local QUEST = 5
local WAIT = 10
local ATTACHMENTS = 16
local TRADE_SLOTS = 6
-- Mail days left fall while the mailbox is open: two reads of one mail differ by less than this.
local DAYS = 0.01
-- { open event, label, close event, close delay }. Opening any window replaces the label.
local WINDOWS = {
	{ "MERCHANT_SHOW", "vendor", "MERCHANT_CLOSED", 0 },
	{ "TRAINER_SHOW", "trainer", "TRAINER_CLOSED", 0 },
	{ "MAIL_SHOW", "mail", "MAIL_CLOSED", 0 },
	{ "AUCTION_HOUSE_SHOW", "auction", "AUCTION_HOUSE_CLOSED", 3 },
	{ "BANKFRAME_OPENED", "bank", "BANKFRAME_CLOSED", 0 },
	{ "TRADE_SHOW", "trade", "TRADE_CLOSED", 2 },
	{ "GOSSIP_SHOW", "gossip", "GOSSIP_CLOSED", 0 },
	{ "QUEST_COMPLETE", "quest", "QUEST_FINISHED", 1 },
	{ "TAXIMAP_OPENED", "flight", "TAXIMAP_CLOSED", 2 },
}
-- Skill line ids of the trainer kinds. The names come from the client, so they match in every language.
local SKILL_KINDS = {
	riding = { 762, 148, 149, 150, 152, 533, 553, 554, 713 },
	weapon = { 44, 172, 45, 226, 173, 473, 46, 54, 160, 229, 136, 43, 55, 176, 228 },
	pet = { 261 },
}
-- The second value of GetTrainerServiceInfo: an availability word, never a rank.
local SERVICE_TYPES = { available = true, unavailable = true, used = true, header = true }

local h
local label, closesAt
local last
local repairAt, wipeAt
-- The last trainer read: { who, n, services }, with services by index { name, skill, cost } and n their count.
local trainer
local clicks = {}
-- Posts in click order: each deposit pays the oldest one.
local posts = {}
local bids = {}
local purchase
-- The open mailbox visit: the mails already handled, the last send, the recent takes and the attachments that wait.
local handled = {}
local send
local takes = {}
local waits = {}
local ticker
local trade, lastPartner
local bought, sold, turnedIn
local expiredSubject, outbidSubject

function Money.CurrentWindow()
	if closesAt and GetTime() >= closesAt then
		label, closesAt = nil, nil
	end
	return label or "none"
end

local function fresh(rec, now, window)
	return rec ~= nil and now - rec.at <= window
end

-- Sets the gold on hand to the real gold, with no line for the gap.
local function sync(gold)
	last = gold
	local counts = h:Counts("money")
	counts.held = gold
	-- The level of a peak reached while the addon was off is unknown.
	if gold > (counts.peak or 0) then
		counts.peak, counts.peakLevel = gold, nil
	end
end

local function prune(list, now, window)
	local keep = {}
	for _, rec in ipairs(list) do
		if fresh(rec, now, window) then
			keep[#keep + 1] = rec
		end
	end
	return keep
end

local function change(delta, src, what)
	h:Write("mn", delta, src, what)
	local size = abs(delta)
	h:Count("money", src .. (delta > 0 and "+" or "-"), size)
	h:Count("money", delta > 0 and "earned" or "spent", size)
	h:Count("money", "held", delta)
	local counts = h:Counts("money")
	if (counts.held or 0) > (counts.peak or 0) then
		counts.peak, counts.peakLevel = counts.held, h:Level()
	end
end

local function auction(act, copper, item)
	h:Write("ah", act, copper, item)
	h:Count("auction", act)
	if copper then
		h:Count("auction", act .. "Copper", copper)
	end
end

local function mail(act, who, copper, item)
	h:Write("ma", act, who or "?", copper ~= 0 and copper or nil, item)
	h:Count("mail", act)
end

-- Trainer ---------------------------------------------------------------------

local kinds

-- The skill line names come from the client and never change during a session, so a full read is kept.
local function skillKinds()
	if kinds then
		return kinds
	end
	local out, any = {}, false
	local info = api(C_SkillInfo, "GetSkillLineInfoByID")
	for kind, ids in pairs(SKILL_KINDS) do
		for _, id in ipairs(ids) do
			local attrs = h:R(call(info, id))
			local name = type(attrs) == "table" and text(attrs.name)
			if name then
				out[name], any = kind, true
			end
		end
	end
	kinds = any and out or nil
	return out
end

-- A read with fewer services never replaces a fuller one of the same trainer: the list fills over a few updates.
local function readTrainer()
	local who = text(UnitGUID("npc")) or text(UnitName("npc"))
	local services, n = {}, 0
	for i = 1, number(call(GetNumTrainerServices)) or 0 do
		local name, kind, _, _, sub = call(GetTrainerServiceInfo, i)
		name, kind, sub = text(name), text(kind), text(sub)
		if name and kind ~= "header" then
			local rank = sub and not SERVICE_TYPES[sub] and sub or nil
			services[i] = {
				name = rank and name .. " (" .. rank .. ")" or name,
				skill = text(call(GetTrainerServiceSkillLine, i)),
				cost = number(call(GetTrainerServiceCost, i)),
			}
			n = n + 1
		end
	end
	if not trainer or trainer.who ~= who or n >= trainer.n then
		trainer = { who = who, n = n, services = services }
	end
	return services
end

-- The hunter's own pet training window has no NPC: it costs training points, never gold. The clicked index is read
-- from the list on screen, since a trainer filter reorders the indexes of the fuller list.
local function onBuyService(index)
	if h:R(UnitExists("npc")) ~= true then
		return
	end
	local s = readTrainer()[index] or trainer.services[index]
	if not s or not s.cost or s.cost <= 0 then
		return
	end
	local kind = h:R(call(IsTradeskillTrainer)) == true and "profession" or s.skill and skillKinds()[s.skill] or "class"
	local now = GetTime()
	clicks = prune(clicks, now, TRAINER_CLICK)
	clicks[#clicks + 1] = { what = s.name, kind = kind, cost = s.cost, at = now }
end

-- The oldest clicks that add up to the loss exactly were paid; the other clicks were not.
local function paidTrainer(loss, now)
	clicks = prune(clicks, now, TRAINER_CLICK)
	local sum = 0
	for k, c in ipairs(clicks) do
		sum = sum + c.cost
		if sum == loss then
			local names = {}
			for i = 1, k do
				local paid = clicks[i]
				h:Write("tb", paid.kind, paid.what, paid.cost)
				h:Count("trainers", paid.kind, paid.cost)
				names[i] = paid.what
			end
			clicks = {}
			return table.concat(names, ", ")
		end
	end
end

-- Auction house ------------------------------------------------------------

local function itemName(id)
	return id and text(call(api(C_Item, "GetItemNameByID"), id)) or nil
end

local function linkName(link)
	return (select(2, ns.LinkItem(link)))
end

local function bid(act, amount, item)
	local now = GetTime()
	bids = prune(bids, now, AUCTION_CLICK)
	bids[#bids + 1] = { act = act, amount = amount, item = item, at = now }
end

local function onPlaceBid(auctionID, amount)
	local info = h:R(call(api(C_AuctionHouse, "GetAuctionInfoByID"), auctionID))
	info = type(info) == "table" and info or {}
	local key = h:R(info.itemKey)
	local item = linkName(text(info.itemLink)) or itemName(type(key) == "table" and number(key.itemID))
	local buyout = number(info.buyoutAmount)
	amount = number(amount)
	bid((buyout and amount and amount >= buyout) and "buyout" or "bid", amount, item)
end

local function onCommodity(itemID, quantity)
	local item, q = itemName(number(itemID)), number(quantity)
	bid("buyout", nil, item and q and q > 1 and item .. " x" .. q or item)
end

local function onLegacyBid(listType, index, amount)
	local item, _, _, _, _, _, _, _, _, buyout = call(GetAuctionItemInfo, listType, index)
	buyout, amount = number(buyout), number(amount)
	bid((buyout and buyout > 0 and amount and amount >= buyout) and "buyout" or "bid", amount, text(item))
end

local function posted(item)
	local now = GetTime()
	posts = prune(posts, now, POST)
	posts[#posts + 1] = { item = item, at = now }
end

local function onPost(location)
	posted(text(call(api(C_Item, "GetItemName"), location)))
end

local function onLegacyPost()
	posted(text(call(GetAuctionSellItemInfo)))
end

-- Clicks wait for the gold drop or the purchase event; whichever comes first takes the click.
local function pendingBids(now)
	bids = prune(bids, now, AUCTION_CLICK)
	return bids
end

local function onPurchase()
	local b = table.remove(pendingBids(GetTime()), 1)
	if b then
		auction(b.act, b.amount, b.item)
		purchase = { item = b.item, at = GetTime() }
	end
end

local function auctionLoss(loss, now)
	posts = prune(posts, now, POST)
	local p = table.remove(posts, 1)
	if p then
		auction("post", loss, p.item)
		return p.item
	end
	local list = pendingBids(now)
	local pick
	for i, b in ipairs(list) do
		if b.amount == loss then
			pick = i
			break
		end
		pick = pick or (not b.amount and i or nil)
	end
	if pick then
		local b = table.remove(list, pick)
		auction(b.act, loss, b.item)
		return b.item
	end
	if fresh(purchase, now, PURCHASE) then
		local item = purchase.item
		purchase = nil
		return item
	end
end

-- Mail ---------------------------------------------------------------------

local function readMail(i)
	local _, _, sender, subject, money, _, days, _, _, _, _, canReply, isGM = call(GetInboxHeaderInfo, i)
	sender, subject = text(sender), text(subject)
	if sender and subject then
		return {
			sender = sender,
			subject = subject,
			money = number(money) or 0,
			days = number(days) or 0,
			player = h:R(canReply) == true and h:R(isGM) ~= true,
		}
	end
end

local function sameMail(a, b)
	return a.sender == b.sender and a.subject == b.subject and abs(a.days - b.days) < DAYS
end

local function attachment(i, slot)
	local name, id, _, count, quality = call(GetInboxItem, i, slot)
	return number(id), text(name), number(count), number(quality)
end

local function firstAttachment(i)
	for slot = 1, ATTACHMENTS do
		local id, name = attachment(i, slot)
		if id or name then
			return name or "?"
		end
	end
end

local function subjectItem(compiled, subject)
	local args = compiled and ns.Match(compiled, subject)
	return args and args.what
end

-- What a mail is: { kind, item, who } of its invoice, the src and what of its gold, the how of its attachments and the
-- item of an outbid or expired auction subject.
local function classify(i, m)
	local kind, item, who = call(GetInboxInvoiceInfo, i)
	local c = { kind = text(kind), item = text(item), who = text(who) }
	local from = m.player and "mail" or "other"
	c.outbid, c.expired = subjectItem(outbidSubject, m.subject), subjectItem(expiredSubject, m.subject)
	if c.kind == "seller" then
		c.src, c.what, c.how = "auction", c.item, "mail"
	elseif c.kind == "buyer" then
		c.src, c.what, c.how = from, m.sender, "bought"
	else
		c.src, c.what, c.how = c.outbid and "auction" or from, c.outbid or m.sender, c.expired and "other" or "mail"
	end
	return c
end

local function mailLines(i, m, c)
	if c.kind == "seller" then
		auction("sold", m.money, c.item)
		mail("invoice", c.who, m.money, c.item)
	elseif c.kind == "buyer" then
		mail("invoice", c.who, m.money, c.item or firstAttachment(i))
	else
		if c.expired then
			auction("expired", nil, c.expired)
		end
		mail("take", m.sender, m.money, firstAttachment(i))
	end
end

local function stopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- Each asked attachment waits until it has left its mail. A failed inbox read proves nothing, so it keeps waiting.
local function check()
	local n = number(call(GetInboxNumItems))
	if not n then
		return
	end
	local mails = {}
	for j = 1, n do
		mails[j] = readMail(j)
		if not mails[j] then
			return
		end
	end
	local now, keep = GetTime(), {}
	for _, w in ipairs(waits) do
		local left = true
		for j, m in ipairs(mails) do
			if left and sameMail(m, w.mail) then
				local id, name = attachment(j, w.slot)
				left = id ~= w.item or name ~= w.name
			end
		end
		if left then
			ns.Loot.RecordItem({ item = w.item, quality = w.quality, count = w.count, how = w.how, name = w.name })
		elseif now - w.at <= WAIT then
			keep[#keep + 1] = w
		end
	end
	waits = keep
	if #waits == 0 then
		stopTicker()
	end
end

local function ask(i, m, how, slot)
	local id, name, count, quality = attachment(i, slot)
	if not id and not name then
		return
	end
	for _, w in ipairs(waits) do
		if w.slot == slot and sameMail(w.mail, m) then
			return
		end
	end
	local w = { mail = m, slot = slot, item = id, name = name, count = count, quality = quality, how = how }
	w.at = GetTime()
	waits[#waits + 1] = w
	ticker = ticker or C_Timer.NewTicker(1, function()
		h:Safe("mail check", check)
	end)
end

-- The how of a waiting attachment of this item, so a pushed line that comes before the wait ends names it the same way.
function Money.MailHow(id)
	for _, w in ipairs(waits) do
		if w.item == id then
			return w.how
		end
	end
end

-- slots: nil for the gold only, a slot, or true for every attachment.
local function onTake(i, slots)
	local m = readMail(i)
	if not m then
		return
	end
	local c = classify(i, m)
	local now = GetTime()
	takes = prune(takes, now, MAIL)
	-- One attachment moves no gold, so a gain never matches that take.
	local money = (slots == true or slots == nil) and m.money or 0
	takes[#takes + 1] = { src = c.src, what = c.what, money = money, at = now }
	local seen = false
	for _, other in ipairs(handled) do
		seen = seen or sameMail(other, m)
	end
	if not seen then
		handled[#handled + 1] = m
		mailLines(i, m, c)
	end
	if slots == true then
		for slot = 1, ATTACHMENTS do
			ask(i, m, c.how, slot)
		end
	elseif slots then
		ask(i, m, c.how, slots)
	end
end

local function onSendMail(recipient)
	local item = call(GetSendMailItem, 1)
	send = {
		who = text(recipient) or "?",
		money = number(call(GetSendMailMoney)) or 0,
		item = text(item),
		at = GetTime(),
	}
end

-- A gain belongs to the take whose mail held that much gold: takes in a row can come before their gold arrives.
local function mailChange(delta, now)
	if delta > 0 then
		takes = prune(takes, now, MAIL)
		local t = takes[#takes]
		for k, other in ipairs(takes) do
			if other.money == delta then
				t = table.remove(takes, k)
				break
			end
		end
		return change(delta, t and t.src or "mail", t and t.what)
	end
	local s = send
	if not (fresh(s, now, MAIL) and not s.paid) then
		return change(delta, "mail")
	end
	s.paid = true
	local loss = -delta
	if s.money > 0 and loss >= s.money then
		change(-s.money, "mail", s.who)
		if loss > s.money then
			change(s.money - loss, "postage", s.who)
		end
	else
		change(delta, "postage", s.who)
	end
end

local function onMailClosed()
	if #waits > 0 and (number(call(GetInboxNumItems)) or 0) > 0 then
		check()
	end
	waits = {}
	stopTicker()
end

-- Trade --------------------------------------------------------------------

local function readTrade()
	if not trade then
		return
	end
	local items = {}
	for slot = 1, TRADE_SLOTS do
		local id, linked = ns.LinkItem(text(call(GetTradeTargetItemLink, slot)))
		local name, _, count, quality = call(GetTradeTargetItemInfo, slot)
		name = text(name) or linked
		if name then
			items[#items + 1] = {
				item = id,
				name = name,
				count = number(count),
				quality = number(quality),
			}
		end
	end
	trade.items = items
	trade.received = number(call(GetTargetTradeMoney)) or 0
	trade.given = number(call(GetPlayerTradeMoney)) or 0
end

-- The message shows in two events, and the trade is written once.
local function onTradeMessage(msg)
	local complete = text(ERR_TRADE_COMPLETE)
	if not trade or trade.done or not complete or text(msg) ~= complete then
		return
	end
	trade.done = true
	local copper = trade.received - trade.given
	h:Write("tr", trade.partner or "?", copper ~= 0 and copper or nil)
	h:Count("trade", "trades")
	for _, item in ipairs(trade.items) do
		item.how = "trade"
		ns.Loot.RecordItem(item)
	end
end

-- Gold ---------------------------------------------------------------------

local function vendorWhat(delta, now)
	if delta < 0 then
		return fresh(bought, now, VENDOR) and bought.name or nil
	end
	if fresh(sold, now, VENDOR) and sold.name then
		return sold.count and sold.count > 1 and sold.count .. " " .. sold.name or sold.name
	end
end

local function attribute(delta, now)
	local loss = delta < 0
	local window = Money.CurrentWindow()
	if loss and repairAt and now - repairAt <= REPAIR then
		repairAt = nil
		return change(delta, "repair")
	elseif loss and wipeAt and now - wipeAt <= RESPEC then
		wipeAt = nil
		return change(delta, "respec")
	end
	local services = loss and paidTrainer(-delta, now)
	if services then
		return change(delta, "trainer", services)
	elseif window == "auction" then
		return change(delta, "auction", loss and auctionLoss(-delta, now) or nil)
	elseif window == "mail" then
		return mailChange(delta, now)
	elseif window == "trade" then
		return change(delta, "trade", trade and trade.partner or lastPartner)
	elseif window == "vendor" then
		return change(delta, "vendor", vendorWhat(delta, now))
	elseif window == "quest" then
		-- A turn-in names one gain only, so the next quest's gold never takes its title.
		local title = fresh(turnedIn, now, QUEST) and turnedIn.title or nil
		turnedIn = nil
		return change(delta, "quest", title)
	elseif window == "flight" then
		local flight = h:Flight()
		return change(delta, "flight", flight and flight.to)
	elseif window ~= "none" then
		return change(delta, window)
	end
	change(delta, loss and "other" or "loot")
end

-- A hidden amount keeps the last known gold and writes nothing.
local function onMoney()
	local gold = number(call(GetMoney))
	if not gold then
		return
	elseif not last then
		return sync(gold)
	end
	local delta = gold - last
	last = gold
	if delta ~= 0 then
		attribute(delta, GetTime())
	end
end

-- Start --------------------------------------------------------------------

local function onWindows()
	for _, w in ipairs(WINDOWS) do
		local open, name, closeEvent, delay = w[1], w[2], w[3], w[4]
		h:On(open, function()
			label, closesAt = name, nil
		end)
		h:On(closeEvent, function()
			if label == name then
				if delay > 0 then
					closesAt = GetTime() + delay
				else
					label = nil
				end
			end
		end)
	end
end

local function onHooks()
	-- A guild bank repair takes no gold from the player.
	h:Hook(nil, "RepairAllItems", function(guildBank)
		repairAt = not guildBank and GetTime() or nil
	end)
	h:Hook(nil, "ConfirmTalentWipe", function()
		wipeAt = GetTime()
	end)
	h:Hook(nil, "BuyMerchantItem", function(index)
		local name = text(call(GetMerchantItemInfo, index)) or itemName(number(call(GetMerchantItemID, index)))
		bought = { name = name, at = GetTime() }
	end)
	local function onUse(bag, slot)
		if Money.CurrentWindow() ~= "vendor" then
			return
		end
		local info = h:R(call(api(C_Container, "GetContainerItemInfo"), bag, slot))
		if type(info) == "table" then
			sold = { name = text(info.itemName), count = number(info.stackCount), at = GetTime() }
		end
	end
	h:Hook(C_Container, "UseContainerItem", onUse)
	h:Hook(nil, "UseContainerItem", onUse)
	h:Hook(nil, "BuyTrainerService", onBuyService)
	h:Hook(C_AuctionHouse, "PlaceBid", onPlaceBid)
	h:Hook(C_AuctionHouse, "PostItem", onPost)
	h:Hook(C_AuctionHouse, "PostCommodity", onPost)
	h:Hook(C_AuctionHouse, "ConfirmCommoditiesPurchase", onCommodity)
	h:Hook(nil, "PlaceAuctionBid", onLegacyBid)
	h:Hook(nil, "PostAuction", onLegacyPost)
	h:Hook(nil, "StartAuction", onLegacyPost)
	h:Hook(nil, "SendMail", onSendMail)
	h:Hook(nil, "TakeInboxMoney", function(i)
		onTake(i)
	end)
	h:Hook(nil, "TakeInboxItem", function(i, slot)
		onTake(i, number(slot) or 1)
	end)
	h:Hook(nil, "AutoLootMailItem", function(i)
		onTake(i, true)
	end)
end

local function onEvents()
	h:On("PLAYER_MONEY", onMoney)
	h:On("QUEST_TURNED_IN", function(_, questID)
		local title = text(call(api(C_QuestLog, "GetTitleForQuestID"), number(questID)))
		turnedIn = { title = title, at = GetTime() }
	end)
	h:On("TRAINER_SHOW", function()
		readTrainer()
		C_Timer.After(1, function()
			h:Safe("trainer", readTrainer)
		end)
	end)
	h:On("TRAINER_UPDATE", function()
		h:Coalesce("trainer", 0.3, readTrainer)
	end)
	h:On("AUCTION_HOUSE_PURCHASE_COMPLETED", onPurchase)
	h:On("COMMODITY_PURCHASE_SUCCEEDED", onPurchase)
	-- Only a commodity click has no amount, so the failed purchase is the newest of those.
	h:On("COMMODITY_PURCHASE_FAILED", function()
		for i = #bids, 1, -1 do
			if not bids[i].amount then
				table.remove(bids, i)
				return
			end
		end
	end)
	h:On("MAIL_SHOW", function()
		handled = {}
	end)
	h:On("MAIL_SEND_SUCCESS", function()
		if send and not send.written then
			send.written = true
			mail("send", send.who, send.money, send.item)
		end
	end)
	h:On("MAIL_FAILED", function()
		send = nil
	end)
	h:On("MAIL_CLOSED", onMailClosed)
	h:On("TRADE_SHOW", function()
		trade = { partner = text(UnitName("NPC")), items = {}, received = 0, given = 0 }
		lastPartner = trade.partner or lastPartner
	end)
	for _, event in ipairs({ "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE" }) do
		h:On(event, readTrade)
	end
	h:On("UI_INFO_MESSAGE", function(_, _, msg)
		onTradeMessage(msg)
	end)
	h:On("CHAT_MSG_SYSTEM", function(_, msg)
		onTradeMessage(msg)
	end)
	h:Listen("LEVEL_UP", function(_, level)
		C_Timer.After(2, function()
			h:Safe("level money", function()
				local gold = number(call(GetMoney))
				if gold then
					h:Snap(level, "money", gold)
				end
			end)
		end)
	end)
	h:Listen("RESTORED", function(_, addon)
		local gold = addon == ADDON and number(call(GetMoney))
		if gold then
			sync(gold)
		end
	end)
end

function Money.Start(handle)
	h = handle
	expiredSubject = ns.Compile(AUCTION_EXPIRED_MAIL_SUBJECT, { "what" })
	outbidSubject = ns.Compile(AUCTION_OUTBID_MAIL_SUBJECT, { "what" })
	local gold = number(call(GetMoney))
	if gold then
		sync(gold)
	end
	onWindows()
	onHooks()
	onEvents()
end

-- A registration after login calls OnLogin before RegisterModule returns, so the handle comes from the argument.
local function onLogin(handle)
	ns.h = handle
	ns.Loot.Start(handle)
	Money.Start(handle)
end

Memories.RegisterModule({
	addon = ADDON,
	api = 1,
	saved = "MemoriesEconomyCharDB",
	kinds = {
		{
			kind = "lo",
			group = "Loot",
			name = L["Loot"],
			fields = { "#item", "#quality", "#count", "how", "name", "#gear", "#first" },
		},
		{
			kind = "rl",
			group = "Loot",
			name = L["Group roll ended"],
			fields = { "#item", "type", "#roll", "#won", "name", "#quality" },
		},
		{ kind = "ge", group = "Loot", name = L["Gear snapshot"], fields = { "#level", "ids", "src" } },
		{ kind = "eq", group = "Loot", name = L["Equipped an item"], fields = { "#slot", "#item", "#quality" } },
		{ kind = "mn", group = "Money", name = L["Money in or out"], fields = { "#delta", "src", "what" } },
		{ kind = "tb", group = "Money", name = L["Trainer purchase"], fields = { "kind", "what", "#cost" } },
		{ kind = "ah", group = "Money", name = L["Auction house"], fields = { "act", "#copper", "item" } },
		{ kind = "ma", group = "Money", name = L["Mail"], fields = { "act", "who", "#copper", "item" } },
		{ kind = "tr", group = "Money", name = L["Traded with someone"], fields = { "name", "#copper" } },
	},
	newOnly = { { key = "loot", label = L["Loot: new findings only"], kinds = { "lo" } } },
	OnLogin = onLogin,
})
