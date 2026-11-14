local _, ns = ...

local L = ns.L

-- /memories and /mem. Each feature registers its own subcommand at load time.
local Commands = {}
ns.Commands = Commands

local COMMAND = "/memories"

local entries = {}
local byName = {}

-- helpKey is a locale key, so the help list is translated.
function Commands.Register(name, fn, helpKey)
	local lower = name:lower()
	local entry = byName[lower]
	if not entry then
		entry = {}
		entries[#entries + 1] = entry
		byName[lower] = entry
	end
	entry.name, entry.fn, entry.helpKey = lower, fn, helpKey
end

function Commands.PrintHelp()
	ns.Print(L["Commands:"])
	for _, entry in ipairs(entries) do
		ns.Print(("%s %s - %s"):format(COMMAND, entry.name, entry.helpKey and L[entry.helpKey] or ""))
	end
end

function Commands.Dispatch(msg)
	local word, rest = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local entry = byName[word:lower()]
	if not entry then
		Commands.PrintHelp()
		return
	end
	ns.ProtectWith(L["The command failed. Some functions can be missing."], "slash:" .. entry.name, entry.fn, rest)
end

Commands.Register("help", Commands.PrintHelp, "show this list")

SLASH_MEMORIES1 = COMMAND
SLASH_MEMORIES2 = "/mem"
SlashCmdList.MEMORIES = Commands.Dispatch
