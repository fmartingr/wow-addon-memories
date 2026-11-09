local _, ns = ...

local T = {
	-- Machine translated. Corrections are welcome.
	deDE = {
		["Battleground ended"] = "Schlachtfeld beendet",
		["Duel"] = "Duell",
		["Enemy player met"] = "Feindlichen Spieler getroffen",
		["Honor gained"] = "Ehre erhalten",
		["Joined a group"] = "Gruppe beigetreten",
		["Left a group"] = "Gruppe verlassen",
		["Memories is not loaded."] = "Memories ist nicht geladen.",
		["Own guild changed"] = "Eigene Gilde geändert",
		["PvP kill or death"] = "PvP-Sieg oder -Tod",
		["PvP rank changed"] = "PvP-Rang geändert",
	},
	-- Machine translated. Corrections are welcome.
	frFR = {
		["Battleground ended"] = "Champ de bataille terminé",
		["Duel"] = "Duel",
		["Enemy player met"] = "Joueur ennemi rencontré",
		["Honor gained"] = "Honneur gagné",
		["Joined a group"] = "Groupe rejoint",
		["Left a group"] = "Groupe quitté",
		["Memories is not loaded."] = "Memories n'est pas chargé.",
		["Own guild changed"] = "Guilde modifiée",
		["PvP kill or death"] = "Victoire ou mort en JcJ",
		["PvP rank changed"] = "Rang JcJ modifié",
	},
	-- Machine translated. Corrections are welcome.
	esES = {
		["Battleground ended"] = "Campo de batalla terminado",
		["Duel"] = "Duelo",
		["Enemy player met"] = "Jugador enemigo encontrado",
		["Honor gained"] = "Honor obtenido",
		["Joined a group"] = "Se unió a un grupo",
		["Left a group"] = "Salió de un grupo",
		["Memories is not loaded."] = "Memories no está cargado.",
		["Own guild changed"] = "Hermandad propia cambiada",
		["PvP kill or death"] = "Muerte o baja en JcJ",
		["PvP rank changed"] = "Rango JcJ cambiado",
	},
	-- Machine translated. Corrections are welcome.
	itIT = {
		["Battleground ended"] = "Campo di battaglia terminato",
		["Duel"] = "Duello",
		["Enemy player met"] = "Giocatore nemico incontrato",
		["Honor gained"] = "Onore ottenuto",
		["Joined a group"] = "Entrato in un gruppo",
		["Left a group"] = "Uscito da un gruppo",
		["Memories is not loaded."] = "Memories non è caricato.",
		["Own guild changed"] = "Gilda cambiata",
		["PvP kill or death"] = "Uccisione o morte in PvP",
		["PvP rank changed"] = "Grado PvP cambiato",
	},
	-- Machine translated. Corrections are welcome.
	ptBR = {
		["Battleground ended"] = "Campo de batalha encerrado",
		["Duel"] = "Duelo",
		["Enemy player met"] = "Jogador inimigo encontrado",
		["Honor gained"] = "Honra ganha",
		["Joined a group"] = "Entrou em um grupo",
		["Left a group"] = "Saiu de um grupo",
		["Memories is not loaded."] = "Memories não está carregado.",
		["Own guild changed"] = "Própria guilda alterada",
		["PvP kill or death"] = "Abate ou morte em JxJ",
		["PvP rank changed"] = "Patente de JxJ alterada",
	},
}
T.esMX = T.esES

local found = T[GetLocale and GetLocale()] or {}

ns.L = setmetatable({}, {
	__index = function(_, key)
		return found[key] or key
	end,
})
