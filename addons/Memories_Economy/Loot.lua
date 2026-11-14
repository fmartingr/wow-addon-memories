local ADDON, ns = ...
local L = ns.L

if not Memories or not Memories.RegisterModule then
	print(ADDON .. ": " .. L.CORE_MISSING)
	return
end

local Loot = {}
ns.Loot = Loot

local MAGIC = "[%^%$%(%)%.%[%]%*%+%-%?]"
-- The loot history link in front of a roll line, "|HlootHistory:<id>|h[<word>]|h: ".
local HISTORY = "^|HlootHistory:([^|]*)|h.-|h:?%s*"
local SLOTS = 19
local DEDUPE = 2
local RECEIVED = 5
local WON = 10
local ROLL_TTL = 300
local IGNORE = "INVTYPE_NON_EQUIP_IGNORE"
-- The chat colors of the item qualities, for a link whose item the client does not know yet.
local HEX = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5 }
-- Money's window to the how of a pushed item.
local PUSHED = { vendor = "bought", auction = "bought", quest = "quest", mail = "mail", trade = "trade" }
-- { GlobalStrings name, argument names, line type, roll type }. A line is read with the first format that matches it,
-- so each "x<count>" form comes before its single form, and "You won" before "<who> won".
local FORMS = {
	{ "LOOT_ITEM_SELF_MULTIPLE", { "item", "count" }, "own" },
	{ "LOOT_ITEM_SELF", { "item" }, "own" },
	{ "LOOT_ITEM_PUSHED_SELF_MULTIPLE", { "item", "count" }, "pushed" },
	{ "LOOT_ITEM_PUSHED_SELF", { "item" }, "pushed" },
	{ "LOOT_ITEM_CREATED_SELF_MULTIPLE", { "item", "count" }, "made" },
	{ "LOOT_ITEM_CREATED_SELF", { "item" }, "made" },
	{ "LOOT_ROLL_NEED_SELF", { "item" }, "select", "need" },
	{ "LOOT_ROLL_GREED_SELF", { "item" }, "select", "greed" },
	{ "LOOT_ROLL_ROLLED_NEED", { "roll", "item", "who" }, "rolled", "need" },
	{ "LOOT_ROLL_ROLLED_GREED", { "roll", "item", "who" }, "rolled", "greed" },
	{ "LOOT_ROLL_YOU_WON", { "item" }, "won" },
	{ "LOOT_ROLL_WON", { "who", "item" }, "won" },
	{ "LOOT_ROLL_ALL_PASSED", { "item" }, "passed" },
}

local forms
-- Open rolls by roll key: { type, roll, item, name, quality, at }, or { done, at } once a result closed it.
local rolls = {}
-- The GetTime() of each item id's last own or pushed line, roll win, recorded pushed line and record from Money.
local received, won, pushed, fromMoney = {}, {}, {}, {}
local STAMPS = { received, won, pushed, fromMoney }
local baseline

local function pass(ok, ...)
	if ok then
		return ...
	end
end

-- An optional game call: nothing when the function is missing or fails.
function ns.Call(fn, ...)
	if type(fn) == "function" then
		return pass(pcall(fn, ...))
	end
end

-- A function of an optional game table.
function ns.Api(t, name)
	return type(t) == "table" and t[name] or nil
end

function ns.Text(v)
	v = ns.h:R(v)
	return type(v) == "string" and v ~= "" and v or nil
end

function ns.Number(v)
	v = ns.h:R(v)
	return type(v) == "number" and v or nil
end

-- The item id and the name of an item link, each nil when the link lacks it.
function ns.LinkItem(link)
	if type(link) ~= "string" then
		return nil, nil
	end
	return tonumber(link:match("|Hitem:(%d+)")), link:match("|h%[(.-)%]|h")
end

-- Turns a GlobalStrings format into a pattern for the whole text, or nil when the format lacks one of names. names
-- holds the format's arguments in their own order, so a translation that reorders them with "%2$s" fills the right
-- name. The argument "item" takes a whole item link, since an item name can hold the words that follow it. A loot
-- history link in front is dropped, as the lines drop it before they match.
function ns.Compile(fmt, names)
	if type(fmt) ~= "string" then
		return nil
	end
	local body = fmt:gsub(HISTORY, "")
	-- The dropped link held the first argument.
	local skip = body == fmt and 0 or 1
	local parts, order, used, arg, i = { "^" }, {}, {}, skip, 1
	while i <= #body do
		local c = body:sub(i, i)
		if c == "%" then
			local pos, conv, nxt = body:match("^(%d+)%$([sd])()", i + 1)
			if not pos then
				conv, nxt = body:match("^([sd%%])()", i + 1)
			end
			if not conv then
				return nil
			end
			if conv == "%" then
				parts[#parts + 1] = "%%"
			else
				arg = arg + 1
				local name = names[(tonumber(pos) or arg) - skip]
				if not name then
					return nil
				end
				order[#order + 1], used[name] = name, true
				parts[#parts + 1] = conv == "d" and "(%d+)" or name == "item" and "(.-|h|r)" or "(.-)"
			end
			i = nxt
		else
			parts[#parts + 1] = c:match(MAGIC) and "%" .. c or c
			i = i + 1
		end
	end
	for _, name in ipairs(names) do
		if not used[name] then
			return nil
		end
	end
	parts[#parts + 1] = "$"
	return { pattern = table.concat(parts), order = order }
end

-- The named arguments of a text that matches a compiled format, else nil.
function ns.Match(compiled, s)
	local caps = { s:match(compiled.pattern) }
	if #caps == 0 then
		return nil
	end
	local args = {}
	for k, name in ipairs(compiled.order) do
		args[name] = caps[k]
	end
	return args
end

local function recent(map, id, now, window)
	local at = map[id]
	return at ~= nil and now - at <= window
end

local function knownQuality(id)
	return id and ns.Number(ns.Call(ns.Api(C_Item, "GetItemQualityByID"), id))
end

local function quality(id, link)
	return knownQuality(id)
		or tonumber(link:match("|cnIQ(%d)"))
		or HEX[(link:match("^|c%x%x(%x%x%x%x%x%x)") or ""):lower()]
end

-- Weapons and armor are wearable unless the game marks them as never equipped; other items need an equip location.
-- An item the client does not describe counts as wearable.
local function wearable(id)
	local _, _, _, loc, _, class = ns.Call(ns.Api(C_Item, "GetItemInfoInstant"), id)
	loc, class = ns.h:R(loc), ns.Number(class)
	loc = type(loc) == "string" and loc or nil
	if class == 2 or class == 4 then
		return loc ~= IGNORE
	elseif loc then
		return loc ~= "" and loc ~= IGNORE
	end
	return class == nil
end

-- Counts the item and writes its lo line. With "new findings only" on, only a new or a rare item writes one.
local function record(item, how)
	local h = ns.h
	local id, count = item.item, item.count or 1
	h:Count("loot", "items", count)
	if item.quality then
		h:Count("loot", "q" .. item.quality, count)
	end
	local first = id ~= nil and h:Count("loot", "item:" .. id, count) == 0
	if first or not id or (item.quality or 0) >= 3 or not h:NewOnly("loot") then
		local gear = id and wearable(id) and 1 or nil
		h:Write("lo", id, item.quality, count > 1 and count or nil, how, item.name or "?", gear, first and 1 or nil)
	end
end

-- Records an item that Money saw arrive by mail or trade: { item, quality, count, how, name }. The chat line of the
-- same item, when it came first, already recorded it.
function Loot.RecordItem(item)
	local now, id = GetTime(), item.item
	if id then
		if recent(pushed, id, now, DEDUPE) then
			return
		end
		fromMoney[id] = now
	end
	item.quality = item.quality or knownQuality(id)
	record(item, item.how)
end

local function close(r, result)
	local h = ns.h
	h:Count("loot", r.type .. "Rolls")
	if result == 1 then
		h:Count("loot", r.type .. "Won")
	end
	if r.roll == 100 then
		h:Count("loot", "perfect")
		h:Count("loot", "perfect:" .. r.type .. ":" .. (r.item or "?"))
	end
	h:Write("rl", r.item, r.type, r.roll, result, r.name or "?", r.quality)
end

-- A roll with no result closes after ROLL_TTL; a closed roll's key is kept as long, since its lines repeat.
local function expire(now)
	for key, r in pairs(rolls) do
		if now - r.at > ROLL_TTL then
			rolls[key] = nil
			if not r.done then
				close(r)
			end
		end
	end
	for _, map in ipairs(STAMPS) do
		for id, at in pairs(map) do
			if now - at > WON then
				map[id] = nil
			end
		end
	end
end

-- Forever names carry a surname after the name.
local function isMe(who)
	local me = ns.Text(UnitName("player"))
	return me ~= nil and (who == me or who:sub(1, #me + 1) == me .. " ")
end

local function join(form, item, key, now)
	local r = rolls[key]
	if not r then
		r = { type = form.roll, item = item.item, name = item.name, quality = item.quality, at = now }
		rolls[key] = r
	end
	return r
end

local LINES = {}

-- An item won by a roll a moment ago comes with its own loot line: the roll recorded it. That line is used up, so it
-- never hides the win of a second copy.
function LINES.own(_, item, _, now)
	local id = item.item
	if id then
		if recent(won, id, now, WON) then
			won[id] = nil
			return
		end
		received[id] = now
	end
	record(item, "loot")
end

function LINES.pushed(_, item, _, now)
	local id = item.item
	if id then
		received[id] = now
		if recent(fromMoney, id, now, DEDUPE) then
			return
		end
		pushed[id] = now
	end
	local window = ns.Money.CurrentWindow()
	record(item, window == "mail" and id and ns.Money.MailHow(id) or PUSHED[window] or "other")
end

function LINES.made(_, item)
	record(item, "made")
end

function LINES.select(_, item, key, now, form)
	join(form, item, key, now)
end

function LINES.rolled(args, item, key, now, form)
	if isMe(args.who) then
		local r = join(form, item, key, now)
		if not r.done and not r.roll then
			r.roll = tonumber(args.roll)
		end
	end
end

function LINES.won(args, item, key, now)
	local r = rolls[key]
	if r and r.done then
		return
	end
	rolls[key] = { done = true, at = now }
	if args.who and not isMe(args.who) then
		if r then
			close(r, 0)
		end
		return
	end
	if r then
		close(r, 1)
	end
	-- The loot line that came first recorded the item, and it stands for this one win only.
	local id = item.item
	if id and recent(received, id, now, RECEIVED) then
		received[id] = nil
		return
	end
	if not (id and recent(won, id, now, WON)) then
		record(item, "roll")
	end
	if id then
		won[id] = now
	end
end

function LINES.passed(_, _, key, now)
	rolls[key] = { done = true, at = now }
end

local function onChat(_, msg)
	msg = ns.Text(msg)
	if not msg then
		return
	end
	local now = GetTime()
	expire(now)
	local history, body = msg:match(HISTORY .. "(.*)$")
	body = body or msg
	for _, form in ipairs(forms) do
		local args = ns.Match(form.compiled, body)
		if args then
			local link = args.item
			local id, name = ns.LinkItem(link)
			local item = {
				item = id,
				name = name ~= "" and name or nil,
				quality = quality(id, link),
				count = tonumber(args.count),
			}
			LINES[form.what](args, item, history or "item:" .. (id or link), now, form)
			return
		end
	end
end

-- The worn item ids of slots 1-19: 0 for an empty slot, "?" for a hidden one.
local function readGear()
	local ids = {}
	for slot = 1, SLOTS do
		local id, secret = ns.h:R(ns.Call(GetInventoryItemID, "player", slot))
		ids[slot] = secret and "?" or type(id) == "number" and id or 0
	end
	return ids
end

-- The first read is the baseline. A hidden slot keeps its last known item, so it never counts as a change.
local function scanGear()
	local ids = readGear()
	for slot = 1, SLOTS do
		local was, now = baseline and baseline[slot], ids[slot]
		if now == "?" then
			ids[slot] = was or now
		elseif baseline and was ~= "?" and was ~= now then
			local q = now ~= 0 and ns.Number(ns.Call(GetInventoryItemQuality, "player", slot)) or nil
			ns.h:Write("eq", slot, now, q)
		end
	end
	baseline = ids
end

-- A ding's snapshot wins over a later login or reload at the same level.
local function snapshot(level, src)
	local h = ns.h
	local ids = readGear()
	baseline = baseline or ids
	level = level or h:Level()
	if not level or (src == "login" and h:Snap(level, "gear")) then
		return
	end
	local gear = table.concat(ids, ",")
	h:Write("ge", level, gear, src)
	h:Snap(level, "gear", gear)
end

function Loot.Start(h)
	forms = {}
	for _, f in ipairs(FORMS) do
		local compiled = ns.Compile(_G[f[1]], f[2])
		if compiled then
			forms[#forms + 1] = { compiled = compiled, what = f[3], roll = f[4] }
		end
	end
	h:On("CHAT_MSG_LOOT", onChat)
	h:On("PLAYER_EQUIPMENT_CHANGED", function()
		h:Coalesce("gear", 0.5, scanGear)
	end)
	-- The core emits LEVEL_UP only with a known level.
	h:Listen("LEVEL_UP", function(_, level)
		C_Timer.After(2, function()
			h:Safe("ding gear", snapshot, level, "ding")
		end)
	end)
	C_Timer.After(4, function()
		h:Safe("login gear", snapshot, nil, "login")
	end)
end
