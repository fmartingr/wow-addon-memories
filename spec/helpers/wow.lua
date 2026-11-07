-- A stub of the WoW client for busted. It loads the real addons from their TOC files.
local serialize = require("helpers.serialize")

local wow = {}

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
	"RegisterForClicks",
	"RegisterForDrag",
	"SetAllPoints",
	"SetAlpha",
	"SetAutoFocus",
	"SetClampedToScreen",
	"SetFontObject",
	"SetFrameLevel",
	"SetFrameStrata",
	"SetHeight",
	"SetHighlightTexture",
	"SetJustifyH",
	"SetMovable",
	"SetMultiLine",
	"SetNormalTexture",
	"SetPushedTexture",
	"SetScrollChild",
	"SetSize",
	"SetTexCoord",
	"SetTexture",
	"SetVertexColor",
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
end

function Frame:ClearFocus()
	self.focused = false
end

function Frame:HighlightText()
	self.highlighted = true
end

function Frame:GetCenter()
	return unpack(self.center or { 0, 0 })
end

function Frame:GetWidth()
	return self.width or 0
end

function Frame:GetEffectiveScale()
	return self.scale or 1
end

function Frame:SetPoint(...)
	self.point = pack(...)
end

function Frame:CreateTexture(name)
	return new_frame("Texture", name, self)
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

local function install_settings()
	wow.categories = {}
	wow.settings_calls = {}
	wow.opened = nil
	local function category_layout(category)
		return {
			AddInitializer = function(_, initializer)
				category.items[#category.items + 1] = initializer
			end,
		}
	end
	local function control(kind)
		return function(category, setting, options, tooltip)
			local initializer = { type = kind, setting = setting, options = options, tooltip = tooltip }
			category.items[#category.items + 1] = initializer
			return initializer
		end
	end
	local api = {
		VarType = { Boolean = "boolean", Number = "number", String = "string" },
		RegisterVerticalLayoutCategory = function(name)
			local category = { name = name, items = {}, settings = {}, id = #wow.categories + 1 }
			function category:GetID()
				return self.id
			end
			wow.categories[#wow.categories + 1] = category
			return category, category_layout(category)
		end,
		RegisterAddOnCategory = function(category)
			category.registered = true
		end,
		RegisterAddOnSetting = function(category, variable, key, tbl, varType, name, default)
			local setting =
				{ variable = variable, key = key, tbl = tbl, varType = varType, name = name, default = default }
			function setting:GetValue()
				local v = self.tbl[self.key]
				if v == nil then
					return self.default
				end
				return v
			end
			function setting:SetValue(v)
				self.tbl[self.key] = v
				if self.callback then
					self.callback(self, v)
				end
			end
			function setting:SetValueChangedCallback(fn)
				self.callback = fn
			end
			category.settings[variable] = setting
			return setting
		end,
		CreateCheckbox = function(category, setting, tooltip)
			return control("checkbox")(category, setting, nil, tooltip)
		end,
		CreateSlider = control("slider"),
		CreateDropdown = control("dropdown"),
		CreateSliderOptions = function(min, max, step)
			return { min = min, max = max, step = step, SetLabelFormatter = noop }
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
		OpenToCategory = function(id)
			wow.opened = id
		end,
	}
	_G.Settings = {}
	for name, v in pairs(api) do
		if type(v) == "function" then
			_G.Settings[name] = function(...)
				wow.settings_calls[#wow.settings_calls + 1] = { name = name, args = pack(...) }
				return v(...)
			end
		else
			_G.Settings[name] = v
		end
	end
	_G.SettingsPanel = {
		GetLayout = function(_, category)
			return category_layout(category)
		end,
	}
	_G.CreateSettingsListSectionHeaderInitializer = function(name, tooltip)
		return { type = "header", name = name, tooltip = tooltip }
	end
	_G.CreateSettingsButtonInitializer = function(name, buttonText, buttonClick, tooltip, addSearchTags)
		return {
			type = "button",
			name = name,
			buttonText = buttonText,
			click = buttonClick,
			tooltip = tooltip,
			addSearchTags = addSearchTags,
		}
	end
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
	_G.UnitName = unit_value("name")
	_G.UnitLevel = unit_value("level")
	_G.UnitSex = unit_value("sex")
	_G.UnitClass = unit_values("class")
	_G.UnitRace = unit_values("race")
	_G.UnitFactionGroup = unit_values("faction")
	_G.UnitExists = function(u)
		return unit(u) ~= nil
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
	_G.InCombatLockdown = function()
		return wow.combat
	end
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
	wow.instance = nil
	wow.secrets = setmetatable({}, { __mode = "k" })
	wow.unknown_events = opts.unknownEvents or {}
	wow.player = merge(DEFAULT_PLAYER, opts.player)
	wow.units = opts.units or {}
	wow.map = merge({ id = 1453, x = 0.5, y = 0.25 }, opts.map)
	wow.maps = opts.maps or {}
	wow.spells = opts.spells or {}
	wow.addon_state = merge({}, opts.installed)
	wow.tocs = {}
	wow.tocs_by_name = {}
	wow.ns = {}

	install_timers()
	install_encoding()
	install_settings()
	install_units()
	install_addons()

	_G.CreateFrame = function(kind, name, parent, template)
		return new_frame(kind, name, parent, template)
	end
	_G.UIParent = new_frame("Frame", "UIParent")
	_G.Minimap = new_frame("Frame", "Minimap", _G.UIParent)
	_G.Minimap.center, _G.Minimap.width, _G.Minimap.scale = { 700, 500 }, 140, 2
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
-- reloading (enter the world as a /reload), spells, map, maps, units, unknownEvents, noSecrets, clock, wall.
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

wow.reset()

return wow
