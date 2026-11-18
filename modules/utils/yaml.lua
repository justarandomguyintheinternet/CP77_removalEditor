--- Minimal YAML reader / writer for ArchiveXL .xl files.
--- Reads block mappings and sequences, flow collections ([1, 2], {a: 1}) on one line, quoted and plain scalars and
--- comments, which are written back on save (see Comments below). Anything else (block scalars |, multi-line values,
--- anchors, tags) gives an error with its line number, instead of wrong data.
local yaml = {}

-- Key order of the mappings read, so that a saved file keeps the order of its source
local keyOrders = setmetatable({}, { __mode = "k" })
-- Tables read as mappings: an empty mapping cannot be told from an empty list otherwise
local mappings = setmetatable({}, { __mode = "k" })

local function fail(line, message)
    error({ yamlError = string.format("line %d: %s", line, message) }, 0)
end

-- YAML 1.1 booleans (PyYAML, yaml-cpp's as<bool>) that a plain string must not look like
local reservedWords = {
    ["true"] = true, ["false"] = true, ["yes"] = true, ["no"] = true, ["on"] = true, ["off"] = true,
    ["y"] = true, ["n"] = true, ["null"] = true, ["~"] = true
}

--- Value of a plain (unquoted) scalar
---@param text string
---@return any
local function resolvePlain(text)
    if text == "" or text == "~" or text == "null" or text == "Null" or text == "NULL" then return nil end
    if text == "true" or text == "True" or text == "TRUE" then return true end
    if text == "false" or text == "False" or text == "FALSE" then return false end

    if text:match("^[-+]?%d+$") then
        -- Node hashes do not fit in a double: kept as text, as Removal Editor writes them
        if #text:gsub("^[-+]", "") > 15 then return text end
        return tonumber(text)
    end
    if text:match("^[-+]?%d*%.%d+$") or text:match("^[-+]?%d+%.%d*$")
        or text:match("^[-+]?%d*%.?%d+[eE][-+]?%d+$") then
        return tonumber(text)
    end

    return text
end

--- Quoted scalar starting at text[i], returns its value and the index after it
local function readQuoted(text, i, line)
    local quote = text:sub(i, i)
    local parts = {}
    local j = i + 1

    while j <= #text do
        local c = text:sub(j, j)
        if quote == "'" then
            if c == "'" then
                if text:sub(j + 1, j + 1) == "'" then
                    parts[#parts + 1] = "'"
                    j = j + 2
                else
                    return table.concat(parts), j + 1
                end
            else
                parts[#parts + 1] = c
                j = j + 1
            end
        else
            if c == '"' then
                return table.concat(parts), j + 1
            elseif c == "\\" then
                local e = text:sub(j + 1, j + 1)
                local simple = { ["\\"] = "\\", ['"'] = '"', ["/"] = "/", n = "\n", t = "\t", r = "\r", ["0"] = "\0",
                    b = "\b", f = "\f", a = "\a", v = "\v", e = "\27", [" "] = " " }
                if simple[e] then
                    parts[#parts + 1] = simple[e]
                    j = j + 2
                elseif e == "x" or e == "u" or e == "U" then
                    local size = ({ x = 2, u = 4, U = 8 })[e]
                    local hex = text:sub(j + 2, j + 1 + size)
                    if not hex:match("^%x+$") or #hex ~= size then fail(line, "bad escape \\" .. e) end
                    local code = tonumber(hex, 16)
                    if code < 0x80 then
                        parts[#parts + 1] = string.char(code)
                    elseif code < 0x800 then
                        parts[#parts + 1] = string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
                    elseif code < 0x10000 then
                        parts[#parts + 1] = string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
                    else
                        parts[#parts + 1] = string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
                            0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
                    end
                    j = j + 2 + size
                else
                    fail(line, "unknown escape \\" .. e)
                end
            else
                parts[#parts + 1] = c
                j = j + 1
            end
        end
    end

    fail(line, "quoted text not closed (values over several lines are not supported)")
end

--- Flow collection or scalar starting at text[i], inside a flow collection
local readFlow

local function skipSpaces(text, i)
    return text:find("[^ ]", i) or #text + 1
end

local function readFlowCollection(text, i, line)
    local open = text:sub(i, i)
    local close = open == "[" and "]" or "}"
    local result = {}
    local keys = {}
    if open == "{" then
        mappings[result] = true
        keyOrders[result] = keys
    end

    i = skipSpaces(text, i + 1)
    if text:sub(i, i) == close then return result, i + 1 end

    while true do
        if i > #text then fail(line, "'" .. open .. "' not closed (collections over several lines are not supported)") end

        if open == "[" then
            local value
            value, i = readFlow(text, i, line, false)
            result[#result + 1] = value
        else
            local key
            key, i = readFlow(text, i, line, true)
            i = skipSpaces(text, i)
            local value = nil
            local c = text:sub(i, i)
            if c == ":" then
                value, i = readFlow(text, skipSpaces(text, i + 1), line, false)
            elseif c ~= "," and c ~= "}" then
                fail(line, "':' expected after key '" .. tostring(key) .. "'")
            end -- "{key}": a key without value
            key = tostring(key)
            if result[key] == nil then keys[#keys + 1] = key end
            result[key] = value
        end

        i = skipSpaces(text, i)
        local c = text:sub(i, i)
        if c == close then return result, i + 1 end
        if c ~= "," then fail(line, "',' or '" .. close .. "' expected") end
        i = skipSpaces(text, i + 1)
        if text:sub(i, i) == close then return result, i + 1 end -- Trailing comma
    end
end

readFlow = function(text, i, line, isKey)
    local c = text:sub(i, i)
    if c == "[" or c == "{" then return readFlowCollection(text, i, line) end
    if c == "'" or c == '"' then return readQuoted(text, i, line) end

    -- Plain scalar: up to a flow indicator (or ':' for a key)
    local stop = isKey and "[,%[%]{}:]" or "[,%[%]{}]"
    local j = text:find(stop, i) or #text + 1
    local value = text:sub(i, j - 1):match("^(.-)%s*$")
    return resolvePlain(value), j
end

--- Value written after "key:" or "- " on one line
local function readInlineValue(text, line)
    local c = text:sub(1, 1)
    if c == "|" or c == ">" then fail(line, "block scalars (| or >) are not supported") end
    if c == "&" or c == "*" or c == "!" then fail(line, "anchors, aliases and tags are not supported") end

    if c == "[" or c == "{" or c == "'" or c == '"' then
        local value, nextIndex = readFlow(text, 1, line, false)
        if text:sub(nextIndex):match("%S") then fail(line, "unexpected text after the value") end
        return value
    end

    return resolvePlain(text)
end

--- Splits a line into its content and its comment ("#" at the start or after a space, outside of quotes), both
--- without trailing spaces / tabs
---@return string content
---@return string? comment
local function splitComment(text)
    local quote = nil
    local i = 1
    while i <= #text do
        local c = text:sub(i, i)
        if quote then
            if c == quote then
                if quote == "'" and text:sub(i + 1, i + 1) == "'" then
                    i = i + 1
                else
                    quote = nil
                end
            elseif c == "\\" and quote == '"' then
                i = i + 1
            end
        elseif c == "'" or c == '"' then
            -- A quote only opens a quoted scalar where a value starts ("V's tent" is plain text)
            local before = text:sub(1, i - 1):match("^(.-)%s*$")
            if before == "" or before:match("[:%-%[{,?]$") then quote = c end
        elseif c == "#" and (i == 1 or text:sub(i - 1, i - 1):match("%s")) then
            return text:sub(1, i - 1):match("^(.-)%s*$"), text:sub(i):match("^(.-)%s*$")
        end
        i = i + 1
    end
    return (text:match("^(.-)%s*$")), nil
end

--- "key: value" split, nil if the text is not a mapping entry
local function splitKey(text, line)
    local c = text:sub(1, 1)
    local key, rest

    if c == "'" or c == '"' then
        local nextIndex
        key, nextIndex = readQuoted(text, 1, line)
        rest = text:sub(nextIndex)
        if not rest:match("^%s*:") then return nil end
        rest = rest:match("^%s*:(.*)$")
        if rest ~= "" and not rest:match("^%s") then return nil end
    else
        if c == "[" or c == "{" or c == "-" and (text == "-" or text:sub(2, 2) == " ") then return nil end
        local at = text:find(":%s") or (text:sub(-1) == ":" and #text or nil)
        if not at then return nil end
        key = text:sub(1, at - 1):match("^(.-)%s*$")
        if key == "" then return nil end
        rest = text:sub(at + 1)
    end

    return key, rest:match("^%s*(.-)$")
end

local function isSequenceItem(text)
    return text == "-" or text:sub(1, 2) == "- "
end

--[[ Comments
Each comment line (and blank line) belongs to what follows it: a key of a mapping or an item of a list. The comments
after the last item of a collection, indented at least as much as it, are its trailing comments. A comment at the end
of a line belongs to that line.

When a key or an item is gone at save time (a removal deleted in Removal Editor), the comments of its own go with
it, but the entries commented out above it ("# - index: 41", as ArchiveXL Sector Updater writes the nodes it left
out, with the comment lines before them) are kept: they move to the next key / item, or to the end of the
collection.
]]

-- Collection -> { order = { anchor, ... }, before = { [anchor] = { lines } }, inline = { [anchor] = text }, trailing = { lines } }
-- An anchor is the key of a mapping, the table of a list item, or "=" .. value for a list item that is a value.
-- A line is { text = "# ...", col = column } or { text = "" } for a blank line.
local comments = setmetatable({}, { __mode = "k" })

local function getComments(collection)
    local data = comments[collection]
    if not data then
        data = { order = {}, before = {}, inline = {}, trailing = {} }
        comments[collection] = data
    end
    return data
end

local function anchorOf(item)
    if type(item) == "table" then return item end
    return "=" .. type(item) .. ":" .. tostring(item)
end

local function record(collection, anchor, before, inline)
    local data = getComments(collection)
    data.seen = data.seen or {}
    if not data.seen[anchor] then
        data.seen[anchor] = true
        data.order[#data.order + 1] = anchor
    end
    -- The same value twice in a list: its comments are merged
    if before and #before > 0 then
        local lines = data.before[anchor] or {}
        for _, line in ipairs(before) do lines[#lines + 1] = line end
        data.before[anchor] = lines
    end
    if inline then data.inline[anchor] = inline end
end

--- Takes the comments before the current line that are indented at least as much as a collection ending there
local function takeTrailing(state, collection, indent)
    local line = state.lines[state.pos] or state.eof
    local data = getComments(collection)
    while line.comments[1] and (line.comments[1].col == nil or line.comments[1].col >= indent) do
        data.trailing[#data.trailing + 1] = table.remove(line.comments, 1)
    end
end

--- Takes the comments before a line, for the key / item it starts
local function takeBefore(line)
    local before = line.comments
    line.comments = {}
    return before
end

--- Spaces between "#" and the text of a comment, nil if it is not an entry commented out
local function commentedEntryStart(text)
    local spaces = text:match("^#( *)%-$") or text:match("^#( *)%- ")
    return spaces and #spaces
end

-- The comment ArchiveXL Sector Updater writes above what it commented out, with the reason
local function isUpdaterNote(text)
    return text:match("^#%s*axl_sector_updater:") ~= nil
end

-- Lists that ArchiveXL Sector Updater comments out with their key, once none of their entries is left
local commentedKeys = { nodeDeletions = true, nodeMutations = true, sectors = true }

local function isCommentedKey(text)
    local key = text:match("^# ([%w_]+):%s*$")
    return key ~= nil and commentedKeys[key] == true
end

--[[ Entries commented out
ArchiveXL Sector Updater comments a node out where it was, by writing "# " at the column of its "- ", above the lines
"# axl_sector_updater: <reason>":
        # axl_sector_updater: not found in 2.5
        # - index: 41
        #   type: worldStaticDecalNode
A whole sector is commented out the same way, its keys and the nodes it held (already commented out) more indented.
Removing that "# " gives the lines back as they were.
]]

--- The groups of lines that are entries commented out: { first, last }, the notes of ArchiveXL Sector Updater just
--- before them included. An entry goes on over the lines more indented than its "#", or at its column when they go on
--- with it ("#   type: ..."), are another entry or a note.
---@param lines table
---@return table[]
local function findCommentedRuns(lines)
    local runs = {}
    local i = 1

    while i <= #lines do
        local line = lines[i]
        if line.text ~= "" and (commentedEntryStart(line.text) or isCommentedKey(line.text)) then
            local col = line.col or 0
            local spaces = #line.text:match("^#( *)")

            local first = i
            while first > 1 and lines[first - 1].text ~= "" and isUpdaterNote(lines[first - 1].text)
                and (lines[first - 1].col or 0) == col do
                first = first - 1
            end

            local last = i
            local j = i + 1
            while j <= #lines do
                local nextLine = lines[j]
                if nextLine.text ~= "" then
                    local nextCol = nextLine.col or 0
                    local nextSpaces = nextLine.text:match("^#( *)")
                    local goesOn = nextCol > col or (nextCol == col and (isUpdaterNote(nextLine.text)
                        or commentedEntryStart(nextLine.text) ~= nil or (nextSpaces ~= nil and #nextSpaces > spaces)))
                    if not goesOn then break end
                    last = j
                end
                j = j + 1
            end

            runs[#runs + 1] = { first = first, last = last }
            i = last + 1
        else
            i = i + 1
        end
    end

    return runs
end

--- The lines of a group that are entries commented out, with the comments before them
local function keptLines(lines)
    local last = 0
    for _, run in ipairs(findCommentedRuns(lines)) do
        last = math.max(last, run.last)
    end

    local kept = {}
    for i = 1, last do kept[i] = lines[i] end
    return kept
end

--- True if a collection holds entries commented out (kept even when it has no entry left)
---@param collection table
---@return boolean
function yaml.hasCommentedEntries(collection)
    local data = type(collection) == "table" and comments[collection]
    if not data then return false end

    if #keptLines(data.trailing) > 0 then return true end
    for _, lines in pairs(data.before) do
        if #keptLines(lines) > 0 then return true end
    end
    return false
end

local parseBlock

local function parseSequence(state, indent)
    local list = {}
    -- Column of the collection, from which its comments keep their offset when written back
    getComments(list).indent = indent

    while true do
        local line = state.lines[state.pos]
        if not line or line.indent < indent then break end
        if line.indent > indent then fail(line.number, "bad indentation") end
        if not isSequenceItem(line.text) then break end

        local content = line.text:sub(2)
        local spaces = #content:match("^ *")
        content = content:sub(spaces + 1)
        local before = takeBefore(line)

        local item
        if content == "" then
            local inline = line.inline
            state.pos = state.pos + 1
            local nextLine = state.lines[state.pos]
            if not nextLine or nextLine.indent <= indent then fail(line.number, "empty list item") end
            item = parseBlock(state)
            record(list, anchorOf(item), before, inline)
        elseif isSequenceItem(content) or splitKey(content, line.number) then
            -- "- key: value": a node that goes on, on the next lines, at the column of its content. The comment at
            -- the end of the line belongs to its first key.
            line.indent = indent + 1 + spaces
            line.text = content
            item = parseBlock(state)
            record(list, anchorOf(item), before, nil)
        else
            item = readInlineValue(content, line.number)
            if item == nil then fail(line.number, "empty list item") end
            record(list, anchorOf(item), before, line.inline)
            state.pos = state.pos + 1
        end

        list[#list + 1] = item
    end

    takeTrailing(state, list, indent)
    return list
end

local function parseMapping(state, indent)
    local map = {}
    local keys = {}
    mappings[map] = true
    keyOrders[map] = keys
    getComments(map).indent = indent

    while true do
        local line = state.lines[state.pos]
        if not line or line.indent < indent then break end
        if line.indent > indent then fail(line.number, "bad indentation") end
        if isSequenceItem(line.text) then fail(line.number, "list item where a 'key: value' is expected") end

        local key, rest = splitKey(line.text, line.number)
        if not key then fail(line.number, "'key: value' expected") end
        record(map, key, takeBefore(line), line.inline)
        state.pos = state.pos + 1

        local value = nil
        if rest == "" then
            local nextLine = state.lines[state.pos]
            if nextLine and nextLine.indent > indent then
                value = parseBlock(state)
            elseif nextLine and nextLine.indent == indent and isSequenceItem(nextLine.text) then
                value = parseSequence(state, indent) -- List written at the indent of its key
            end
        else
            value = readInlineValue(rest, line.number)
        end

        if map[key] == nil and value ~= nil then keys[#keys + 1] = key end
        map[key] = value
    end

    takeTrailing(state, map, indent)
    return map
end

parseBlock = function(state)
    local line = state.lines[state.pos]
    if isSequenceItem(line.text) then
        return parseSequence(state, line.indent)
    end
    if splitKey(line.text, line.number) then
        return parseMapping(state, line.indent)
    end

    -- A single value, e.g. a JSON document on one line
    local value = readInlineValue(line.text, line.number)
    state.pos = state.pos + 1
    return value
end

--- Reads a YAML document
---@param text string
---@return any data
---@return string? err
function yaml.decode(text)
    local lines = {}
    local pending = {} -- Comment / blank lines before the next line
    local number = 0

    for raw in (text .. "\n"):gmatch("(.-)\r?\n") do
        number = number + 1
        if number == 1 then raw = raw:gsub("^\239\187\191", "") end -- UTF-8 BOM

        local indentText = raw:match("^[ \t]*")
        local content, comment = splitComment(raw:sub(#indentText + 1))

        if content == "" then
            if comment then
                pending[#pending + 1] = { text = comment, col = #indentText }
            else
                pending[#pending + 1] = { text = "" }
            end
        elseif not (#indentText == 0 and (content == "---" or content == "...")) then
            if indentText:find("\t") then
                return nil, string.format("line %d: tab in the indentation", number)
            end
            if #indentText == 0 and content:match("^%-%-%-%s") then
                return nil, string.format("line %d: content after '---' is not supported", number)
            end
            lines[#lines + 1] = { indent = #indentText, text = content, number = number, comments = pending, inline = comment }
            pending = {}
        end
    end

    if #lines == 0 then return nil end

    -- Blank lines at the end of the file are not kept
    while pending[#pending] and pending[#pending].text == "" do pending[#pending] = nil end

    local state = { lines = lines, pos = 1, eof = { indent = -1, comments = pending } }
    local ok, result = pcall(function()
        local value = parseBlock(state)
        local extra = state.lines[state.pos]
        if extra then fail(extra.number, "unexpected content") end
        -- What is left at the end of the file goes to the end of the document
        if type(value) == "table" then
            takeTrailing(state, value, -1)
            -- The comments before the first line are the header of the file
            local data = getComments(value)
            local first = data.order[1]
            if first ~= nil and data.before[first] then
                data.header = data.before[first]
                data.before[first] = nil
            end
        end
        return value
    end)

    if not ok then
        if type(result) == "table" and result.yamlError then return nil, result.yamlError end
        error(result, 0)
    end

    return result
end

--- Comment lines at the start of a document ("# ..."; "" for a blank line)
---@param root table
---@return string[]
function yaml.getHeader(root)
    local lines = {}
    local data = type(root) == "table" and comments[root]
    for _, line in ipairs(data and data.header or {}) do
        lines[#lines + 1] = line.text
    end
    return lines
end

--- Sets the comment lines at the start of a document
---@param root table
---@param lines string[] Each "# ..." or "" for a blank line
function yaml.setHeader(root, lines)
    local header = {}
    for _, text in ipairs(lines) do
        header[#header + 1] = { text = text, col = 0 }
    end
    getComments(root).header = header
end

--- Marks a table as a mapping, so that it is written as {} when empty
function yaml.markMapping(tbl)
    mappings[tbl] = true
    return tbl
end

local function isList(tbl)
    if mappings[tbl] then return false end

    local size = #tbl
    local count = 0
    for key in pairs(tbl) do
        count = count + 1
        if type(key) ~= "number" or key < 1 or key > size or key % 1 ~= 0 then return false end
    end

    return count == size
end

--- A comment line of an entry commented out, as it was before: its "# " removed when what follows is YAML (a list
--- item or a key), the notes and other comments left as comments
---@param line table { text, col }
---@return string
local function uncommentLine(line)
    if line.text == "" or line.text == "#" then return "" end

    local pad = string.rep(" ", line.col or 0)
    local rest = line.text:match("^# (.*)$")

    if rest and not isUpdaterNote(line.text) then
        local content = rest:match("^%s*(.-)$")
        local ok, key = pcall(splitKey, content, 0)
        if isSequenceItem(content) or (ok and key) then
            return pad .. rest
        end
    end

    return pad .. line.text
end

--- The entries commented out in the comments of a collection (see Entries commented out), read back as YAML. Each is
--- { value = the list or mapping they make, nil if they cannot be read, lines = their comment lines }. The notes of
--- ArchiveXL Sector Updater are the comments of what they are above, those of the first entry the header of value.
---@param collection table
---@return table[]
function yaml.getCommentedEntries(collection)
    local data = type(collection) == "table" and comments[collection]
    if not data then return {} end

    local groups = {}
    for _, anchor in ipairs(data.order) do
        if data.before[anchor] then groups[#groups + 1] = data.before[anchor] end
    end
    groups[#groups + 1] = data.trailing

    local entries = {}
    for _, lines in ipairs(groups) do
        for _, run in ipairs(findCommentedRuns(lines)) do
            local text, raw = {}, {}
            for i = run.first, run.last do
                text[#text + 1] = uncommentLine(lines[i])
                raw[#raw + 1] = lines[i].text
            end

            local ok, value = pcall(yaml.decode, table.concat(text, "\n"))
            entries[#entries + 1] = { value = ok and value or nil, lines = raw }
        end
    end

    return entries
end

--- The comment lines before a key of a mapping, or an item of a list
---@param collection table
---@param item any
---@return string[]
function yaml.getCommentsBefore(collection, item)
    local data = type(collection) == "table" and comments[collection]
    if not data then return {} end

    local anchor = isList(collection) and anchorOf(item) or item
    local lines = {}
    for _, line in ipairs(data.before[anchor] or {}) do
        lines[#lines + 1] = line.text
    end
    return lines
end

local function formatString(text)
    if text == "" then return "''" end

    if text:find("%c") then
        local escaped = text:gsub('[%c"\\]', function(c)
            local names = { ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r", ['"'] = '\\"', ["\\"] = "\\\\" }
            return names[c] or string.format("\\x%02X", c:byte())
        end)
        return '"' .. escaped .. '"'
    end

    local plain = not text:match("^[%s%-%?:,%[%]{}#&%*!|>'\"%%@`]")
        and not text:match("%s$")
        and not text:find(": ", 1, true)
        and not text:find(" #", 1, true)
        and text:sub(-1) ~= ":"
        and not reservedWords[text:lower()]
        and not text:match("^[-+]?%.?%d") -- Would be read as a number (or is a hash kept as text)

    if plain then return text end
    return "'" .. text:gsub("'", "''") .. "'"
end

local function formatScalar(value)
    local kind = type(value)
    if kind == "string" then return formatString(value) end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        if value ~= value then return ".nan" end
        if value == math.huge then return ".inf" end
        if value == -math.huge then return "-.inf" end
        if value % 1 == 0 and math.abs(value) < 2 ^ 53 then return string.format("%d", value) end
        return tostring(value)
    end
    return formatString(tostring(value))
end

local function sortedKeys(tbl, priority)
    local keys = {}
    local seen = {}

    for _, key in ipairs(keyOrders[tbl] or {}) do
        if tbl[key] ~= nil and not seen[key] then
            keys[#keys + 1] = key
            seen[key] = true
        end
    end

    local rest = {}
    for key in pairs(tbl) do
        if not seen[key] then rest[#rest + 1] = key end
    end
    table.sort(rest, function(a, b)
        local pa, pb = priority[a] or math.huge, priority[b] or math.huge
        if pa ~= pb then return pa < pb end
        return tostring(a) < tostring(b)
    end)

    for _, key in ipairs(rest) do keys[#keys + 1] = key end
    return keys
end

--- Comments of a collection for its current content: { before = { [anchor] = lines }, trailing = lines }
local function placeComments(collection, anchors)
    local data = comments[collection]
    if not data then return { before = {}, inline = {}, trailing = {} } end

    local present = {}
    for _, anchor in ipairs(anchors) do present[anchor] = true end

    local before, carried = {}, {}
    for _, anchor in ipairs(data.order) do
        local lines = data.before[anchor] or {}
        if present[anchor] then
            local all = {}
            for _, line in ipairs(carried) do all[#all + 1] = line end
            for _, line in ipairs(lines) do all[#all + 1] = line end
            before[anchor] = all
            carried = {}
        else
            -- Gone: its entries commented out move on, its own comments go with it
            for _, line in ipairs(keptLines(lines)) do carried[#carried + 1] = line end
        end
    end

    local trailing = carried
    for _, line in ipairs(data.trailing) do trailing[#trailing + 1] = line end

    return { before = before, inline = data.inline, trailing = trailing }
end

--- Writes comment lines at the indent of their collection, plus the offset they had from it when read (base: its
--- column then), so that what is commented out over several levels keeps them
local function writeLines(lines, pad, out, base)
    for _, line in ipairs(lines or {}) do
        if line.text == "" then
            out[#out + 1] = ""
        else
            local offset = (base and line.col) and math.max(0, line.col - base) or 0
            out[#out + 1] = pad .. string.rep(" ", offset) .. line.text
        end
    end
end

--- Column a collection was read at, nil for one that was not read from YAML
local function readIndent(collection)
    local data = comments[collection]
    return data and data.indent
end

local function withInline(text, inline)
    return inline and (text .. " " .. inline) or text
end

local emit

--- Writes a collection value after its key / dash: on the same line when empty or a value, else below
local function emitValue(head, item, indent, out, priority, inline)
    if type(item) ~= "table" then
        out[#out + 1] = withInline(head .. " " .. formatScalar(item), inline)
    elseif next(item) == nil then
        out[#out + 1] = withInline(head .. " " .. (isList(item) and "[]" or "{}"), inline)
        -- An empty collection keeps its comments (e.g. a list whose entries are all commented out)
        writeLines(placeComments(item, {}).trailing, string.rep(" ", indent + 2), out, readIndent(item))
    else
        out[#out + 1] = withInline(head, inline)
        emit(item, indent + 2, out, priority)
    end
end

emit = function(value, indent, out, priority)
    local pad = string.rep(" ", indent)
    local base = readIndent(value)

    if isList(value) then
        local anchors = {}
        for i, item in ipairs(value) do anchors[i] = anchorOf(item) end
        local placed = placeComments(value, anchors)

        for i, item in ipairs(value) do
            writeLines(placed.before[anchors[i]], pad, out, base)
            local inline = placed.inline[anchors[i]]
            if type(item) == "table" and next(item) ~= nil then
                -- First line of the item after its "- ", unless it is a comment
                local first = #out + 1
                emit(item, indent + 2, out, priority)
                local content = out[first]:sub(indent + 3)
                if content == "" or content:sub(1, 1) == "#" then
                    table.insert(out, first, withInline(pad .. "-", inline))
                else
                    out[first] = withInline(pad .. "- " .. content, inline)
                end
            else
                emitValue(pad .. "-", item, indent, out, priority, inline)
            end
        end

        writeLines(placed.trailing, pad, out, base)
        return
    end

    local keys = sortedKeys(value, priority)
    local placed = placeComments(value, keys)

    for _, key in ipairs(keys) do
        writeLines(placed.before[key], pad, out, base)
        emitValue(pad .. formatString(tostring(key)) .. ":", value[key], indent, out, priority, placed.inline[key])
    end

    writeLines(placed.trailing, pad, out, base)
end

--- Writes data as YAML, with the comments it was read with
---@param data table
---@param options table? { keyOrder = { "key", ... } }: order of the keys a mapping read from YAML did not have
---@return string
function yaml.encode(data, options)
    local priority = {}
    for i, key in ipairs(options and options.keyOrder or {}) do
        priority[key] = i
    end

    if type(data) ~= "table" then
        return formatScalar(data) .. "\n"
    end
    if next(data) == nil then
        return (isList(data) and "[]" or "{}") .. "\n"
    end

    local out = {}
    writeLines(comments[data] and comments[data].header, "", out)
    emit(data, 0, out, priority)
    return table.concat(out, "\n") .. "\n"
end

return yaml
