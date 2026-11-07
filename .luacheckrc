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
	"StaticPopupDialogs",
}

read_globals = {
	"C_AddOns",
	"C_EncodingUtil",
	"C_Map",
	"C_Spell",
	"C_Timer",
	"C_UI",
	"ChatFontNormal",
	"CreateFrame",
	"DEFAULT_CHAT_FRAME",
	"Enum",
	"GameTooltip",
	"GetCursorPosition",
	"GetRealmName",
	"GetTime",
	"InCombatLockdown",
	"IsInInstance",
	"Minimap",
	"StaticPopup_Show",
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
	globals = { "_G", "print", "C_EncodingUtil", "Enum", "MemoriesMinimapButton", "MemoriesTestCharDB", "MemoriesOtherCharDB", "MemoriesCombatCharDB", "SomeBlizzardFunc" },
}
