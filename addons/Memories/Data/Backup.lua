local _, ns = ...

local Backup = {}
ns.Backup = Backup

local U = ns.U

Backup.EVERY = 15 * 60
Backup.FIRST = 5

local function playerGuid()
	return (ns.R(UnitGUID("player")))
end

-- The backups of one character, by addon. MemoriesDB is a file the player can edit, so every level is checked.
local function records(guid, create)
	if not guid or type(MemoriesDB) ~= "table" then
		return nil
	end
	if create then
		return U.TableAt(U.TableAt(MemoriesDB, "backups"), guid)
	end
	local all = MemoriesDB.backups
	local mine = type(all) == "table" and all[guid]
	return type(mine) == "table" and mine or nil
end

-- The player's backup record of an addon, or nil.
function Backup.Record(addon, guid)
	local mine = records(guid or playerGuid())
	local rec = mine and mine[addon]
	return type(rec) == "table" and rec or nil
end

local function compression()
	local enum = Enum and Enum.CompressionMethod
	local level = Enum and Enum.CompressionLevel
	return enum and enum.Deflate, level and level.OptimizeForSpeed
end

local function encode(data)
	local E = C_EncodingUtil
	local method, level = compression()
	local s = E.SerializeCBOR(data)
	local packed
	if method and level then
		packed = E.CompressString(s, method, level)
	elseif method then
		packed = E.CompressString(s, method)
	else
		packed = E.CompressString(s)
	end
	local blob = E.EncodeBase64(packed)
	assert(type(blob) == "string" and blob ~= "", "no blob")
	return blob
end

local function decode(blob)
	local E = C_EncodingUtil
	local method = compression()
	local packed = E.DecodeBase64(blob)
	local s
	if method then
		s = E.DecompressString(packed, method)
	else
		s = E.DecompressString(packed)
	end
	local data = E.DeserializeCBOR(s)
	assert(type(data) == "table", "the backup is not a table")
	return data
end

local function canEncode()
	local E = C_EncodingUtil
	return type(E) == "table"
		and E.SerializeCBOR
		and E.CompressString
		and E.EncodeBase64
		and E.DecodeBase64
		and E.DecompressString
		and E.DeserializeCBOR
		and true
end

-- Returns true, or false and why it skipped: "unknown", "read only", "held", "empty" or "no guid".
function Backup.Write(addon)
	local item = ns.Registry.Journal(addon)
	if not item then
		return false, "unknown"
	end
	local j = item.journal
	if not j:CanWrite() then
		return false, "read only"
	end
	local guid = playerGuid()
	if not guid then
		return false, "no guid"
	end
	local old = Backup.Record(addon, guid)
	if old and old.hold then
		return false, "held"
	end
	local lines = j:LineCount()
	if lines == 0 then
		return false, "empty"
	end
	local rec = { t = time(), level = ns.Level(), lines = lines }
	local ok, blob = false, nil
	if canEncode() then
		ok, blob = pcall(encode, j.data)
	end
	if ok then
		rec.blob = blob
	else
		rec.data = U.Copy(j.data)
	end
	records(guid, true)[addon] = rec
	return true
end

-- Returns the backup's data table as a new table, or nil and why.
function Backup.Read(addon, guid)
	local rec = Backup.Record(addon, guid)
	if not rec then
		return nil, "no backup"
	end
	if type(rec.data) == "table" then
		return U.Copy(rec.data)
	end
	if type(rec.blob) ~= "string" then
		return nil, "no backup"
	end
	if not canEncode() then
		return nil, "no decoder"
	end
	local ok, data = pcall(decode, rec.blob)
	if not ok then
		return nil, "bad backup: " .. tostring(data)
	end
	return data
end

-- Replaces the addon's data with its backup. The current data goes to MemoriesDB.orphans. Returns true, or false and
-- why. A backup that does not decode leaves the current data as it is.
function Backup.Restore(addon)
	local item = ns.Registry.Journal(addon)
	if not item then
		return false, "unknown"
	end
	if not item.journal:CanWrite() then
		return false, "read only"
	end
	local guid = playerGuid()
	local data, err = Backup.Read(addon, guid)
	if not data then
		ns.LogError("backup:" .. addon, err)
		return false, err
	end
	local saved = _G[item.saved]
	local char = type(saved.char) == "table" and saved.char or {}
	ns.Store.Orphan(addon, guid, char.name, saved, "restored backup")
	for k, v in pairs(data) do
		saved[k] = v
	end
	-- The hold ends before the journal opens again, so the data guard sees the restored lines and stays quiet.
	Backup.Record(addon, guid).hold = nil
	local j = ns.Registry.Reopen(addon)
	j:Write("nt", "restored backup", j:LineCount())
	ns.Emit("RESTORED", addon)
	return true
end

local queue
local again = false

local function step()
	local addon = table.remove(queue, 1)
	if not addon then
		queue = nil
		if again then
			again = false
			Backup.Run()
		end
		return
	end
	ns.Protect("backup:" .. addon, Backup.Write, addon)
	-- One addon per frame spreads the encoding cost of large journals.
	C_Timer.After(0, function()
		ns.AfterCombat("backup", step)
	end)
end

-- Writes the backup of every open journal, one per frame and never in combat. A request during a run starts one more
-- run after it, so the addons that run already wrote get the newer state too.
function Backup.Run()
	if queue then
		again = true
		return
	end
	-- The queue is set only once it is complete, so an error while listing never blocks the later runs.
	local list = {}
	for _, item in ipairs(ns.Registry.Journals()) do
		list[#list + 1] = item.addon
	end
	queue = list
	ns.AfterCombat("backup", step)
end

local function run()
	ns.Protect("backup", Backup.Run)
end

ns.Listen("LOGIN", function()
	C_Timer.After(Backup.FIRST, run)
	C_Timer.NewTicker(Backup.EVERY, run)
end, "backup")

ns.Listen("LEVEL_UP", Backup.Run, "backup")
