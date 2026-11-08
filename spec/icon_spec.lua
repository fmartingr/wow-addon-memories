local wow = require("helpers.wow")

describe("addon icon", function()
	-- The client finds "Interface\AddOns\<addon>\<path>" without an extension, as a .tga or .blp file.
	local function file_of(texture)
		local rel = texture:match("^Interface\\AddOns\\(.+)$")
		assert.is_string(rel, texture)
		return "addons/" .. rel:gsub("\\", "/") .. ".tga"
	end

	local function exists(path)
		local f = io.open(path, "rb")
		if f then
			f:close()
		end
		return f ~= nil
	end

	it("is a file of the addon in the TOC", function()
		local f = assert(io.open("addons/Memories/Memories.toc"))
		local icon = f:read("*a"):match("\n## IconTexture: ([^\r\n]+)")
		f:close()
		assert.equal("Interface\\AddOns\\Memories\\Media\\icon", icon)
		assert.is_true(exists(file_of(icon)))
	end)

	it("is the same file on the minimap button", function()
		wow.boot()
		local paths = {}
		for _, texture in ipairs(MemoriesMinimapButton.textures) do
			paths[texture.texture or ""] = true
		end
		assert.is_true(paths["Interface\\AddOns\\Memories\\Media\\icon"])
		assert.is_true(exists(file_of("Interface\\AddOns\\Memories\\Media\\icon")))
	end)
end)
