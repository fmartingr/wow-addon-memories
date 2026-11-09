local _, ns = ...

local T = {
	-- Machine translated. Corrections are welcome.
	deDE = {
		["Auction house"] = "Auktionshaus",
		["Equipped an item"] = "Gegenstand angelegt",
		["Gear snapshot"] = "Ausrüstungsabbild",
		["Group roll ended"] = "Gruppenwurf beendet",
		["Loot"] = "Beute",
		["Loot: new findings only"] = "Beute: nur neue Funde",
		["Mail"] = "Post",
		["Memories is not loaded."] = "Memories ist nicht geladen.",
		["Money in or out"] = "Geld rein oder raus",
		["Traded with someone"] = "Mit jemandem gehandelt",
		["Trainer purchase"] = "Lehrerkauf",
	},
	-- Machine translated. Corrections are welcome.
	frFR = {
		["Auction house"] = "Hôtel des ventes",
		["Equipped an item"] = "Objet équipé",
		["Gear snapshot"] = "Aperçu de l'équipement",
		["Group roll ended"] = "Jet de groupe terminé",
		["Loot"] = "Butin",
		["Loot: new findings only"] = "Butin : nouvelles trouvailles uniquement",
		["Mail"] = "Courrier",
		["Memories is not loaded."] = "Memories n'est pas chargé.",
		["Money in or out"] = "Argent reçu ou dépensé",
		["Traded with someone"] = "Échange avec quelqu'un",
		["Trainer purchase"] = "Achat chez un maître",
	},
	-- Machine translated. Corrections are welcome.
	esES = {
		["Auction house"] = "Casa de subastas",
		["Equipped an item"] = "Objeto equipado",
		["Gear snapshot"] = "Instantánea del equipo",
		["Group roll ended"] = "Tirada de grupo terminada",
		["Loot"] = "Botín",
		["Loot: new findings only"] = "Botín: solo hallazgos nuevos",
		["Mail"] = "Correo",
		["Memories is not loaded."] = "Memories no está cargado.",
		["Money in or out"] = "Dinero entrante o saliente",
		["Traded with someone"] = "Comerció con alguien",
		["Trainer purchase"] = "Compra al instructor",
	},
	-- Machine translated. Corrections are welcome.
	itIT = {
		["Auction house"] = "Casa d'aste",
		["Equipped an item"] = "Oggetto equipaggiato",
		["Gear snapshot"] = "Istantanea dell'equipaggiamento",
		["Group roll ended"] = "Tiro di gruppo terminato",
		["Loot"] = "Bottino",
		["Loot: new findings only"] = "Bottino: solo nuovi ritrovamenti",
		["Mail"] = "Posta",
		["Memories is not loaded."] = "Memories non è caricato.",
		["Money in or out"] = "Denaro in entrata o in uscita",
		["Traded with someone"] = "Scambio con qualcuno",
		["Trainer purchase"] = "Acquisto dall'addestratore",
	},
	-- Machine translated. Corrections are welcome.
	ptBR = {
		["Auction house"] = "Casa de leilões",
		["Equipped an item"] = "Item equipado",
		["Gear snapshot"] = "Resumo do equipamento",
		["Group roll ended"] = "Rolagem de grupo encerrada",
		["Loot"] = "Saque",
		["Loot: new findings only"] = "Saque: apenas novos achados",
		["Mail"] = "Correio",
		["Memories is not loaded."] = "Memories não está carregado.",
		["Money in or out"] = "Dinheiro entrando ou saindo",
		["Traded with someone"] = "Negociou com alguém",
		["Trainer purchase"] = "Compra com instrutor",
	},
}
T.esMX = T.esES

local found = T[GetLocale and GetLocale()] or {}

ns.L = setmetatable({}, {
	__index = function(_, key)
		return found[key] or key
	end,
})
