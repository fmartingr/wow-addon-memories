local _, ns = ...

local Bosses = {}
ns.Bosses = Bosses

-- The last boss of each dungeon and raid, by the English name that ENCOUNTER_END reports, with its place.
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
	["C'Thun"] = "Ahn'Qiraj Temple",
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

-- The place of a last boss, else nil.
function Bosses.Place(name)
	return type(name) == "string" and LAST[name] or nil
end

function Bosses.All()
	return ns.U.Copy(LAST)
end

-- True when the list has a last boss for this instance name.
function Bosses.KnownPlace(place)
	return type(place) == "string" and places[Bosses.Normalize(place)] == true
end
