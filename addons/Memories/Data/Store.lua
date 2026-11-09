local ADDON, ns = ...

local L = ns.L

local Store = {}
ns.Store = Store

local floor = math.floor

local core
local playedBase, playedAt
local warned = {}
-- True when char.first was made in this load: a login before the /played answer cannot date it any more, a reload can.
local firstMadeNow = false

local function firstRecord()
	local char = type(MemoriesCharDB) == "table" and MemoriesCharDB.char
	return type(char) == "table" and type(char.first) == "table" and char.first or nil
end

-- char.first.wait stays in the saved file until an answer dates the first login, so a reload before the answer keeps
-- it. The wall clock dates it across that reload.
function Store.SetPlayed(seconds)
	playedBase, playedAt = seconds, GetTime()
	local first = firstRecord()
	if first and first.wait and core and core:CanWrite() then
		if first.played == nil and type(first.t) == "number" then
			first.played = math.max(0, floor(seconds - (time() - first.t)))
		end
		first.wait = nil
	end
end

-- A login after the one that made char.first adds offline time between first.t and the answer, so it stops the wait.
function Store.EndFirstWait()
	local first = firstRecord()
	if first and not firstMadeNow and core and core:CanWrite() then
		first.wait = nil
	end
end

-- nil until the first /played answer sets the base.
function Store.PlayedNow()
	if not playedBase then
		return nil
	end
	return floor(playedBase + GetTime() - playedAt)
end

local function newer(schema)
	return type(schema) == "number" and schema > ns.SCHEMA
end

function Store.ReadOnlyAll()
	return type(MemoriesDB) == "table" and newer(MemoriesDB.schema)
end

-- Moves every key into a new table, so the saved global keeps its identity and the old data costs no copy.
function Store.MoveOut(data)
	local old = {}
	for k, v in pairs(data) do
		old[k] = v
	end
	for k in pairs(old) do
		data[k] = nil
	end
	return old
end

-- Moves the addon's data into a new record of MemoriesDB.orphans. why is nil for a new character.
function Store.Orphan(addon, guid, name, data, why)
	local orphans = ns.U.TableAt(MemoriesDB, "orphans")
	orphans[#orphans + 1] =
		{ t = time(), guid = guid, name = name, addon = addon, why = why, data = Store.MoveOut(data) }
end

-- Opens one addon's character table as a journal with the schema and new-GUID rules. data is the saved table
-- itself; a new character empties it in place. Returns the journal.
function Store.Open(addon, data)
	local guid = ns.R(UnitGUID("player"))
	local readOnly = Store.ReadOnlyAll()
	local oldGuid
	local char = type(data.char) == "table" and data.char or nil
	-- An orphan keeps the old data whole, so it is moved even when a newer Memories wrote it.
	if not readOnly and guid and char and char.guid and char.guid ~= guid then
		oldGuid = char.guid
		Store.Orphan(addon, oldGuid, char.name, data)
	elseif newer(data.schema) then
		readOnly = true
	end
	if readOnly and not warned[addon] then
		warned[addon] = true
		ns.Print(
			addon == ADDON and L["saved data from a newer version; this addon will not write"]
				or L["%s: saved data from a newer version; this addon will not write"]:format(addon)
		)
	end
	local j = ns.Journal.New(data, { addon = addon, readOnly = readOnly })
	if not readOnly then
		local name, realm = ns.RN(UnitName("player"), GetRealmName())
		-- A rename keeps the GUID, so the name and realm follow the game; a secret value keeps the stored one.
		data.char.guid = data.char.guid or guid
		data.char.name = name or data.char.name
		data.char.realm = realm or data.char.realm
		if oldGuid then
			j:Write("nt", "new character", oldGuid)
		end
	end
	return j
end

local function coreChar(data)
	local char = data.char
	local _, class = UnitClass("player")
	local _, race = UnitRace("player")
	local faction = UnitFactionGroup("player")
	local values = { ns.RN(class, race, UnitSex("player"), faction, UnitLevel("player")) }
	for i, key in ipairs({ "class", "race", "sex", "faction", "level" }) do
		if values[i] ~= nil then
			char[key] = values[i]
		end
	end
	local locale = GetLocale and GetLocale()
	if type(locale) == "string" and locale ~= "" and #locale <= 8 then
		char.locale = locale
	end
	if type(char.first) ~= "table" then
		local m, x, y = ns.OutdoorPosition(ns.InInstance())
		local played = Store.PlayedNow()
		char.first =
			{ t = time(), level = char.level, played = played, m = m, x = x, y = y, wait = played == nil or nil }
		firstMadeNow = true
	end
	ns.U.TableAt(data, "sessions")
	ns.U.TableAt(data, "flags")
	if type(data.trail) ~= "table" then
		data.trail = { v = 1, chunks = {} }
	end
end

-- Kinds already saved stay: a sub-addon can be off on this character while its saved lines still need their kinds.
function Store.SaveKinds()
	if Store.ReadOnlyAll() then
		return
	end
	local kinds = ns.U.TableAt(MemoriesDB, "kinds")
	for kind, text in pairs(ns.Kinds.Describe()) do
		kinds[kind] = text
	end
end

-- Runs on PLAYER_LOGIN before the modules' OnLogin.
function Store.Init()
	if not Store.ReadOnlyAll() then
		MemoriesDB.schema = MemoriesDB.schema or ns.SCHEMA
		Store.SaveKinds()
	end
	Store.Reopen()
end

-- Opens MemoriesCharDB again as the core journal, for example after a backup filled it. JOURNAL_OPENED fires once
-- Store.Core() returns the new journal.
function Store.Reopen()
	core = Store.Open(ADDON, MemoriesCharDB)
	if core:CanWrite() then
		coreChar(MemoriesCharDB)
	end
	ns.Emit("JOURNAL_OPENED", ADDON, core)
	return core
end

function Store.Core()
	return core
end
