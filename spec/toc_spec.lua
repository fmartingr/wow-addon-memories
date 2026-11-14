local wow = require("helpers.wow")

local ADDONS = {
	"Memories",
	"Memories_Character",
	"Memories_Combat",
	"Memories_Economy",
	"Memories_Gathering",
	"Memories_Social",
}
local NOTES_LOCALES = { "deDE", "esES", "esMX", "frFR", "itIT", "ptBR" }
local ICON = "Interface\\AddOns\\Memories\\assets\\icon"

local function read(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

local function exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
	end
	return f ~= nil
end

local function tocFiles(text)
	local files = {}
	for line in text:gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and line:match("%S") then
			files[#files + 1] = line:gsub("\\", "/"):match("^%s*(.-)%s*$")
		end
	end
	return files
end

local function field(toc, key)
	return toc:match("\n## " .. key:gsub("%-", "%%-") .. ": ([^\r\n]+)") or toc:match("^## " .. key .. ": ([^\r\n]+)")
end

for _, addon in ipairs(ADDONS) do
	describe(addon .. ".toc", function()
		local dir = "addons/" .. addon .. "/"
		local toc = read(dir .. addon .. ".toc")

		after_each(function()
			wow.restore()
		end)

		it("loads in WoW Forever and takes its version from the tag", function()
			assert.equal("16001", field(toc, "Interface"))
			assert.equal("camelot", field(toc, "AllowLoadGameType"))
			assert.equal("@project-version@", field(toc, "Version"))
		end)

		it("names the CurseForge project, the author, the license and the icon", function()
			assert.is_truthy(toc:match("## X%-Curse%-Project%-ID: %d+"))
			assert.equal("Felipe M.", field(toc, "Author"))
			assert.equal("GPL-3.0-or-later", field(toc, "X-License"))
			assert.equal(ICON, field(toc, "IconTexture"))
			assert.is_true(exists("addons/Memories/assets/icon.tga"))
		end)

		it("has no compartment function, because LibDBIcon adds the entry", function()
			assert.is_nil(field(toc, "AddonCompartmentFunc"))
		end)

		it("has notes for each translated locale, and a title only when it changes", function()
			for _, locale in ipairs(NOTES_LOCALES) do
				assert.is_truthy(field(toc, "Notes-" .. locale), "Notes-" .. locale)
				local title = field(toc, "Title-" .. locale)
				assert.are_not.equal(field(toc, "Title"), title)
			end
		end)

		it("lists only files that exist", function()
			for _, name in ipairs(tocFiles(toc)) do
				assert.is_true(exists(dir .. name), name)
			end
		end)

		it("lists every addon Lua file", function()
			local listed = {}
			for _, name in ipairs(tocFiles(toc)) do
				listed[name] = true
			end
			local p = assert(io.popen("cd " .. dir .. " && find . -name '*.lua' -not -path './Libs/*' | sort"))
			for path in p:lines() do
				local name = path:gsub("^%./", "")
				assert.is_true(listed[name] == true, name)
			end
			p:close()
		end)

		it("loads Locales.lua before the addon code", function()
			local first
			for _, name in ipairs(tocFiles(toc)) do
				if not name:match("^Libs/") then
					first = first or name
				end
			end
			assert.equals("Locales.lua", first)
		end)
	end)
end

describe("Memories.toc file order", function()
	it("loads the shared modules first and the window and the minimap button last", function()
		local files = tocFiles(read("addons/Memories/Memories.toc"))
		local at = {}
		for i, name in ipairs(files) do
			at[name] = i
		end
		assert.is_true(at["Core/Core.lua"] < at["Core/Commands.lua"])
		assert.is_true(at["Core/Commands.lua"] < at["Data/Settings.lua"])
		assert.equal(#files - 2, at["UI/Window.lua"])
		assert.equal(#files - 1, at["UI/Minimap.lua"])
		assert.equal(#files, at["Init.lua"])
	end)
end)
