local serialize = require("helpers.serialize")

describe("serialize", function()
	it("writes the saved-file form with sorted keys", function()
		local text = serialize.file({ B = { "x", "y", z = 1, [10] = true, a = 0.5 }, A = false })
		assert.equal(
			'A = false\nB = {\n\t"x", -- [1]\n\t"y", -- [2]\n\t[10] = true,\n\t["a"] = 0.5,\n\t["z"] = 1,\n}\n',
			text
		)
	end)

	it("loads back what it writes", function()
		local value = {
			s = 'quote " slash \\ bar | line\n cr\r nul\0 del\127 ñ',
			n = { 1, -2, 3.25, 1e15, 0.1 },
			nested = { deep = { [true] = "t", [false] = "f" } },
			empty = {},
		}
		local env = assert(serialize.load(serialize.file({ Saved = value })))
		assert.same(value, env.Saved)
	end)

	it("returns the load error", function()
		local env, err = serialize.load("Saved = {")
		assert.is_nil(env)
		assert.matches("expected", err)
	end)

	it("refuses values that a saved file cannot hold", function()
		assert.has_error(function()
			serialize.value({ f = print })
		end)
		local t = {}
		t.self = t
		assert.has_error(function()
			serialize.value(t)
		end)
		assert.has_error(function()
			serialize.value(0 / 0)
		end)
	end)
end)
