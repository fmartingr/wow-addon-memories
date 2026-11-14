local _, ns = ...

ns.locales = {}
local locales = ns.locales

locales.enUS = {
	BATTLEGROUND_ENDED = "Battleground ended",
	CORE_MISSING = "Memories is not loaded.",
	DUEL = "Duel",
	ENEMY_PLAYER_MET = "Enemy player met",
	HONOR_GAINED = "Honor gained",
	JOINED_GROUP = "Joined a group",
	LEFT_GROUP = "Left a group",
	OWN_GUILD_CHANGED = "Own guild changed",
	PVP_KILL_OR_DEATH = "PvP kill or death",
	PVP_RANK_CHANGED = "PvP rank changed",
}

-- Machine translated. Corrections are welcome.
locales.deDE = {
	BATTLEGROUND_ENDED = "Schlachtfeld beendet",
	CORE_MISSING = "Memories ist nicht geladen.",
	DUEL = "Duell",
	ENEMY_PLAYER_MET = "Feindlichen Spieler getroffen",
	HONOR_GAINED = "Ehre erhalten",
	JOINED_GROUP = "Gruppe beigetreten",
	LEFT_GROUP = "Gruppe verlassen",
	OWN_GUILD_CHANGED = "Eigene Gilde geändert",
	PVP_KILL_OR_DEATH = "PvP-Sieg oder -Tod",
	PVP_RANK_CHANGED = "PvP-Rang geändert",
}

-- Machine translated. Corrections are welcome.
locales.esES = {
	BATTLEGROUND_ENDED = "Campo de batalla terminado",
	CORE_MISSING = "Memories no está cargado.",
	DUEL = "Duelo",
	ENEMY_PLAYER_MET = "Jugador enemigo encontrado",
	HONOR_GAINED = "Honor obtenido",
	JOINED_GROUP = "Se unió a un grupo",
	LEFT_GROUP = "Salió de un grupo",
	OWN_GUILD_CHANGED = "Hermandad propia cambiada",
	PVP_KILL_OR_DEATH = "Muerte o baja en JcJ",
	PVP_RANK_CHANGED = "Rango JcJ cambiado",
}

-- Machine translated. Corrections are welcome.
locales.frFR = {
	BATTLEGROUND_ENDED = "Champ de bataille terminé",
	CORE_MISSING = "Memories n'est pas chargé.",
	DUEL = "Duel",
	ENEMY_PLAYER_MET = "Joueur ennemi rencontré",
	HONOR_GAINED = "Honneur gagné",
	JOINED_GROUP = "Groupe rejoint",
	LEFT_GROUP = "Groupe quitté",
	OWN_GUILD_CHANGED = "Guilde modifiée",
	PVP_KILL_OR_DEATH = "Victoire ou mort en JcJ",
	PVP_RANK_CHANGED = "Rang JcJ modifié",
}

-- Machine translated. Corrections are welcome.
locales.itIT = {
	BATTLEGROUND_ENDED = "Campo di battaglia terminato",
	CORE_MISSING = "Memories non è caricato.",
	DUEL = "Duello",
	ENEMY_PLAYER_MET = "Giocatore nemico incontrato",
	HONOR_GAINED = "Onore ottenuto",
	JOINED_GROUP = "Entrato in un gruppo",
	LEFT_GROUP = "Uscito da un gruppo",
	OWN_GUILD_CHANGED = "Gilda cambiata",
	PVP_KILL_OR_DEATH = "Uccisione o morte in PvP",
	PVP_RANK_CHANGED = "Grado PvP cambiato",
}

-- Machine translated. Corrections are welcome.
locales.ptBR = {
	BATTLEGROUND_ENDED = "Campo de batalha encerrado",
	CORE_MISSING = "Memories não está carregado.",
	DUEL = "Duelo",
	ENEMY_PLAYER_MET = "Jogador inimigo encontrado",
	HONOR_GAINED = "Honra ganha",
	JOINED_GROUP = "Entrou em um grupo",
	LEFT_GROUP = "Saiu de um grupo",
	OWN_GUILD_CHANGED = "Própria guilda alterada",
	PVP_KILL_OR_DEATH = "Abate ou morte em JxJ",
	PVP_RANK_CHANGED = "Patente de JxJ alterada",
}

locales.enGB = locales.enUS
locales.esMX = locales.esES

local active = locales[GetLocale and GetLocale()] or locales.enUS
local fallback = locales.enUS

ns.L = setmetatable({}, {
	__index = function(_, key)
		local text = active[key] or fallback[key]
		if text then
			return text
		end
		if ns.debug and ns.ReportOnce then
			ns.ReportOnce("missing-" .. tostring(key), "Missing text key: " .. tostring(key))
		end
		return tostring(key)
	end,
})
