local _, ns = ...

-- The notes that the player writes. A note is one "un" line. A link to an item or a quest is a token, because the
-- codec turns "|" into "/" and so breaks a game hyperlink.
local Notes = {}
ns.Notes = Notes

Notes.MAX = 400

local function wholeNumber(id)
	return type(id) == "number" and id > 0 and id % 1 == 0 and id < 2 ^ 31
end

-- A link name can hold escapes (a quality atlas, a colour); the codec would turn their "|" into "/".
local function cleanName(name)
	name = tostring(name or ""):gsub("|[TA].-|[ta]", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", "")
	name = name:gsub("|r", ""):gsub("|n", " "):gsub("[{}|]", ""):gsub("%c", " "):gsub("%s+", " ")
	return (name:gsub("^ ", ""):gsub(" $", ""))
end

local function token(kind, id, name)
	if not wholeNumber(id) then
		return nil
	end
	return ("{%s:%d:%s}"):format(kind, id, cleanName(name))
end

function Notes.ItemToken(id, name)
	return token("item", id, name)
end

function Notes.QuestToken(id, title)
	return token("quest", id, title)
end

-- A token for a game hyperlink of an item or a quest, else nil.
function Notes.TokenFromLink(link)
	if type(link) ~= "string" then
		return nil
	end
	local kind, id, name = link:match("|H(%a+):(%d+)[^|]*|h%[(.-)%]|h")
	if kind == "item" then
		return Notes.ItemToken(tonumber(id), name)
	elseif kind == "quest" then
		return Notes.QuestToken(tonumber(id), name)
	end
	return nil
end

-- The text as the journal keeps it: an escaped "||" from an edit box is one "|", control characters (line breaks too)
-- become a space, and the ends are trimmed.
function Notes.Clean(text)
	if type(text) ~= "string" then
		return ""
	end
	return (text:gsub("||", "|"):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- True when tail (from a "{" to the end) is the start of an item or quest token and not a plain brace.
local function openToken(tail)
	local kind, rest = tail:match("^{(%a*)(.*)$")
	if kind ~= "item" and kind ~= "quest" then
		return rest == "" and (("item"):sub(1, #kind) == kind or ("quest"):sub(1, #kind) == kind)
	end
	return rest == "" or rest:match("^:%d*$") ~= nil or rest:match("^:%d+:[^}]*$") ~= nil
end

-- Cuts text to Notes.MAX bytes, never inside a character, and drops a token that the cut leaves open.
function Notes.Fit(text)
	if #text <= Notes.MAX then
		return text
	end
	local cut = ns.U.Utf8Cut(text, Notes.MAX)
	local open = cut:match("^.*(){")
	if open and openToken(cut:sub(open)) then
		cut = cut:sub(1, open - 1)
	end
	return (cut:gsub("%s+$", ""))
end

-- Returns the line, or nil and why: "empty", "off" or "read only".
function Notes.Add(text)
	text = Notes.Fit(Notes.Clean(text))
	if text == "" then
		return nil, "empty"
	end
	local j = ns.Store.Core()
	if not j then
		return nil, "read only"
	end
	local line, why = j:Write("un", text)
	if not line then
		return nil, why
	end
	j:Count("notes", "written")
	return line
end
