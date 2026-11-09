local wow = require("helpers.wow")

describe("addon strings", function()
	local PLAIN = { "Title", "Notes" }
	local TOC_LOCALES = { "deDE", "frFR", "esES", "esMX", "itIT", "ptBR" }
	local LANGUAGES = { "deDE", "frFR", "esES", "itIT", "ptBR" }
	local ADDONS = { "Memories" }

	local function read(path)
		local f = assert(io.open(path))
		local text = f:read("*a")
		f:close()
		return text
	end

	local function luaFiles(dir)
		local out = {}
		local p = assert(io.popen("find " .. dir .. " -name '*.lua' | sort"))
		for path in p:lines() do
			out[#out + 1] = path
		end
		p:close()
		return out
	end

	local function placeholders(text)
		local out = {}
		for spec in text:gmatch("%%[%-%d%.]*[%a%%]") do
			out[#out + 1] = spec
		end
		return table.concat(out, " ")
	end

	-- Runs Locales.lua and returns the table of every language, which the file keeps in a local.
	local function catalogs(addon)
		local source = read("addons/" .. addon .. "/Locales.lua")
		local patched, n = source:gsub("local found =", "ns.catalogs = T\nlocal found =", 1)
		assert.equal(1, n)
		local ns = {}
		assert(loadstring(patched, addon .. "/Locales.lua"))(addon, ns)
		return ns.catalogs
	end

	local function usedKeys(addon)
		local keys = {}
		for _, path in ipairs(luaFiles("addons/" .. addon)) do
			for key in read(path):gmatch('L%["(.-)"%]') do
				keys[key] = true
			end
		end
		return keys
	end

	local function loadLocales(locale)
		local saved = _G.GetLocale
		_G.GetLocale = function()
			return locale
		end
		local ns = {}
		local ok, err = pcall(assert(loadfile("addons/Memories/Locales.lua")), "Memories", ns)
		_G.GetLocale = saved
		assert(ok, err)
		return ns.L
	end

	describe("ns.L", function()
		it("answers in the language of the client", function()
			assert.equal("Speichererinnerung", loadLocales("deDE")["Save reminder"])
			assert.equal("Recordatorio de guardado", loadLocales("esES")["Save reminder"])
		end)

		it("uses Spanish for esMX", function()
			assert.equal("Recordatorio de guardado", loadLocales("esMX")["Save reminder"])
		end)

		it("answers in English for another locale", function()
			assert.equal("Save reminder", loadLocales("ruRU")["Save reminder"])
			assert.equal("Save reminder", loadLocales("enGB")["Save reminder"])
			assert.equal("Save reminder", loadLocales("zhCN")["Save reminder"])
		end)

		it("answers in English when GetLocale is missing or returns nothing", function()
			wow.boot({ login = false })
			local saved = _G.GetLocale
			finally(function()
				_G.GetLocale = saved
			end)
			local ns = {}
			_G.GetLocale = nil
			assert(loadfile("addons/Memories/Locales.lua"))("Memories", ns)
			assert.equal("Save reminder", ns.L["Save reminder"])
			_G.GetLocale = function() end
			ns = {}
			assert(loadfile("addons/Memories/Locales.lua"))("Memories", ns)
			assert.equal("Save reminder", ns.L["Save reminder"])
		end)

		it("answers with the key for a string that has no translation", function()
			local L = loadLocales("deDE")
			assert.equal("not a known string", L["not a known string"])
		end)
	end)

	describe("catalogs", function()
		for _, addon in ipairs(ADDONS) do
			describe(addon, function()
				local used = usedKeys(addon)
				local all = catalogs(addon)

				it("uses at least one string", function()
					assert.is_truthy(next(used))
				end)

				for _, lang in ipairs(LANGUAGES) do
					it("has in " .. lang .. " exactly the keys the code uses", function()
						local missing, extra = {}, {}
						for key in pairs(used) do
							if all[lang][key] == nil then
								missing[#missing + 1] = key
							end
						end
						for key in pairs(all[lang]) do
							if not used[key] then
								extra[#extra + 1] = key
							end
						end
						table.sort(missing)
						table.sort(extra)
						assert.same({}, missing)
						assert.same({}, extra)
					end)

					it("keeps the placeholders of each key in " .. lang, function()
						local bad = {}
						for key, text in pairs(all[lang]) do
							assert.is_string(text)
							assert.is_truthy(text ~= "")
							if placeholders(key) ~= placeholders(text) then
								bad[#bad + 1] = key
							end
						end
						table.sort(bad)
						assert.same({}, bad)
					end)
				end

				it("starts each translation with the machine translation note", function()
					local source = read("addons/" .. addon .. "/Locales.lua")
					local _, notes = source:gsub("%-%- Machine translated%. Corrections are welcome%.", "")
					assert.equal(#LANGUAGES, notes)
				end)

				it("uses the Spanish catalog for esMX", function()
					assert.equal(all.esES, all.esMX)
				end)
			end)
		end
	end)

	describe("TOC", function()
		for _, addon in ipairs(ADDONS) do
			it(addon .. " has a title and notes for each locale, after the plain lines", function()
				local order = {}
				for line in read("addons/" .. addon .. "/" .. addon .. ".toc"):gmatch("[^\r\n]+") do
					local key = line:match("^##%s*([^:]+):")
					if key then
						order[#order + 1] = key
					end
				end
				local function at(key)
					for i, k in ipairs(order) do
						if k == key then
							return i
						end
					end
				end
				for _, base in ipairs(PLAIN) do
					assert.is_truthy(at(base), base)
					for _, locale in ipairs(TOC_LOCALES) do
						local localized = at(base .. "-" .. locale)
						assert.is_truthy(localized, base .. "-" .. locale)
						assert.is_true(at(base) < localized)
					end
				end
			end)

			it(addon .. " lists Locales.lua first", function()
				assert.equal("addons/" .. addon .. "/Locales.lua", wow.read_toc(addon).files[1])
			end)
		end
	end)

	describe("surfaces in Spanish", function()
		local function boot(opts)
			opts = opts or {}
			opts.locale = opts.locale or "esES"
			return wow.boot(opts)
		end

		it("prints the status line in Spanish", function()
			boot()
			wow.chat_raw = {}
			SlashCmdList.MEMORIES("status")
			local lines = wow.chat()
			assert.equal("Memories: estado:", lines[1])
			assert.matches("^  Memories: activo, %d+ líneas, 0 tipos desactivados, sin copia$", lines[2])
			assert.matches("^  tiempo de inicio: init %d+ ms, login %d+ ms, world %d+ ms$", lines[#lines])
		end)

		it("prints the commands help in Spanish", function()
			boot()
			wow.chat_raw = {}
			SlashCmdList.MEMORIES("nothing")
			local lines = wow.chat()
			assert.equal("Memories: comandos:", lines[1])
			assert.equal("  /memories options - abrir la página de opciones", lines[3])
		end)

		it("prints the save reminder in Spanish", function()
			boot()
			wow.advance(60 * 60 + 60)
			local text = "Memories: 1 hora desde el último guardado. "
				.. "Haz clic en el botón del minimapa para guardar (recarga la interfaz)."
			local found = false
			for _, line in ipairs(wow.chat()) do
				found = found or line == text
			end
			assert.is_true(found)
		end)

		it("shows the minimap tooltip in Spanish", function()
			boot()
			MemoriesMinimapButton:GetScript("OnEnter")(MemoriesMinimapButton)
			assert.same({
				"Memories",
				"0 min desde el último guardado",
				"Clic izquierdo: guardar (recargar)",
				"Clic derecho: opciones",
			}, wow.tooltip.lines)
		end)

		it("asks about the low-health flash in Spanish", function()
			boot({ cvars = { doNotFlashLowHealthWarning = "1" } })
			local popup = wow.popups[#wow.popups]
			assert.equal("Mantener activado", popup.info.button1)
			assert.equal("Desactivarlo", popup.info.button2)
			assert.truthy(popup.info.text:find("Memories necesita esta opción activada", 1, true))
		end)

		it("asks about an empty journal in Spanish", function()
			local ns =
				boot({ saved = { MemoriesDB = { settings = { kinds = { ["in"] = false, pc = false, zo = false } } } } })
			ns.Store.Core():Write("ex", "test", "line", 1)
			ns.Backup.Write("Memories")
			local db = MemoriesDB
			boot({ saved = { MemoriesDB = db } })
			local popup
			for _, p in ipairs(wow.popups) do
				if p.which == "MEMORIES_GUARD" then
					popup = p
				end
			end
			assert.is_truthy(popup)
			assert.equal("Restaurar", popup.info.button1)
			assert.equal("Empezar de cero", popup.info.button2)
			assert.matches("^Memories: Memories volvió vacío%. Una copia de .* tiene %d+ líneas%.$", popup.text1)
		end)

		it("titles the groups of the Settings page in Spanish", function()
			boot()
			local headers = {}
			for _, item in ipairs(wow.categories[1].items) do
				if item.type == "header" then
					headers[#headers + 1] = item.name
				end
			end
			assert.same({
				"General",
				"Memories — Sesiones",
				"Memories — Progreso",
				"Memories — Muertes",
				"Memories — Viajes",
				"Memories — Mazmorras",
				"Memories — Capturas de pantalla",
				"Memories — Otros addons",
			}, headers)
		end)

		it("names every core kind in Spanish", function()
			local ns = boot()
			local spanish = {}
			for _, text in pairs(catalogs("Memories").esES) do
				spanish[text] = true
			end
			local english = {}
			for _, k in ipairs(ns.Kinds.All()) do
				if k.addon == "Memories" and not spanish[k.name] then
					english[#english + 1] = k.name
				end
			end
			assert.same({}, english)
		end)

		it("keeps the English group token in MemoriesDB.kinds", function()
			boot({ locale = "deDE" })
			assert.equal("Memories;Sessions;how", MemoriesDB.kinds["in"])
			assert.equal("Memories;Travel;from,to,#cost", MemoriesDB.kinds.tx)
		end)

		it("keeps the English note tokens in the journal", function()
			local ns = boot({ locale = "deDE", saved = { MemoriesCharDB = { char = { guid = "Player-OTHER" } } } })
			local found = false
			for line in ns.Store.Core():Lines() do
				found = found or line:find("|nt|new character|", 1, true) ~= nil
			end
			assert.is_true(found)
		end)
	end)
end)
