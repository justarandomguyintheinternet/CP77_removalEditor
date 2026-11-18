-- The .xl presets of the data folder: loading, saving, the game version they were made for, installing them.
local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local yaml = require("modules/utils/yaml")
local logger = require("modules/utils/logger")
local settings = require("modules/utils/settings")
local commentedNodes = require("modules/utils/commentedNodes")

local DATA = "data/"
local INSTALL_PATH = "bin\\x64\\plugins\\cyber_engine_tweaks\\mods\\removalEditor\\data\\%s"

-- Order of the keys written to a YAML preset, for the keys its file did not have
local keyOrder = {
    "streaming", "sectors", "path", "expectedNodes", "nodeDeletions", "nodeMutations",
    "index", "type", "note", "debugName", "resource", "nodeRef", "position", "orientation",
    "expectedActors", "actorDeletions", "expectedInstances", "instanceDeletions",
    "nodeRefHash", "nbNodesUnderProxyDiff", "proxyHash", "proxyDiff", "x", "y", "z", "w", "i", "j", "k", "r"
}

-- Line of the header of a YAML preset that gives the game version it was made for
local gameVersionPattern = "^#%s*[Gg]ame [Vv]ersion%s*:%s*(.-)%s*$"

local presets = {
    list = {}, -- File name -> preset
    info = {}, -- File name -> { format = "json" | "yaml" }
    invalid = {}, -- File name -> reason it cannot be loaded
    currentFile = "",
    gameVersion = nil, -- e.g. "2.5", nil if unknown

    reload = false, -- Install & Reload is reloading the last save
    reloadTransform = {}
}

--- Loads a preset file (JSON or YAML), nil and the reason if it cannot be used
---@param name string
---@return table? preset
---@return table|string info { format } or the reason it cannot be loaded
local function loadPreset(name)
    local text = config.readText(DATA .. name)
    if not text then return nil, "cannot be opened" end

    local format = text:match("^\239?\187?\191?%s*[{%[]") and "json" or "yaml"
    local ok, preset, err
    if format == "json" then
        ok, preset = pcall(json.decode, text)
        if not ok then return nil, "not valid JSON (" .. tostring(preset) .. ")" end
    else
        ok, preset, err = pcall(yaml.decode, text)
        if not ok then return nil, "not valid YAML (" .. tostring(preset) .. ")" end
        if err then return nil, "not valid YAML (" .. err .. ")" end
    end
    if preset == nil then return nil, "empty" end

    -- Every sector commented out by ArchiveXL Sector Updater: "sectors:" is left without a value
    if type(preset) == "table" and type(preset.streaming) == "table" and preset.streaming.sectors == nil
        and yaml.hasCommentedEntries(preset.streaming) then
        preset.streaming.sectors = {}
    end

    if type(preset) ~= "table" or type(preset.streaming) ~= "table" or type(preset.streaming.sectors) ~= "table" then
        return nil, "no streaming.sectors list"
    end

    for _, sector in pairs(preset.streaming.sectors) do
        if type(sector) ~= "table" or type(sector.path) ~= "string" then
            return nil, "a sector has no path"
        end
        sector.nodeDeletions = sector.nodeDeletions or {}
        sector.nodeMutations = sector.nodeMutations or {}
        if type(sector.nodeDeletions) ~= "table" or type(sector.nodeMutations) ~= "table" then
            return nil, "nodeDeletions / nodeMutations of " .. sector.path .. " is not a list"
        end
        for _, entry in pairs(sector.nodeDeletions) do
            if type(entry) ~= "table" then
                return nil, "a removal of " .. sector.path .. " is not a 'key: value' list"
            end
        end
    end

    return preset, { format = format, commented = commentedNodes.find(preset) }
end

--- The opened preset, nil if none
---@return table?
function presets.getCurrent()
    return presets.list[presets.currentFile]
end

---@param name string
function presets.open(name)
    presets.currentFile = name
end

---@param name string
---@return boolean
function presets.isYaml(name)
    return (presets.info[name] or {}).format == "yaml"
end

--- The nodes of a preset that ArchiveXL Sector Updater commented out, read when the preset was loaded
---@param name string
---@return commentedNode[]
function presets.getCommented(name)
    return (presets.info[name] or {}).commented or {}
end

--- Writes a preset to its file, in the format it was read in (new presets are YAML). A YAML preset keeps its comments.
---@param name string
---@return boolean
function presets.save(name)
    local preset = presets.list[name]
    if not preset then return false end

    if not presets.isYaml(name) then
        return config.saveFile(DATA .. name, preset)
    end

    return config.writeText(DATA .. name, yaml.encode(preset, { keyOrder = keyOrder }))
end

---@return boolean
function presets.saveCurrent()
    return presets.save(presets.currentFile)
end

--- Game version a preset was made for ("# Game version: 2.5" at the start of a YAML preset), nil if it does not say
---@param preset table
---@return string?
function presets.getGameVersion(preset)
    for _, line in ipairs(yaml.getHeader(preset)) do
        local version = line:match(gameVersionPattern)
        if version and version ~= "" then return version end
    end
end

--- Sets the "# Game version: ..." line of a YAML preset's header, the other lines stay
---@param preset table
---@param version string
function presets.setGameVersion(preset, version)
    local header = yaml.getHeader(preset)
    local found = false
    for i, line in ipairs(header) do
        if line:match(gameVersionPattern) then
            header[i] = "# Game version: " .. version
            found = true
        end
    end
    if not found then
        header[#header + 1] = "# Game version: " .. version
    end
    yaml.setHeader(preset, header)
end

--- nil if the preset was made for the running game version, else its version or "unknown"
---@param preset table
---@return string?
function presets.getOutdatedVersion(preset)
    local current = presets.gameVersion
    if not current then return nil end

    local version = presets.getGameVersion(preset)
    if version == current then return nil end
    return version or "unknown"
end

--- Keeps the loaded presets in sync with the .xl files of the data folder
function presets.refresh()
    local files = {}
    for _, file in pairs(dir("data") or {}) do
        if file.name:match("^.+(%..+)$") == ".xl" then
            files[file.name] = true

            if not presets.list[file.name] and not presets.invalid[file.name] then
                local preset, info = loadPreset(file.name)
                if preset then
                    presets.list[file.name] = preset
                    presets.info[file.name] = info
                else
                    presets.invalid[file.name] = info
                    logger.error(string.format("Preset \"%s\" cannot be loaded: %s", file.name, info), false)
                end
            end
        end
    end

    -- Files removed outside of Removal Editor
    for name, _ in pairs(presets.list) do
        if not files[name] then
            presets.list[name] = nil
            presets.info[name] = nil
            if presets.currentFile == name then presets.currentFile = "" end
        end
    end
    for name, _ in pairs(presets.invalid) do
        if not files[name] then presets.invalid[name] = nil end
    end
end

--- File names of the loaded presets, sorted
---@return string[]
function presets.getSortedNames()
    local names = utils.getKeys(presets.list)
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

--- Creates an empty preset, in the format of settings.defaultPresetFormat. A YAML preset gets the game version in its header.
---@param name string Without extension
---@return boolean created
function presets.create(name)
    local path = DATA .. name .. ".xl"
    if config.fileExists(path) then
        logger.warn(string.format("A preset named \"%s\" already exists.", name))
        return false
    end

    local preset = { streaming = { sectors = {} } }

    if settings.defaultPresetFormat == "json" then
        return config.saveFile(path, preset)
    end

    if presets.gameVersion then
        presets.setGameVersion(preset, presets.gameVersion)
    end
    return config.writeText(path, yaml.encode(preset, { keyOrder = keyOrder }))
end

---@param name string
function presets.delete(name)
    os.remove(DATA .. name)
    presets.list[name] = nil
    presets.info[name] = nil
    if presets.currentFile == name then
        presets.currentFile = ""
    end
    logger.success(string.format("Deleted \"%s\".", utils.removeExtension(name)))
end

--- Installs a preset through RHT and reloads the last save, the player is put back where they were
---@param name string
function presets.install(name)
    RedHotTools.HotInstall(string.format(INSTALL_PATH, name))

    presets.reloadTransform.position = GetPlayer():GetWorldPosition()
    presets.reloadTransform.rotation = GetPlayer():GetWorldOrientation():ToEulerAngles()
    presets.reload = true

    Game.GetSystemRequestsHandler():LoadLastCheckpoint(true)
end

--- Called once the save is loaded
function presets.onSessionStart()
    if not presets.reload then return end
    presets.reload = false

    if settings.teleportOnReload then
        Game.GetTeleportationFacility():Teleport(GetPlayer(), presets.reloadTransform.position, presets.reloadTransform.rotation)
    end
end

--- Key of a node in the former notes.json, e.g. "exterior_-7_6_0_2_540"
---@param sectorPath string
---@param index number
---@return string
local function getNoteKey(sectorPath, index)
    return utils.getSectorName(sectorPath) .. "_" .. tostring(index)
end

--- Notes are kept in the removals of the presets ("note" field, ignored by ArchiveXL), so that they follow their node
--- when a preset is converted to another game version. notes.json, which identified a node by sector and index, is
--- moved into the presets once.
function presets.migrateNotes()
    if not config.fileExists("data/notes.json") then return end

    local notes, err = config.tryLoadFile("data/notes.json")
    if type(notes) ~= "table" then
        os.rename("data/notes.json", "data/notes.invalid.json")
        logger.error(string.format("notes.json cannot be loaded (%s), it was renamed to notes.invalid.json.", tostring(err)), false)
        return
    end

    presets.refresh()

    local moved, changedPresets, used = 0, 0, {}
    for name, preset in pairs(presets.list) do
        local changed = false
        for _, sector in pairs(preset.streaming.sectors) do
            for _, entry in pairs(sector.nodeDeletions) do
                local key = getNoteKey(sector.path, entry.index)
                local note = notes[key]
                if type(note) == "string" and note ~= "" then
                    used[key] = true
                    if entry.note == nil or entry.note == "" then
                        entry.note = note
                        moved = moved + 1
                        changed = true
                    end
                end
            end
        end
        if changed and presets.save(name) then
            changedPresets = changedPresets + 1
        end
    end

    local unused = 0
    for key, _ in pairs(notes) do
        if not used[key] then unused = unused + 1 end
    end

    -- Kept as a backup, without overwriting an older one
    local backup = "data/notes.migrated.json"
    local suffix = 1
    while config.fileExists(backup) do
        suffix = suffix + 1
        backup = string.format("data/notes.migrated.%d.json", suffix)
    end
    os.rename("data/notes.json", backup)

    logger.info(string.format("Moved %d note(s) from notes.json into %d preset(s), %d note(s) matched no removal. notes.json was kept as %s.",
        moved, changedPresets, unused, backup:match("[^/]+$")), false)
    for name, _ in pairs(presets.invalid) do
        logger.warn(string.format("\"%s\" cannot be loaded, it got no notes. Fix it, then rename %s to notes.json to move them again.", name, backup:match("[^/]+$")), false)
    end
end

presets.keyOrder = keyOrder

return presets
