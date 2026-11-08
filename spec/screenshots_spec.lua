local wow = require("helpers.wow")

describe("screenshots", function()
	-- 2026-11-06 14:03:09 on the clock of the machine that runs the tests: file names use local time.
	local WALL = os.time({ year = 2026, month = 11, day = 6, hour = 14, min = 3, sec = 9 })
	local STEM = "WoWScrnShot_110626_140309"

	local ns

	local function boot(opts)
		opts = opts or {}
		opts.wall = opts.wall or WALL
		ns = wow.boot(opts)
		return ns
	end

	local function lines()
		local out = {}
		for line in ns.Store.Core():Lines() do
			local k, rest = line:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(%w+)|?(.*)$")
			if k == "ss" then
				out[#out + 1] = rest
			end
		end
		return out
	end

	local function counts()
		return ns.Store.Core():Counts("screenshots")
	end

	it("writes a by-hand line with the predicted jpg name", function()
		boot({ cvars = { screenshotFormat = "jpeg" } })
		wow.screenshot(true)
		assert.same({ "by hand|ok|" .. STEM .. ".jpg" }, lines())
		assert.equal(1, counts().shots)
		assert.equal(0, wow.shots)
	end)

	it("maps each screenshot format to its extension", function()
		boot()
		for format, ext in pairs({ jpg = ".jpg", JPEG = ".jpg", png = ".png", tga = ".tga", bmp = "", [""] = "" }) do
			wow.cvars.screenshotFormat = format
			assert.equal(STEM .. ext, ns.Screenshots.FileName(WALL))
		end
		wow.cvars.screenshotFormat = nil
		assert.equal(STEM, ns.Screenshots.FileName(WALL))
		wow.cvars.screenshotFormat = wow.secret("png")
		assert.equal(STEM, ns.Screenshots.FileName(WALL))
		wow.cvar_fail.get = "no cvar"
		assert.equal(STEM, ns.Screenshots.FileName(WALL))
		_G.C_CVar = nil
		assert.equal(STEM, ns.Screenshots.FileName(WALL))
		wow.cvar_fail.get = nil
		wow.cvars.screenshotFormat = "png"
		assert.equal(STEM .. ".png", ns.Screenshots.FileName(WALL))
		_G.GetCVar = nil
		assert.equal(STEM, ns.Screenshots.FileName(WALL))
	end)

	it("names the file from the clock at the answer", function()
		boot({ cvars = { screenshotFormat = "png" } })
		wow.set_wall(WALL + 1)
		wow.screenshot(true)
		assert.same({ "by hand|ok|WoWScrnShot_110626_140310.png" }, lines())
	end)

	it("writes one line for each saved shot", function()
		boot({ cvars = { screenshotFormat = "png" } })
		wow.screenshot(true)
		wow.screenshot(true)
		assert.equal(2, #lines())
		assert.equal(2, counts().shots)
	end)

	it("writes nothing for a failed shot", function()
		boot()
		wow.screenshot(false)
		assert.same({}, lines())
		assert.is_nil(counts().shots)
	end)

	it("counts a by-hand shot while ss is off", function()
		boot()
		ns.Settings.SetKind("ss", false)
		wow.screenshot(true)
		assert.same({}, lines())
		assert.equal(1, counts().shots)
	end)

	it("takes no screenshot of its own at a level-up", function()
		boot()
		wow.fire("PLAYER_LEVEL_UP", 20)
		wow.advance(5)
		assert.equal(0, wow.shots)
		assert.same({}, lines())
	end)

	describe("a core journal that cannot write", function()
		it("records nothing", function()
			boot({ saved = { MemoriesDB = { schema = 99 } } })
			wow.screenshot(true)
			assert.same({}, lines())
		end)
	end)
end)
