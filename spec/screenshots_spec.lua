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

	local function take(why)
		ns.Settings.Set("shots.level", true)
		return ns.Screenshots.Take(why, "shots.level")
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
		assert.is_true(take("level 10"))
		assert.equal(1, wow.shots)
		wow.set_wall(WALL + 1)
		wow.screenshot(true)
		assert.same({ "level 10|ok|WoWScrnShot_110626_140310.png" }, lines())
	end)

	it("writes no line for a silent shot", function()
		boot()
		ns.Screenshots.Expect("")
		wow.screenshot(true)
		assert.same({}, lines())
		assert.is_nil(counts().shots)
	end)

	it("lets a by-hand shot after a cancelled expect keep its line", function()
		boot({ cvars = { screenshotFormat = "png" } })
		local entry = ns.Screenshots.Expect("")
		assert.is_true(ns.Screenshots.Cancel(entry))
		assert.is_false(ns.Screenshots.Cancel(entry))
		wow.screenshot(true)
		assert.same({ "by hand|ok|" .. STEM .. ".png" }, lines())
	end)

	it("drops a shot that waited more than 10 s", function()
		boot({ cvars = { screenshotFormat = "png" } })
		take("level 10")
		wow.advance(15)
		wow.screenshot(true)
		assert.same({ "by hand|ok|WoWScrnShot_110626_140324.png" }, lines())
		wow.screenshot(true)
		assert.equal(2, #lines())
	end)

	it("gives each answer to the oldest shot", function()
		boot({ cvars = { screenshotFormat = "png" } })
		take("level 10")
		take("last boss Edwin VanCleef")
		wow.screenshot(false)
		wow.screenshot(true)
		assert.same({ "level 10|failed", "last boss Edwin VanCleef|ok|" .. STEM .. ".png" }, lines())
	end)

	it("writes a failed line with no file", function()
		boot({ cvars = { screenshotFormat = "png" } })
		take("last boss Van Cleef")
		wow.screenshot(false)
		assert.same({ "last boss Van Cleef|failed" }, lines())
		assert.equal(1, counts().shotsFailed)
		assert.is_nil(counts().shots)
	end)

	it("writes nothing for a failed answer that no shot waits for", function()
		boot()
		wow.screenshot(false)
		assert.same({}, lines())
		assert.is_nil(counts().shotsFailed)
	end)

	it("writes a failed line at once when Screenshot() raises", function()
		boot({ cvars = { screenshotFormat = "png" } })
		wow.shot_fail = "no screenshot"
		assert.is_false(take("level 5"))
		assert.same({ "level 5|failed" }, lines())
		assert.equal(1, counts().shotsFailed)
		wow.shot_fail = nil
		wow.screenshot(true)
		assert.same({ "level 5|failed", "by hand|ok|" .. STEM .. ".png" }, lines())
	end)

	it("refuses a why that is not text", function()
		boot()
		assert.has_error(function()
			ns.Screenshots.Take("", "shots.level")
		end)
		assert.has_error(function()
			ns.Screenshots.Take(nil, "shots.level")
		end)
		assert.has_error(function()
			ns.Screenshots.Take("level 5")
		end)
		assert.has_error(function()
			ns.Screenshots.Expect(5)
		end)
		assert.equal(0, wow.shots)
	end)

	it("takes no shot while the named setting is off", function()
		boot()
		assert.is_false(ns.Screenshots.Take("last boss Van Cleef", "shots.lastBoss"))
		ns.Settings.Set("shots.lastBoss", true)
		assert.is_true(ns.Screenshots.Take("last boss Van Cleef", "shots.lastBoss"))
		assert.equal(1, wow.shots)
	end)

	it("counts a by-hand shot while ss is off", function()
		boot()
		ns.Settings.SetKind("ss", false)
		wow.screenshot(true)
		assert.same({}, lines())
		assert.equal(1, counts().shots)
	end)

	describe("level-up shot", function()
		it("is off by default", function()
			boot()
			assert.is_false(ns.Settings.Get("shots.level"))
			assert.is_false(ns.Settings.Get("shots.lastBoss"))
			wow.fire("PLAYER_LEVEL_UP", 20)
			wow.advance(5)
			assert.equal(0, wow.shots)
			assert.same({}, lines())
		end)

		it("takes the shot 1.5 s after the level-up when shots.level is on", function()
			boot({ cvars = { screenshotFormat = "jpg" } })
			ns.Settings.Set("shots.level", true)
			wow.fire("PLAYER_LEVEL_UP", 20)
			wow.advance(1.4)
			assert.equal(0, wow.shots)
			wow.advance(0.1)
			assert.equal(1, wow.shots)
			wow.screenshot(true)
			assert.same({ "level 20|ok|" .. os.date("WoWScrnShot_%m%d%y_%H%M%S.jpg", wow.wall) }, lines())
		end)

		it("takes one shot for levels gained together", function()
			boot({ cvars = { screenshotFormat = "jpg" } })
			ns.Settings.Set("shots.level", true)
			wow.fire("PLAYER_LEVEL_UP", 20)
			wow.fire("PLAYER_LEVEL_UP", 21)
			wow.advance(1.5)
			assert.equal(1, wow.shots)
			wow.screenshot(true)
			assert.same({ "level 21|ok|" .. os.date("WoWScrnShot_%m%d%y_%H%M%S.jpg", wow.wall) }, lines())
		end)

		it("takes no shot when shots.level is turned off during the delay", function()
			boot()
			ns.Settings.Set("shots.level", true)
			wow.fire("PLAYER_LEVEL_UP", 20)
			wow.advance(1)
			ns.Settings.Set("shots.level", false)
			wow.advance(1)
			assert.equal(0, wow.shots)
			assert.same({}, lines())
		end)
	end)

	describe("a core journal that cannot write", function()
		it("takes no shot and records nothing", function()
			boot({ saved = { MemoriesDB = { schema = 99 } } })
			ns.Settings.Set("shots.level", true)
			assert.is_false(ns.Screenshots.Take("level 5", "shots.level"))
			wow.fire("PLAYER_LEVEL_UP", 5)
			wow.advance(2)
			wow.screenshot(true)
			assert.equal(0, wow.shots)
			assert.same({}, lines())
		end)
	end)
end)
