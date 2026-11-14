local ADDON, ns = ...

local L = ns.L

-- The Settings page. Settings is the client's API; ns.Settings holds the values.
local Options = {}
ns.Options = Options

Options.NAME = "Memories"
local VARIABLE = "Memories_"

local category, layout
local byPath = {}
-- True while the page shows a value that changed elsewhere, so the setting's callback does not write it back.
local syncing = false

local function bind(setting, path)
	byPath[path] = setting
	setting:SetValueChangedCallback(function(_, value)
		if not syncing then
			ns.Protect("options:" .. path, ns.Settings.Set, path, value)
		end
	end)
	return setting
end

local function register(path, varType, name)
	local tbl, key = ns.Settings.Slot(path)
	local setting =
		Settings.RegisterAddOnSetting(category, VARIABLE .. path, key, tbl, varType, name, ns.Settings.Default(path))
	return bind(setting, path)
end

local function checkbox(path, name, tooltip)
	Settings.CreateCheckbox(category, register(path, Settings.VarType.Boolean, name), tooltip)
end

local function rateOptions()
	local container = Settings.CreateControlTextContainer()
	for _, rate in ipairs(ns.Settings.RATES) do
		container:Add(rate, L["%d s"]:format(rate))
	end
	return container:GetData()
end

local function general()
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["General"]))
	local rate = register("recordRate", Settings.VarType.Number, L["Recording rate"])
	Settings.CreateDropdown(category, rate, rateOptions, L["Seconds between two points of the position trail."])
	checkbox("saveReminder", L["Save reminder"], L["Reminds you to save after one hour without a reload."])
	checkbox("minimapButton", L["Minimap button"], L["Shows the Memories button on the minimap."])
	checkbox(
		"lowHealthFlash",
		L["Low-health flash"],
		L["Keeps the game's low-health flash on, so Memories can record close calls."]
	)
end

local function groupButton(addon, group, label, on)
	local text = on and L["Enable all"] or L["Disable all"]
	return CreateSettingsButtonInitializer(label, text, function()
		ns.Protect("options:group", ns.Settings.SetGroup, addon, group, on)
	end, on and L["Turns on every kind of this group."] or L["Turns off every kind of this group."], false)
end

-- The groups of an addon in the order of its first kind, each with its kinds and its new-only boxes.
local function groups(addon, boxes)
	local order, byGroup = {}, {}
	for _, spec in ipairs(ns.Kinds.All()) do
		if spec.addon == addon and not spec.always then
			local g = spec.group or ""
			if not byGroup[g] then
				byGroup[g] = { kinds = {}, boxes = {} }
				order[#order + 1] = g
			end
			local kinds = byGroup[g].kinds
			kinds[#kinds + 1] = spec
		end
	end
	-- The registry checks that a box lists only its own addon's kinds, so the first kind names its group.
	for _, box in ipairs(boxes) do
		local list = byGroup[ns.Kinds.Get(box.kinds[1]).group or ""].boxes
		list[#list + 1] = box
	end
	return order, byGroup
end

-- The groups stay English tokens in MemoriesDB.kinds; only this page shows these labels. The sub-addon groups are here
-- because this page draws their sections.
local GROUPS = {
	Sessions = L["Sessions"],
	Progress = L["Progress"],
	Deaths = L["Deaths"],
	Travel = L["Travel"],
	Dungeons = L["Dungeons"],
	Screenshots = L["Screenshots"],
	["Other addons"] = L["Other addons"],
	Notes = L["Notes"],
	Combat = L["Combat"],
	Gathering = L["Gathering"],
	Character = L["Character"],
	Milestones = L["Milestones"],
	Loot = L["Loot"],
	Money = L["Money"],
	Social = L["Social"],
	PvP = L["PvP"],
}

Options.GROUPS = GROUPS

local function section(addon, boxes)
	local order, byGroup = groups(addon, boxes)
	for _, g in ipairs(order) do
		local label, title = addon, addon
		if g ~= "" then
			label = GROUPS[g] or g
			title = addon .. " — " .. label
		end
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
		layout:AddInitializer(groupButton(addon, g, L["All %s kinds"]:format(label), true))
		layout:AddInitializer(groupButton(addon, g, "", false))
		for _, spec in ipairs(byGroup[g].kinds) do
			checkbox("kinds." .. spec.kind, spec.name, L["Writes the %s line."]:format(spec.kind))
		end
		for _, box in ipairs(byGroup[g].boxes) do
			checkbox(
				"newOnly." .. box.key,
				box.label or box.key,
				L["Writes a line only for a first finding or a rare one. Every event is still counted."]
			)
		end
	end
end

local function build()
	assert(type(Settings) == "table" and Settings.RegisterVerticalLayoutCategory, "the Settings API is missing")
	local cat, lay = Settings.RegisterVerticalLayoutCategory(Options.NAME)
	category, layout = cat, lay
	general()
	section(ADDON, {})
	for _, item in ipairs(ns.Registry.Registered()) do
		section(item.addon, item.boxes)
	end
	Settings.RegisterAddOnCategory(cat)
end

-- Runs once, at login after every early registration; a later registration adds its own section. A page that failed
-- stays failed: its settings are half registered, and the client refuses a variable twice.
function Options.Build()
	if not ns.ProtectWith(L["The settings panel is not available on this client."], "options", build) then
		category, layout = nil, nil
	end
end

function Options.Open()
	if not category then
		ns.Print(L["The settings panel is not available on this client."])
		return false
	end
	Settings.OpenToCategory(category:GetID())
	return true
end

ns.Listen("LOGIN", Options.Build, "options")

ns.Listen("REGISTERED", function(_, addon, boxes)
	if category then
		section(addon, boxes)
	end
end, "options")

-- A change from a group button or from code reaches the checkbox that shows it.
ns.Listen("SETTING_CHANGED", function(_, path)
	local setting = byPath[path]
	if not setting then
		return
	end
	syncing = true
	local ok, err = pcall(setting.NotifyUpdate, setting)
	syncing = false
	if not ok then
		error(err, 0)
	end
end, "options")

ns.Commands.Register("options", Options.Open, "open the settings page")
ns.Commands.Register("settings", Options.Open, "open the settings page")
