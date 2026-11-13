-- A stub of the WoW client for busted. It loads the real addons from their TOC files.
local serialize = require("helpers.serialize")

local wow = {}

wow.default_locale = "esES"

local real_time, real_date = os.time, os.date

local baseline = {}
for k in pairs(_G) do
	baseline[k] = true
end

local ADDON_DIRS = { "addons/", "spec/fixtures/addons/" }

local DEFAULT_PLAYER = {
	guid = "Player-1234-0ABCDEF0",
	name = "Kaelys",
	realm = "Brumamar",
	level = 10,
	class = { "Mage", "MAGE", 8 },
	race = { "Human", "Human", 1 },
	sex = 3,
	faction = { "Alliance", "Alliance" },
}

-- Spanish client values: the recorders must build their chat patterns from these, never from English text.
local DEFAULT_STRINGS = {
	COMBATLOG_XPGAIN_FIRSTPERSON = "%s muere, ganas %d p. de experiencia.",
	COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "Ganas %d p. de experiencia.",
	COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP = "Ganas %d p. de experiencia. (+%d bonif. grupo)",
	ERR_ZONE_EXPLORED = "Descubierto: %s.",
	ERR_ZONE_EXPLORED_XP = "Has descubierto %s: %d p. de experiencia ganados",
	ERR_SKILL_GAINED_S = "Has aprendido la habilidad %s.",
	ERR_FISH_ESCAPED = "¡El pez se ha escapado!",
	ERR_FISH_NOT_HOOKED = "No has pescado nada.",
	LOOT_ITEM_SELF = "Recibes botín: %s.",
	LOOT_ITEM_SELF_MULTIPLE = "Recibes botín: %sx%d.",
	LOOT_ITEM_PUSHED_SELF = "Recibes objeto: %s.",
	LOOT_ITEM_PUSHED_SELF_MULTIPLE = "Recibes objeto: %sx%d.",
	LOOT_ITEM_CREATED_SELF = "Creas: %s.",
	LOOT_ITEM_CREATED_SELF_MULTIPLE = "Creas: %sx%d.",
	LOOT_ROLL_NEED_SELF = "|HlootHistory:%d|h[Botín]|h: Has seleccionado Necesidad para: %s",
	LOOT_ROLL_GREED_SELF = "|HlootHistory:%d|h[Botín]|h: Has seleccionado Codicia para: %s",
	LOOT_ROLL_ROLLED_NEED = "|HlootHistory:%d|h[Botín]|h: Necesidad - %d para %s por %s",
	LOOT_ROLL_ROLLED_GREED = "|HlootHistory:%d|h[Botín]|h: Codicia - %d para %s por %s",
	LOOT_ROLL_YOU_WON = "|HlootHistory:%d|h[Botín]|h: Has ganado: %s",
	LOOT_ROLL_WON = "|HlootHistory:%d|h[Botín]|h: %s ha ganado: %s",
	LOOT_ROLL_ALL_PASSED = "|HlootHistory:%d|h[Botín]|h: Todos han pasado de: %s",
	ERR_TRADE_COMPLETE = "Comercio completado.",
	AUCTION_EXPIRED_MAIL_SUBJECT = "Subasta caducada: %s",
	AUCTION_OUTBID_MAIL_SUBJECT = "Puja superada: %s",
	ERR_LEARN_SPELL_S = "Has aprendido un nuevo hechizo: %s.",
	ERR_LEARN_ABILITY_S = "Has aprendido una nueva facultad: %s.",
	ERR_LEARN_RECIPE_S = "Has aprendido a crear un nuevo objeto: %s.",
	ERR_DEATHBIND_SUCCESS_S = "%s es ahora tu hogar.",
	ERR_NEWTAXIPATH = "Has descubierto una nueva ruta de vuelo.",
	FACTION_STANDING_LABEL1 = "Odiado",
	FACTION_STANDING_LABEL2 = "Hostil",
	FACTION_STANDING_LABEL3 = "Antipático",
	FACTION_STANDING_LABEL4 = "Neutral",
	FACTION_STANDING_LABEL5 = "Amistoso",
	FACTION_STANDING_LABEL6 = "Honorable",
	FACTION_STANDING_LABEL7 = "Reverenciado",
	FACTION_STANDING_LABEL8 = "Exaltado",
	DUEL_WINNER_KNOCKOUT = "%1$s ha derrotado a %2$s en un duelo.",
	DUEL_WINNER_RETREAT = "%2$s ha huido de %1$s en un duelo.",
	COMBATLOG_HONORGAIN = "%s muere, muerte con honor. Rango: %s (Puntos de honor estimados: %d)",
	COMBATLOG_HONORGAIN_NO_RANK = "%s muere, muerte con honor (Puntos de honor estimados: %d)",
	COMBATLOG_HONORAWARD = "Se te han concedido %d puntos de honor.",
	PVP_RANK_0_NAME = "Civil",
	UNKNOWNOBJECT = "Desconocido",
	PVP_RANK_6_1 = "Cabo",
	PVP_RANK_7_1 = "Sargento",
}

local function pack(...)
	return { n = select("#", ...), ... }
end

local function merge(base, over)
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	for k, v in pairs(over or {}) do
		out[k] = v
	end
	return out
end

-- Frames ---------------------------------------------------------------------

local Frame = {}
local function noop() end
local frame_mt = { __index = Frame }

-- Layout and look methods that the stub does not model.
for _, name in ipairs({
	"ClearAllPoints",
	"EnableMouse",
	"EnableMouseWheel",
	"RegisterForClicks",
	"RegisterForDrag",
	"SetAutoFocus",
	"SetClipsChildren",
	"SetDesaturated",
	"SetBlendMode",
	"SetFontObject",
	"SetFrameStrata",
	"SetHeight",
	"SetHighlightTexture",
	"SetJustifyH",
	"SetMovable",
	"SetMultiLine",
	"SetNormalTexture",
	"SetObeyStepOnDrag",
	"SetOrientation",
	"SetThumbTexture",
	"SetToplevel",
	"SetPushedTexture",
	"SetScrollChild",
	"SetWidth",
	"StartMoving",
	"StopMovingOrSizing",
}) do
	Frame[name] = noop
end

local function new_frame(kind, name, parent, template)
	local frame = setmetatable({
		kind = kind,
		name = name,
		parent = parent,
		template = template,
		events = {},
		scripts = {},
		shown = true,
	}, frame_mt)
	wow.frames[#wow.frames + 1] = frame
	if name then
		_G[name] = frame
	end
	return frame
end

function Frame:RegisterEvent(event)
	if wow.unknown_events[event] then
		error('Attempt to register unknown event "' .. event .. '"', 2)
	end
	self.events[event] = true
end

function Frame:RegisterUnitEvent(event, ...)
	self:RegisterEvent(event)
	self.units = self.units or {}
	self.units[event] = { ... }
end

function Frame:UnregisterEvent(event)
	self.events[event] = nil
end

function Frame:UnregisterAllEvents()
	self.events = {}
end

function Frame:IsEventRegistered(event)
	return self.events[event] == true
end

function Frame:SetScript(name, fn)
	self.scripts[name] = fn
end

function Frame:GetScript(name)
	return self.scripts[name]
end

-- A plain frame has no OnClick script, as in the client.
function Frame:HasScript(name)
	return name ~= "OnClick" or self.kind ~= "Frame"
end

function Frame:HookScript(name, fn)
	local orig = self.scripts[name]
	self.scripts[name] = function(...)
		if orig then
			orig(...)
		end
		fn(...)
	end
end

function Frame:Show()
	self.shown = true
	if self.scripts.OnShow then
		self.scripts.OnShow(self)
	end
end

function Frame:Hide()
	self.shown = false
	if self.scripts.OnHide then
		self.scripts.OnHide(self)
	end
end

function Frame:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end

function Frame:IsShown()
	return self.shown
end

function Frame:GetName()
	return self.name
end

function Frame:GetParent()
	return self.parent
end

function Frame:SetText(text)
	self.text = text
end

function Frame:GetText()
	return self.text
end

function Frame:SetFocus()
	self.focused = true
	if self.scripts.OnEditFocusGained then
		self.scripts.OnEditFocusGained(self)
	end
end

function Frame:ClearFocus()
	self.focused = false
	if self.scripts.OnEditFocusLost then
		self.scripts.OnEditFocusLost(self)
	end
end

function Frame:HasFocus()
	return self.focused == true
end

function Frame:SetMaxBytes(n)
	self.maxBytes = n
end

function Frame:Insert(text)
	self.text = (self.text or "") .. text
end

function Frame:HighlightText()
	self.highlighted = true
end

function Frame:GetCenter()
	return unpack(self.center or { 0, 0 })
end

function Frame:GetWidth()
	return self.width or (self.size and self.size[1]) or 0
end

function Frame:GetEffectiveScale()
	return self.scale or 1
end

function Frame:SetPoint(...)
	self.point = pack(...)
end

function Frame:CreateTexture(name, layer)
	local texture = new_frame("Texture", name, self)
	texture.layer = layer
	self.textures = self.textures or {}
	self.textures[#self.textures + 1] = texture
	return texture
end

function Frame:SetTexture(path)
	self.texture = path
end

function Frame:CreateLine(name)
	local line = new_frame("Line", name, self)
	self.lines = self.lines or {}
	self.lines[#self.lines + 1] = line
	return line
end

function Frame:SetStartPoint(...)
	self.startPoint = pack(...)
end

function Frame:SetEndPoint(...)
	self.endPoint = pack(...)
end

function Frame:SetColorTexture(...)
	self.color = pack(...)
end

function Frame:SetMouseClickEnabled(on)
	self.mouseClickEnabled = on
end

function Frame:SetFrameLevel(level)
	self.frameLevel = level
end

function Frame:SetAllPoints(target)
	self.allPoints = target or self.parent
end

function Frame:SetAlpha(alpha)
	self.alpha = alpha
end

function Frame:SetScale(scale)
	self.scale = scale
end

function Frame:SetTextColor(...)
	self.textColor = pack(...)
end

function Frame:SetVertexColor(...)
	self.vertexColor = pack(...)
end

function Frame:SetTexCoord(...)
	self.texCoord = { ... }
end

function Frame:SetRotation(angle)
	self.rotation = angle
end

function Frame:SetThickness(thickness)
	self.thickness = thickness
end

function Frame:GetFrameLevel()
	return self.frameLevel or 1
end

function Frame:GetLeft()
	return self.left
end

function Frame:GetTop()
	return self.topEdge
end

function Frame:GetBottom()
	return self.bottom
end

function Frame:GetVerticalScroll()
	return self.verticalScroll or 0
end

function Frame:SetVerticalScroll(offset)
	self.verticalScroll = offset
	if self.scripts.OnVerticalScroll then
		self.scripts.OnVerticalScroll(self, offset)
	end
end

function Frame:SetClampedToScreen(on)
	self.clamped = on == true
end

function Frame:SetEnabled(on)
	self.enabled = on == true
end

function Frame:SetMinMaxValues(lo, hi)
	self.range = { lo, hi }
end

function Frame:SetValue(value)
	self.value = value
end

function Frame:GetValue()
	return self.value
end

function Frame:SetChecked(on)
	self.checked = on == true
end

function Frame:GetChecked()
	return self.checked == true
end

function Frame:SetSize(w, h)
	self.size = { w, h }
end

function Frame:GetSize()
	local size = self.size or { 0, 0 }
	return size[1], size[2]
end

function Frame:CreateFontString(name)
	return new_frame("FontString", name, self)
end

-- Timers ---------------------------------------------------------------------

local function install_timers()
	wow.timers = {}
	local seq = 0
	local function add(delay, fn, interval, iterations)
		seq = seq + 1
		local timer = {
			due = wow.clock + delay,
			fn = fn,
			seq = seq,
			interval = interval,
			left = iterations,
			cancelled = false,
		}
		function timer:Cancel()
			self.cancelled = true
		end
		function timer:IsCancelled()
			return self.cancelled
		end
		wow.timers[#wow.timers + 1] = timer
		return timer
	end
	_G.C_Timer = {
		After = function(delay, fn)
			add(delay, function()
				fn()
			end)
		end,
		NewTimer = function(delay, fn)
			return add(delay, fn)
		end,
		NewTicker = function(interval, fn, iterations)
			return add(interval, fn, interval, iterations)
		end,
	}
end

local function next_timer(target)
	local found
	for _, timer in ipairs(wow.timers) do
		if not timer.cancelled and not timer.done and timer.due <= target then
			if not found or timer.due < found.due or (timer.due == found.due and timer.seq < found.seq) then
				found = timer
			end
		end
	end
	return found
end

function wow.advance(seconds)
	local target = wow.clock + seconds
	while true do
		local timer = next_timer(target)
		if not timer then
			break
		end
		wow.wall = wow.wall + (timer.due - wow.clock)
		wow.clock = timer.due
		if timer.interval then
			if timer.left then
				timer.left = timer.left - 1
			end
			if timer.left == 0 then
				timer.done = true
			else
				timer.due = timer.due + timer.interval
			end
		else
			timer.done = true
		end
		timer.fn(timer)
	end
	wow.wall = wow.wall + (target - wow.clock)
	wow.clock = target
end

-- Encoding -------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do
	B64_INDEX[B64:sub(i, i)] = i - 1
end

local function b64_encode(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local q = {
			math.floor(n / 262144) % 64,
			math.floor(n / 4096) % 64,
			math.floor(n / 64) % 64,
			n % 64,
		}
		out[#out + 1] = B64:sub(q[1] + 1, q[1] + 1)
			.. B64:sub(q[2] + 1, q[2] + 1)
			.. (b and B64:sub(q[3] + 1, q[3] + 1) or "=")
			.. (c and B64:sub(q[4] + 1, q[4] + 1) or "=")
	end
	return table.concat(out)
end

local function b64_decode(s)
	assert(#s % 4 == 0, "bad base64 length")
	local out = {}
	for i = 1, #s, 4 do
		local n, pad = 0, 0
		for j = i, i + 3 do
			local ch = s:sub(j, j)
			if ch == "=" then
				pad = pad + 1
				n = n * 64
			else
				local v = B64_INDEX[ch]
				assert(v and pad == 0, "bad base64 character")
				n = n * 64 + v
			end
		end
		local bytes = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
		out[#out + 1] = bytes:sub(1, 3 - pad)
	end
	return table.concat(out)
end

local COMPRESSED = "stub-deflate:"

local function install_encoding()
	_G.Enum = {
		CompressionMethod = { Deflate = 0, Zlib = 1 },
		CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 },
		FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 },
	}
	-- A reversible stand-in: CBOR becomes Lua table text and compression only adds a marker.
	_G.C_EncodingUtil = {
		SerializeCBOR = function(v)
			return serialize.value(v)
		end,
		DeserializeCBOR = function(s)
			return assert(loadstring("return " .. s, "=cbor"))()
		end,
		CompressString = function(s)
			return COMPRESSED .. s
		end,
		DecompressString = function(s)
			assert(s:sub(1, #COMPRESSED) == COMPRESSED, "not compressed data")
			return s:sub(#COMPRESSED + 1)
		end,
		EncodeBase64 = b64_encode,
		DecodeBase64 = b64_decode,
	}
end

-- Settings -------------------------------------------------------------------

-- Stubs of the client's Settings API with the argument checks of Blizzard_Settings.lua and Blizzard_Setting.lua.
-- wow.categories holds each category with its layout items and its settings by variable; wow.settings_calls records
-- every call. wow.settings_fail[name] = message makes that function raise.
local function install_settings()
	wow.categories = {}
	wow.settings_calls = {}
	wow.settings_fail = {}
	wow.opened = nil
	local variables = {}

	local function new_layout(category)
		return {
			AddInitializer = function(_, initializer)
				category.items[#category.items + 1] = initializer
			end,
			GetInitializers = function()
				return category.items
			end,
		}
	end

	local Setting = {}
	Setting.__index = Setting
	function Setting:GetValue()
		return self.tbl[self.key]
	end
	function Setting:GetDefaultValue()
		return self.default
	end
	function Setting:GetVariable()
		return self.variable
	end
	function Setting:GetVariableType()
		return self.varType
	end
	function Setting:GetName()
		return self.name
	end
	function Setting:NotifyUpdate()
		self.notified = (self.notified or 0) + 1
		self:TriggerValueChanged(self:GetValue())
	end
	function Setting:TriggerValueChanged(value)
		for _, fn in ipairs(self.callbacks) do
			fn(self, value)
		end
	end
	function Setting:SetValue(value)
		if self.tbl[self.key] ~= value then
			if type(value) ~= self.varType then
				error(("SetValue '%s' requires '%s' type, not '%s' type."):format(self.name, self.varType, type(value)))
			end
			self.tbl[self.key] = value
		end
		self:TriggerValueChanged(value)
	end
	function Setting:SetValueChangedCallback(fn)
		self.callbacks[#self.callbacks + 1] = fn
	end

	local function add(category, initializer)
		category.items[#category.items + 1] = initializer
		return initializer
	end

	local api = {
		VarType = { Boolean = "boolean", String = "string", Number = "number" },
		Default = { True = true, False = false },
		RegisterVerticalLayoutCategory = function(name)
			local category = { name = name, items = {}, settings = {}, id = #wow.categories + 1 }
			function category:GetID()
				return self.id
			end
			function category:GetName()
				return self.name
			end
			category.layout = new_layout(category)
			wow.categories[#wow.categories + 1] = category
			return category, category.layout
		end,
		RegisterAddOnCategory = function(category)
			category.registered = true
		end,
		RegisterAddOnSetting = function(category, variable, key, tbl, varType, name, default)
			if type(name) ~= "string" then
				error(("'name' for variable '%s' requires string type."):format(tostring(variable)))
			end
			if type(variable) ~= "string" then
				error(("'variable' for '%s' requires string type."):format(name))
			end
			if type(varType) ~= "string" then
				error(("'variableType' for '%s', '%s' requires string type."):format(name, variable))
			end
			if default ~= nil and type(default) ~= varType then
				error(("'defaultValue' argument for '%s', '%s' doesn't match."):format(name, variable))
			end
			assert(type(tbl) == "table", "'variableTbl' argument must be a table.")
			assert(not variables[variable], "variable " .. variable .. " registered twice")
			variables[variable] = true
			if tbl[key] == nil then
				tbl[key] = default
			end
			local setting = setmetatable({
				category = category,
				variable = variable,
				key = key,
				tbl = tbl,
				varType = varType,
				name = name,
				default = default,
				callbacks = {},
			}, Setting)
			category.settings[variable] = setting
			return setting
		end,
		CreateCheckbox = function(category, setting, tooltip)
			return add(category, { type = "checkbox", setting = setting, tooltip = tooltip })
		end,
		CreateSlider = function(category, setting, options, tooltip)
			assert(setting.varType == "number" and options ~= nil)
			return add(category, { type = "slider", setting = setting, options = options, tooltip = tooltip })
		end,
		CreateDropdown = function(category, setting, options, tooltip)
			assert(options ~= nil)
			return add(category, { type = "dropdown", setting = setting, options = options, tooltip = tooltip })
		end,
		CreateSliderOptions = function(min, max, rate)
			return { minValue = min or 0, maxValue = max or 1, steps = rate and (max - min) / rate or 100 }
		end,
		CreateControlTextContainer = function()
			local container = { data = {} }
			function container:Add(value, label, tooltip)
				self.data[#self.data + 1] = { value = value, label = label, tooltip = tooltip }
			end
			function container:GetData()
				return self.data
			end
			return container
		end,
		OpenToCategory = function(categoryID, scrollToElementName)
			wow.opened = categoryID
			wow.opened_element = scrollToElementName
		end,
	}

	local function wrap(name, fn)
		return function(...)
			wow.settings_calls[#wow.settings_calls + 1] = { name = name, args = pack(...) }
			if wow.settings_fail[name] then
				error(wow.settings_fail[name], 2)
			end
			return fn(...)
		end
	end

	_G.Settings = {}
	for name, v in pairs(api) do
		_G.Settings[name] = type(v) == "function" and wrap(name, v) or v
	end
	_G.SettingsPanel = {
		GetLayout = function(_, category)
			return category.layout
		end,
	}
	_G.CreateSettingsListSectionHeaderInitializer = wrap(
		"CreateSettingsListSectionHeaderInitializer",
		function(name, tooltip, newTagID)
			return { type = "header", name = name, tooltip = tooltip, newTagID = newTagID }
		end
	)
	_G.CreateSettingsButtonInitializer = wrap(
		"CreateSettingsButtonInitializer",
		function(name, buttonText, buttonClick, tooltip, addSearchTags)
			assert(addSearchTags ~= nil)
			return {
				type = "button",
				name = name,
				buttonText = buttonText,
				click = buttonClick,
				tooltip = tooltip,
				addSearchTags = addSearchTags,
			}
		end
	)
end

-- Units, maps and add-ons ----------------------------------------------------

local function unit(u)
	if u == "player" then
		return wow.player
	end
	return wow.units[u]
end

local function unit_values(field)
	return function(u)
		local data = unit(u)
		if data and data[field] then
			return unpack(data[field])
		end
	end
end

local function unit_value(field)
	return function(u)
		local data = unit(u)
		return data and data[field]
	end
end

local function install_units()
	_G.UnitGUID = unit_value("guid")
	-- Forever gives a stranger's surname as the second value.
	_G.UnitName = function(u)
		local data = unit(u)
		if data then
			return data.name, data.surname
		end
	end
	_G.UnitLevel = unit_value("level")
	_G.UnitSex = unit_value("sex")
	_G.UnitClass = unit_values("class")
	_G.UnitRace = unit_values("race")
	_G.UnitFactionGroup = unit_values("faction")
	_G.UnitExists = function(u)
		return unit(u) ~= nil
	end
	_G.UnitIsUnit = function(a, b)
		local data = unit(a)
		return data ~= nil and data == unit(b)
	end
	-- A unit of opts.units attacks and can be attacked when it has hostile = true.
	_G.UnitCanAttack = function(_, u)
		local data = unit(u)
		return data ~= nil and data.hostile == true
	end
	_G.GetRealmName = function()
		return wow.player.realm
	end
	_G.IsInInstance = function()
		return wow.instance ~= nil, wow.instance and wow.instance.type or "none"
	end
	_G.GetInstanceInfo = function()
		local i = wow.instance
		if not i then
			return GetRealZoneText(), "none", 0, "", 0, 0, false, 0, 0
		end
		return i.name, i.type, i.difficulty or 1, "", i.size or 5, 0, false, i.id or 0, 0
	end
	_G.GetRealZoneText = function()
		return wow.zone
	end
	_G.GetZoneText = function()
		return wow.zone
	end
	_G.GetSubZoneText = function()
		return wow.subzone
	end
	_G.UnitIsPlayer = unit_value("isPlayer")
	-- wow.world holds the world yards and the instance id that UnitPosition reports.
	_G.UnitPosition = function(u)
		if u == "player" and wow.world then
			return wow.world.y, wow.world.x, 0, wow.world.inst
		end
	end
	-- Another unit has the flag when its entry of opts.units has the field set to true.
	local function flag(name)
		return function(u)
			if u == nil or u == "player" then
				return wow.flags[name] or false
			end
			local data = wow.units[u]
			return data ~= nil and data[name] == true
		end
	end
	_G.UnitOnTaxi = flag("taxi")
	_G.IsFlying = flag("flying")
	_G.IsMounted = flag("mounted")
	_G.UnitIsGhost = flag("ghost")
	_G.UnitIsDead = flag("dead")
	_G.IsSwimming = flag("swimming")
	_G.IsPlayerMoving = flag("moving")
	_G.UnitIsAFK = flag("afk")
	_G.GetXPExhaustion = function()
		return wow.rested
	end
	_G.RequestTimePlayed = function()
		wow.played_asks = wow.played_asks + 1
	end
	_G.JumpOrAscendStart = function()
		wow.jumps = wow.jumps + 1
	end
	_G.C_QuestLog = {
		GetTitleForQuestID = function(id)
			return wow.quests[id]
		end,
	}
	if wow.rules then
		_G.C_GameRules = {
			IsHardcoreActive = function()
				return wow.rules.hardcore
			end,
			IsSelfFoundAllowed = function()
				return wow.rules.selfFound
			end,
		}
	end
	_G.InCombatLockdown = function()
		return wow.combat
	end
	_G.UnitIsDeadOrGhost = function(u)
		return flag("dead")(u) or flag("ghost")(u)
	end
	-- wow.flags.combat stands for UnitAffectingCombat; wow.combat for InCombatLockdown.
	_G.UnitAffectingCombat = flag("combat")
	_G.UnitClassification = unit_value("classification")
	_G.UnitPlayerControlled = flag("controlled")
	_G.UnitIsTapDenied = flag("tapDenied")
	-- creatureType is { name, id }.
	_G.UnitCreatureType = unit_values("creatureType")
	-- threat and petThreat are the threat states of the player and of the pet on the unit.
	_G.UnitThreatSituation = function(who, u)
		local data = unit(u)
		if data then
			return who == "pet" and data.petThreat or who == "player" and data.threat or nil
		end
	end
	local function vector(x, y)
		return {
			x = x,
			y = y,
			GetXY = function(self)
				return self.x, self.y
			end,
		}
	end
	_G.CreateVector2D = vector
	_G.C_Map = {
		GetBestMapForUnit = function(u)
			if u == "player" then
				return wow.map.id
			end
		end,
		GetPlayerMapPosition = function(mapID, u)
			if u ~= "player" or mapID ~= wow.map.id or wow.map.x == nil then
				return nil
			end
			return {
				GetXY = function()
					return wow.map.x, wow.map.y
				end,
			}
		end,
		GetMapInfo = function(mapID)
			return wow.maps[mapID]
		end,
		-- A map of wow.maps has art: one layer of 1002 x 668 in tiles of 256, unless wow.art[map] says otherwise
		-- (false for none).
		GetMapArtLayers = function(mapID)
			local art = wow.art[mapID]
			if art == false or (art == nil and not wow.maps[mapID]) then
				return {}
			end
			return { art or { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } }
		end,
		GetMapArtLayerTextures = function(mapID)
			local out = {}
			for i = 1, 12 do
				out[i] = mapID * 100 + i
			end
			return out
		end,
		-- wow.zoneAt(mapID, x, y) gives the map under a point of a map.
		GetMapInfoAtPosition = function(mapID, x, y)
			local id = wow.zoneAt and wow.zoneAt(mapID, x, y)
			return id and { mapID = id, name = "Zone " .. id } or nil
		end,
		-- wow.projections[map] = { continent, x0, y0, x1, y1 }: the rectangle of the map in world units.
		GetWorldPosFromMapPos = function(mapID, v)
			local r = wow.projections[mapID]
			if not r then
				return nil
			end
			local x, y = v:GetXY()
			return r.continent, vector(r.x0 + x * (r.x1 - r.x0), r.y0 + y * (r.y1 - r.y0))
		end,
		GetMapPosFromWorldPos = function(continent, v, mapID)
			local r = wow.projections[mapID]
			if not r or r.continent ~= continent then
				return nil
			end
			local x, y = v:GetXY()
			return mapID, vector((x - r.x0) / (r.x1 - r.x0), (y - r.y0) / (r.y1 - r.y0))
		end,
	}
end

local function addon_info(name)
	local state = wow.addon_state[name]
	local toc = wow.tocs_by_name[name]
	local meta = toc and toc.meta or {}
	return state, meta
end

local function install_addons()
	_G.C_AddOns = {
		GetAddOnInfo = function(name)
			local state, meta = addon_info(name)
			if state == "loaded" or state == "enabled" then
				return name, meta.Title, meta.Notes, true, nil, "INSECURE"
			elseif state == "disabled" then
				return name, meta.Title, meta.Notes, false, "DISABLED", "INSECURE"
			end
			return name, nil, nil, false, "MISSING", "INSECURE"
		end,
		IsAddOnLoaded = function(name)
			local loaded = wow.addon_state[name] == "loaded"
			return loaded, loaded
		end,
		GetAddOnEnableState = function(name)
			local state = wow.addon_state[name]
			return (state == "loaded" or state == "enabled") and 2 or 0
		end,
		GetAddOnMetadata = function(name, field)
			local _, meta = addon_info(name)
			return meta[field]
		end,
		LoadAddOn = function(name)
			local state = wow.addon_state[name]
			if state == "loaded" then
				return true
			end
			return false, state == "disabled" and "DISABLED" or "MISSING"
		end,
	}
end

-- Deaths and CVars -----------------------------------------------------------

-- wow.recap is the death recap list of C_DeathRecap; wow.res counts the revive calls; wow.cvars holds the CVars, and
-- wow.cvar_fail.get or .set makes that call raise. SetCVar fires CVAR_UPDATE at once, as the client does.
local function install_deaths()
	wow.recap = wow.opts.recap
	_G.C_DeathRecap = {
		HasRecapEvents = function()
			return wow.recap ~= nil and #wow.recap > 0
		end,
		GetRecapEvents = function()
			return wow.recap or {}
		end,
	}
	wow.res = { accept = 0, corpse = 0, self = 0 }
	_G.AcceptResurrect = function()
		wow.res.accept = wow.res.accept + 1
	end
	_G.RetrieveCorpse = function()
		wow.res.corpse = wow.res.corpse + 1
	end
	_G.C_DeathInfo = {
		UseSelfResurrectOption = function()
			wow.res.self = wow.res.self + 1
		end,
	}
	wow.panels = {}
	_G.GetUIPanel = function(key)
		return wow.panels[key]
	end
	wow.cvars = merge({ doNotFlashLowHealthWarning = "0" }, wow.opts.cvars)
	wow.cvar_fail = {}
	wow.cvar_sets = {}
	local function get(name)
		if wow.cvar_fail.get then
			error(wow.cvar_fail.get, 2)
		end
		return wow.cvars[name]
	end
	local function set(name, value)
		if wow.cvar_fail.set then
			error(wow.cvar_fail.set, 2)
		end
		value = tostring(value)
		wow.cvars[name] = value
		wow.cvar_sets[#wow.cvar_sets + 1] = { name, value }
		wow.fire("CVAR_UPDATE", name, value)
		return true
	end
	_G.C_CVar = { GetCVar = get, SetCVar = set }
	_G.GetCVar, _G.SetCVar = get, set
end

-- Travel ---------------------------------------------------------------------

-- wow.taxi is the flight master's node list: { name, type ("CURRENT", "REACHABLE", ...), cost }; wow.taxi_map holds
-- the C_TaxiMap.GetAllTaxiNodes entries and wow.taken the slots of TakeTaxiNode. wow.summon = { who, area } is the
-- open summon; wow.mounts maps a mount id to { name, spell, active }; wow.skill_lines maps a skill line id to its name.
local function install_travel()
	wow.taxi = wow.opts.taxi or {}
	wow.taxi_map = {}
	wow.taken = {}
	wow.summon = {}
	wow.summons = 0
	wow.mounts = wow.opts.mounts or {}
	wow.skill_lines = wow.opts.skillLines or {}
	wow.bind = wow.opts.bind
	wow.region = wow.opts.region
	wow.locale = wow.opts.locale or wow.default_locale
	_G.NumTaxiNodes = function()
		return #wow.taxi
	end
	local function node(field)
		return function(i)
			return wow.taxi[i] and wow.taxi[i][field]
		end
	end
	_G.TaxiNodeGetType = function(i)
		return wow.taxi[i] and wow.taxi[i].type or "NONE"
	end
	_G.TaxiNodeName = node("name")
	_G.TaxiNodeCost = node("cost")
	_G.TakeTaxiNode = function(slot)
		wow.taken[#wow.taken + 1] = slot
	end
	_G.C_TaxiMap = {
		GetAllTaxiNodes = function()
			return wow.taxi_map
		end,
	}
	_G.C_SummonInfo = {
		GetSummonConfirmSummoner = function()
			return wow.summon.who
		end,
		GetSummonConfirmAreaName = function()
			return wow.summon.area
		end,
		ConfirmSummon = function()
			wow.summons = wow.summons + 1
		end,
	}
	_G.C_MountJournal = {
		GetMountFromSpell = function(spell)
			for id, m in pairs(wow.mounts) do
				if m.spell == spell then
					return id
				end
			end
		end,
		GetMountInfoByID = function(id)
			local m = wow.mounts[id]
			if m then
				return m.name, m.spell, 0, m.active == true, true, 0, false, false, nil, false, true, id, false
			end
		end,
		GetMountIDs = function()
			local ids = {}
			for id in pairs(wow.mounts) do
				ids[#ids + 1] = id
			end
			table.sort(ids)
			return ids
		end,
	}
	_G.C_SkillInfo = {
		GetSkillLineInfoByID = function(id)
			local name = wow.skill_lines[id]
			if name then
				return { skillID = id, name = name }
			end
		end,
	}
	_G.GetBindLocation = function()
		return wow.bind
	end
	_G.GetCurrentRegion = function()
		return wow.region
	end
	_G.GetLocale = function()
		return wow.locale
	end
end

-- Fires the player's UNIT_SPELLCAST_SUCCEEDED for spell.
function wow.cast(spell)
	wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-" .. tostring(spell) .. "-0", spell)
end

-- Loot -----------------------------------------------------------------------

-- wow.loot is the open loot window: { fishing, slots = { { money = true } or { item, name, count, quality, quest } } };
-- a slot's source is the GUID that GetLootSourceInfo answers. wow.bags[bag][slot] is the C_Container item info
-- ({ itemID, hasLoot, itemName }) and wow.items the C_Item names by id.
local function install_loot()
	wow.loot = { slots = {} }
	wow.bags = {}
	wow.items = {}
	local function slot(i)
		return wow.loot.slots[i]
	end
	_G.GetNumLootItems = function()
		return #wow.loot.slots
	end
	_G.GetLootSlotType = function(i)
		local s = slot(i)
		return s and (s.money and 2 or 1) or 0
	end
	_G.GetLootSlotInfo = function(i)
		local s = slot(i)
		if not s then
			return nil
		end
		return 134400, s.name, s.count or 1, nil, s.quality, false, s.quest == true, nil, false, s.money == true
	end
	_G.GetLootSlotLink = function(i)
		local s = slot(i)
		if s and s.item then
			return "|cffffffff|Hitem:" .. s.item .. "::::::::10:::::|h[" .. tostring(s.name) .. "]|h|r"
		end
	end
	_G.GetLootSourceInfo = function(i)
		local s = slot(i)
		if s and s.source then
			return s.source, s.count or 1
		end
	end
	_G.IsFishingLoot = function()
		return wow.loot.fishing == true
	end
	_G.C_Container = {
		GetContainerItemInfo = function(bag, i)
			return (wow.bags[bag] or {})[i]
		end,
		UseContainerItem = noop,
	}
	_G.C_Item = {
		GetItemNameByID = function(id)
			return wow.items[id]
		end,
	}
end

-- Economy ------------------------------------------------------------------

-- wow.money is the gold (wow.set_money fires PLAYER_MONEY); wow.gear[slot] = { id, quality } the worn items;
-- wow.item_info[id] = { quality, class, sub, equipLoc }; wow.merchant[index] = { name, id }; wow.trainer = { services =
-- { { name, type, sub, skill, cost } }, tradeskill }; wow.auctions[id] the C_AuctionHouse auction info and
-- wow.legacy_auctions[index] = { name, buyout }, wow.sell_item the legacy sell slot name; wow.inbox is a list of
-- mails { sender, subject, money, days, canReply, isGM, items = { [slot] = { id, name, count, quality } }, invoice =
-- { type, item, player } } and wow.inbox_fail makes GetInboxNumItems answer nil; wow.send_mail = { money, item };
-- wow.trade = { items = { [slot] = { id, name, count, quality } }, money, given }. The game actions are no-ops that
-- the recorders hook.
local function install_economy()
	wow.money = wow.opts.money or 0
	wow.gear = {}
	wow.item_info = {}
	wow.merchant = {}
	wow.trainer = { services = {} }
	wow.auctions = {}
	wow.legacy_auctions = {}
	wow.inbox = {}
	wow.send_mail = { money = 0 }
	wow.trade = { items = {}, money = 0, given = 0 }
	_G.GetMoney = function()
		return wow.money
	end
	_G.GetInventoryItemID = function(u, slot)
		return u == "player" and wow.gear[slot] and wow.gear[slot].id or nil
	end
	_G.GetInventoryItemQuality = function(u, slot)
		return u == "player" and wow.gear[slot] and wow.gear[slot].quality or nil
	end
	_G.C_Item.GetItemQualityByID = function(id)
		return wow.item_info[id] and wow.item_info[id].quality
	end
	_G.C_Item.GetItemInfoInstant = function(id)
		local info = wow.item_info[id]
		if info then
			return id, nil, nil, info.equipLoc, 134400, info.class, info.sub or 0
		end
	end
	_G.C_Item.GetItemName = function(location)
		return location and location.name
	end
	for _, name in ipairs({
		"RepairAllItems",
		"ConfirmTalentWipe",
		"BuyMerchantItem",
		"UseContainerItem",
		"BuyTrainerService",
		"PlaceAuctionBid",
		"PostAuction",
		"StartAuction",
		"SendMail",
		"TakeInboxMoney",
		"TakeInboxItem",
		"AutoLootMailItem",
	}) do
		_G[name] = noop
	end
	_G.GetMerchantItemInfo = function(i)
		return wow.merchant[i] and wow.merchant[i].name
	end
	_G.GetMerchantItemID = function(i)
		return wow.merchant[i] and wow.merchant[i].id
	end
	_G.GetNumTrainerServices = function()
		return #wow.trainer.services
	end
	_G.GetTrainerServiceInfo = function(i)
		local s = wow.trainer.services[i]
		if s then
			return s.name, s.type or "available", 134400, 1, s.sub
		end
	end
	_G.GetTrainerServiceCost = function(i)
		local s = wow.trainer.services[i]
		return s and s.cost, wow.trainer.tradeskill == true
	end
	_G.GetTrainerServiceSkillLine = function(i)
		return wow.trainer.services[i] and wow.trainer.services[i].skill
	end
	_G.IsTradeskillTrainer = function()
		return wow.trainer.tradeskill == true
	end
	_G.C_AuctionHouse = {
		PlaceBid = noop,
		PostItem = noop,
		PostCommodity = noop,
		ConfirmCommoditiesPurchase = noop,
		GetAuctionInfoByID = function(id)
			return wow.auctions[id]
		end,
	}
	_G.GetAuctionItemInfo = function(_, i)
		local a = wow.legacy_auctions[i]
		if a then
			return a.name, 134400, 1, 2, true, 10, "", 100, 10, a.buyout
		end
	end
	_G.GetAuctionSellItemInfo = function()
		return wow.sell_item
	end
	_G.GetInboxNumItems = function()
		if wow.inbox_fail then
			return nil
		end
		return #wow.inbox, #wow.inbox
	end
	_G.GetInboxHeaderInfo = function(i)
		local m = wow.inbox[i]
		if m then
			local items = 0
			for _ in pairs(m.items or {}) do
				items = items + 1
			end
			return nil,
				nil,
				m.sender,
				m.subject,
				m.money or 0,
				0,
				m.days or 30,
				items,
				false,
				false,
				false,
				m.canReply,
				m.isGM
		end
	end
	_G.GetInboxItem = function(i, slot)
		local item = wow.inbox[i] and (wow.inbox[i].items or {})[slot]
		if item then
			return item.name, item.id, 134400, item.count or 1, item.quality, true
		end
	end
	_G.GetInboxInvoiceInfo = function(i)
		local inv = wow.inbox[i] and wow.inbox[i].invoice
		if inv then
			return inv.type, inv.item, inv.player
		end
	end
	_G.GetSendMailMoney = function()
		return wow.send_mail.money
	end
	_G.GetSendMailItem = function(i)
		local item = i == 1 and wow.send_mail.item
		if item then
			return item, 0, 134400, 1, 1
		end
	end
	_G.GetTradeTargetItemLink = function(slot)
		local item = wow.trade.items[slot]
		if item and item.id then
			return "|cffffffff|Hitem:" .. item.id .. "::::::::10:::::|h[" .. tostring(item.name) .. "]|h|r"
		end
	end
	_G.GetTradeTargetItemInfo = function(slot)
		local item = wow.trade.items[slot]
		if item then
			return item.name, 134400, item.count or 1, item.quality, true, nil
		end
	end
	_G.GetTargetTradeMoney = function()
		return wow.trade.money
	end
	_G.GetPlayerTradeMoney = function()
		return wow.trade.given
	end
end

-- Character --------------------------------------------------------------------

-- wow.skills is the skill pane: rows { name, header, collapsed, rank, max, id }; wow.trade_skills maps a skill line id
-- to its display name and wow.trade_open is the open trade window's profession name. wow.talents = { config, spec,
-- specs = { spec ids }, trees = { [spec id] = { tree, nodes = { ranks per node } } }, unspent }. wow.auras is the
-- player's helpful auras { name, spellId, sourceUnit }; wow.auras_secret answers C_Secrets.ShouldAurasBeSecret and
-- wow.aura_error makes each aura read raise. wow.form is the shapeshift index and wow.forms[index] its spell id;
-- wow.totems[slot] a totem name. wow.factions[id] = { name, reaction, currentStanding }; wow.item_text the open book's
-- title; wow.stats = { { category, { { id, value } } } } the Statistics pane; wow.channel = { spell, start, stop } the
-- player's channel in GetTime() seconds.
local function install_character()
	wow.skills = wow.opts.skills or {}
	wow.trade_skills = wow.opts.tradeSkills or {}
	wow.trade_open = nil
	wow.talents = wow.opts.talents
	wow.auras = {}
	wow.auras_secret = false
	wow.aura_error = nil
	wow.form = 0
	wow.forms = {}
	wow.totems = {}
	wow.factions = {}
	wow.item_text = nil
	wow.stats = wow.opts.stats
	wow.channel = nil
	_G.UnitChannelInfo = function(u)
		local c = wow.channel
		if u == "player" and c then
			return "Channel", "Channel", 134400, c.start * 1000, c.stop * 1000, false, false, c.spell
		end
	end
	_G.C_SkillInfo.GetNumSkillLines = function()
		return #wow.skills
	end
	_G.C_SkillInfo.GetSkillLineInfo = function(i)
		local row = wow.skills[i]
		if row then
			return {
				skillID = row.id or 0,
				name = row.name,
				isHeader = row.header == true,
				isCollapsed = row.collapsed == true,
				rank = row.rank or 0,
				maxRank = row.max or 0,
			}
		end
	end
	_G.C_TradeSkillUI = {
		GetTradeSkillDisplayName = function(id)
			return wow.trade_skills[id] or ""
		end,
		GetBaseProfessionInfo = function()
			return { professionName = wow.trade_open }
		end,
	}
	_G.C_Container.GetContainerNumSlots = function(bag)
		local n = 0
		for slot in pairs(wow.bags[bag] or {}) do
			n = math.max(n, slot)
		end
		return n
	end
	_G.C_UnitAuras = {
		GetAuraDataByIndex = function(u, i)
			if wow.aura_error then
				error(wow.aura_error, 0)
			end
			return u == "player" and wow.auras[i] or nil
		end,
	}
	_G.C_Secrets = {
		ShouldAurasBeSecret = function()
			return wow.auras_secret
		end,
	}
	_G.GetShapeshiftForm = function()
		return wow.form
	end
	_G.GetShapeshiftFormInfo = function(i)
		return 134400, i == wow.form, true, wow.forms[i]
	end
	_G.GetTotemInfo = function(slot)
		local name = wow.totems[slot]
		return name ~= nil, name or "", 0, 0, 134400
	end
	_G.UnitCreatureFamily = unit_value("family")
	_G.C_Reputation = {
		GetFactionDataByID = function(id)
			return wow.factions[id]
		end,
	}
	_G.ItemTextGetItem = function()
		return wow.item_text
	end
	local function talents()
		return wow.talents or {}
	end
	local function tree(spec)
		return (talents().trees or {})[spec]
	end
	_G.C_ClassTalents = {
		GetActiveConfigID = function()
			return talents().config
		end,
		GetTraitTreeForSpec = function(spec)
			return tree(spec) and tree(spec).tree
		end,
	}
	_G.C_SpecializationInfo = {
		GetSpecialization = function()
			return talents().spec or 1
		end,
		GetSpecializationInfo = function(i)
			return (talents().specs or {})[i]
		end,
		GetNumSpecializationsForClassID = function()
			return #(talents().specs or {})
		end,
	}
	_G.GetSpecializationInfoForClassID = function(_, i)
		return (talents().specs or {})[i]
	end
	local function treeByID(id)
		for _, t in pairs(talents().trees or {}) do
			if t.tree == id then
				return t
			end
		end
	end
	_G.C_Traits = {
		GetTreeNodes = function(id)
			local out = {}
			for node in ipairs((treeByID(id) or {}).nodes or {}) do
				out[#out + 1] = id * 100 + node
			end
			return out
		end,
		GetNodeInfo = function(_, node)
			local t = treeByID(math.floor(node / 100))
			return { ID = node, ranksPurchased = t and t.nodes[node % 100] or 0 }
		end,
		GetTreeCurrencyInfo = function()
			return { { quantity = talents().unspent or 0 } }
		end,
	}
	_G.GetStatisticsCategoryList, _G.GetCategoryNumAchievements, _G.GetAchievementInfo, _G.GetStatistic =
		nil, nil, nil, nil
	if wow.stats then
		_G.GetStatisticsCategoryList = function()
			local out = {}
			for i, cat in ipairs(wow.stats) do
				out[i] = cat[1]
			end
			return out
		end
		local function category(id)
			for _, cat in ipairs(wow.stats) do
				if cat[1] == id then
					return cat[2]
				end
			end
			return {}
		end
		_G.GetCategoryNumAchievements = function(cat)
			return #category(cat)
		end
		_G.GetAchievementInfo = function(cat, i)
			local stat = category(cat)[i]
			return stat and stat[1]
		end
		_G.GetStatistic = function(id)
			for _, cat in ipairs(wow.stats) do
				for _, stat in ipairs(cat[2]) do
					if stat[1] == id then
						return stat[2]
					end
				end
			end
		end
	end
end

function wow.set_money(copper)
	wow.money = copper
	wow.fire("PLAYER_MONEY")
end

-- Opens a loot window and closes it, as the client does: LOOT_READY, then LOOT_OPENED and LOOT_CLOSED. With
-- window.autoLoot, the client sends no LOOT_OPENED and the slots are empty before LOOT_CLOSED, as with an auto-loot
-- addon.
function wow.open_loot(window, isFromItem)
	wow.loot = window
	local auto = window.autoLoot == true
	wow.fire("LOOT_READY", auto)
	if auto then
		wow.loot = { slots = {} }
	else
		wow.fire("LOOT_OPENED", false, isFromItem == true)
	end
	wow.fire("LOOT_CLOSED")
end

-- Fires the player's UNIT_SPELLCAST_SENT for spell on a target, with the castGUID that wow.cast uses.
function wow.send(spell, target)
	wow.fire("UNIT_SPELLCAST_SENT", "player", target or "", "Cast-3-0-0-0-" .. tostring(spell) .. "-0", spell)
end

-- Screenshots ----------------------------------------------------------------

-- wow.shots counts the Screenshot() calls, so a test can prove that Memories takes none. wow.screenshot(ok) answers the
-- way the client does, with SCREENSHOT_SUCCEEDED or SCREENSHOT_FAILED and no payload.
local function install_screenshots()
	wow.shots = 0
	_G.Screenshot = function()
		wow.shots = wow.shots + 1
	end
end

function wow.screenshot(ok)
	wow.fire(ok == false and "SCREENSHOT_FAILED" or "SCREENSHOT_SUCCEEDED")
end

-- Reset ----------------------------------------------------------------------

-- A wrapped value stands in for a secret value of the client.
function wow.secret(v)
	local wrapped = { value = v }
	wow.secrets[wrapped] = true
	return wrapped
end

function wow.set_wall(unix)
	wow.wall = unix
end

-- Social and PvP -------------------------------------------------------------

-- wow.group = { raid, n } with the members in wow.units (party1-4, raid1-40). wow.guild = { name, rank, index } is the
-- player's guild, or true for a guild whose name the client has not sent yet; a unit's guild is its guild field, and
-- guildError makes GetGuildInfo on it raise. wow.tabard is the C_GuildInfo tabard (wow.tabard_error makes it raise)
-- and wow.logo the GetGuildLogoInfo values. wow.pvp holds kills and maxRank (GetPVPLifetimeStats), renown, points
-- and threshold (rank faction 2800), currency (id -> quantity), winner (GetBattlefieldWinner), matchWinner and
-- complete (C_PvP), score (the player's PVPScoreInfo; scoreError makes it raise) and queues (status by index).
local function install_social()
	wow.group = { raid = false, n = 0 }
	wow.guild = wow.opts.guild
	wow.tabard, wow.tabard_error, wow.logo = nil, nil, nil
	wow.roster_asks, wow.score_asks = 0, 0
	wow.pvp = merge({ kills = 0, maxRank = 0, queues = {}, currency = {} }, wow.opts.pvp)
	_G.GetNumGroupMembers = function()
		return wow.group.n
	end
	_G.IsInRaid = function()
		return wow.group.raid
	end
	_G.IsInGuild = function()
		return wow.guild ~= nil
	end
	_G.GetGuildInfo = function(u)
		if u == "player" then
			local g = wow.guild
			if type(g) == "table" then
				return g.name, g.rank, g.index
			end
			return nil
		end
		local data = unit(u)
		if data and data.guildError then
			error(data.guildError)
		end
		if data and data.guild then
			return data.guild, "Miembro", 1
		end
	end
	_G.C_GuildInfo = {
		GuildRoster = function()
			wow.roster_asks = wow.roster_asks + 1
		end,
		GetGuildTabardInfo = function(u)
			assert(u == "player")
			if wow.tabard_error then
				error(wow.tabard_error)
			end
			return wow.tabard
		end,
	}
	_G.GetGuildLogoInfo = function()
		if wow.logo then
			return unpack(wow.logo)
		end
	end
	_G.GetPVPLifetimeStats = function()
		return wow.pvp.kills, wow.pvp.maxRank
	end
	_G.C_MajorFactions = {
		GetMajorFactionProgressionInfo = function(id)
			if id == 2800 and wow.pvp.renown then
				return {
					renownLevel = wow.pvp.renown,
					renownReputationEarned = wow.pvp.points,
					renownLevelThreshold = wow.pvp.threshold,
				}
			end
		end,
	}
	_G.C_CurrencyInfo = {
		GetCurrencyInfo = function(id)
			local quantity = wow.pvp.currency[id]
			if quantity then
				return { quantity = quantity }
			end
		end,
	}
	_G.GetBattlefieldWinner = function()
		return wow.pvp.winner
	end
	_G.C_PvP = {
		IsMatchComplete = function()
			return wow.pvp.complete == true
		end,
		GetActiveMatchWinner = function()
			return wow.pvp.matchWinner
		end,
		GetScoreInfoByPlayerGuid = function(guid)
			if wow.pvp.scoreError then
				error(wow.pvp.scoreError)
			end
			return guid == wow.player.guid and wow.pvp.score or nil
		end,
	}
	_G.GetMaxBattlefieldID = function()
		return #wow.pvp.queues
	end
	_G.GetBattlefieldStatus = function(i)
		return wow.pvp.queues[i] or "none"
	end
	_G.RequestBattlefieldScoreData = function()
		wow.score_asks = wow.score_asks + 1
	end
end

local function strip(msg)
	return (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Returns the chat lines without color codes.
function wow.chat()
	local out = {}
	for i, line in ipairs(wow.chat_raw) do
		out[i] = strip(line)
	end
	return out
end

function wow.reset(opts)
	opts = opts or {}
	for k in pairs(_G) do
		if not baseline[k] then
			_G[k] = nil
		end
	end

	wow.opts = opts
	wow.clock = opts.clock or 0
	wow.wall = opts.wall or 1793560500
	wow.frames = {}
	wow.chat_raw = {}
	wow.errors = {}
	wow.popups = {}
	wow.reloads = 0
	wow.combat = false
	wow.instance = opts.instance
	wow.secrets = setmetatable({}, { __mode = "k" })
	wow.unknown_events = opts.unknownEvents or {}
	wow.player = merge(DEFAULT_PLAYER, opts.player)
	wow.units = opts.units or {}
	wow.map = merge({ id = 1453, x = 0.5, y = 0.25 }, opts.map)
	wow.maps = opts.maps or {}
	wow.projections = opts.projections or {}
	wow.art = opts.art or {}
	wow.explored = opts.explored or {}
	wow.zoneAt = opts.zoneAt
	_G.C_MapExplorationInfo = {
		GetExploredMapTextures = function(mapID)
			return wow.explored[mapID] or {}
		end,
	}
	wow.spells = opts.spells or {}
	wow.addon_state = merge({}, opts.installed)
	wow.flags = merge({}, opts.flags)
	wow.world = merge({ x = 0, y = 0, inst = 0 }, opts.world)
	wow.zone = opts.zone or "Bosque de Elwynn"
	wow.subzone = opts.subzone
	wow.rested = opts.rested
	wow.quests = opts.quests or {}
	wow.rules = opts.rules
	wow.played_asks = 0
	wow.shift = false
	wow.jumps = 0
	wow.tocs = {}
	wow.tocs_by_name = {}
	wow.ns = {}

	for name, value in pairs(merge(DEFAULT_STRINGS, opts.strings)) do
		_G[name] = value
	end

	install_timers()
	install_encoding()
	install_settings()
	install_units()
	install_addons()
	install_deaths()
	install_screenshots()
	install_travel()
	install_loot()
	install_economy()
	install_character()
	install_social()

	_G.CreateFrame = function(kind, name, parent, template)
		return new_frame(kind, name, parent, template)
	end
	_G.UIParent = new_frame("Frame", "UIParent")
	_G.Minimap = new_frame("Frame", "Minimap", _G.UIParent)
	_G.Minimap.center, _G.Minimap.width, _G.Minimap.scale = { 700, 500 }, 140, 2
	if opts.lowHealthFrame ~= false then
		new_frame("Frame", "LowHealthFrame", _G.UIParent).shown = false
	end
	wow.cursor = { 0, 0 }
	_G.GetCursorPosition = function()
		return wow.cursor[1], wow.cursor[2]
	end
	wow.tooltip = { lines = {} }
	_G.GameTooltip = new_frame("GameTooltip", "GameTooltip", _G.UIParent)
	_G.GameTooltip.shown = false
	function _G.GameTooltip:SetOwner(owner, anchor)
		self.owner, self.anchor, wow.tooltip.lines = owner, anchor, {}
	end
	function _G.GameTooltip:SetText(text)
		wow.tooltip.lines = { text }
	end
	function _G.GameTooltip:AddLine(text)
		wow.tooltip.lines[#wow.tooltip.lines + 1] = text
	end
	_G.ChatFontNormal = {}
	_G.SlashCmdList = {}
	_G.StaticPopupDialogs = {}
	_G.StaticPopup_Show = function(which, text1, text2, data)
		local dialog = { which = which, text1 = text1, text2 = text2, data = data, info = _G.StaticPopupDialogs[which] }
		wow.popups[#wow.popups + 1] = dialog
		return dialog
	end
	_G.StaticPopup_Hide = function(which)
		for _, dialog in ipairs(wow.popups) do
			if dialog.which == which then
				dialog.hidden = true
			end
		end
	end
	_G.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, msg)
			wow.chat_raw[#wow.chat_raw + 1] = msg
		end,
	}
	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		wow.chat_raw[#wow.chat_raw + 1] = table.concat(parts, " ")
	end
	_G.geterrorhandler = function()
		return function(msg)
			wow.errors[#wow.errors + 1] = msg
		end
	end
	_G.debugstack = function()
		return debug.traceback("", 2)
	end
	_G.debugprofilestop = function()
		return wow.clock * 1000
	end
	_G.hooksecurefunc = function(a, b, c)
		local tbl, name, fn = a, b, c
		if type(a) == "string" then
			tbl, name, fn = _G, a, b
		end
		local orig = tbl[name]
		assert(type(orig) == "function", "hooksecurefunc: " .. tostring(name) .. " is not a function")
		tbl[name] = function(...)
			local results = pack(orig(...))
			fn(...)
			return unpack(results, 1, results.n)
		end
	end
	if not opts.noSecrets then
		_G.issecretvalue = function(v)
			return wow.secrets[v] == true
		end
	end
	_G.GetTime = function()
		return wow.clock
	end
	_G.time = function(t)
		if t then
			return real_time(t)
		end
		return wow.wall
	end
	_G.date = function(fmt, t)
		return real_date(fmt, t or wow.wall)
	end
	_G.C_Spell = {
		GetSpellName = function(id)
			return wow.spells[id]
		end,
	}
	_G.IsShiftKeyDown = function()
		return wow.shift == true
	end
	_G.C_UI = {
		Reload = function()
			wow.reloads = wow.reloads + 1
		end,
	}
end

-- Boot -----------------------------------------------------------------------

function wow.read_toc(name)
	local dir, path
	for _, base in ipairs(ADDON_DIRS) do
		local candidate = base .. name .. "/" .. name .. ".toc"
		local f = io.open(candidate)
		if f then
			f:close()
			dir, path = base .. name .. "/", candidate
			break
		end
	end
	assert(path, "no TOC for addon " .. name)
	local toc = { name = name, meta = {}, files = {}, saved = {}, deps = {} }
	for line in io.lines(path) do
		line = line:gsub("%s+$", "")
		local key, value = line:match("^##%s*([^:]+):%s*(.*)$")
		if key then
			toc.meta[key] = value
		elseif line ~= "" and not line:match("^#") then
			toc.files[#toc.files + 1] = dir .. line:gsub("\\", "/")
		end
	end
	for _, key in ipairs({ "SavedVariables", "SavedVariablesPerCharacter" }) do
		for var in (toc.meta[key] or ""):gmatch("[^,%s]+") do
			toc.saved[#toc.saved + 1] = var
		end
	end
	for dep in (toc.meta.Dependencies or ""):gmatch("[^,%s]+") do
		toc.deps[#toc.deps + 1] = dep
	end
	return toc
end

-- "deps" loads each addon after its dependencies; "reverse" loads in the opposite order.
local function load_order(tocs, order)
	local by_name, seen, out = {}, {}, {}
	for _, toc in ipairs(tocs) do
		by_name[toc.name] = toc
	end
	local function visit(toc)
		if seen[toc.name] then
			return
		end
		seen[toc.name] = true
		for _, dep in ipairs(toc.deps) do
			if by_name[dep] then
				visit(by_name[dep])
			end
		end
		out[#out + 1] = toc
	end
	for _, toc in ipairs(tocs) do
		visit(toc)
	end
	if order == "reverse" then
		local reversed = {}
		for i = #out, 1, -1 do
			reversed[#reversed + 1] = out[i]
		end
		return reversed
	end
	return out
end

-- Sets the addon's saved globals from saved and runs its files with one shared namespace, without ADDON_LOADED.
-- Call it after wow.reset (wow.boot does both).
function wow.load_addon(name, saved)
	local toc = wow.tocs_by_name[name] or wow.read_toc(name)
	wow.tocs_by_name[name] = toc
	if not wow.ns[name] then
		wow.tocs[#wow.tocs + 1] = toc
	end
	wow.addon_state[name] = "loaded"
	for _, var in ipairs(toc.saved) do
		_G[var] = (saved or {})[var]
	end
	local ns = {}
	wow.ns[name] = ns
	for _, file in ipairs(toc.files) do
		assert(loadfile(file))(name, ns)
	end
	return ns
end

function wow.login(isReload)
	wow.fire("PLAYER_LOGIN")
	wow.fire("PLAYER_ENTERING_WORLD", not isReload, isReload == true)
end

-- opts: addons (names, default { "Memories" }), saved (global name -> table), player, order ("deps" or "reverse"),
-- login (false stops before PLAYER_LOGIN), installed (addon name -> "enabled" or "disabled" for addons not booted),
-- reloading (enter the world as a /reload), spells, map, maps, units, unknownEvents, noSecrets, clock, wall,
-- flags (taxi, flying, mounted, ghost, dead, swimming, moving, afk), world ({ x, y, inst } yards), zone, rested,
-- quests (id -> title), rules ({ hardcore, selfFound } for C_GameRules), strings (GlobalStrings over Spanish ones),
-- recap (death recap events), cvars (name -> value), lowHealthFrame (false: no LowHealthFrame), subzone, taxi
-- (flight master nodes), mounts (id -> { name, spell, active }), skillLines (id -> name), bind, region, locale,
-- instance ({ name, type, id, difficulty, size } for IsInInstance and GetInstanceInfo), money (the gold), skills,
-- tradeSkills, talents and stats (see install_character), guild and pvp (see install_social).
-- Returns the core namespace and a table of every booted addon's namespace by name.
function wow.boot(opts)
	opts = opts or {}
	wow.reset(opts)
	local tocs = {}
	for i, name in ipairs(opts.addons or { "Memories" }) do
		tocs[i] = wow.read_toc(name)
		wow.tocs_by_name[name] = tocs[i]
	end
	for _, toc in ipairs(load_order(tocs, opts.order)) do
		wow.load_addon(toc.name, opts.saved)
		wow.fire("ADDON_LOADED", toc.name)
	end
	if opts.login ~= false then
		wow.login(opts.reloading)
	end
	return wow.ns.Memories, wow.ns
end

-- Logs out, writes every saved global with the WoW saved-file form, loads that text under Lua 5.1 and boots again.
function wow.reload()
	wow.fire("PLAYER_LOGOUT")
	local globals, names = {}, {}
	for _, toc in ipairs(wow.tocs) do
		names[#names + 1] = toc.name
		for _, var in ipairs(toc.saved) do
			globals[var] = _G[var]
		end
	end
	local saved = assert(serialize.load(serialize.file(globals)))
	return wow.boot(merge(wow.opts, {
		addons = wow.opts.addons or names,
		saved = saved,
		clock = wow.clock,
		wall = wow.wall,
		player = wow.player,
		map = wow.map,
		spells = wow.spells,
		reloading = true,
	}))
end

function wow.fire(event, ...)
	for _, frame in ipairs(wow.frames) do
		local handler = frame.scripts.OnEvent
		if handler and frame.events[event] then
			handler(frame, event, ...)
		end
	end
end

-- Makes every boot inside the enclosing describe report locale unless a boot sets its own. Busted's hooks are passed
-- in because they live in the spec file environment.
function wow.pin_locale(locale, before_each, after_each)
	local previous
	before_each(function()
		previous = wow.default_locale
		wow.default_locale = locale
	end)
	after_each(function()
		wow.default_locale = previous
	end)
end

wow.reset()

return wow
