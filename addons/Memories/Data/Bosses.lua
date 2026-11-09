local _, ns = ...

local Bosses = {}
ns.Bosses = Bosses

-- The last boss of each dungeon and raid by DungeonEncounterID, which does not change with the client language. The
-- IDs come from the Classic Era DungeonEncounter table (wago.tools, build 1.15.9.70576). A boss with several IDs has
-- one for each difficulty or season variant of the same instance.
local LAST_ID = {
	[2767] = "Blackfathom Deeps",
	[2891] = "Blackfathom Deeps",
	[2910] = "Blackfathom Deeps",
	[2785] = "Razorfen Downs",
	[554] = "Uldaman",
	[2755] = "Shadowfang Keep",
	[484] = "Stratholme",
	[478] = "Stratholme",
	[2760] = "Stormwind Stockade",
	[2735] = "Ragefire Chasm",
	[2778] = "Razorfen Kraul",
	[600] = "Zul'Farrak",
	[2801] = "Scholomance",
	[2747] = "Deadmines",
	[2790] = "Blackrock Depths",
	[3069] = "Upper Blackrock Spire",
	[275] = "Lower Blackrock Spire",
	[450] = "Scarlet Monastery",
	[448] = "Scarlet Monastery",
	[447] = "Scarlet Monastery",
	[2779] = "Scarlet Monastery",
	[368] = "Dire Maul",
	[361] = "Dire Maul",
	[346] = "Dire Maul",
	[2772] = "Gnomeregan",
	[2940] = "Gnomeregan",
	[592] = "Wailing Caverns",
	[429] = "Maraudon",
	[493] = "Sunken Temple",
	[2959] = "Sunken Temple",
	[1084] = "Onyxia's Lair",
	[672] = "Molten Core",
	[617] = "Blackwing Lair",
	[793] = "Zul'Gurub",
	[723] = "Ruins of Ahn'Qiraj",
	[717] = "Ahn'Qiraj Temple",
	[1114] = "Naxxramas",
}

-- Encounters that share the English name of a last boss but are not one: Balnazzar opens the Season of Discovery
-- Scarlet Enclave raid (map 2856) and is not the last boss of Stratholme.
local NOT_LAST_ID = {
	[3185] = true,
}

-- The same bosses by the English name that ENCOUNTER_END reports. A boss with an ID above is found by the ID on any
-- client language and by this name on an English client. The name table also holds the bosses with no public ID: the
-- WoW Forever custom bosses (Blazeroar, Durgen Dirgehammer, Lyn the Ignored, Shade of the Archmage, Nanaya,
-- Rath'mael, Sonya Darkhallow, The Wild King, Relic Guardian) and Scarlet Commander Mograine. Their clears count on an
-- English client only.
local LAST = {
	["Aku'mai"] = "Blackfathom Deeps",
	["Amnennar the Coldbringer"] = "Razorfen Downs",
	["Archaedas"] = "Uldaman",
	["Archmage Arugal"] = "Shadowfang Keep",
	["Baron Rivendare"] = "Stratholme",
	["Balnazzar"] = "Stratholme",
	["Bazil Thredd"] = "Stormwind Stockade",
	["Bazzalan"] = "Ragefire Chasm",
	["Blazeroar"] = "Alcaz Prison",
	["Charlga Razorflank"] = "Razorfen Kraul",
	["Chief Ukorz Sandscalp"] = "Zul'Farrak",
	["Darkmaster Gandling"] = "Scholomance",
	["Durgen Dirgehammer"] = "Hall of Thanes",
	["Edwin VanCleef"] = "Deadmines",
	["Emperor Dagran Thaurissan"] = "Blackrock Depths",
	["General Drakkisath"] = "Upper Blackrock Spire",
	["Overlord Wyrmthalak"] = "Lower Blackrock Spire",
	["High Inquisitor Whitemane"] = "Scarlet Monastery",
	["Scarlet Commander Mograine"] = "Scarlet Monastery",
	["Herod"] = "Scarlet Monastery",
	["Arcanist Doan"] = "Scarlet Monastery",
	["Bloodmage Thalnos"] = "Scarlet Monastery",
	["King Gordok"] = "Dire Maul",
	["Prince Tortheldrin"] = "Dire Maul",
	["Alzzin the Wildshaper"] = "Dire Maul",
	["Lyn the Ignored"] = "City of Dalaran",
	["Shade of the Archmage"] = "City of Dalaran",
	["Mekgineer Thermaplugg"] = "Gnomeregan",
	["Mutanus the Devourer"] = "Wailing Caverns",
	["Nanaya"] = "Shaper's Terrace",
	["Princess Theradras"] = "Maraudon",
	["Rath'mael"] = "Ruins of Lordaeron",
	["Shade of Eranikus"] = "Sunken Temple",
	["Sonya Darkhallow"] = "Barrow Deeps",
	["The Wild King"] = "Hyjal Summit",
	["Relic Guardian"] = "Excavation Site: Wetlands",
	["Onyxia"] = "Onyxia's Lair",
	["Ragnaros"] = "Molten Core",
	["Nefarian"] = "Blackwing Lair",
	["Hakkar"] = "Zul'Gurub",
	["Ossirian the Unscarred"] = "Ruins of Ahn'Qiraj",
	["C'thun"] = "Ahn'Qiraj Temple",
	["Kel'Thuzad"] = "Naxxramas",
}

-- "The Deadmines" and "Deadmines: Mast Room" both name the place "deadmines".
function Bosses.Normalize(place)
	local s = place:lower():gsub(":.*$", "")
	s = s:match("^%s*(.-)%s*$")
	return (s:gsub("^the ", ""))
end

local places = {}
for _, place in pairs(LAST) do
	places[Bosses.Normalize(place)] = true
end

-- The place of a last boss, else nil. The encounter ID wins over the name.
function Bosses.Place(id, name)
	if type(id) == "number" then
		if LAST_ID[id] then
			return LAST_ID[id]
		end
		if NOT_LAST_ID[id] then
			return nil
		end
	end
	return type(name) == "string" and LAST[name] or nil
end

function Bosses.AllIds()
	return ns.U.Copy(LAST_ID)
end

function Bosses.All()
	return ns.U.Copy(LAST)
end

-- True when the list has a last boss for this instance name.
function Bosses.KnownPlace(place)
	return type(place) == "string" and places[Bosses.Normalize(place)] == true
end
