local wow = require("helpers.wow")

describe("milestones", function()
	local STORMWIND = { name = "Ventormenta", reaction = 5, currentStanding = 3000 }
	local NEW_PATH = "Has descubierto una nueva ruta de vuelo."

	local ns

	local function boot(opts)
		opts = opts or {}
		opts.addons = opts.addons or { "Memories", "Memories_Character" }
		ns = wow.boot(opts)
		wow.advance(11)
		return ns
	end

	local function journal()
		return ns.Registry.Journal("Memories_Character").journal
	end

	-- The milestone lines, whole or as "kind|fields", in journal order.
	local function lines(whole)
		local out = {}
		for line in journal():Lines() do
			local rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(.*)$")
			if not rest:match("^nt|") then
				out[#out + 1] = whole and line or rest
			end
		end
		return out
	end

	local function counts()
		return journal():Counts("milestones")
	end

	describe("reputation", function()
		it("writes the value, the standing and its label", function()
			boot()
			wow.factions[72] = STORMWIND
			wow.fire("FACTION_STANDING_CHANGED", 72, 3250)
			assert.same({ "rp|Ventormenta|3250|5|Amistoso" }, lines())
		end)

		it("writes nothing for the same value again in a session, and writes it after a reload", function()
			boot()
			wow.factions[72] = STORMWIND
			wow.fire("FACTION_STANDING_CHANGED", 72, 3250)
			wow.fire("FACTION_STANDING_CHANGED", 72, 3250)
			assert.equal(1, #lines())
			ns = wow.reload()
			wow.factions[72] = STORMWIND
			wow.fire("FACTION_STANDING_CHANGED", 72, 3250)
			assert.equal(2, #lines())
		end)

		it("takes the value from the faction data when the event has none", function()
			boot()
			wow.factions[72] = STORMWIND
			wow.fire("FACTION_STANDING_CHANGED", 72)
			assert.same({ "rp|Ventormenta|3000|5|Amistoso" }, lines())
		end)

		it("uses the gendered label of GetText", function()
			boot()
			_G.GetText = function(token, sex, ...)
				assert.equal(0, select("#", ...))
				return _G[token] .. (sex == 3 and "a" or "")
			end
			wow.factions[72] = { name = "Ventormenta", reaction = 8 }
			wow.fire("FACTION_STANDING_CHANGED", 72, 42000)
			assert.same({ "rp|Ventormenta|42000|8|Exaltadoa" }, lines())
		end)

		it("writes nothing for a faction with no name", function()
			boot()
			wow.factions[72] = { name = wow.secret("Ventormenta"), reaction = 5 }
			wow.fire("FACTION_STANDING_CHANGED", 72, 3250)
			wow.fire("FACTION_STANDING_CHANGED", 99, 3250)
			assert.same({}, lines())
		end)

		it("writes no line with rp off", function()
			boot()
			ns.Settings.SetKind("rp", false)
			wow.factions[72] = STORMWIND
			wow.fire("FACTION_STANDING_CHANGED", 72, 3250)
			assert.same({}, lines())
		end)
	end)

	describe("quests", function()
		it("writes a quest with a known title at once", function()
			boot({ quests = { [783] = "Una amenaza interna" } })
			wow.fire("QUEST_ACCEPTED", 783)
			assert.same({ "qa|783|Una amenaza interna" }, lines())
			assert.equal(1, counts().questsAccepted)
		end)

		it("waits 2 s for a title that is not cached and keeps the accept-time position", function()
			boot()
			wow.fire("QUEST_ACCEPTED", 5, 783)
			local at = wow.wall
			wow.map.x = 0.9
			wow.quests[783] = "Una amenaza interna"
			wow.advance(1.9)
			assert.same({}, lines())
			wow.advance(0.1)
			local t, _, _, x, _, rest = lines(true)[1]:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
			assert.equal("qa|783|Una amenaza interna", rest)
			assert.equal(tostring(at), t)
			assert.equal("5000", x)
		end)

		it("writes an empty title when the second try has none", function()
			boot()
			wow.fire("QUEST_ACCEPTED", 783)
			wow.advance(2)
			assert.same({ "qa|783" }, lines())
		end)

		it("writes no line with qa off and still counts", function()
			boot({ quests = { [783] = "Una amenaza interna" } })
			ns.Settings.SetKind("qa", false)
			wow.fire("QUEST_ACCEPTED", 783)
			wow.fire("QUEST_ACCEPTED")
			assert.same({}, lines())
			assert.equal(1, counts().questsAccepted)
		end)
	end)

	describe("home", function()
		it("writes one hb for the Spanish chat line and HEARTHSTONE_BOUND", function()
			boot()
			wow.fire("CHAT_MSG_SYSTEM", "Villadorada es ahora tu hogar.")
			wow.advance(0.2)
			wow.bind = "Villadorada"
			wow.fire("HEARTHSTONE_BOUND")
			assert.same({ "hb|Villadorada" }, lines())
		end)

		it("reads no chat line without the home format", function()
			boot({ strings = { ERR_DEATHBIND_SUCCESS_S = false } })
			wow.fire("CHAT_MSG_SYSTEM", "Villadorada es ahora tu hogar.")
			assert.same({}, lines())
		end)

		it("writes nothing when the last home is the same, also after a reload", function()
			boot({ bind = "Villadorada" })
			wow.fire("HEARTHSTONE_BOUND")
			ns = wow.reload()
			wow.advance(60)
			wow.bind = "Villadorada"
			wow.fire("HEARTHSTONE_BOUND")
			assert.equal(1, #lines())
			wow.bind = "Ventormenta"
			wow.fire("HEARTHSTONE_BOUND")
			assert.same({ "hb|Villadorada", "hb|Ventormenta" }, lines())
		end)

		it("writes no line with hb off and still keeps the last home", function()
			boot({ bind = "Villadorada" })
			ns.Settings.SetKind("hb", false)
			wow.fire("HEARTHSTONE_BOUND")
			ns.Settings.SetKind("hb", true)
			wow.fire("HEARTHSTONE_BOUND")
			assert.same({}, lines())
		end)
	end)

	describe("flight paths", function()
		local function openMap(node)
			wow.taxi = { { name = "Ventormenta", type = "REACHABLE" }, { name = node, type = "CURRENT" } }
			wow.fire("TAXIMAP_OPENED", 1)
		end

		it("names the node of a flight map opened before the message", function()
			boot()
			openMap("Colina del Centinela")
			wow.advance(2)
			wow.fire("UI_INFO_MESSAGE", 0, NEW_PATH)
			assert.same({ "fp|Colina del Centinela" }, lines())
			assert.equal(1, counts().flightPaths)
		end)

		it("writes one fp for both sources and names the subzone after 6 s", function()
			boot({ subzone = "Villa del Lago" })
			wow.fire("UI_INFO_MESSAGE", 0, NEW_PATH)
			wow.advance(0.1)
			wow.fire("CHAT_MSG_SYSTEM", NEW_PATH)
			wow.advance(5.8)
			assert.same({}, lines())
			wow.advance(0.1)
			assert.same({ "fp|Villa del Lago" }, lines())
			assert.equal(1, counts().flightPaths)
		end)

		it("names the node of a flight map opened after the message", function()
			boot()
			wow.fire("CHAT_MSG_SYSTEM", NEW_PATH)
			wow.advance(3)
			openMap("Colina del Centinela")
			wow.advance(6)
			assert.same({ "fp|Colina del Centinela" }, lines())
		end)

		it("names the zone with no subzone, and ? with neither", function()
			boot({ zone = "Páramos de Poniente" })
			wow.fire("CHAT_MSG_SYSTEM", NEW_PATH)
			wow.advance(10)
			wow.zone = nil
			wow.fire("CHAT_MSG_SYSTEM", NEW_PATH)
			wow.advance(6)
			assert.same({ "fp|Páramos de Poniente", "fp|?" }, lines())
		end)

		it("ignores a flight map opened long before", function()
			boot({ subzone = "Villa del Lago" })
			openMap("Colina del Centinela")
			wow.advance(7)
			wow.fire("CHAT_MSG_SYSTEM", NEW_PATH)
			wow.advance(6)
			assert.same({ "fp|Villa del Lago" }, lines())
		end)

		it("writes no line with fp off and still counts", function()
			boot()
			ns.Settings.SetKind("fp", false)
			openMap("Colina del Centinela")
			wow.fire("CHAT_MSG_SYSTEM", NEW_PATH)
			assert.same({}, lines())
			assert.equal(1, counts().flightPaths)
		end)
	end)

	describe("books", function()
		local function read(title)
			wow.item_text = title
			wow.fire("ITEM_TEXT_BEGIN")
		end

		it("writes the first read of a title and counts every read, also after a reload", function()
			boot()
			read("En memoria de")
			ns = wow.reload()
			read("En memoria de")
			assert.same({ "bk|En memoria de" }, lines())
			assert.equal(2, counts().booksRead)
		end)

		it("writes nothing for an empty title", function()
			boot()
			read("")
			read(nil)
			assert.same({}, lines())
			assert.is_nil(counts().booksRead)
		end)

		it("writes no line with bk off and still counts", function()
			boot()
			ns.Settings.SetKind("bk", false)
			read("En memoria de")
			assert.same({}, lines())
			assert.equal(1, counts().booksRead)
		end)
	end)

	describe("missing game functions", function()
		it("writes nothing without the optional functions", function()
			boot()
			_G.C_Reputation, _G.C_QuestLog, _G.ItemTextGetItem, _G.NumTaxiNodes = nil, nil, nil, nil
			wow.fire("FACTION_STANDING_CHANGED", 72, 3250)
			wow.fire("QUEST_ACCEPTED", 783)
			wow.fire("ITEM_TEXT_BEGIN")
			wow.fire("TAXIMAP_OPENED", 1)
			wow.advance(2)
			assert.same({ "qa|783" }, lines())
			assert.same({}, ns.Errors())
		end)
	end)
end)
