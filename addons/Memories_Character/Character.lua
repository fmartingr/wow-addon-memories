local ADDON, ns = ...
local L = ns.L

if not Memories or not Memories.RegisterModule then
	print(ADDON .. ": " .. L["Memories is not loaded."])
	return
end

local Character = {}
ns.Character = Character

local MAGIC = "[%^%$%(%)%.%[%]%*%+%-%?]"
-- English key -> { skill line id, base spell id }: the ids give the profession's name in the client's language.
local PROFESSIONS = {
	Mining = { 186, 2575 },
	Herbalism = { 182, 2366 },
	Skinning = { 393, 8613 },
	Blacksmithing = { 164, 2018 },
	Engineering = { 202, 4036 },
	Leatherworking = { 165, 2108 },
	Tailoring = { 197, 3908 },
	Enchanting = { 333, 7411 },
	Alchemy = { 171, 2259 },
	["First Aid"] = { 129, 3273 },
	Cooking = { 185, 2550 },
	Fishing = { 356, 7620 },
}
local BY_LINE = {}
for key, ids in pairs(PROFESSIONS) do
	BY_LINE[ids[1]] = key
end
local VERBS = { Mining = "smelted", Cooking = "cooked", Enchanting = "applied" }
-- Auto Shot, Shoot and Attack repeat on their own, so they are never a cast.
local IGNORED = { [75] = true, [5019] = true, [6603] = true }
local TAME_BEAST = 1515
local DISENCHANT = 13262
-- Food and drink share one item subclass: only the paired cast's name tells a drink.
local DRINK = 430
local FOOD_AND_DRINK = 5
local KINDS = { [1] = "potion", [2] = "elixir", [3] = "flask", [4] = "scroll", [7] = "bandage" }
-- Special buffs by aura spell id, counted under one key in every client language.
local SPECIAL = { [431567] = "Self-Found", [364001] = "Soul of Iron" }
local SECRET_ERROR = "cannot be accessed when secret"
local LEARN_DEDUPE = 10
local PAIR = 1.5
local HOLD = 2
local MAX_LINES = 3
local TAME_WINDOW = 30
-- A Tame Beast channel that stops this many seconds before its end was cancelled.
local CUT_SHORT = 0.5
local SECRET_RESCAN = 5
-- Coin textures of a statistic value, for example "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t".
local COINS = { Gold = "g", Silver = "s", Copper = "c" }

local h
local professionNames
-- GetTime() of the last lr and rc per name: the event and the chat line tell the same spell.
local learnedAt, recipeAt = {}, {}
local learnForms, createForms
-- The last successful cast { name, at }, the drops that wait for one { item, n, at } and the bag counts by item id.
local lastCast, held, bags = nil, {}, nil
local names, items = {}, {}
local castStart, castGUID, castChannel, fightCasts, tamedAt, tameEnd, disenchantTarget
local auras, shapeshift, tradeName
local mounts = {}
-- Buff scans skipped while the client hid auras, and the first reason, for a debug view.
Character.secretAuras = { skipped = 0 }

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

function ns.SpellName(id)
	return id and ns.Text(ns.Call(ns.h.SpellName, ns.h, id))
end

-- A GlobalStrings format as a pattern for the whole text, or nil. Each argument is captured by its position in the
-- format, so a translation that reorders them with "%2$s" still fills the right one.
function ns.Compile(fmt)
	if type(fmt) ~= "string" or fmt == "" then
		return nil
	end
	local parts, order, arg, i = { "^" }, {}, 0, 1
	while i <= #fmt do
		local c = fmt:sub(i, i)
		if c == "%" then
			local pos, conv, nxt = fmt:match("^(%d+)%$([sd])()", i + 1)
			if not pos then
				conv, nxt = fmt:match("^([sd%%])()", i + 1)
			end
			if not conv then
				return nil
			end
			if conv == "%" then
				parts[#parts + 1] = "%%"
			else
				arg = arg + 1
				order[#order + 1] = tonumber(pos) or arg
				parts[#parts + 1] = conv == "d" and "(%d+)" or "(.-)"
			end
			i = nxt
		else
			parts[#parts + 1] = c:match(MAGIC) and "%" .. c or c
			i = i + 1
		end
	end
	parts[#parts + 1] = "$"
	return { pattern = table.concat(parts), order = order }
end

-- The arguments of a text that matches a compiled format, by their position in the format, else nil.
function ns.Match(compiled, s)
	if not compiled then
		return nil
	end
	local caps = { s:match(compiled.pattern) }
	if #caps == 0 then
		return nil
	end
	local args = {}
	for k, pos in ipairs(compiled.order) do
		args[pos] = caps[k]
	end
	return args
end

local call, api, text, number, spellName = ns.Call, ns.Api, ns.Text, ns.Number, ns.SpellName

local function snap(key, value)
	local level = h:Level()
	if level then
		h:Snap(level, key, value)
	end
end

-- The English key of a profession name in the client's language. Until the client gives any localized name, only
-- the English keys match and the next call tries again.
local function professionKey(name)
	if not name or PROFESSIONS[name] then
		return name
	end
	if not professionNames then
		local map, any = {}, false
		local function add(n, key)
			if n then
				map[n], any = key, true
			end
		end
		local lineInfo = api(C_SkillInfo, "GetSkillLineInfoByID")
		for key, ids in pairs(PROFESSIONS) do
			local line = h:R(call(lineInfo, ids[1]))
			add(type(line) == "table" and text(line.name) or nil, key)
			add(text(call(api(C_TradeSkillUI, "GetTradeSkillDisplayName"), ids[1])), key)
			add(spellName(ids[2]), key)
		end
		if not any then
			return nil
		end
		professionNames = map
	end
	return professionNames[name]
end

-- Skills ---------------------------------------------------------------------

local function skillRow(i)
	if api(C_SkillInfo, "GetSkillLineInfo") then
		local info = h:R(call(C_SkillInfo.GetSkillLineInfo, i))
		if type(info) == "table" then
			return info.name, h:R(info.isHeader), h:R(info.isCollapsed), info.rank, info.maxRank, info.skillID
		end
		return nil
	end
	local name, isHeader, isExpanded, rank, _, _, max = call(GetSkillLineInfo, i)
	return name, h:R(isHeader), not h:R(isExpanded), rank, max
end

-- The skill rows { name, header, rank, max, line } in pane order, and whether a collapsed header or an unreadable row
-- hid some of them.
local function readSkills()
	local count = api(C_SkillInfo, "GetNumSkillLines") or GetNumSkillLines
	local rows, seen, header, partial = {}, {}, "", false
	for i = 1, number(call(count)) or 0 do
		local name, isHeader, collapsed, rank, max, line = skillRow(i)
		name = text(name)
		if isHeader then
			header = name or ""
			partial = partial or collapsed == true
		elseif not name then
			partial = true
		elseif not seen[name] then
			seen[name] = true
			rows[#rows + 1] =
				{ name = name, header = header, rank = number(rank), max = number(max), line = number(line) }
		end
	end
	return rows, partial
end

local function byName(a, b)
	return a.name < b.name
end

local function checkSkills()
	local rows, partial = readSkills()
	if #rows == 0 then
		return
	end
	table.sort(rows, byName)
	local known = h:State("skills")
	local present = {}
	for _, row in ipairs(rows) do
		present[row.name] = true
		if row.rank and row.max then
			local was = known[row.name]
			local new = type(was) ~= "table"
			if new or was[1] ~= row.rank or was[2] ~= row.max then
				if new or was[2] ~= row.max or BY_LINE[row.line] or professionKey(row.name) then
					h:Write("sk", row.name, row.rank, row.max)
				end
				known[row.name] = { row.rank, row.max }
			end
		end
	end
	if partial then
		return
	end
	local gone = {}
	for name in pairs(known) do
		if not present[name] then
			gone[#gone + 1] = name
		end
	end
	table.sort(gone)
	for _, name in ipairs(gone) do
		known[name] = nil
		h:Write("sk", name, 0, 0)
	end
	local parts = {}
	for i, row in ipairs(rows) do
		parts[i] = row.header .. ":" .. row.name .. "=" .. (row.rank or "?") .. "/" .. (row.max or "?")
	end
	snap("skills", table.concat(parts, ";"))
end

-- Learned spells and recipes -------------------------------------------------

-- Two ranks of one spell share its name, so a report with another spell id is a new spell, never a repeat.
local function fresh(map, name, spell)
	local now, last = GetTime(), map[name]
	if last and now - last.at < LEARN_DEDUPE and (not spell or not last.spell or last.spell == spell) then
		last.spell = last.spell or spell
		return false
	end
	map[name] = { at = now, spell = spell }
	return true
end

local function learned(name, spell)
	if name and fresh(learnedAt, name, spell) then
		h:Count("character", "learned")
		h:Write("lr", name, spell)
	end
end

local function recipe(name, spell)
	learned(name, spell)
	if name and fresh(recipeAt, name, spell) then
		h:Count("character", "recipes")
		h:Write("rc", name, spell)
	end
end

local function onLearnLine(_, msg)
	msg = text(msg)
	if not msg then
		return
	end
	for _, form in ipairs(learnForms) do
		local args = ns.Match(form.compiled, msg)
		if args then
			local arg = args[1] or ""
			local name = arg:match("|h%[(.-)%]|h") or (arg:gsub("%.$", ""))
			local learn = form.recipe and recipe or learned
			learn(name ~= "" and name or nil, tonumber(arg:match("|Hspell:(%d+)")))
			return
		end
	end
end

-- Talents --------------------------------------------------------------------

-- The current spec first, then the class's other specs.
local function specs()
	local out, seen = {}, {}
	local function add(spec)
		if spec and not seen[spec] then
			seen[spec] = true
			out[#out + 1] = spec
		end
	end
	local current = number(call(api(C_SpecializationInfo, "GetSpecialization")))
	add(current and number(call(api(C_SpecializationInfo, "GetSpecializationInfo"), current)))
	local _, _, class = h:RN(UnitClass("player"))
	local n = class and number(call(api(C_SpecializationInfo, "GetNumSpecializationsForClassID"), class)) or 0
	for i = 1, n do
		add(number(call(GetSpecializationInfoForClassID, class, i)))
	end
	return out
end

-- The tree with the most spent points among the trees with a readable node: { spent, unspent, tree }, else nil.
local function readTalents()
	local config = number(call(api(C_ClassTalents, "GetActiveConfigID")))
	if not config then
		return nil
	end
	local best, read = nil, {}
	for _, spec in ipairs(specs()) do
		-- Specs of one class can share one tree, which is read once.
		local tree = number(call(api(C_ClassTalents, "GetTraitTreeForSpec"), spec))
		if read[tree] then
			tree = nil
		elseif tree then
			read[tree] = true
		end
		local nodes = tree and h:R(call(api(C_Traits, "GetTreeNodes"), tree))
		local spent, readable = 0, false
		for _, node in ipairs(type(nodes) == "table" and nodes or {}) do
			local info = h:R(call(api(C_Traits, "GetNodeInfo"), config, node))
			local ranks = type(info) == "table" and number(info.ranksPurchased)
			if ranks then
				spent, readable = spent + ranks, true
			end
		end
		if readable and (not best or spent > best.spent) then
			best = { spent = spent, tree = tree }
		end
	end
	if best then
		-- A tree can hold more than one point currency (class and spec points): unspent is their sum.
		local currency = h:R(call(api(C_Traits, "GetTreeCurrencyInfo"), config, best.tree, false))
		for _, entry in ipairs(type(currency) == "table" and currency or {}) do
			entry = h:R(entry)
			local quantity = type(entry) == "table" and number(entry.quantity)
			if quantity then
				best.unspent = (best.unspent or 0) + quantity
			end
		end
	end
	return best
end

local function checkTalents()
	local now = readTalents()
	local last = h:State("talents")
	if not now or (last.spent == now.spent and last.unspent == now.unspent) then
		return
	end
	if last.spent and now.spent < last.spent then
		h:Count("character", "respecs")
	end
	last.spent, last.unspent = now.spent, now.unspent
	h:Write("ta", now.spent, now.unspent)
	snap("talents", now.spent)
end

-- Consumables ----------------------------------------------------------------

local function itemInfo(id)
	if not items[id] then
		local _, _, _, _, _, class, sub = call(api(C_Item, "GetItemInfoInstant"), id)
		class, sub = number(class), number(sub)
		-- An item the client does not know yet is asked again on the next scan.
		if not class then
			return {}
		end
		items[id] = { class = class, sub = sub }
	end
	return items[id]
end

local function credit(drop, cast)
	local id, n = drop.item, drop.n
	local sub = itemInfo(id).sub
	local kind = KINDS[sub] or "other"
	if sub == FOOD_AND_DRINK then
		kind = cast.name and cast.name == spellName(DRINK) and "drink" or "food"
	end
	local combat = InCombatLockdown() == true
	local counts = h:Counts("items")
	local before = (counts["c:" .. id] or 0) + (counts["o:" .. id] or 0)
	h:Count("items", "total", n)
	h:Count("items", "k:" .. kind, n)
	h:Count("items", (combat and "c:" or "o:") .. id, n)
	local lines = n
	if h:NewOnly("consumables") then
		lines = before == 0 and 1 or 0
	end
	local name = names[id] or text(call(api(C_Item, "GetItemNameByID"), id)) or "?"
	for _ = 1, lines do
		h:Write("cu", id, kind, name, combat and "1" or nil)
	end
end

local function recentCast(now)
	return lastCast and now - lastCast.at <= PAIR and lastCast or nil
end

-- Pairs the newest held drop with the cast that just landed; drops older than HOLD were sold, traded or destroyed.
local function creditHeld(now)
	local cast = recentCast(now)
	for i = #held, 1, -1 do
		local drop = held[i]
		if now - drop.at > HOLD then
			table.remove(held, i)
		elseif cast and now - drop.at <= PAIR then
			table.remove(held, i)
			lastCast = nil
			credit(drop, cast)
			cast = nil
		end
	end
end

-- Consumable stack counts by item id in bags 0-4.
local function readBags()
	local out = {}
	for bag = 0, 4 do
		for slot = 1, number(call(api(C_Container, "GetContainerNumSlots"), bag)) or 0 do
			local info = h:R(call(api(C_Container, "GetContainerItemInfo"), bag, slot))
			local id = type(info) == "table" and number(info.itemID)
			if id and itemInfo(id).class == 0 then
				out[id] = (out[id] or 0) + (number(info.stackCount) or 1)
				names[id] = names[id] or text(info.itemName)
			end
		end
	end
	return out
end

-- The first scan is the baseline. A drop of 1 to 3 is a use; a larger one was sold, banked or mailed.
local function checkBags()
	local before = bags
	bags = readBags()
	if not before then
		return
	end
	local now = GetTime()
	for id, n in pairs(before) do
		local drop = n - (bags[id] or 0)
		if drop >= 1 and drop <= MAX_LINES then
			local cast = recentCast(now)
			if cast then
				lastCast = nil
				credit({ item = id, n = drop }, cast)
			else
				held[#held + 1] = { item = id, n = drop, at = now }
			end
		end
	end
end

-- Casts ----------------------------------------------------------------------

local baseNames = {}

-- name is spellName(spell), which the caller already holds.
local function isSpell(spell, base, name)
	if spell == base then
		return true
	end
	baseNames[base] = baseNames[base] or spellName(base)
	return name ~= nil and name == baseNames[base]
end

local function isMount(spell)
	if mounts[spell] == nil then
		mounts[spell] = number(call(api(C_MountJournal, "GetMountFromSpell"), spell)) ~= nil
	end
	return mounts[spell]
end

-- name is spellName(spell): a spell with no name never counts.
local function counted(spell, name)
	return name ~= nil and not IGNORED[spell] and not isMount(spell)
end

local function onSent(unit, target, _, spell)
	spell = number(spell)
	if unit == "player" and spell and isSpell(spell, DISENCHANT, spellName(spell)) then
		disenchantTarget = text(target)
	end
end

local function onSucceeded(unit, _, spell)
	spell = number(spell)
	if unit ~= "player" or not spell or IGNORED[spell] then
		return
	end
	local now = GetTime()
	local name = spellName(spell)
	lastCast = { name = name, at = now }
	creditHeld(now)
	if isSpell(spell, TAME_BEAST, name) then
		tamedAt = now
	elseif isSpell(spell, DISENCHANT, name) then
		h:Count("prof", "disenchanted|" .. (disenchantTarget or "?") .. "|Enchanting")
		disenchantTarget = nil
	end
	if not counted(spell, name) then
		return
	end
	local combat = InCombatLockdown() == true
	h:Count("spells", "total")
	h:Count("spells", combat and "combat" or "calm")
	h:Count("spells", (combat and "c:" or "o:") .. name)
	if fightCasts then
		fightCasts = fightCasts + 1
	end
end

local function startCast(unit, guid, spell, channel)
	spell = number(spell)
	if unit == "player" and counted(spell, spellName(spell)) then
		castStart, castGUID, castChannel = GetTime(), text(guid), channel
	end
end

local function onCastStart(unit, guid, spell)
	startCast(unit, guid, spell, false)
end

-- A failed attempt during a cast (a key pressed while casting) carries its own GUID and leaves the cast running. A
-- channel can carry no GUID, so only its own stop event ends it.
local function endCast(unit, guid, channel)
	if unit ~= "player" or not castStart or castChannel ~= channel then
		return
	end
	guid = text(guid)
	if castGUID and guid and guid ~= castGUID then
		return
	end
	local seconds = math.floor((GetTime() - castStart) * 10 + 0.5) / 10
	castStart, castGUID, castChannel = nil, nil, nil
	if seconds > 0 then
		h:Count("spells", "castTime", seconds)
	end
end

local function onCastEnd(unit, guid)
	endCast(unit, guid, false)
end

local function isTame(unit, spell)
	return unit == "player" and spell ~= nil and isSpell(spell, TAME_BEAST, spellName(spell))
end

local function onChannelStart(unit, guid, spell)
	startCast(unit, guid, spell, true)
	if isTame(unit, number(spell)) then
		local _, _, _, _, endMs = call(UnitChannelInfo, "player")
		endMs = number(endMs)
		tameEnd = endMs and endMs / 1000
	end
end

-- An interrupted or cancelled Tame Beast channel tames nothing: a pet called after it is never a tame. The player's
-- own cancel carries no interrupter, so a stop well before the channel's end also counts as cancelled.
local function onChannelStop(unit, guid, spell, interruptedBy)
	local by, secret = h:R(interruptedBy)
	if isTame(unit, number(spell)) then
		if by ~= nil or secret or (tameEnd and GetTime() < tameEnd - CUT_SHORT) then
			tamedAt = nil
		end
		tameEnd = nil
	end
	endCast(unit, guid, true)
end

local function place()
	local inside = h:InInstance()
	if inside then
		return text((call(GetInstanceInfo)))
	end
	return text(call(GetRealZoneText))
end

local function onFightEnd(_, fight)
	local casts = fightCasts or 0
	fightCasts = nil
	local seconds = math.floor(fight.stop - fight.start + 0.5)
	h:Count("spells", "combatSec", seconds)
	local level = h:Level()
	local best = level and h:Snap(level, "bestFight")
	if casts > 0 and level and (type(best) ~= "table" or casts > (best.n or 0)) then
		h:Snap(level, "bestFight", { n = casts, sec = seconds, t = time(), place = place() })
	end
end

-- Buffs ----------------------------------------------------------------------

local scanBuffs

local function skipSecret(reason)
	local s = Character.secretAuras
	s.skipped = s.skipped + 1
	s.reason = s.reason or reason
	-- The client sends no UNIT_AURA when the auras become readable again.
	h:Coalesce("buffs", SECRET_RESCAN, scanBuffs)
end

local function fromOther(source)
	source = text(source)
	return source ~= nil
		and source ~= "player"
		and h:R(UnitIsPlayer(source)) == true
		and h:R(UnitIsUnit(source, "player")) ~= true
end

-- The helpful auras of the player, or nil when the client hid them.
local function readAuras()
	local get = api(C_UnitAuras, "GetAuraDataByIndex")
	local list = {}
	for i = 1, 40 do
		local ok, raw = pcall(get, "player", i, "HELPFUL")
		if not ok then
			if tostring(raw):find(SECRET_ERROR, 1, true) then
				return nil, tostring(raw)
			end
			error(raw, 0)
		end
		-- A secret aura in the middle is a half read, never the end of the list.
		local aura, secret = h:R(raw)
		if secret then
			return nil, "secret aura"
		end
		if type(aura) ~= "table" then
			break
		end
		list[#list + 1] = aura
	end
	return list
end

-- The first scan only notes what is on. A half-read scan is dropped whole, so the known buffs stay.
scanBuffs = function()
	if not api(C_UnitAuras, "GetAuraDataByIndex") then
		return
	end
	if h:R(call(api(C_Secrets, "ShouldAurasBeSecret"))) == true then
		return skipSecret("secret auras")
	end
	local list, err = readAuras()
	if not list then
		return skipSecret(err)
	end
	local now, special, specials = {}, {}, {}
	for _, aura in ipairs(list) do
		local name = text(aura.name)
		local key = SPECIAL[number(aura.spellId)]
		if name then
			if auras and not auras[name] then
				h:Count("character", "buffs")
				if fromOther(aura.sourceUnit) then
					h:Count("character", "buffsFromOthers")
				end
				if key then
					h:Count("character", "special:" .. key)
				end
			end
			now[name] = true
		end
		if key and not special[key] then
			special[key] = true
			specials[#specials + 1] = key
		end
	end
	auras = now
	table.sort(specials)
	local level = h:Level()
	if level and (#specials > 0 or h:Snap(level, "buffs")) then
		h:Snap(level, "buffs", table.concat(specials, ","))
	end
end

-- Forms, totems and pets -----------------------------------------------------

-- The first read is the baseline; leaving a form (index 0) counts nothing.
local function checkForm()
	local index = number(call(GetShapeshiftForm))
	if not index then
		return
	end
	local before = shapeshift
	shapeshift = index
	if before == nil or index == before or index == 0 then
		return
	end
	local _, _, _, spell = call(GetShapeshiftFormInfo, index)
	h:Count("character", "form:" .. (spellName(number(spell)) or "form " .. index))
end

local function onTotem(_, slot)
	local have, name = call(GetTotemInfo, number(slot))
	name = text(name)
	if h:R(have) == true and name then
		h:Count("character", "totem:" .. name)
	end
end

-- A pet counts once per family and name, so a summon or a reload counts nothing. A tame writes even for a family and
-- name seen before: two beasts tamed from one family can share a default name.
local function checkPet()
	if h:R(UnitExists("pet")) ~= true then
		return
	end
	local family = text(call(UnitCreatureFamily, "pet")) or text((call(UnitCreatureType, "pet")))
	if not family then
		return
	end
	local name = text(UnitName("pet")) or "?"
	local key = "petn:" .. family .. "|" .. name
	if h:IsFirst("character", key) then
		h:Count("character", key)
		h:Count("character", "pet:" .. family)
	end
	if tamedAt and GetTime() - tamedAt < TAME_WINDOW then
		tamedAt = nil
		h:Count("character", "tames")
		h:Write("pt", family, name, number(UnitLevel("pet")))
	end
end

-- Crafting -------------------------------------------------------------------

local function onTradeShow()
	local info = h:R(call(api(C_TradeSkillUI, "GetBaseProfessionInfo")))
	tradeName = type(info) == "table" and text(info.professionName) or nil
end

local function onLootLine(_, msg)
	msg = text(msg)
	if not msg then
		return
	end
	for _, compiled in ipairs(createForms) do
		local args = ns.Match(compiled, msg)
		if args and args[1] then
			local item = args[1]:match("|h%[(.-)%]|h") or args[1]
			local key = professionKey(tradeName)
			local verb = VERBS[key] or "made"
			h:Count("prof", verb .. "|" .. item .. "|" .. (key or tradeName or "?"), tonumber(args[2]) or 1)
			return
		end
	end
end

-- Statistics pane ------------------------------------------------------------

local function cleanStat(v)
	v = text(v)
	if not v then
		return nil
	end
	v = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	for coin, short in pairs(COINS) do
		v = v:gsub("|T[^|]*UI%-" .. coin .. "Icon[^|]*|t", short)
	end
	v = v:gsub("|T.-|t", ""):gsub("[|;=]", ""):match("^%s*(.-)%s*$")
	if v == "" or v == "--" or v == "0" then
		return nil
	end
	return v
end

-- A ding read keeps the list of the new level; any other read keeps the first list of a level as stats.
local function readStats(ding)
	if not (GetStatisticsCategoryList and GetCategoryNumAchievements and GetAchievementInfo and GetStatistic) then
		return
	end
	local parts = {}
	local cats = h:R(call(GetStatisticsCategoryList))
	for _, cat in ipairs(type(cats) == "table" and cats or {}) do
		cat = number(cat)
		for i = 1, cat and number(call(GetCategoryNumAchievements, cat)) or 0 do
			local id = number((call(GetAchievementInfo, cat, i)))
			local value = id and cleanStat(call(GetStatistic, id))
			if value then
				parts[#parts + 1] = id .. "=" .. value
			end
		end
	end
	local level = h:Level()
	if #parts == 0 or not level then
		return
	end
	local list = table.concat(parts, ";")
	if ding or not h:Snap(level, "stats") then
		h:Snap(level, "stats", list)
	end
	h:Snap(level, "statsNow", list)
end

-- Start ----------------------------------------------------------------------

local function later(delay, where, fn)
	C_Timer.After(delay, function()
		h:Safe(where, fn)
	end)
end

local UNIT_EVENTS = {
	UNIT_SPELLCAST_SENT = onSent,
	UNIT_SPELLCAST_SUCCEEDED = onSucceeded,
	UNIT_SPELLCAST_START = onCastStart,
	UNIT_SPELLCAST_CHANNEL_START = onChannelStart,
	UNIT_SPELLCAST_STOP = onCastEnd,
	UNIT_SPELLCAST_FAILED = onCastEnd,
	UNIT_SPELLCAST_INTERRUPTED = onCastEnd,
	UNIT_SPELLCAST_CHANNEL_STOP = onChannelStop,
	UNIT_AURA = function(unit)
		if unit == "player" then
			h:Coalesce("buffs", 1, scanBuffs)
		end
	end,
	UNIT_PET = function(unit)
		if unit == "player" then
			h:Coalesce("pet", 0.5, checkPet)
		end
	end,
}

local function onEvents()
	-- Other units' events never reach this frame, so a crowded place costs nothing.
	local frame = CreateFrame("Frame")
	-- A client without one of the events refuses it; the error is logged and the other recorders still start.
	for event in pairs(UNIT_EVENTS) do
		h:Safe("register:" .. event, frame.RegisterUnitEvent, frame, event, "player")
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		h:Safe(event, UNIT_EVENTS[event], ...)
	end)
	h:On("SKILL_LINES_CHANGED", function()
		h:Coalesce("skills", 3, checkSkills)
	end)
	h:On("LEARNED_SPELL_IN_SKILL_LINE", function(_, spell)
		spell = number(spell)
		learned(spellName(spell), spell)
	end)
	h:On("NEW_RECIPE_LEARNED", function(_, spell)
		spell = number(spell)
		recipe(spellName(spell), spell)
	end)
	h:On("CHAT_MSG_SYSTEM", onLearnLine)
	h:On("CHAT_MSG_SKILL", onLearnLine)
	for _, event in ipairs({ "TRAIT_NODE_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE" }) do
		h:On(event, function()
			h:Coalesce("talents", 1, checkTalents)
		end)
	end
	for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED" }) do
		h:On(event, function()
			h:Coalesce("bags", 0.2, checkBags)
		end)
	end
	h:On("UPDATE_SHAPESHIFT_FORM", checkForm)
	h:On("PLAYER_TOTEM_UPDATE", onTotem)
	h:On("TRADE_SKILL_SHOW", onTradeShow)
	h:On("TRADE_SKILL_CLOSE", function()
		tradeName = nil
	end)
	h:On("CHAT_MSG_LOOT", onLootLine)
	h:Listen("FIGHT_START", function()
		fightCasts = 0
	end)
	h:Listen("FIGHT_END", onFightEnd)
	h:Listen("LEVEL_UP", function(_, level)
		if type(level) == "number" then
			h:Snap(level, "casts", h:Counts("spells").total or 0)
		end
		later(4, "level stats", function()
			readStats(true)
		end)
		later(6, "level skills", function()
			checkSkills()
			checkTalents()
		end)
	end)
end

function Character.Start(handle)
	h = handle
	learnForms = {}
	for _, f in ipairs({ { "ERR_LEARN_RECIPE_S", true }, { "ERR_LEARN_SPELL_S" }, { "ERR_LEARN_ABILITY_S" } }) do
		local compiled = ns.Compile(_G[f[1]])
		if compiled then
			learnForms[#learnForms + 1] = { compiled = compiled, recipe = f[2] }
		end
	end
	-- The "x<count>" form first: the single form would take the count as part of the item.
	createForms = {}
	for _, name in ipairs({ "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" }) do
		createForms[#createForms + 1] = ns.Compile(_G[name])
	end
	onEvents()
	later(3, "login buffs", scanBuffs)
	later(3, "login pet", checkPet)
	later(3, "login bags", checkBags)
	later(3, "login form", checkForm)
	later(4, "login talents", checkTalents)
	later(8, "login stats", readStats)
	later(10, "login skills", checkSkills)
end
