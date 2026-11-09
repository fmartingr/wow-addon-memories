local ADDON, ns = ...
local L = ns.L

if not Memories or not Memories.RegisterModule then
	print(ADDON .. ": " .. L["Memories is not loaded."])
	return
end

local CAST_WINDOW = 3
local ITEM_WINDOW = 2
-- Enum.LootSlotType
local SLOT_ITEM, SLOT_MONEY = 1, 2

-- from is the source kind of the cast's own window: a window from the other kind belongs to something else, such as a
-- corpse looted after an Opening cast on a door or lever, which opens no window of its own.
local MINING = { what = "gather", prof = "Mining", verb = "mined", from = "object" }
local HERBALISM = { what = "gather", prof = "Herbalism", verb = "picked", from = "object" }
local SKINNING = { what = "gather", prof = "Skinning", verb = "skinned", from = "npc" }
local FISHING = { what = "fish", prof = "Fishing", verb = "caught" }
local CHEST = { what = "chest", from = "object" }
local PICK = { what = "pick", from = "npc" }
-- Disenchanting opens an item window too: it belongs to crafting, so its window writes nothing here.
local DISENCHANT = { what = "craft" }
-- Base spell ids. Higher ranks have other ids with the same localized name, so they match by name.
local CASTS = {
	[2575] = MINING,
	[2366] = HERBALISM,
	[8613] = SKINNING,
	[7620] = FISHING,
	[921] = PICK,
	[3365] = CHEST,
	[13262] = DISENCHANT,
}
-- "Opening - No Text" is not translated in any client, so no id gives it.
local UNTRANSLATED = { ["Opening - No Text"] = CHEST }
-- Black Lotus and Arcane Crystal.
local RARE_ITEMS = { [13468] = true, [12363] = true }

local h
local byName
-- The cast of each spell id matched by name, false for a spell known to match none.
local byID = {}
-- The sent cast { guid, target }, the last known cast { what, prof, from, node, at } and the last loot-bearing item use
-- { item, name, at }. One loot window uses them up.
local sent, cast, used
-- The open loot window { c, u, fishing, window, done }, from its first LOOT_READY to its LOOT_CLOSED.
local open

local function pass(ok, ...)
	if ok then
		return ...
	end
end

-- An optional game call: nothing when the function is missing or fails.
local function call(fn, ...)
	if type(fn) == "function" then
		return pass(pcall(fn, ...))
	end
end

local function text(v)
	v = h:R(v)
	return type(v) == "string" and v ~= "" and v or nil
end

local function number(v)
	v = h:R(v)
	return type(v) == "number" and v or nil
end

-- A name to write: "?" when the game hid it or gave none.
local function name(v)
	return text(v) or "?"
end

-- The localized names stay unknown until the client answers; until one is read, the next cast tries again.
local function names()
	if byName then
		return byName
	end
	local map, any = {}, false
	for spell, c in pairs(UNTRANSLATED) do
		map[spell] = c
	end
	for id, c in pairs(CASTS) do
		local spell = text(call(h.SpellName, h, id))
		if spell then
			map[spell], any = c, true
		end
	end
	if any then
		byName = map
	end
	return map
end

local function castOf(spellID)
	spellID = number(spellID)
	if not spellID then
		return nil
	end
	if CASTS[spellID] then
		return CASTS[spellID]
	end
	if byID[spellID] ~= nil then
		return byID[spellID] or nil
	end
	local spell = text(call(h.SpellName, h, spellID))
	local c = spell and names()[spell] or nil
	-- A miss before the localized names are read is asked again on the next cast.
	if c or (spell and byName) then
		byID[spellID] = c or false
	end
	return c
end

local function onSent(unit, target, guid, spellID)
	if unit ~= "player" or not castOf(spellID) then
		return
	end
	sent = { guid = h:R(guid), target = text(target) }
end

local function onSucceeded(unit, guid, spellID)
	if unit ~= "player" then
		return
	end
	local c = castOf(spellID)
	if not c then
		return
	end
	guid = h:R(guid)
	local node = sent and guid and sent.guid == guid and sent.target or nil
	sent = nil
	if c.verb then
		h:Count("gather", "cast:" .. c.verb .. "|" .. (node or "?") .. "|" .. c.prof)
	end
	if c.what ~= "fish" then
		cast = { what = c.what, prof = c.prof, from = c.from, node = node, at = GetTime() }
	end
end

local function onUse(bag, slot)
	local info = h:R(call(C_Container.GetContainerItemInfo, bag, slot))
	if type(info) ~= "table" or h:R(info.hasLoot) ~= true then
		return
	end
	local item = number(info.itemID)
	local itemName = item and type(C_Item) == "table" and text(call(C_Item.GetItemNameByID, item))
	used = { item = item, name = itemName or text(info.itemName), at = GetTime() }
end

-- GUID form Type-0-server-instance-zone-ID-spawn.
local function sourceOf(guid)
	local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-([^-]*)")
	id = tonumber(id)
	if kind == "GameObject" then
		return { object = id }
	elseif kind == "Creature" or kind == "Vehicle" then
		return { npc = id }
	end
	return {}
end

-- The open window as { items = { { item, name, count, quality, quest } }, money, source = { object, npc } }.
local function readWindow()
	local out = { items = {}, money = false }
	for i = 1, number(call(GetNumLootItems)) or 0 do
		local slotType = number(call(GetLootSlotType, i))
		if slotType == SLOT_MONEY then
			out.money = true
		elseif slotType == SLOT_ITEM then
			local _, itemName, count, _, quality, _, quest = call(GetLootSlotInfo, i)
			local link = text(call(GetLootSlotLink, i))
			local item = link and tonumber(link:match("item:(%d+)"))
			if item then
				count = number(count)
				out.items[#out.items + 1] = {
					item = item,
					name = name(itemName),
					count = count and count >= 1 and count or 1,
					quality = number(quality),
					quest = h:R(quest) == true,
				}
			end
		end
		if not out.source then
			local guid = text(call(GetLootSourceInfo, i))
			out.source = guid and sourceOf(guid)
		end
	end
	out.source = out.source or {}
	return out
end

-- Counts every find and returns whether it writes a line, and why. With "new findings only" on, only a first or a rare
-- find writes one.
local function find(prof, slot, rare)
	h:Count("gather", prof, slot.count)
	local before = h:Count("gather", "item:" .. prof .. "|" .. slot.item, slot.count)
	local why = rare and "rare" or before == 0 and "first" or nil
	return why ~= nil or not h:NewOnly("gathering"), why
end

local function many(count)
	return count > 1 and count or nil
end

local function gather(c, window)
	for _, slot in ipairs(window.items) do
		local write, why = find(c.prof, slot, (slot.quality or 0) >= 3 or RARE_ITEMS[slot.item])
		if write then
			local at = window.source.object
			h:Write("ga", c.prof, c.node or "?", at, slot.item, slot.quality, many(slot.count), slot.name, why)
		end
	end
end

local function fish(window)
	local pool = window.source.object
	for _, slot in ipairs(window.items) do
		local write, why = find("Fishing", slot, (slot.quality or 0) >= 2)
		if write then
			h:Write("fs", slot.item, slot.quality, many(slot.count), slot.name, pool, why)
		end
	end
end

-- Quest crates opened with the same spell hold only their quest item: they are no chest.
local function chest(c, window)
	local loot = window.money
	for _, slot in ipairs(window.items) do
		loot = loot or not slot.quest
	end
	if loot then
		h:Count("gather", "open:chest")
		h:Write("op", "chest", nil, c.node or "?", window.source.object)
	end
end

local function pick(c, window)
	h:Count("gather", "pickpockets")
	local best
	for _, slot in ipairs(window.items) do
		if not best or (slot.quality or -1) > (best.quality or -1) then
			best = slot
		end
	end
	if best then
		h:Write("pp", c.node or "?", window.source.npc, best.item, best.quality, best.name)
	end
end

local CLASSES = { gather = gather, chest = chest, pick = pick }

-- With auto-loot on, the client sends no LOOT_OPENED, and an auto-loot addon empties the slots before LOOT_CLOSED. So
-- the window is read at its first LOOT_READY, and handled at LOOT_OPENED, which tells an item's window, else at
-- LOOT_CLOSED. The client can send LOOT_READY more than once for one window.
local function onReady()
	if open then
		return
	end
	local now = GetTime()
	local c = cast and now - cast.at <= CAST_WINDOW and cast or nil
	local u = used and now - used.at <= ITEM_WINDOW and used or nil
	cast, used, sent = nil, nil, nil
	open = { c = c, u = u, fishing = h:R(call(IsFishingLoot)) == true }
	-- Most windows are corpses looted with nothing pending, and they are not read.
	if open.fishing or (c and c.what ~= "craft") or u then
		open.window = readWindow()
	end
end

local function claim(fromItem)
	if open.done then
		return
	end
	open.done = true
	local c, u, window = open.c, open.u, open.window
	if open.fishing then
		fish(window)
		return
	end
	if (c and c.what == "craft") or not (fromItem or c or u) then
		return
	end
	local source = window and window.source or {}
	-- An item used with no window of its own, such as a locked box, leaves a corpse or object window unclaimed.
	if fromItem or (u and not c and not source.npc and not source.object) then
		h:Count("gather", "open:item")
		h:Write("op", "item", u and u.item, u and u.name or "?")
	elseif c and not (c.from == "object" and source.npc or c.from == "npc" and source.object) then
		CLASSES[c.what](c, window)
	end
end

local function onOpened(_, _, isFromItem)
	onReady()
	claim(h:R(isFromItem) == true)
end

local function onClosed()
	if open then
		claim(false)
		open = nil
	end
end

local function onMessage(_, _, message)
	message = text(message)
	if not message then
		return
	end
	if message == text(ERR_FISH_ESCAPED) then
		h:Count("gather", "fish:escaped")
	elseif message == text(ERR_FISH_NOT_HOOKED) then
		h:Count("gather", "fish:missed")
	end
end

-- A registration after login calls OnLogin before RegisterModule returns, so the handle comes from the argument.
local function onLogin(handle)
	h = handle
	h:On("LOOT_READY", onReady)
	h:On("LOOT_OPENED", onOpened)
	h:On("LOOT_CLOSED", onClosed)
	-- Forever sends the fishing messages as UI info messages; other clients send them as UI errors.
	h:On("UI_INFO_MESSAGE", onMessage)
	h:On("UI_ERROR_MESSAGE", onMessage)
	if type(C_Container) == "table" then
		h:Hook(C_Container, "UseContainerItem", onUse)
	end
	-- Other units' casts never reach this frame, so a crowded place costs nothing.
	local frame = CreateFrame("Frame")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	frame:SetScript("OnEvent", function(_, event, ...)
		h:Safe(event, event == "UNIT_SPELLCAST_SENT" and onSent or onSucceeded, ...)
	end)
end

Memories.RegisterModule({
	addon = ADDON,
	api = 1,
	saved = "MemoriesGatheringCharDB",
	kinds = {
		{
			kind = "ga",
			group = "Gathering",
			name = L["Gathered"],
			fields = { "prof", "node", "#object", "#item", "#quality", "#count", "name", "why" },
		},
		{
			kind = "fs",
			group = "Gathering",
			name = L["Caught while fishing"],
			fields = { "#item", "#quality", "#count", "name", "#object", "why" },
		},
		{
			kind = "op",
			group = "Gathering",
			name = L["Opened a container or chest"],
			fields = { "how", "#item", "name", "#object" },
		},
		{
			kind = "pp",
			group = "Gathering",
			name = L["Picked a pocket"],
			fields = { "who", "#npc", "#item", "#quality", "name" },
		},
	},
	newOnly = { { key = "gathering", label = L["Gathering: new findings only"], kinds = { "ga", "fs" } } },
	OnLogin = onLogin,
})
