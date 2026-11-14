local _, ns = ...

local L = ns.L

-- /memories status: one line for each addon of the set, then the core's login time.
local Status = {}
ns.Status = Status

function Status.Age(seconds)
	seconds = math.max(0, seconds)
	if seconds < 60 then
		return L.DURATION_SECONDS:format(seconds)
	elseif seconds < 3600 then
		return L.DURATION_MINUTES:format(seconds / 60)
	elseif seconds < 86400 then
		return L.DURATION_HOURS:format(seconds / 3600)
	end
	return L.DURATION_DAYS:format(seconds / 86400)
end

-- The owner of each kind: the registered ones, and the saved ones of addons that are not loaded now.
local function owners()
	local out = {}
	local saved = type(MemoriesDB) == "table" and type(MemoriesDB.kinds) == "table" and MemoriesDB.kinds or {}
	for kind, text in pairs(saved) do
		if type(text) == "string" then
			out[kind] = text:match("^([^;]*);")
		end
	end
	for _, spec in ipairs(ns.Kinds.All()) do
		out[spec.kind] = not spec.always and spec.addon or nil
	end
	return out
end

local function kindsOff()
	local off = {}
	local owner = owners()
	for kind, on in pairs(ns.Settings.Root().kinds) do
		local addon = owner[kind]
		if on == false and addon then
			off[addon] = (off[addon] or 0) + 1
		end
	end
	return off
end

local function backup(addon)
	local rec = ns.Backup.Record(addon)
	if not rec or type(rec.t) ~= "number" then
		return L.NO_BACKUP
	end
	return L.BACKUP_AGO:format(Status.Age(time() - rec.t))
end

-- The registry keeps these states as English tokens; the translation happens here, where they are printed.
local STATE = {
	on = L.ON,
	failed = L.FAILED,
	missing = L.MISSING,
	off = L.OFF,
	["newer api"] = L.NEWER_API,
}

local STEPS = { "init", "login", "world" }

function Status.Lines()
	local out = {}
	local off = kindsOff()
	for _, a in ipairs(ns.Public.Addons()) do
		local line =
			L.STATUS_LINE:format(a.addon, STATE[a.state] or a.state, a.lines, off[a.addon] or 0, backup(a.addon))
		out[#out + 1] = a.readOnly and L.READ_ONLY:format(line) or line
	end
	local times = {}
	for _, step in ipairs(STEPS) do
		local ms = ns.loginTime[step]
		if ms then
			times[#times + 1] = ("%s %.0f ms"):format(step, ms)
		end
	end
	out[#out + 1] = L.LOGIN_TIME:format(#times > 0 and table.concat(times, ", ") or L.UNKNOWN)
	return out
end

function Status.Print()
	ns.Print(L.STATUS_HEADER)
	for _, line in ipairs(Status.Lines()) do
		ns.Print(line)
	end
end

ns.Commands.Register("status", Status.Print, "HELP_STATUS")
