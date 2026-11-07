local wow = require("helpers.wow")

describe("/memories status", function()
	local GUID = "Player-1234-0ABCDEF0"

	local function status()
		wow.chat_raw = {}
		SlashCmdList.MEMORIES("status")
		return wow.chat()
	end

	it("prints one line for each addon of the set, with each state, then the login time", function()
		local saved = {
			MemoriesDB = {
				kinds = { ki = "Memories_Combat;Combat;name,#npc", ra = "Memories_Combat;Combat;name" },
				settings = { kinds = { lv = false, gh = false, zz = false, ki = false, ra = true, qq = false } },
				backups = { [GUID] = { Memories = { t = 1793560500 - 600, lines = 2, blob = "x" } } },
			},
		}
		wow.boot({
			addons = { "Memories", "Memories_Test" },
			login = false,
			saved = saved,
			installed = { Memories_Combat = "enabled", Memories_Gathering = "disabled" },
		})
		assert.is_nil(Memories.RegisterModule({ addon = "Memories_Social", api = 2, saved = "MemoriesSocialCharDB" }))
		wow.login()
		wow.ns.Memories_Test.handle:Write("zy", "one")
		local lines = status()
		assert.same({
			"Memories: status:",
			"  Memories: on, 0 lines, 2 kinds off, backup 10 min ago",
			"  Memories_Test: on, 1 lines, 1 kinds off, no backup",
			"  Memories_Social: newer api, 0 lines, 0 kinds off, no backup",
			"  Memories_Combat: failed, 0 lines, 1 kinds off, no backup",
			"  Memories_Gathering: off, 0 lines, 0 kinds off, no backup",
			"  Memories_Character: missing, 0 lines, 0 kinds off, no backup",
			"  Memories_Economy: missing, 0 lines, 0 kinds off, no backup",
			"  login time: init 0 ms, login 0 ms, world 0 ms",
		}, lines)
	end)

	it("marks a read-only addon and reports a failed core", function()
		wow.boot({
			addons = { "Memories", "Memories_Test" },
			saved = { MemoriesTestCharDB = { schema = 99 } },
		})
		assert.equal("  Memories_Test: on, 0 lines, 0 kinds off, no backup, read only", status()[3])
	end)

	it("reports the login time in whole milliseconds", function()
		local ns = wow.boot()
		ns.loginTime = { init = 1.4, login = 12.6 }
		local lines = status()
		assert.equal("  login time: init 1 ms, login 13 ms", lines[#lines])
		ns.loginTime = {}
		lines = status()
		assert.equal("  login time: unknown", lines[#lines])
	end)

	it("works when the core stopped at login", function()
		local ns = wow.boot({ login = false })
		ns.Store.Init = function()
			error("store broke")
		end
		wow.login()
		assert.equal("  Memories: failed, 0 lines, 0 kinds off, no backup", status()[2])
	end)

	it("ignores saved kind texts and backups that are not what it expects", function()
		wow.boot({
			saved = {
				MemoriesDB = {
					kinds = { ki = 5 },
					settings = { kinds = { ki = false } },
					backups = { [GUID] = { Memories = { t = "soon" } } },
				},
			},
		})
		assert.equal("  Memories: on, 0 lines, 0 kinds off, no backup", status()[2])
	end)

	it("formats an age in seconds, minutes, hours and days", function()
		local ns = wow.boot()
		assert.equal("0 s", ns.Status.Age(-5))
		assert.equal("59 s", ns.Status.Age(59))
		assert.equal("1 min", ns.Status.Age(60))
		assert.equal("59 min", ns.Status.Age(3599))
		assert.equal("1 h", ns.Status.Age(3600))
		assert.equal("23 h", ns.Status.Age(86399))
		assert.equal("2 d", ns.Status.Age(2 * 86400 + 5))
	end)
end)
