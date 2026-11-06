std = "lua51"
max_line_length = 120
codes = true
exclude_files = { ".lua/", ".luarocks/", "build/" }
ignore = { "212/self", "211/_.*", "212/_.*" }

globals = {
	"Memories",
	"MemoriesDB",
	"MemoriesCharDB",
	"Memories_OnAddonCompartmentClick",
	"SLASH_MEMORIES1",
	"SLASH_MEMORIES2",
	"SlashCmdList",
}

read_globals = {
	"C_AddOns",
	"C_Map",
	"C_Spell",
	"C_Timer",
	"ChatFontNormal",
	"CreateFrame",
	"DEFAULT_CHAT_FRAME",
	"GetRealmName",
	"GetTime",
	"InCombatLockdown",
	"IsInInstance",
	"UIParent",
	"UISpecialFrames",
	"UnitCanAttack",
	"UnitClass",
	"UnitFactionGroup",
	"UnitExists",
	"UnitGUID",
	"UnitLevel",
	"UnitName",
	"UnitRace",
	"UnitSex",
	"date",
	"debugprofilestop",
	"debugstack",
	"geterrorhandler",
	"hooksecurefunc",
	"issecretvalue",
	"time",
}

files["spec/"] = {
	std = "+busted",
	globals = { "_G", "print", "MemoriesTestCharDB", "MemoriesOtherCharDB", "MemoriesCombatCharDB", "SomeBlizzardFunc" },
}
