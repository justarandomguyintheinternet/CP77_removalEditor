-- Same layout as World Builder's modules/utils/config.lua. Reads never raise an error (tryLoadFile, readText),
-- and text files are kept byte for byte (readText / writeText), which the YAML presets need.
local config = {}

function config.fileExists(filename)
    local f=io.open(filename,"r")
    if (f~=nil) then io.close(f) return true else return false end
end

function config.tryCreateConfig(path, data)
	if not config.fileExists(path) then
        config.saveFile(path, data)
    end
end

--- Reads a JSON file without ever raising an error
---@param path string
---@return any? data
---@return string? err Reason the file could not be read
function config.tryLoadFile(path)
    local file = io.open(path, "r")
    if not file then return nil, "cannot be opened" end

    local content = file:read("*a")
    file:close()

    local ok, data = pcall(json.decode, content)
    if not ok then return nil, "not valid JSON (" .. tostring(data) .. ")" end
    if data == nil then return nil, "empty" end

    return data
end

--- Content of a file, nil if it cannot be opened
---@param path string
---@return string?
function config.readText(path)
    -- Binary: the text is kept byte for byte (line endings included)
    local file = io.open(path, "rb")
    if not file then return nil end

    local content = file:read("*a")
    file:close()
    return content
end

---@param path string
---@param text string
---@return boolean
function config.writeText(path, text)
    local file = io.open(path, "wb")
    if not file then
        print(string.format("[RemovalEditor] Error: %s cannot be written!", path))
        return false
    end

    file:write(text)
    file:close()
    return true
end

function config.loadFile(path)
    local data, err = config.tryLoadFile(path)
    if err then
        error(string.format("[RemovalEditor] %s: %s", path, err))
    end
    return data
end

function config.saveFile(path, data)
    local file = io.open(path, "w")
    if not file then
        print(string.format("[RemovalEditor] Error: %s cannot be written!", path))
        return false
    end

    local jconfig = json.encode(data)
    file:write(jconfig)
    file:close()
    return true
end

local function recursiveAddMissingKeys(source, target)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            recursiveAddMissingKeys(v, target[k])
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

--- Adds the keys of data missing from a JSON file (nested ones too), e.g. new settings
---@param path string
---@param data table
function config.backwardComp(path, data)
    local f = config.loadFile(path)

    recursiveAddMissingKeys(data, f)

    config.saveFile(path, f)
end

return config