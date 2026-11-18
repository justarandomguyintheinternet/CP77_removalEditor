-- Taken from Dialogue Browser (modules/ui/settingsSearch.lua), as it is.
---The query above the settings pages, and what it fades.

---@class settingDef
---@field label string What the setting is called on the page.
---@field category string Page it belongs to, dotted for a block inside one.
---@field searchTerms string? Words it should answer to beyond its label.
---@field tooltip string? What it does, said in full.

local settingsSearch = {}

local SearchState = {}
SearchState.__index = SearchState

---@param text string
---@return string[]
local function splitWords(text)
    local words = {}

    for word in text:gmatch("%S+") do
        words[#words + 1] = word:lower()
    end

    return words
end

---Everything one setting can be found by: what it is called, the words it answers to, and what its tooltip says about it.
---@param def settingDef?
---@return string
local function getSearchTerms(def)
    if type(def) ~= "table" then
        return ""
    end

    local terms = def.label or ""

    if def.searchTerms then
        terms = terms .. " " .. def.searchTerms
    end

    if def.tooltip then
        terms = terms .. " " .. def.tooltip
    end

    return terms
end

settingsSearch.getSearchTerms = getSearchTerms

-- ----------------------------------------------------------------------------- query

---@param text string
function SearchState:setQuery(text)
    if self.query == text then
        return
    end

    self.query = text
    self.words = splitWords(text)
    self.cacheVersion = self.cacheVersion + 1
end

---@return string
function SearchState:getQuery()
    return self.query
end

function SearchState:clear()
    self:setQuery("")
end

---@return boolean
function SearchState:isEmpty()
    return #self.words == 0
end

-- --------------------------------------------------------------------------- matching

---@param key string Identifies the setting, and keys its cached result.
---@param terms string?
---@return boolean
function SearchState:matches(key, terms)
    if #self.words == 0 then
        return true
    end

    if not terms or terms == "" then
        return false
    end

    local cached = self.itemCache[key]
    if cached and cached.version == self.cacheVersion then
        return cached.result
    end

    local lowerTerms = terms:lower()
    local result = true

    for _, word in ipairs(self.words) do
        if not lowerTerms:find(word, 1, true) then
            result = false
            break
        end
    end

    self.itemCache[key] = { version = self.cacheVersion, result = result }

    return result
end

---@param key string
---@param defs table<string, settingDef>
---@return boolean
function SearchState:matchesKey(key, defs)
    return self:matches(key, getSearchTerms(defs and defs[key]))
end

---Whether anything on a page answers to the query.
---@param category string
---@param defs table<string, settingDef>
---@return boolean
function SearchState:categoryHasMatch(category, defs)
    if #self.words == 0 then
        return true
    end

    if not defs then
        return true
    end

    local cacheKey = "category:" .. category
    local cached = self.categoryCache[cacheKey]
    if cached and cached.version == self.cacheVersion then
        return cached.result
    end

    local prefix = category .. "."
    local prefixLength = #prefix
    local result = false

    for key, def in pairs(defs) do
        local defCategory = def.category

        if defCategory and (defCategory == category or defCategory:sub(1, prefixLength) == prefix) then
            if self:matches(key, getSearchTerms(def)) then
                result = true
                break
            end
        end
    end

    self.categoryCache[cacheKey] = { version = self.cacheVersion, result = result }

    return result
end

-- ---------------------------------------------------------------------------- dimming

---Fade whatever is drawn next when it does not answer to the query.
---@param key string
---@param terms string?
function SearchState:beginDim(key, terms)
    if #self.words == 0 or self:matches(key, terms) then
        self.dimDepth[#self.dimDepth + 1] = false
        return
    end

    ImGui.PushStyleVar(ImGuiStyleVar.Alpha, self.dimAlpha)
    self.dimDepth[#self.dimDepth + 1] = true
end

---@param key string
---@param defs table<string, settingDef>
function SearchState:beginDimKey(key, defs)
    self:beginDim(key, getSearchTerms(defs and defs[key]))
end

---@param category string
---@param defs table<string, settingDef>
function SearchState:beginDimCategory(category, defs)
    if #self.words == 0 or self:categoryHasMatch(category, defs) then
        self.dimDepth[#self.dimDepth + 1] = false
        return
    end

    ImGui.PushStyleVar(ImGuiStyleVar.Alpha, self.dimAlpha)
    self.dimDepth[#self.dimDepth + 1] = true
end

function SearchState:endDim()
    local count = #self.dimDepth

    if count == 0 then
        return
    end

    if self.dimDepth[count] then
        ImGui.PopStyleVar()
    end

    self.dimDepth[count] = nil
end

-- ------------------------------------------------------------------------ constructor

---@param id string Names the input, so two of these never share an ImGui id.
---@param opts {dimAlpha: number?}?
---@return table
function settingsSearch.new(id, opts)
    opts = opts or {}

    return setmetatable({
        id = id,
        query = "",
        words = {},
        cacheVersion = 0,
        itemCache = {},
        categoryCache = {},
        dimAlpha = opts.dimAlpha or 0.25,
        dimDepth = {}
    }, SearchState)
end

return settingsSearch
