local _, ns = ...

ns.locales = {}
local locales = ns.locales

locales.enUS = {
	CONSUMABLES_NEW_FINDINGS_ONLY = "Consumables: new findings only",
	CORE_MISSING = "Memories is not loaded.",
	HEARTHSTONE_BOUND = "Hearthstone bound",
	LEARNED_FLIGHT_PATH = "Learned a flight path",
	LEARNED_RECIPE = "Learned a recipe",
	LEARNED_SPELL = "Learned a spell",
	QUEST_ACCEPTED = "Quest accepted",
	READ_BOOK = "Read a book",
	REPUTATION_CHANGED = "Reputation changed",
	SKILL_CHANGED = "Skill changed",
	TALENT_POINTS = "Talent points",
	TAMED_BEAST = "Tamed a beast",
	USED_CONSUMABLE = "Used a consumable",
}

-- Machine translated. Corrections are welcome.
locales.deDE = {
	CONSUMABLES_NEW_FINDINGS_ONLY = "Verbrauchsgüter: nur neue Funde",
	CORE_MISSING = "Memories ist nicht geladen.",
	HEARTHSTONE_BOUND = "Ruhestein gebunden",
	LEARNED_FLIGHT_PATH = "Flugroute gelernt",
	LEARNED_RECIPE = "Rezept gelernt",
	LEARNED_SPELL = "Zauber gelernt",
	QUEST_ACCEPTED = "Quest angenommen",
	READ_BOOK = "Buch gelesen",
	REPUTATION_CHANGED = "Ruf geändert",
	SKILL_CHANGED = "Fertigkeit geändert",
	TALENT_POINTS = "Talentpunkte",
	TAMED_BEAST = "Wildtier gezähmt",
	USED_CONSUMABLE = "Verbrauchsgut benutzt",
}

-- Machine translated. Corrections are welcome.
locales.esES = {
	CONSUMABLES_NEW_FINDINGS_ONLY = "Consumibles: solo hallazgos nuevos",
	CORE_MISSING = "Memories no está cargado.",
	HEARTHSTONE_BOUND = "Piedra de hogar vinculada",
	LEARNED_FLIGHT_PATH = "Ruta de vuelo aprendida",
	LEARNED_RECIPE = "Receta aprendida",
	LEARNED_SPELL = "Hechizo aprendido",
	QUEST_ACCEPTED = "Misión aceptada",
	READ_BOOK = "Libro leído",
	REPUTATION_CHANGED = "Reputación cambiada",
	SKILL_CHANGED = "Habilidad cambiada",
	TALENT_POINTS = "Puntos de talento",
	TAMED_BEAST = "Bestia domada",
	USED_CONSUMABLE = "Consumible usado",
}

-- Machine translated. Corrections are welcome.
locales.frFR = {
	CONSUMABLES_NEW_FINDINGS_ONLY = "Consommables : nouvelles trouvailles uniquement",
	CORE_MISSING = "Memories n'est pas chargé.",
	HEARTHSTONE_BOUND = "Pierre de foyer liée",
	LEARNED_FLIGHT_PATH = "Trajet de vol appris",
	LEARNED_RECIPE = "Recette apprise",
	LEARNED_SPELL = "Sort appris",
	QUEST_ACCEPTED = "Quête acceptée",
	READ_BOOK = "Livre lu",
	REPUTATION_CHANGED = "Réputation modifiée",
	SKILL_CHANGED = "Compétence modifiée",
	TALENT_POINTS = "Points de talent",
	TAMED_BEAST = "Bête apprivoisée",
	USED_CONSUMABLE = "Consommable utilisé",
}

-- Machine translated. Corrections are welcome.
locales.itIT = {
	CONSUMABLES_NEW_FINDINGS_ONLY = "Consumabili: solo nuovi ritrovamenti",
	CORE_MISSING = "Memories non è caricato.",
	HEARTHSTONE_BOUND = "Pietra del Ritorno vincolata",
	LEARNED_FLIGHT_PATH = "Rotta di volo appresa",
	LEARNED_RECIPE = "Ricetta appresa",
	LEARNED_SPELL = "Incantesimo appreso",
	QUEST_ACCEPTED = "Missione accettata",
	READ_BOOK = "Libro letto",
	REPUTATION_CHANGED = "Reputazione cambiata",
	SKILL_CHANGED = "Abilità cambiata",
	TALENT_POINTS = "Punti talento",
	TAMED_BEAST = "Bestia domata",
	USED_CONSUMABLE = "Consumabile usato",
}

-- Machine translated. Corrections are welcome.
locales.ptBR = {
	CONSUMABLES_NEW_FINDINGS_ONLY = "Consumíveis: apenas novos achados",
	CORE_MISSING = "Memories não está carregado.",
	HEARTHSTONE_BOUND = "Pedra de Regresso vinculada",
	LEARNED_FLIGHT_PATH = "Rota de voo aprendida",
	LEARNED_RECIPE = "Receita aprendida",
	LEARNED_SPELL = "Feitiço aprendido",
	QUEST_ACCEPTED = "Missão aceita",
	READ_BOOK = "Livro lido",
	REPUTATION_CHANGED = "Reputação alterada",
	SKILL_CHANGED = "Habilidade alterada",
	TALENT_POINTS = "Pontos de talento",
	TAMED_BEAST = "Fera domada",
	USED_CONSUMABLE = "Consumível usado",
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
