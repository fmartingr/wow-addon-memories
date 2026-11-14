local _, ns = ...

ns.locales = {}
local locales = ns.locales

locales.enUS = {
	AUCTION_HOUSE = "Auction house",
	CORE_MISSING = "Memories is not loaded.",
	EQUIPPED_ITEM = "Equipped an item",
	GEAR_SNAPSHOT = "Gear snapshot",
	GROUP_ROLL_ENDED = "Group roll ended",
	LOOT = "Loot",
	LOOT_NEW_FINDINGS_ONLY = "Loot: new findings only",
	MAIL = "Mail",
	MONEY_IN_OR_OUT = "Money in or out",
	TRADED_WITH_SOMEONE = "Traded with someone",
	TRAINER_PURCHASE = "Trainer purchase",
}

-- Machine translated. Corrections are welcome.
locales.deDE = {
	AUCTION_HOUSE = "Auktionshaus",
	CORE_MISSING = "Memories ist nicht geladen.",
	EQUIPPED_ITEM = "Gegenstand angelegt",
	GEAR_SNAPSHOT = "Ausrüstungsabbild",
	GROUP_ROLL_ENDED = "Gruppenwurf beendet",
	LOOT = "Beute",
	LOOT_NEW_FINDINGS_ONLY = "Beute: nur neue Funde",
	MAIL = "Post",
	MONEY_IN_OR_OUT = "Geld rein oder raus",
	TRADED_WITH_SOMEONE = "Mit jemandem gehandelt",
	TRAINER_PURCHASE = "Lehrerkauf",
}

-- Machine translated. Corrections are welcome.
locales.esES = {
	AUCTION_HOUSE = "Casa de subastas",
	CORE_MISSING = "Memories no está cargado.",
	EQUIPPED_ITEM = "Objeto equipado",
	GEAR_SNAPSHOT = "Instantánea del equipo",
	GROUP_ROLL_ENDED = "Tirada de grupo terminada",
	LOOT = "Botín",
	LOOT_NEW_FINDINGS_ONLY = "Botín: solo hallazgos nuevos",
	MAIL = "Correo",
	MONEY_IN_OR_OUT = "Dinero entrante o saliente",
	TRADED_WITH_SOMEONE = "Comerció con alguien",
	TRAINER_PURCHASE = "Compra al instructor",
}

-- Machine translated. Corrections are welcome.
locales.frFR = {
	AUCTION_HOUSE = "Hôtel des ventes",
	CORE_MISSING = "Memories n'est pas chargé.",
	EQUIPPED_ITEM = "Objet équipé",
	GEAR_SNAPSHOT = "Aperçu de l'équipement",
	GROUP_ROLL_ENDED = "Jet de groupe terminé",
	LOOT = "Butin",
	LOOT_NEW_FINDINGS_ONLY = "Butin : nouvelles trouvailles uniquement",
	MAIL = "Courrier",
	MONEY_IN_OR_OUT = "Argent reçu ou dépensé",
	TRADED_WITH_SOMEONE = "Échange avec quelqu'un",
	TRAINER_PURCHASE = "Achat chez un maître",
}

-- Machine translated. Corrections are welcome.
locales.itIT = {
	AUCTION_HOUSE = "Casa d'aste",
	CORE_MISSING = "Memories non è caricato.",
	EQUIPPED_ITEM = "Oggetto equipaggiato",
	GEAR_SNAPSHOT = "Istantanea dell'equipaggiamento",
	GROUP_ROLL_ENDED = "Tiro di gruppo terminato",
	LOOT = "Bottino",
	LOOT_NEW_FINDINGS_ONLY = "Bottino: solo nuovi ritrovamenti",
	MAIL = "Posta",
	MONEY_IN_OR_OUT = "Denaro in entrata o in uscita",
	TRADED_WITH_SOMEONE = "Scambio con qualcuno",
	TRAINER_PURCHASE = "Acquisto dall'addestratore",
}

-- Machine translated. Corrections are welcome.
locales.ptBR = {
	AUCTION_HOUSE = "Casa de leilões",
	CORE_MISSING = "Memories não está carregado.",
	EQUIPPED_ITEM = "Item equipado",
	GEAR_SNAPSHOT = "Resumo do equipamento",
	GROUP_ROLL_ENDED = "Rolagem de grupo encerrada",
	LOOT = "Saque",
	LOOT_NEW_FINDINGS_ONLY = "Saque: apenas novos achados",
	MAIL = "Correio",
	MONEY_IN_OR_OUT = "Dinheiro entrando ou saindo",
	TRADED_WITH_SOMEONE = "Negociou com alguém",
	TRAINER_PURCHASE = "Compra com instrutor",
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
