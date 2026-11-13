local _, ns = ...

-- The icon of each kind of event on the Journey map: a coin with a gold rim and the glyph of the kind, from
-- Media/MapIcons (64 x 64 TGA). assets/icons holds the pack in every size, with event_names.csv, the source of this
-- table. Media/MapIcons/ATTRIBUTION.txt credits the glyphs.
local MapIcons = {}
ns.MapIcons = MapIcons

local ROOT = "Interface\\AddOns\\Memories\\Media\\MapIcons\\"

MapIcons.FILES = {
	-- Sessions
	["in"] = "login_or_reload",
	["out"] = "logout_or_reload",
	["pl"] = "total_played",
	["gp"] = "unsaved_session_gap",
	["pc"] = "computer_this_session_ran_on",
	["af"] = "away_from_keyboard",
	-- Progress
	["lv"] = "level_up",
	["xp"] = "experience_gained",
	["qt"] = "quest_turned_in",
	["di"] = "discovered_an_area",
	["rs"] = "rested_state",
	-- Deaths
	["de"] = "died",
	["gh"] = "released_spirit",
	["al"] = "alive_again",
	["cc"] = "close_call",
	["lh"] = "low_health_warning",
	["hc"] = "hardcore_death",
	-- Travel
	["zo"] = "entered_a_zone",
	["sz"] = "entered_a_subzone",
	["ld"] = "loading_screen_started",
	["le"] = "loading_screen_ended",
	["tx"] = "took_a_flight",
	["tl"] = "flight_landed",
	["bt"] = "boat_or_zeppelin",
	["hs"] = "hearthstone",
	["so"] = "summon_offered",
	["su"] = "summoned",
	["po"] = "portal_or_teleport",
	["jp"] = "other_teleport",
	["mo"] = "first_mount_up_with_a_mount",
	["ml"] = "learned_a_mount_or_riding",
	-- Dungeons
	["dn"] = "entered_a_dungeon_or_raid",
	["dx"] = "left_a_dungeon_or_raid",
	["bo"] = "boss_fight_ended",
	["wb"] = "world_boss_killed",
	-- Screenshots
	["ss"] = "screenshot_saved",
	-- Other addons
	["sn"] = "screenshot_note_from_another_addon",
	["ex"] = "event_from_another_addon",
	["nt"] = "note_from_memories",
	["un"] = "note_from_memories",
	-- Combat
	["ki"] = "killed_a_creature",
	["ra"] = "killed_a_rare",
	["fi"] = "long_fight",
	-- Gathering
	["ga"] = "gathered",
	["fs"] = "caught_while_fishing",
	["op"] = "opened_a_container_or_chest",
	["pp"] = "picked_a_pocket",
	-- Character
	["sk"] = "skill_changed",
	["lr"] = "learned_a_spell",
	["rc"] = "learned_a_recipe",
	["ta"] = "talent_points",
	["cu"] = "used_a_consumable",
	["pt"] = "tamed_a_beast",
	-- Milestones
	["rp"] = "reputation_changed",
	["qa"] = "quest_accepted",
	["hb"] = "hearthstone_bound",
	["fp"] = "learned_a_flight_path",
	["bk"] = "read_a_book",
	-- Loot
	["lo"] = "loot",
	["rl"] = "group_roll_ended",
	["ge"] = "gear_snapshot",
	["eq"] = "equipped_an_item",
	-- Money
	["mn"] = "money_in_or_out",
	["tb"] = "trainer_purchase",
	["ah"] = "auction_house",
	["ma"] = "mail",
	["tr"] = "traded_with_someone",
	-- Social
	["gj"] = "joined_a_group",
	["gl"] = "left_a_group",
	["gu"] = "own_guild_changed",
	-- PvP
	["ep"] = "enemy_player_met",
	["pk"] = "pvp_kill_or_death",
	["hk"] = "honor_gained",
	["du"] = "duel",
	["bg"] = "battleground_ended",
	["rk"] = "pvp_rank_changed",
}

-- The texture path of the icon of a kind, or nil for a kind with no icon.
function MapIcons.Get(kind)
	local file = MapIcons.FILES[kind]
	return file and ROOT .. file or nil
end
