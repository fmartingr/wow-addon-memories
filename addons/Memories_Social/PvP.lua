local ADDON, ns = ...
local L = ns.L

-- Social.lua stopped at its missing-core guard.
if not ns.Social then
	return
end

local PvP = {}
ns.PvP = PvP

local Social = ns.Social
local call, api, text, number, flag = ns.Call, ns.Api, ns.Text, ns.Number, ns.Flag
local floor = math.floor

local MET_AGAIN = 30 * 60
local SCAN_EVERY = 0.5
local SCAN_AFTER = 5
local FOUGHT = 30
local WIN_GUARD = 60
local FALLBACK_FOUGHT = 15
local FALLBACK_WAIT = 6
local LOSS_GUARD = 15
local RELEASE_GUARD = 30
local KILLS_DELAY = 1
local RANK_DELAY = 2
local LOGIN_RANK = 5
local WORLD_DELAY = 2
local DUEL_CLEAR = 2
local PLATES = 40
local RANK_FACTION = 2800
local HONOR_CURRENCY = 1901
local OLD_HONOR_CURRENCY = 1792
local RANK_BASE = 5
local ALLIANCE = 1
local CLASSES = {
	WARRIOR = true,
	PALADIN = true,
	HUNTER = true,
	ROGUE = true,
	PRIEST = true,
	SHAMAN = true,
	MAGE = true,
	WARLOCK = true,
	DRUID = true,
}

local h
-- Enemies of this session by full name: { rec, targeted, fought, metAt, metGuild } with GetTime() values; rec is the
-- latest record of Social's memory, kept here because the memory can be full.
local enemies = {}
local seenEnemy = false
local wonAt = {}
local ticker, scanUntil
-- GetTime() of the last judged death line, of the last pk lost, of the last fallback pk lost and of the last
-- PLAYER_DEAD that started a fallback.
local judgedAt, lostAt, fallbackAt, deadAt
-- Names of the players of this scan run that are not enemies, so one over Social's memory cap is not read again on
-- every tick.
local strangers = {}
-- The duel request you received: { name, death }.
local duel
-- The battleground of now: { name, start, honor, kills, over, won, score }; won stays nil after a draw.
local tally
local queued = {}
local baseline
local honorForms, knockout, retreat

local function inBattleground()
	local _, itype = h:InInstance()
	return itype == "pvp"
end

local function inGroupInstance()
	local inside, itype = h:InInstance()
	return inside and (itype == "party" or itype == "raid")
end

local function enemy(rec)
	local e = enemies[rec.name]
	if not e then
		e = {}
		enemies[rec.name] = e
	end
	e.rec = rec
	return e
end

-- A tracked enemy by name, else Social's record; enemies also holds the enemies over the memory cap.
local function findEnemy(name)
	local e = name and enemies[name]
	return e and e.rec or Social.Find(name)
end

-- 1 for Alliance and 0 for Horde, as battleground winners and rank tokens count sides.
local function side()
	return text(UnitFactionGroup("player")) == "Alliance" and ALLIANCE or 0
end

-- Fights ---------------------------------------------------------------------

local function won(rec)
	local now = GetTime()
	if wonAt[rec.name] and now - wonAt[rec.name] < WIN_GUARD then
		return
	end
	wonAt[rec.name] = now
	h:Count("pvp", "won")
	if inBattleground() then
		h:Count("pvp", "bgWon")
	end
	h:Write("pk", "won", rec.name, rec.class, rec.level, rec.guild)
end

local function lost(name, class, level, guild)
	lostAt = GetTime()
	h:Count("pvp", "lost")
	if inBattleground() then
		h:Count("pvp", "bgLost")
	end
	h:Write("pk", "lost", name or "?", class, level, guild)
end

local function inCombat()
	return h:InFight() or h:R(InCombatLockdown()) == true
end

local function scanUnit(unit, now)
	if not Social.IsOther(unit) then
		return
	end
	local name = Social.FullName(unit)
	-- enemies also holds the enemies over the memory cap, so they are not read again on every tick. It comes before
	-- strangers, so a player first read with an unknown faction is scanned once a later read shows an enemy.
	local tracked = name and enemies[name]
	if not name or (not tracked and strangers[name]) then
		return
	end
	local rec = tracked and tracked.rec or Social.Find(name, true) or Social.Read(unit, "scan")
	if not rec or not rec.enemy then
		strangers[name] = true
		return
	end
	local e = enemy(rec)
	if flag(UnitIsDeadOrGhost, unit) then
		if e.fought and now - e.fought <= FOUGHT then
			e.fought = nil
			won(rec)
		end
	elseif flag(UnitIsUnit, unit, "target") or flag(UnitIsUnit, unit .. "target", "player") then
		e.fought = now
	end
end

local function scan()
	local now = GetTime()
	scanUnit("target", now)
	if not inGroupInstance() then
		for i = 1, PLATES do
			scanUnit("nameplate" .. i, now)
		end
	end
end

-- The stop check stays outside the scan, so an error in a scan never keeps the ticker running.
local function startScan()
	if ticker or not seenEnemy then
		return
	end
	strangers = {}
	ticker = C_Timer.NewTicker(SCAN_EVERY, function()
		h:Safe("scan", scan)
		if not inCombat() and GetTime() >= (scanUntil or 0) then
			ticker:Cancel()
			ticker = nil
		end
	end)
end

-- Enemies ----------------------------------------------------------------------

local function met(rec, e)
	e.metAt, e.metGuild = GetTime(), rec.guild
	h:Count("pvp", "met")
	h:Write("ep", rec.name, rec.class, rec.race, rec.level, rec.guild)
end

local function onUnit(unit, source)
	if inGroupInstance() then
		return
	end
	local rec = Social.Read(unit, source)
	if not rec or not rec.enemy then
		return
	end
	local now = GetTime()
	local e = enemy(rec)
	if not seenEnemy then
		seenEnemy = true
		if inCombat() then
			startScan()
		end
	end
	if source == "target" then
		e.targeted = now
		if flag(UnitAffectingCombat, "player") then
			e.fought = now
		end
		if not e.metAt or now - e.metAt > MET_AGAIN then
			met(rec, e)
			return
		end
	end
	-- The met guild, not Social's memory, tells a late guild, so an enemy over the memory cap gets one too.
	if e.metAt and e.metGuild == nil and rec.guild ~= nil then
		met(rec, e)
	end
end

-- Honor ------------------------------------------------------------------------

-- Returns the honor, the victim and the rank name of an honor line, or nil.
local function parseHonor(msg)
	for _, form in ipairs(honorForms) do
		local args = ns.Match(form.compiled, msg)
		local honor = args and ns.Whole(args[form.honor])
		if honor then
			return honor, form.victim and args[form.victim], form.rank and args[form.rank]
		end
	end
end

-- The record of the enemy fought or targeted last, within the window.
local function recentEnemy(window, foughtOnly)
	local now, best, bestAt = GetTime(), nil, nil
	for _, e in pairs(enemies) do
		local at = e.fought
		if not foughtOnly and e.targeted and (not at or e.targeted > at) then
			at = e.targeted
		end
		if at and now - at <= window and (not bestAt or at > bestAt) then
			best, bestAt = e.rec, at
		end
	end
	return best
end

local function onHonor(_, msg)
	local honor, victim, rank = parseHonor(text(msg))
	if not honor then
		return
	end
	h:Count("pvp", "honor", honor)
	if inBattleground() then
		h:Count("pvp", "honorBg", honor)
		if tally then
			tally.honor = tally.honor + honor
		end
		return
	end
	h:Count("pvp", "honorWorld", honor)
	victim = Social.NameFromText(victim)
	local rec
	if victim then
		rec = findEnemy(victim)
	else
		rec = recentEnemy(FOUGHT)
		victim = rec and rec.name
	end
	h:Write("hk", honor, victim, text(rank))
	if rec and rec.enemy then
		won(rec)
	end
end

local function lifetimeKills()
	return number((call(GetPVPLifetimeStats)))
end

local function readKills()
	local kills = lifetimeKills()
	if not kills then
		return
	end
	local gained = baseline and kills - baseline or 0
	baseline = kills
	if gained <= 0 then
		return
	end
	h:Count("pvp", "hk", gained)
	if inBattleground() then
		h:Count("pvp", "hkBg", gained)
		if tally then
			tally.kills = tally.kills + gained
		end
	else
		h:Count("pvp", "hkWorld", gained)
	end
end

-- Deaths -----------------------------------------------------------------------

-- A death line with no creature id is a player kill when the killer is a known enemy, has a class token or the
-- core saw a player's GUID.
local function onDied(_, info)
	judgedAt = GetTime()
	if type(info) ~= "table" or info.npc then
		return
	end
	local killer = text(info.killer)
	local rec = killer and killer ~= "?" and findEnemy(killer) or nil
	local known = rec and rec.enemy
	if not (known or CLASSES[info.kclass] or info.byPlayer == true) then
		return
	end
	if fallbackAt and judgedAt - fallbackAt < LOSS_GUARD then
		return
	end
	if known then
		lost(rec.name, rec.class or text(info.kclass), rec.level or number(info.klevel), rec.guild)
	else
		lost(killer, text(info.kclass), number(info.klevel))
	end
end

local function onDead()
	local now = GetTime()
	-- The game fires PLAYER_DEAD again at the spirit release.
	if (judgedAt and now - judgedAt < RELEASE_GUARD) or (lostAt and now - lostAt < RELEASE_GUARD) then
		return
	end
	deadAt = now
	local rec = recentEnemy(FALLBACK_FOUGHT, true)
	if not rec then
		return
	end
	C_Timer.After(FALLBACK_WAIT, function()
		h:Safe("fallback loss", function()
			if (judgedAt and judgedAt >= now) or (lostAt and lostAt >= now) or deadAt ~= now then
				return
			end
			lost(rec.name, rec.class, rec.level, rec.guild)
			fallbackAt = lostAt
		end)
	end)
end

-- Duels ------------------------------------------------------------------------

local function isMe(name, me)
	return name == me or name:sub(1, #me + 1) == me .. " "
end

local function onDuelLine(_, msg)
	msg = text(msg)
	local me = text(UnitName("player"))
	if not msg or not me then
		return
	end
	local fled = false
	local args = ns.Match(knockout, msg)
	if not args then
		args, fled = ns.Match(retreat, msg), true
	end
	if not args or not args[1] or not args[2] then
		return
	end
	local winner, loser = Social.NameFromText(args[1]), Social.NameFromText(args[2])
	local result, opponent
	if winner and isMe(winner, me) then
		result, opponent = "won", loser
	elseif loser and isMe(loser, me) then
		result, opponent = fled and "fled" or "lost", winner
	else
		return
	end
	local death = duel ~= nil and duel.death and duel.name == opponent
	duel = nil
	local rec = opponent and Social.Find(opponent)
	local class = rec and rec.class
	h:Count("pvp", "duel_" .. result)
	if class then
		h:Count("pvp", "duel_" .. result .. ":" .. class)
	end
	if death then
		h:Count("pvp", "duelDeath")
	end
	h:Write("du", result, opponent or "?", class)
end

local function onDuelRequest(death)
	return function(_, name)
		duel = { name = Social.NameFromText(name), death = death }
	end
end

-- A declined or cancelled request ends with no result line, so the request is dropped a moment after the duel ends,
-- whichever of the end event and the result line comes first.
local function onDuelFinished()
	local pending = duel
	C_Timer.After(DUEL_CLEAR, function()
		if duel == pending then
			duel = nil
		end
	end)
end

-- Battlegrounds ----------------------------------------------------------------

local function scoreOf()
	local fn = api(C_PvP, "GetScoreInfoByPlayerGuid")
	local guid = text(UnitGUID("player"))
	if not fn or not guid then
		return nil
	end
	local ok, info = pcall(fn, guid)
	if not ok then
		ns.Log("score", info)
		return nil
	end
	info = h:R(info)
	if type(info) == "table" then
		return {
			kills = number(info.honorableKills),
			kb = number(info.killingBlows),
			deaths = number(info.deaths),
			honor = number(info.honorGained),
		}
	end
end

local function matchWinner(winner)
	winner = number(winner) or number(call(GetBattlefieldWinner))
	if winner then
		return winner
	end
	-- The active match winner means nothing before the match is over.
	if h:R(call(api(C_PvP, "IsMatchComplete"))) == true then
		return number(call(api(C_PvP, "GetActiveMatchWinner")))
	end
end

-- The winner is decided once; the score keeps updating, since the final scoreboard can arrive after the winner.
local function onWinner(_, winner)
	if not tally then
		return
	end
	if not tally.over then
		winner = matchWinner(winner)
		if not winner then
			return
		end
		tally.over = true
		-- Any other winner value is a draw, which counts as no winner.
		if winner == 0 or winner == ALLIANCE then
			tally.won = winner == side()
		end
		call(RequestBattlefieldScoreData)
	end
	tally.score = scoreOf() or tally.score
end

local function raise(key, value)
	local counts = h:Counts("pvp")
	if type(counts[key]) ~= "number" or value > counts[key] then
		counts[key] = value
	end
end

local function endBattleground()
	local t = tally
	tally = nil
	local score = t.score or {}
	local result = t.won == nil and "left" or t.won and "won" or "lost"
	local seconds = floor(GetTime() - t.start + 0.5)
	local kills = score.kills or t.kills
	h:Count("pvp", "bg_" .. result)
	h:Count("pvp", "bgSec", seconds)
	h:Count("pvp", "bgPlayed:" .. t.name)
	if t.won then
		h:Count("pvp", "bgWon:" .. t.name)
	end
	raise("bgBest:" .. t.name, kills)
	raise("bgBest", kills)
	h:Write("bg", t.name, result, seconds, score.honor or t.honor, kills, score.kb, score.deaths)
end

local function checkBattleground()
	if inBattleground() then
		if not tally then
			tally = { name = text(call(GetInstanceInfo)) or "?", start = GetTime(), honor = 0, kills = 0 }
			call(RequestBattlefieldScoreData)
		end
	elseif tally then
		endBattleground()
	end
end

local function checkQueues()
	local n = number(call(GetMaxBattlefieldID)) or 0
	local now = GetTime()
	for i, start in pairs(queued) do
		if i > n or text(call(GetBattlefieldStatus, i)) ~= "queued" then
			h:Count("pvp", "queueSec", floor(now - start + 0.5))
			queued[i] = nil
		end
	end
	for i = 1, n do
		if not queued[i] and text(call(GetBattlefieldStatus, i)) == "queued" then
			queued[i] = now
		end
	end
end

-- Rank -------------------------------------------------------------------------

-- The rank index of rank 1, as GetText tokens and GetPVPLifetimeStats count ranks.
local function rankBase()
	local ranks = type(Enum) == "table" and Enum.PvPRanks
	return type(ranks) == "table" and number(ranks.Rank_1) or RANK_BASE
end

local function rankTitle(rank)
	if rank <= 0 then
		return text(PVP_RANK_0_NAME)
	end
	local token = "PVP_RANK_" .. (rankBase() + rank - 1) .. "_" .. side()
	-- GetText gives the token back for a token it does not know.
	local title = text(call(GetText, token, (h:R(UnitSex("player")))))
	if not title or title == token then
		title = text(_G[token])
	end
	return title
end

local function honorTotal()
	local fn = api(C_CurrencyInfo, "GetCurrencyInfo")
	local consts = type(Constants) == "table" and Constants.CurrencyConsts
	local id = type(consts) == "table" and number(consts.CLASSIC_HONOR_CURRENCY_ID) or HONOR_CURRENCY
	for _, currency in ipairs({ id, OLD_HONOR_CURRENCY }) do
		local info = h:R(call(fn, currency))
		local quantity = type(info) == "table" and number(info.quantity)
		if quantity then
			return quantity
		end
	end
end

local function readRank()
	local data = h:R(call(api(C_MajorFactions, "GetMajorFactionProgressionInfo"), RANK_FACTION))
	local rank = type(data) == "table" and number(data.renownLevel)
	if not rank then
		return
	end
	local kills, maxRank = call(GetPVPLifetimeStats)
	maxRank = number(maxRank)
	local base = rankBase()
	local highest = maxRank and (maxRank >= base and maxRank - base + 1 or 0)
	local title = rankTitle(rank)
	local level = h:Level()
	if level then
		h:Snap(level, "pvp", {
			rank = rank,
			title = title,
			points = number(data.renownReputationEarned),
			threshold = number(data.renownLevelThreshold),
			highest = highest,
			kills = number(kills),
			honor = honorTotal(),
		})
	end
	raise("highestRank", math.max(highest or 0, rank))
	local s = h:State("pvp")
	if s.rank ~= rank then
		s.rank = rank
		h:Write("rk", rank, title)
	end
end

-- Start ------------------------------------------------------------------------

function PvP.Tally()
	if tally then
		return { name = tally.name, start = tally.start, honor = tally.honor, kills = tally.kills, won = tally.won }
	end
end

function PvP.EnterWorld(handle)
	C_Timer.After(WORLD_DELAY, function()
		handle:Safe("battleground", checkBattleground)
	end)
end

local function compileHonor()
	honorForms = {}
	local forms = {
		{ COMBATLOG_HONORGAIN, victim = 1, rank = 2, honor = 3 },
		{ COMBATLOG_HONORGAIN_NO_RANK, victim = 1, honor = 2 },
		{ COMBATLOG_HONORAWARD, honor = 1 },
	}
	for _, f in ipairs(forms) do
		local compiled = ns.Compile(f[1])
		if compiled then
			honorForms[#honorForms + 1] = { compiled = compiled, victim = f.victim, rank = f.rank, honor = f.honor }
		end
	end
end

function PvP.Start(handle)
	h = handle
	compileHonor()
	-- The winner is the first argument in both formats; only the words around them differ.
	knockout, retreat = ns.Compile(DUEL_WINNER_KNOCKOUT), ns.Compile(DUEL_WINNER_RETREAT)
	baseline = lifetimeKills()
	h:On("PLAYER_TARGET_CHANGED", function()
		onUnit("target", "target")
	end)
	h:On("UPDATE_MOUSEOVER_UNIT", function()
		onUnit("mouseover", "mouseover")
	end)
	h:On("NAME_PLATE_UNIT_ADDED", function(_, unit)
		onUnit(unit, "nameplate")
	end)
	h:Listen("FIGHT_START", startScan)
	h:Listen("FIGHT_END", function()
		scanUntil = GetTime() + SCAN_AFTER
	end)
	h:On("CHAT_MSG_COMBAT_HONOR_GAIN", onHonor)
	h:On("PLAYER_PVP_KILLS_CHANGED", function()
		h:Coalesce("kills", KILLS_DELAY, readKills)
		h:Coalesce("rank", RANK_DELAY, readRank)
	end)
	h:On("PLAYER_DEAD", onDead)
	h:Listen("DIED", onDied)
	h:On("DUEL_REQUESTED", onDuelRequest(false))
	h:On("DUEL_TO_THE_DEATH_REQUESTED", onDuelRequest(true))
	h:On("DUEL_FINISHED", onDuelFinished)
	h:On("CHAT_MSG_SYSTEM", onDuelLine)
	h:On("ZONE_CHANGED_NEW_AREA", checkBattleground)
	h:On("UPDATE_BATTLEFIELD_STATUS", function()
		checkBattleground()
		checkQueues()
	end)
	h:On("UPDATE_BATTLEFIELD_SCORE", onWinner)
	h:On("PVP_MATCH_COMPLETE", onWinner)
	for _, event in ipairs({ "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" }) do
		h:On(event, function()
			h:Coalesce("rank", RANK_DELAY, readRank)
		end)
	end
	-- A restored journal brings its own last rk.
	h:Listen("RESTORED", function(_, addon)
		if addon == ADDON then
			h:Coalesce("rank", RANK_DELAY, readRank)
		end
	end)
	C_Timer.After(LOGIN_RANK, function()
		h:Safe("login rank", readRank)
	end)
end

-- A registration after login calls OnLogin before RegisterModule returns, so the handle comes from the argument.
local function onLogin(handle)
	ns.h = handle
	Social.Start(handle)
	PvP.Start(handle)
end

Memories.RegisterModule({
	addon = ADDON,
	api = 1,
	saved = "MemoriesSocialCharDB",
	kinds = {
		{ kind = "gj", group = "Social", name = L["Joined a group"], fields = { "name", "guild", "class", "#level" } },
		{ kind = "gl", group = "Social", name = L["Left a group"], fields = { "name" } },
		{ kind = "gu", group = "Social", name = L["Own guild changed"], fields = { "guild", "rank" } },
		{
			kind = "ep",
			group = "PvP",
			name = L["Enemy player met"],
			fields = { "name", "class", "race", "#level", "guild" },
		},
		{
			kind = "pk",
			group = "PvP",
			name = L["PvP kill or death"],
			fields = { "result", "name", "class", "#level", "guild" },
		},
		{ kind = "hk", group = "PvP", name = L["Honor gained"], fields = { "#honor", "victim", "rank" } },
		{ kind = "du", group = "PvP", name = L["Duel"], fields = { "result", "opponent", "class" } },
		{
			kind = "bg",
			group = "PvP",
			name = L["Battleground ended"],
			fields = { "name", "result", "#seconds", "#honor", "#kills", "#kb", "#deaths" },
		},
		{ kind = "rk", group = "PvP", name = L["PvP rank changed"], fields = { "#rank", "title" } },
	},
	OnLogin = onLogin,
	OnEnterWorld = PvP.EnterWorld,
})
