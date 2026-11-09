local _, ns = ...

local T = {
	-- Machine translated. Corrections are welcome.
	deDE = {
		["Caught while fishing"] = "Beim Angeln gefangen",
		["Gathered"] = "Gesammelt",
		["Gathering: new findings only"] = "Sammeln: nur neue Funde",
		["Memories is not loaded."] = "Memories ist nicht geladen.",
		["Opened a container or chest"] = "Behälter oder Truhe geöffnet",
		["Picked a pocket"] = "Taschendiebstahl",
	},
	-- Machine translated. Corrections are welcome.
	frFR = {
		["Caught while fishing"] = "Pêché",
		["Gathered"] = "Récolté",
		["Gathering: new findings only"] = "Récolte : nouvelles trouvailles uniquement",
		["Memories is not loaded."] = "Memories n'est pas chargé.",
		["Opened a container or chest"] = "Conteneur ou coffre ouvert",
		["Picked a pocket"] = "Vol à la tire",
	},
	-- Machine translated. Corrections are welcome.
	esES = {
		["Caught while fishing"] = "Pescado",
		["Gathered"] = "Recolectado",
		["Gathering: new findings only"] = "Recolección: solo hallazgos nuevos",
		["Memories is not loaded."] = "Memories no está cargado.",
		["Opened a container or chest"] = "Contenedor o cofre abierto",
		["Picked a pocket"] = "Bolsillo robado",
	},
	-- Machine translated. Corrections are welcome.
	itIT = {
		["Caught while fishing"] = "Pescato",
		["Gathered"] = "Raccolto",
		["Gathering: new findings only"] = "Raccolta: solo nuovi ritrovamenti",
		["Memories is not loaded."] = "Memories non è caricato.",
		["Opened a container or chest"] = "Contenitore o forziere aperto",
		["Picked a pocket"] = "Borseggio",
	},
	-- Machine translated. Corrections are welcome.
	ptBR = {
		["Caught while fishing"] = "Pescado",
		["Gathered"] = "Coletado",
		["Gathering: new findings only"] = "Coleta: apenas novos achados",
		["Memories is not loaded."] = "Memories não está carregado.",
		["Opened a container or chest"] = "Recipiente ou baú aberto",
		["Picked a pocket"] = "Furto",
	},
}
T.esMX = T.esES

local found = T[GetLocale and GetLocale()] or {}

ns.L = setmetatable({}, {
	__index = function(_, key)
		return found[key] or key
	end,
})
