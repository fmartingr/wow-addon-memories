local wow = require("helpers.wow")

describe("windows", function()
	local ns

	before_each(function()
		ns = wow.boot()
		_G.UISpecialFrames = {}
	end)

	it("uses ButtonFrameTemplate without the portrait, and the inset fills the window", function()
		local hidden
		_G.ButtonFrameTemplate_HidePortrait = function(frame)
			hidden = frame
		end
		local real = _G.CreateFrame
		_G.CreateFrame = function(kind, name, parent, template)
			local frame = real(kind, name, parent, template)
			if template == "ButtonFrameTemplate" then
				frame.Inset = real("Frame", nil, frame)
				frame.SetTitle = function(self, text)
					self.title = text
				end
			end
			return frame
		end
		local frame = ns.Window.Create("MemoriesProbeFrame", 300, 200, "Probe")
		assert.equal("ButtonFrameTemplate", frame.template)
		assert.equal(frame, hidden)
		assert.equal("Probe", frame.title)
		assert.same({ "BOTTOMRIGHT", -6, 4, n = 3 }, frame.Inset.point)
		assert.is_false(frame:IsShown())
		assert.is_true(frame.clamped)
		assert.same({ "MemoriesProbeFrame" }, UISpecialFrames)
	end)

	it("falls back to BasicFrameTemplateWithInset when the client refuses ButtonFrameTemplate", function()
		local real = _G.CreateFrame
		_G.CreateFrame = function(kind, name, parent, template)
			if template == "ButtonFrameTemplate" then
				error("unknown template")
			end
			return real(kind, name, parent, template)
		end
		local frame = ns.Window.Create("MemoriesProbeFrame", 300, 200, "Probe")
		assert.equal("BasicFrameTemplateWithInset", frame.template)
	end)

	it("lists a frame name once for Escape", function()
		ns.Window.Create("MemoriesProbeFrame", 300, 200, "Probe")
		ns.Window.Create("MemoriesProbeFrame", 300, 200, "Probe")
		assert.same({ "MemoriesProbeFrame" }, UISpecialFrames)
	end)

	it("moves with a drag", function()
		local frame = ns.Window.Create("MemoriesProbeFrame", 300, 200, "Probe")
		local calls = {}
		frame.StartMoving = function()
			calls[#calls + 1] = "start"
		end
		frame.StopMovingOrSizing = function()
			calls[#calls + 1] = "stop"
		end
		frame:GetScript("OnDragStart")(frame)
		frame:GetScript("OnDragStop")(frame)
		assert.same({ "start", "stop" }, calls)
	end)
end)
