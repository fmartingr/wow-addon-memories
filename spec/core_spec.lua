local wow = require("helpers.wow")

describe("core", function()
	wow.pin_locale("enUS", before_each, after_each)

	local ns

	before_each(function()
		ns = wow.boot({ login = false })
	end)

	describe("Module", function()
		it("keeps modules in creation order and finds them by name", function()
			local a = ns.Module("A")
			local b = ns.Module("B")
			assert.equal(a, ns.GetModule("A"))
			assert.equal(b, ns.modules[#ns.modules])
			assert.equal("B", b.name)
		end)

		it("asserts on a duplicate name", function()
			ns.Module("A")
			assert.has_error(function()
				ns.Module("A")
			end)
		end)
	end)

	describe("On and Off", function()
		it("calls each listener in registration order with the event and its arguments", function()
			local calls = {}
			ns.On("UNIT_HEALTH", function(event, unit)
				calls[#calls + 1] = "1:" .. event .. ":" .. unit
			end)
			ns.On("UNIT_HEALTH", function(event, unit)
				calls[#calls + 1] = "2:" .. event .. ":" .. unit
			end)
			wow.fire("UNIT_HEALTH", "player")
			assert.same({ "1:UNIT_HEALTH:player", "2:UNIT_HEALTH:player" }, calls)
		end)

		it("keeps running the other listeners when one fails", function()
			local ran = false
			ns.On("UNIT_HEALTH", function()
				error("broken recorder")
			end, "broken")
			ns.On("UNIT_HEALTH", function()
				ran = true
			end)
			wow.fire("UNIT_HEALTH", "player")
			assert.is_true(ran)
			local errors = ns.Errors()
			assert.equal("broken", errors[#errors].where)
			assert.matches("broken recorder", errors[#errors].msg)
		end)

		it("stops one listener and unregisters the event after the last one", function()
			local calls = 0
			local h1 = ns.On("BAG_UPDATE", function()
				calls = calls + 1
			end)
			local h2 = ns.On("BAG_UPDATE", function()
				calls = calls + 10
			end)
			ns.Off("BAG_UPDATE", h1)
			wow.fire("BAG_UPDATE")
			assert.equal(10, calls)
			ns.Off("BAG_UPDATE", h2)
			wow.fire("BAG_UPDATE")
			assert.equal(10, calls)
			for _, frame in ipairs(wow.frames) do
				assert.is_nil(frame.events.BAG_UPDATE)
			end
		end)

		it("finishes the running dispatch when a listener removes another", function()
			local calls = {}
			local second
			ns.On("BAG_UPDATE", function()
				calls[#calls + 1] = "first"
				ns.Off("BAG_UPDATE", second)
			end)
			second = ns.On("BAG_UPDATE", function()
				calls[#calls + 1] = "second"
			end)
			wow.fire("BAG_UPDATE")
			wow.fire("BAG_UPDATE")
			assert.same({ "first", "second", "first" }, calls)
		end)

		it("logs an event that the frame refuses once and does not raise", function()
			ns = wow.boot({ login = false, unknownEvents = { COMBAT_LOG_EVENT_UNFILTERED = true } })
			local before = #ns.Errors()
			assert.is_nil(ns.On("COMBAT_LOG_EVENT_UNFILTERED", function() end, "combat log"))
			assert.is_nil(ns.On("COMBAT_LOG_EVENT_UNFILTERED", function() end, "combat log"))
			local errors = ns.Errors()
			assert.equal(before + 1, #errors)
			assert.equal("combat log", errors[#errors].where)
			assert.matches("unknown event", errors[#errors].msg)
		end)
	end)

	describe("OnUnit", function()
		it("gets the events of its unit only, through one frame for each unit", function()
			local frames = #wow.frames
			local calls = {}
			ns.OnUnit("UNIT_AURA", "player", function(event, unit)
				calls[#calls + 1] = event .. ":" .. unit
			end)
			ns.OnUnit("UNIT_PET", "player", function(event, unit)
				calls[#calls + 1] = event .. ":" .. unit
			end)
			ns.OnUnit("UNIT_AURA", "target", function(event, unit)
				calls[#calls + 1] = "target " .. event .. ":" .. unit
			end)
			-- The core already has the frame of the player, for the casts of a fight.
			assert.equal(frames + 1, #wow.frames)
			wow.fire("UNIT_AURA", "party1")
			wow.fire("UNIT_AURA", "player")
			wow.fire("UNIT_PET", "player")
			wow.fire("UNIT_AURA", "target")
			assert.same({ "UNIT_AURA:player", "UNIT_PET:player", "target UNIT_AURA:target" }, calls)
		end)

		it("keeps running the other handlers when one fails, and logs the failure", function()
			local ran = false
			ns.OnUnit("UNIT_AURA", "player", function()
				error("broken unit handler")
			end, "aura")
			ns.OnUnit("UNIT_AURA", "player", function()
				ran = true
			end)
			wow.fire("UNIT_AURA", "player")
			assert.is_true(ran)
			local errors = ns.Errors()
			assert.equal("aura", errors[#errors].where)
		end)

		it("logs an event that the frame refuses once and does not raise", function()
			ns = wow.boot({ login = false, unknownEvents = { UNIT_NOPE = true } })
			local before = #ns.Errors()
			assert.is_nil(ns.OnUnit("UNIT_NOPE", "player", function() end, "nope"))
			assert.is_nil(ns.OnUnit("UNIT_NOPE", "player", function() end, "nope"))
			local errors = ns.Errors()
			assert.equal(before + 1, #errors)
			assert.equal("nope", errors[#errors].where)
		end)
	end)

	describe("Listen and Emit", function()
		it("calls each handler in order with the message and its arguments", function()
			local calls = {}
			ns.Listen("LEVEL_UP", function(msg, level)
				calls[#calls + 1] = "1:" .. msg .. ":" .. level
			end)
			ns.Listen("LEVEL_UP", function(msg, level)
				calls[#calls + 1] = "2:" .. msg .. ":" .. level
			end)
			ns.Emit("LEVEL_UP", 11)
			assert.same({ "1:LEVEL_UP:11", "2:LEVEL_UP:11" }, calls)
		end)

		it("keeps running the other handlers when one fails", function()
			local ran = false
			ns.Listen("LEVEL_UP", function()
				error("broken handler")
			end, "level handler")
			ns.Listen("LEVEL_UP", function()
				ran = true
			end)
			ns.Emit("LEVEL_UP", 11)
			assert.is_true(ran)
			assert.equal("level handler", ns.Errors()[#ns.Errors()].where)
		end)

		it("keeps messages apart from game events and from each other", function()
			local calls = 0
			ns.Listen("LEVEL_UP", function()
				calls = calls + 1
			end)
			wow.fire("LEVEL_UP", 11)
			ns.Emit("DIED")
			ns.Emit("NOBODY_LISTENS")
			assert.equal(0, calls)
		end)
	end)

	describe("Protect", function()
		it("returns true and up to 4 results", function()
			assert.same({ true, 1, 2, 3, 4 }, { ns.Protect("w", function(a, b)
				return a, b, 3, 4, 5
			end, 1, 2) })
		end)

		it("passes nil arguments in place", function()
			local ok, n = ns.Protect("w", function(...)
				return select("#", ...)
			end, nil, 2, nil)
			assert.is_true(ok)
			assert.equal(3, n)
		end)

		it("returns false, saves the error with a stack and passes it to the error handler", function()
			assert.is_false(ns.Protect("test", error, "boom", 0))
			local e = ns.Errors()[#ns.Errors()]
			assert.equal("test", e.where)
			assert.equal("boom", e.msg)
			assert.equal(wow.wall, e.t)
			assert.is_string(e.stack)
			assert.equal("boom", wow.errors[#wow.errors])
		end)

		it("logs the message when building the stack fails", function()
			_G.debugstack = function()
				error("no stack")
			end
			assert.is_false(ns.Protect("test", error, "boom", 0))
			local e = ns.Errors()[#ns.Errors()]
			assert.equal("test", e.where)
			assert.is_string(e.msg)
			assert.are_not.equal("nil", e.msg)
		end)

		it("prints one chat line for each place per session, with the place and the error", function()
			ns.Protect("a", error, "1", 0)
			ns.Protect("a", error, "2", 0)
			ns.Protect("b", error, "3", 0)
			assert.same({
				"Memories: A feature could not start. Some functions can be missing. [a: 1]",
				"Memories: A feature could not start. Some functions can be missing. [b: 3]",
			}, wow.chat())
		end)

		it("prints the chat line that the caller names", function()
			assert.is_false(ns.ProtectWith("Custom line.", "c", error, "4", 0))
			assert.same({ "Memories: Custom line. [c: 4]" }, wow.chat())
		end)

		it("ReportOnce prints a key once, with or without an error", function()
			assert.is_true(ns.ReportOnce("k", "Text."))
			assert.is_false(ns.ReportOnce("k", "Text.", "again"))
			assert.is_true(ns.ReportOnce("e", "Text.", "boom"))
			assert.same({ "Memories: Text. [k]", "Memories: Text. [e: boom]" }, wow.chat())
		end)

		it("keeps the last 100 errors", function()
			for i = 1, 101 do
				ns.LogError("loop", "error " .. i)
			end
			local errors = MemoriesDB.errors
			assert.equal(100, #errors)
			assert.equal("error 2", errors[1].msg)
			assert.equal("error 101", errors[100].msg)
		end)
	end)

	describe("Coalesce", function()
		it("runs once per key after the delay", function()
			local runs = 0
			for _ = 1, 3 do
				ns.Coalesce("bags", 1, function()
					runs = runs + 1
				end)
			end
			wow.advance(0.5)
			assert.equal(0, runs)
			wow.advance(0.5)
			assert.equal(1, runs)
			ns.Coalesce("bags", 1, function()
				runs = runs + 1
			end)
			wow.advance(1)
			assert.equal(2, runs)
		end)

		it("runs the function of the latest request", function()
			local ran
			ns.Coalesce("bags", 1, function()
				ran = "first"
			end)
			ns.Coalesce("bags", 1, function()
				ran = "last"
			end)
			wow.advance(1)
			assert.equal("last", ran)
		end)

		it("restarts the timer on each request", function()
			local runs = 0
			local function bump()
				runs = runs + 1
			end
			ns.Coalesce("bags", 1, bump)
			wow.advance(0.9)
			ns.Coalesce("bags", 1, bump)
			wow.advance(0.9)
			assert.equal(0, runs)
			wow.advance(0.1)
			assert.equal(1, runs)
		end)

		it("keeps keys apart", function()
			local runs = {}
			ns.Coalesce("a", 1, function()
				runs[#runs + 1] = "a"
			end)
			ns.Coalesce("b", 1, function()
				runs[#runs + 1] = "b"
			end)
			wow.advance(1)
			assert.same({ "a", "b" }, runs)
		end)
	end)

	describe("AfterCombat", function()
		it("runs at once out of combat", function()
			local ran = false
			ns.AfterCombat("x", function()
				ran = true
			end)
			assert.is_true(ran)
		end)

		it("waits for PLAYER_REGEN_ENABLED and runs each key once with its last function", function()
			wow.combat = true
			local runs = {}
			ns.AfterCombat("x", function()
				runs[#runs + 1] = "x1"
			end)
			ns.AfterCombat("y", function()
				runs[#runs + 1] = "y"
			end)
			ns.AfterCombat("x", function()
				runs[#runs + 1] = "x2"
			end)
			assert.same({}, runs)
			wow.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.same({ "x2", "y" }, runs)
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.same({ "x2", "y" }, runs)
		end)
	end)

	describe("Print", function()
		it("prefixes the addon name", function()
			ns.Print("hello", 3)
			assert.same({ "|cff9fd3ffMemories|r: hello 3" }, wow.chat_raw)
		end)
	end)

	describe("R and RN", function()
		it("passes a normal value", function()
			assert.same({ "Minería", false }, { ns.R("Minería") })
		end)

		it("turns a secret value into nil", function()
			assert.same({ nil, true }, { ns.R(wow.secret("x")) })
		end)

		it("works when issecretvalue does not exist", function()
			ns = wow.boot({ login = false, noSecrets = true })
			assert.same({ 5, false }, { ns.R(5) })
			assert.same({ 1, 2, false }, { ns.RN(1, 2) })
		end)

		it("filters several values and reports any secret", function()
			local a, b, c, secret = ns.RN("a", wow.secret("b"), nil)
			assert.equal("a", a)
			assert.is_nil(b)
			assert.is_nil(c)
			assert.is_true(secret)
			assert.same({ 1, 2, false }, { ns.RN(1, 2) })
		end)
	end)

	describe("Position", function()
		it("returns the map and integer coordinates", function()
			wow.map = { id = 1429, x = 0.41234, y = 0.6 }
			assert.same({ 1429, 4123, 6000 }, { ns.Position() })
		end)

		it("returns nil without a map", function()
			wow.map = {}
			assert.same({}, { ns.Position() })
		end)

		it("returns only the map when the position is unknown", function()
			wow.map = { id = 1429 }
			assert.same({ 1429 }, { ns.Position() })
		end)

		it("returns only the map when a coordinate is secret", function()
			wow.map = { id = 1429, x = wow.secret(0.5), y = 0.5 }
			assert.same({ 1429 }, { ns.Position() })
		end)

		it("returns only the map when the player is outside the map's rectangle", function()
			wow.map = { id = 1429, x = -0.05, y = 0.5 }
			assert.same({ 1429 }, { ns.Position() })
			wow.map = { id = 1429, x = 0.5, y = 1.2 }
			assert.same({ 1429 }, { ns.Position() })
			wow.map = { id = 1429, x = 1, y = 0 }
			assert.same({ 1429, 10000, 0 }, { ns.Position() })
		end)

		it("returns nil when the map is secret", function()
			wow.map = { id = wow.secret(1429), x = 0.5, y = 0.5 }
			assert.same({}, { ns.Position() })
		end)
	end)

	describe("Util", function()
		it("splits on a plain separator and keeps empty fields", function()
			assert.same({ "a", "", "b.c", "" }, ns.U.Split("a||b.c|", "|"))
			assert.same({ "" }, ns.U.Split("", "|"))
		end)

		it("copies tables deeply", function()
			local t = { a = { b = { 1, 2 } }, c = "x" }
			local copy = ns.U.Copy(t)
			assert.same(t, copy)
			assert.are_not.equal(t.a, copy.a)
			assert.are_not.equal(t.a.b, copy.a.b)
			assert.equal(5, ns.U.Copy(5))
		end)

		describe("Utf8Cut", function()
			it("keeps a string that fits", function()
				assert.equal("Minería", ns.U.Utf8Cut("Minería", 8))
				assert.equal("Minería", ns.U.Utf8Cut("Minería", 20))
			end)

			it("never splits a 2-byte character", function()
				assert.equal("Miner", ns.U.Utf8Cut("Minería", 6))
				assert.equal("Minerí", ns.U.Utf8Cut("Minería", 7))
			end)

			it("never splits a 3-byte character", function()
				assert.equal("a", ns.U.Utf8Cut("a€b", 2))
				assert.equal("a", ns.U.Utf8Cut("a€b", 3))
				assert.equal("a€", ns.U.Utf8Cut("a€b", 4))
			end)

			it("never splits a 4-byte character", function()
				for n = 1, 4 do
					assert.equal("a", ns.U.Utf8Cut("a😀b", n))
				end
				assert.equal("a😀", ns.U.Utf8Cut("a😀b", 5))
				assert.equal("", ns.U.Utf8Cut("😀", 3))
			end)

			it("returns an empty string for a limit of zero or less", function()
				assert.equal("", ns.U.Utf8Cut("abc", 0))
				assert.equal("", ns.U.Utf8Cut("abc", -1))
			end)
		end)

		describe("Hook", function()
			it("runs the function after the original with its arguments", function()
				local calls = {}
				local target = {
					Open = function(_, what)
						calls[#calls + 1] = "orig:" .. what
						return "result"
					end,
				}
				assert.is_true(ns.U.Hook(target, "Open", function(_, what)
					calls[#calls + 1] = "hook:" .. what
				end))
				assert.equal("result", target:Open("bag"))
				assert.same({ "orig:bag", "hook:bag" }, calls)
			end)

			it("hooks a global function when the target is nil", function()
				local seen
				_G.TakeTaxiNode = function() end
				assert.is_true(ns.U.Hook(nil, "TakeTaxiNode", function(node)
					seen = node
				end))
				_G.TakeTaxiNode(3)
				assert.equal(3, seen)
			end)

			it("logs an error inside the hook and does not raise", function()
				local target = { Open = function() end }
				ns.U.Hook(target, "Open", function()
					error("hook failed")
				end)
				assert.has_no.errors(function()
					target.Open()
				end)
				assert.equal("hook:Open", ns.Errors()[#ns.Errors()].where)
			end)

			it("returns false and logs nothing for a missing function", function()
				local before = #ns.Errors()
				assert.is_false(ns.U.Hook({}, "Missing", function() end))
				assert.is_false(ns.U.Hook(nil, "NoSuchGlobalFunction", function() end))
				assert.is_false(ns.U.Hook({ Value = 5 }, "Value", function() end))
				assert.equal(before, #ns.Errors())
			end)
		end)
	end)
end)
