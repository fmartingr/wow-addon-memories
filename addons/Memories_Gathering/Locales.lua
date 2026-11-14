local _, ns = ...

ns.locales = {}
local locales = ns.locales

locales.enUS = {
	CAUGHT_WHILE_FISHING = "Caught while fishing",
	CORE_MISSING = "Memories is not loaded.",
	GATHERED = "Gathered",
	GATHERING_NEW_FINDINGS_ONLY = "Gathering: new findings only",
	OPENED_CONTAINER_OR_CHEST = "Opened a container or chest",
	PICKED_POCKET = "Picked a pocket",
}

-- Machine translated. Corrections are welcome.
locales.deDE = {
	CAUGHT_WHILE_FISHING = "Beim Angeln gefangen",
	CORE_MISSING = "Memories ist nicht geladen.",
	GATHERED = "Gesammelt",
	GATHERING_NEW_FINDINGS_ONLY = "Sammeln: nur neue Funde",
	OPENED_CONTAINER_OR_CHEST = "Behälter oder Truhe geöffnet",
	PICKED_POCKET = "Taschendiebstahl",
}

-- Machine translated. Corrections are welcome.
locales.esES = {
	CAUGHT_WHILE_FISHING = "Pescado",
	CORE_MISSING = "Memories no está cargado.",
	GATHERED = "Recolectado",
	GATHERING_NEW_FINDINGS_ONLY = "Recolección: solo hallazgos nuevos",
	OPENED_CONTAINER_OR_CHEST = "Contenedor o cofre abierto",
	PICKED_POCKET = "Bolsillo robado",
}

-- Machine translated. Corrections are welcome.
locales.frFR = {
	CAUGHT_WHILE_FISHING = "Pêché",
	CORE_MISSING = "Memories n'est pas chargé.",
	GATHERED = "Récolté",
	GATHERING_NEW_FINDINGS_ONLY = "Récolte : nouvelles trouvailles uniquement",
	OPENED_CONTAINER_OR_CHEST = "Conteneur ou coffre ouvert",
	PICKED_POCKET = "Vol à la tire",
}

-- Machine translated. Corrections are welcome.
locales.itIT = {
	CAUGHT_WHILE_FISHING = "Pescato",
	CORE_MISSING = "Memories non è caricato.",
	GATHERED = "Raccolto",
	GATHERING_NEW_FINDINGS_ONLY = "Raccolta: solo nuovi ritrovamenti",
	OPENED_CONTAINER_OR_CHEST = "Contenitore o forziere aperto",
	PICKED_POCKET = "Borseggio",
}

-- Machine translated. Corrections are welcome.
locales.ptBR = {
	CAUGHT_WHILE_FISHING = "Pescado",
	CORE_MISSING = "Memories não está carregado.",
	GATHERED = "Coletado",
	GATHERING_NEW_FINDINGS_ONLY = "Coleta: apenas novos achados",
	OPENED_CONTAINER_OR_CHEST = "Recipiente ou baú aberto",
	PICKED_POCKET = "Furto",
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
