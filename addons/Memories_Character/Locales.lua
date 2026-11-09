local _, ns = ...

local T = {
	-- Machine translated. Corrections are welcome.
	deDE = {
		["Consumables: new findings only"] = "Verbrauchsgüter: nur neue Funde",
		["Hearthstone bound"] = "Ruhestein gebunden",
		["Learned a flight path"] = "Flugroute gelernt",
		["Learned a recipe"] = "Rezept gelernt",
		["Learned a spell"] = "Zauber gelernt",
		["Memories is not loaded."] = "Memories ist nicht geladen.",
		["Quest accepted"] = "Quest angenommen",
		["Read a book"] = "Buch gelesen",
		["Reputation changed"] = "Ruf geändert",
		["Skill changed"] = "Fertigkeit geändert",
		["Talent points"] = "Talentpunkte",
		["Tamed a beast"] = "Wildtier gezähmt",
		["Used a consumable"] = "Verbrauchsgut benutzt",
	},
	-- Machine translated. Corrections are welcome.
	frFR = {
		["Consumables: new findings only"] = "Consommables : nouvelles trouvailles uniquement",
		["Hearthstone bound"] = "Pierre de foyer liée",
		["Learned a flight path"] = "Trajet de vol appris",
		["Learned a recipe"] = "Recette apprise",
		["Learned a spell"] = "Sort appris",
		["Memories is not loaded."] = "Memories n'est pas chargé.",
		["Quest accepted"] = "Quête acceptée",
		["Read a book"] = "Livre lu",
		["Reputation changed"] = "Réputation modifiée",
		["Skill changed"] = "Compétence modifiée",
		["Talent points"] = "Points de talent",
		["Tamed a beast"] = "Bête apprivoisée",
		["Used a consumable"] = "Consommable utilisé",
	},
	-- Machine translated. Corrections are welcome.
	esES = {
		["Consumables: new findings only"] = "Consumibles: solo hallazgos nuevos",
		["Hearthstone bound"] = "Piedra de hogar vinculada",
		["Learned a flight path"] = "Ruta de vuelo aprendida",
		["Learned a recipe"] = "Receta aprendida",
		["Learned a spell"] = "Hechizo aprendido",
		["Memories is not loaded."] = "Memories no está cargado.",
		["Quest accepted"] = "Misión aceptada",
		["Read a book"] = "Libro leído",
		["Reputation changed"] = "Reputación cambiada",
		["Skill changed"] = "Habilidad cambiada",
		["Talent points"] = "Puntos de talento",
		["Tamed a beast"] = "Bestia domada",
		["Used a consumable"] = "Consumible usado",
	},
	-- Machine translated. Corrections are welcome.
	itIT = {
		["Consumables: new findings only"] = "Consumabili: solo nuovi ritrovamenti",
		["Hearthstone bound"] = "Pietra del Ritorno vincolata",
		["Learned a flight path"] = "Rotta di volo appresa",
		["Learned a recipe"] = "Ricetta appresa",
		["Learned a spell"] = "Incantesimo appreso",
		["Memories is not loaded."] = "Memories non è caricato.",
		["Quest accepted"] = "Missione accettata",
		["Read a book"] = "Libro letto",
		["Reputation changed"] = "Reputazione cambiata",
		["Skill changed"] = "Abilità cambiata",
		["Talent points"] = "Punti talento",
		["Tamed a beast"] = "Bestia domata",
		["Used a consumable"] = "Consumabile usato",
	},
	-- Machine translated. Corrections are welcome.
	ptBR = {
		["Consumables: new findings only"] = "Consumíveis: apenas novos achados",
		["Hearthstone bound"] = "Pedra de Regresso vinculada",
		["Learned a flight path"] = "Rota de voo aprendida",
		["Learned a recipe"] = "Receita aprendida",
		["Learned a spell"] = "Feitiço aprendido",
		["Memories is not loaded."] = "Memories não está carregado.",
		["Quest accepted"] = "Missão aceita",
		["Read a book"] = "Livro lido",
		["Reputation changed"] = "Reputação alterada",
		["Skill changed"] = "Habilidade alterada",
		["Talent points"] = "Pontos de talento",
		["Tamed a beast"] = "Fera domada",
		["Used a consumable"] = "Consumível usado",
	},
}
T.esMX = T.esES

local found = T[GetLocale and GetLocale()] or {}

ns.L = setmetatable({}, {
	__index = function(_, key)
		return found[key] or key
	end,
})
