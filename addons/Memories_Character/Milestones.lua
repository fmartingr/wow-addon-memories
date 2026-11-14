local ADDON, ns = ...
local L = ns.L

-- Character.lua stopped at its missing-core guard.
if not ns.Character then
	return
end

local Milestones = {}
ns.Milestones = Milestones

local call, api, text, number = ns.Call, ns.Api, ns.Text, ns.Number

local PATH_DEDUPE = 10
local MAP_WINDOW = 6
local QUEST_RETRY = 2

local h
local homeForm
-- The last value written per faction id, for this session only: after a reload the first change always writes.
local reputation = {}
-- The flight map's current node { node, at }, the GetTime() of the last new path message and the path that waits for
-- the flight map { at }.
local taxi, pathAt, pending

local function label(standing)
	local token = "FACTION_STANDING_LABEL" .. standing
	return text(call(GetText, token, (h:R(UnitSex("player"))))) or text(_G[token])
end

-- The event's value is the reputation value (Friendly starts at 3000), not the standing.
local function onFaction(_, id, value)
	id = number(id)
	local data = id and h:R(call(api(C_Reputation, "GetFactionDataByID"), id))
	local name = type(data) == "table" and text(data.name)
	if not name then
		return
	end
	value = number(value) or number(data.currentStanding)
	if not value or reputation[id] == value then
		return
	end
	reputation[id] = value
	local standing = number(data.reaction)
	h:Write("rp", name, value, standing, standing and label(standing))
end

local function questTitle(id)
	return text(call(api(C_QuestLog, "GetTitleForQuestID"), id))
end

-- The quest id is the last value: Forever gives (questId), older clients (questLogIndex, questId).
local function onQuest(_, ...)
	local n = select("#", ...)
	local id = n > 0 and number((select(n, ...)))
	if not id then
		return
	end
	local at = h:Here()
	h:Count("milestones", "questsAccepted")
	local title = questTitle(id)
	if title then
		h:WriteAt(at, "qa", id, title)
		return
	end
	C_Timer.After(QUEST_RETRY, function()
		h:Safe("quest", function()
			h:WriteAt(at, "qa", id, questTitle(id))
		end)
	end)
end

-- The saved last home also drops the second report of one bind: the chat line and HEARTHSTONE_BOUND.
local function home(name)
	name = text(name)
	local state = h:State("milestones")
	if not name or state.home == name then
		return
	end
	state.home = name
	h:Write("hb", name)
end

local function writePath(at, node)
	h:Count("milestones", "flightPaths")
	h:WriteAt(at, "fp", node or "?")
end

local function currentNode()
	for i = 1, number(call(NumTaxiNodes)) or 0 do
		if h:R(call(TaxiNodeGetType, i)) == "CURRENT" then
			return text(call(TaxiNodeName, i))
		end
	end
end

local function onTaxiMap()
	local node = currentNode()
	taxi = { node = node, at = GetTime() }
	if pending and node then
		local at = pending.at
		pending = nil
		writePath(at, node)
	end
end

-- The node comes from the flight map opened up to MAP_WINDOW before or after the message, else from the zone.
local function newPath()
	local now = GetTime()
	if pathAt and now - pathAt < PATH_DEDUPE then
		return
	end
	pathAt = now
	local at = h:Here()
	if taxi and taxi.node and now - taxi.at <= MAP_WINDOW then
		writePath(at, taxi.node)
		return
	end
	local wait = { at = at }
	pending = wait
	C_Timer.After(MAP_WINDOW, function()
		if pending ~= wait then
			return
		end
		pending = nil
		h:Safe("flight path", function()
			writePath(at, text(call(GetSubZoneText)) or text(call(GetZoneText)))
		end)
	end)
end

local function isNewPath(msg)
	return msg ~= nil and msg == text(ERR_NEWTAXIPATH)
end

local function onSystem(_, msg)
	msg = text(msg)
	if not msg then
		return
	end
	if isNewPath(msg) then
		newPath()
		return
	end
	local args = ns.Match(homeForm, msg)
	if args then
		home(args[1])
	end
end

-- Every read counts; only the first read of a title writes a line.
local function onBook()
	local title = text(call(ItemTextGetItem))
	if not title then
		return
	end
	h:Count("milestones", "booksRead")
	local books = h:State("books")
	if not books[title] then
		books[title] = true
		h:Write("bk", title)
	end
end

function Milestones.Start(handle)
	h = handle
	homeForm = ns.Compile(ERR_DEATHBIND_SUCCESS_S)
	h:On("FACTION_STANDING_CHANGED", onFaction)
	h:On("QUEST_ACCEPTED", onQuest)
	h:On("HEARTHSTONE_BOUND", function()
		home(call(GetBindLocation))
	end)
	h:On("CHAT_MSG_SYSTEM", onSystem)
	h:On("UI_INFO_MESSAGE", function(_, _, msg)
		if isNewPath(text(msg)) then
			newPath()
		end
	end)
	h:On("TAXIMAP_OPENED", onTaxiMap)
	h:On("ITEM_TEXT_BEGIN", onBook)
end

-- A registration after login calls OnLogin before RegisterModule returns, so the handle comes from the argument.
local function onLogin(handle)
	ns.h = handle
	ns.Character.Start(handle)
	Milestones.Start(handle)
end

Memories.RegisterModule({
	addon = ADDON,
	api = 1,
	saved = "MemoriesCharacterCharDB",
	kinds = {
		{ kind = "sk", group = "Character", name = L.SKILL_CHANGED, fields = { "name", "#rank", "#max" } },
		{ kind = "lr", group = "Character", name = L.LEARNED_SPELL, fields = { "name", "#spell" } },
		{ kind = "rc", group = "Character", name = L.LEARNED_RECIPE, fields = { "name", "#spell" } },
		{ kind = "ta", group = "Character", name = L.TALENT_POINTS, fields = { "#spent", "#unspent" } },
		{
			kind = "cu",
			group = "Character",
			name = L.USED_CONSUMABLE,
			fields = { "#item", "kind", "name", "combat" },
		},
		{ kind = "pt", group = "Character", name = L.TAMED_BEAST, fields = { "family", "name", "#level" } },
		{
			kind = "rp",
			group = "Milestones",
			name = L.REPUTATION_CHANGED,
			fields = { "faction", "#value", "#standing", "label" },
		},
		{ kind = "qa", group = "Milestones", name = L.QUEST_ACCEPTED, fields = { "#quest", "title" } },
		{ kind = "hb", group = "Milestones", name = L.HEARTHSTONE_BOUND, fields = { "home" } },
		{ kind = "fp", group = "Milestones", name = L.LEARNED_FLIGHT_PATH, fields = { "node" } },
		{ kind = "bk", group = "Milestones", name = L.READ_BOOK, fields = { "title" } },
	},
	newOnly = { { key = "consumables", label = L.CONSUMABLES_NEW_FINDINGS_ONLY, kinds = { "cu" } } },
	OnLogin = onLogin,
})
