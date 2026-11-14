local _, ns = ...

ns.locales = {}
local locales = ns.locales

locales.enUS = {
	CORE_MISSING = "Memories is not loaded.",
	KILLED_CREATURE = "Killed a creature",
	KILLED_RARE = "Killed a rare",
	KILLS_NEW_FINDINGS_ONLY = "Kills: new findings only",
	LONG_FIGHT = "Long fight",
}

-- Machine translated. Corrections are welcome.
locales.deDE = {
	CORE_MISSING = "Memories ist nicht geladen.",
	KILLED_CREATURE = "Kreatur getötet",
	KILLED_RARE = "Seltenen Gegner getötet",
	KILLS_NEW_FINDINGS_ONLY = "Tötungen: nur neue Funde",
	LONG_FIGHT = "Langer Kampf",
}

-- Machine translated. Corrections are welcome.
locales.esES = {
	CORE_MISSING = "Memories no está cargado.",
	KILLED_CREATURE = "Criatura muerta",
	KILLED_RARE = "Criatura rara muerta",
	KILLS_NEW_FINDINGS_ONLY = "Muertes: solo hallazgos nuevos",
	LONG_FIGHT = "Combate largo",
}

-- Machine translated. Corrections are welcome.
locales.frFR = {
	CORE_MISSING = "Memories n'est pas chargé.",
	KILLED_CREATURE = "Créature tuée",
	KILLED_RARE = "Rare tué",
	KILLS_NEW_FINDINGS_ONLY = "Victimes : nouvelles trouvailles uniquement",
	LONG_FIGHT = "Combat long",
}

-- Machine translated. Corrections are welcome.
locales.itIT = {
	CORE_MISSING = "Memories non è caricato.",
	KILLED_CREATURE = "Creatura uccisa",
	KILLED_RARE = "Raro ucciso",
	KILLS_NEW_FINDINGS_ONLY = "Uccisioni: solo nuovi ritrovamenti",
	LONG_FIGHT = "Combattimento lungo",
}

-- Machine translated. Corrections are welcome.
locales.ptBR = {
	CORE_MISSING = "Memories não está carregado.",
	KILLED_CREATURE = "Criatura morta",
	KILLED_RARE = "Raro morto",
	KILLS_NEW_FINDINGS_ONLY = "Mortes: apenas novos achados",
	LONG_FIGHT = "Luta longa",
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
