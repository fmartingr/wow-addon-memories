-- Memories event-kind icon mapping (named TGA textures for WoW map)
-- Install tga64/*.tga to Interface/AddOns/Memories/Media/MapIcons/
local root = "Interface\\AddOns\\Memories\\Media\\MapIcons\\"
local EVENT_ICONS = {
  -- Sessions
  ["in"] = root .. "login_or_reload", -- Login or reload
  ["out"] = root .. "logout_or_reload", -- Logout or reload
  ["pl"] = root .. "total_played", -- Total /played
  ["gp"] = root .. "unsaved_session_gap", -- Unsaved session gap
  ["pc"] = root .. "computer_this_session_ran_on", -- Computer this session ran on
  ["af"] = root .. "away_from_keyboard", -- Away from keyboard
  -- Progress
  ["lv"] = root .. "level_up", -- Level up
  ["xp"] = root .. "experience_gained", -- Experience gained
  ["qt"] = root .. "quest_turned_in", -- Quest turned in
  ["di"] = root .. "discovered_an_area", -- Discovered an area
  ["rs"] = root .. "rested_state", -- Rested state
  -- Deaths
  ["de"] = root .. "died", -- Died
  ["gh"] = root .. "released_spirit", -- Released spirit
  ["al"] = root .. "alive_again", -- Alive again
  ["cc"] = root .. "close_call", -- Close call
  ["lh"] = root .. "low_health_warning", -- Low-health warning
  ["hc"] = root .. "hardcore_death", -- Hardcore death
  -- Travel
  ["zo"] = root .. "entered_a_zone", -- Entered a zone
  ["sz"] = root .. "entered_a_subzone", -- Entered a subzone
  ["ld"] = root .. "loading_screen_started", -- Loading screen started
  ["le"] = root .. "loading_screen_ended", -- Loading screen ended
  ["tx"] = root .. "took_a_flight", -- Took a flight
  ["tl"] = root .. "flight_landed", -- Flight landed
  ["bt"] = root .. "boat_or_zeppelin", -- Boat or zeppelin
  ["hs"] = root .. "hearthstone", -- Hearthstone
  ["so"] = root .. "summon_offered", -- Summon offered
  ["su"] = root .. "summoned", -- Summoned
  ["po"] = root .. "portal_or_teleport", -- Portal or teleport
  ["jp"] = root .. "other_teleport", -- Other teleport
  ["mo"] = root .. "first_mount_up_with_a_mount", -- First mount-up with a mount
  ["ml"] = root .. "learned_a_mount_or_riding", -- Learned a mount or riding
  -- Dungeons
  ["dn"] = root .. "entered_a_dungeon_or_raid", -- Entered a dungeon or raid
  ["dx"] = root .. "left_a_dungeon_or_raid", -- Left a dungeon or raid
  ["bo"] = root .. "boss_fight_ended", -- Boss fight ended
  ["wb"] = root .. "world_boss_killed", -- World boss killed
  -- Screenshots
  ["ss"] = root .. "screenshot_saved", -- Screenshot saved
  -- Other addons
  ["sn"] = root .. "screenshot_note_from_another_addon", -- Screenshot note from another addon
  ["ex"] = root .. "event_from_another_addon", -- Event from another addon
  ["nt"] = root .. "note_from_memories", -- Note from Memories
  -- Combat
  ["ki"] = root .. "killed_a_creature", -- Killed a creature
  ["ra"] = root .. "killed_a_rare", -- Killed a rare
  ["fi"] = root .. "long_fight", -- Long fight
  -- Gathering
  ["ga"] = root .. "gathered", -- Gathered
  ["fs"] = root .. "caught_while_fishing", -- Caught while fishing
  ["op"] = root .. "opened_a_container_or_chest", -- Opened a container or chest
  ["pp"] = root .. "picked_a_pocket", -- Picked a pocket
  -- Character
  ["sk"] = root .. "skill_changed", -- Skill changed
  ["lr"] = root .. "learned_a_spell", -- Learned a spell
  ["rc"] = root .. "learned_a_recipe", -- Learned a recipe
  ["ta"] = root .. "talent_points", -- Talent points
  ["cu"] = root .. "used_a_consumable", -- Used a consumable
  ["pt"] = root .. "tamed_a_beast", -- Tamed a beast
  -- Milestones
  ["rp"] = root .. "reputation_changed", -- Reputation changed
  ["qa"] = root .. "quest_accepted", -- Quest accepted
  ["hb"] = root .. "hearthstone_bound", -- Hearthstone bound
  ["fp"] = root .. "learned_a_flight_path", -- Learned a flight path
  ["bk"] = root .. "read_a_book", -- Read a book
  -- Loot
  ["lo"] = root .. "loot", -- Loot
  ["rl"] = root .. "group_roll_ended", -- Group roll ended
  ["ge"] = root .. "gear_snapshot", -- Gear snapshot
  ["eq"] = root .. "equipped_an_item", -- Equipped an item
  -- Money
  ["mn"] = root .. "money_in_or_out", -- Money in or out
  ["tb"] = root .. "trainer_purchase", -- Trainer purchase
  ["ah"] = root .. "auction_house", -- Auction house
  ["ma"] = root .. "mail", -- Mail
  ["tr"] = root .. "traded_with_someone", -- Traded with someone
  -- Social
  ["gj"] = root .. "joined_a_group", -- Joined a group
  ["gl"] = root .. "left_a_group", -- Left a group
  ["gu"] = root .. "own_guild_changed", -- Own guild changed
  -- PvP
  ["ep"] = root .. "enemy_player_met", -- Enemy player met
  ["pk"] = root .. "pvp_kill_or_death", -- PvP kill or death
  ["hk"] = root .. "honor_gained", -- Honor gained
  ["du"] = root .. "duel", -- Duel
  ["bg"] = root .. "battleground_ended", -- Battleground ended
  ["rk"] = root .. "pvp_rank_changed", -- PvP rank changed
}
return EVENT_ICONS
