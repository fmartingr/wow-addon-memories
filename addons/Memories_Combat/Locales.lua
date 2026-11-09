local _, ns = ...

local T = {
	-- Machine translated. Corrections are welcome.
	deDE = {
		["Killed a creature"] = "Kreatur getötet",
		["Killed a rare"] = "Seltenen Gegner getötet",
		["Kills: new findings only"] = "Tötungen: nur neue Funde",
		["Long fight"] = "Langer Kampf",
		["Memories is not loaded."] = "Memories ist nicht geladen.",
	},
	-- Machine translated. Corrections are welcome.
	frFR = {
		["Killed a creature"] = "Créature tuée",
		["Killed a rare"] = "Rare tué",
		["Kills: new findings only"] = "Victimes : nouvelles trouvailles uniquement",
		["Long fight"] = "Combat long",
		["Memories is not loaded."] = "Memories n'est pas chargé.",
	},
	-- Machine translated. Corrections are welcome.
	esES = {
		["Killed a creature"] = "Criatura muerta",
		["Killed a rare"] = "Criatura rara muerta",
		["Kills: new findings only"] = "Muertes: solo hallazgos nuevos",
		["Long fight"] = "Combate largo",
		["Memories is not loaded."] = "Memories no está cargado.",
	},
	-- Machine translated. Corrections are welcome.
	itIT = {
		["Killed a creature"] = "Creatura uccisa",
		["Killed a rare"] = "Raro ucciso",
		["Kills: new findings only"] = "Uccisioni: solo nuovi ritrovamenti",
		["Long fight"] = "Combattimento lungo",
		["Memories is not loaded."] = "Memories non è caricato.",
	},
	-- Machine translated. Corrections are welcome.
	ptBR = {
		["Killed a creature"] = "Criatura morta",
		["Killed a rare"] = "Raro morto",
		["Kills: new findings only"] = "Mortes: apenas novos achados",
		["Long fight"] = "Luta longa",
		["Memories is not loaded."] = "Memories não está carregado.",
	},
}
T.esMX = T.esES

local found = T[GetLocale and GetLocale()] or {}

ns.L = setmetatable({}, {
	__index = function(_, key)
		return found[key] or key
	end,
})
