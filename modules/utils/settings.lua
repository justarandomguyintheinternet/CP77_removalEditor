-- Same pattern as World Builder's modules/utils/settings.lua, with reset and getDefault from Dialogue Browser.
local config = require("modules/utils/config")

local PATH = "data/config.json"

---@class settingsData
---@field public directAdd boolean A node sent from RHT is added to the preset at once, instead of being staged
---@field public deleteConfirm boolean Ask before deleting a preset
---@field public teleportOnReload boolean Put the player back where they were after Install & Reload
---@field public defaultPresetFormat string Format of new presets: "yaml" or "json"
---@field public mainWindowWidth number Size the window was left at, 0 until it is known
---@field public mainWindowHeight number
---@field public activeTab integer Tab the window opens on
---@field public settingsSection integer Settings page the tab opens on
---@field public settingsSidebarWidth number Width of the settings sidebar, unscaled
---@field public commentedListHeight number Height of the list of nodes commented out in the Edit tab, unscaled
local settingsData = {
    directAdd = true,
    deleteConfirm = true,
    teleportOnReload = true,
    defaultPresetFormat = "yaml",

    mainWindowWidth = 0,
    mainWindowHeight = 0,
    activeTab = 1,

    settingsSection = 1,
    settingsSidebarWidth = 150,
    commentedListHeight = 160
}

---@param source table
---@return table
local function copyDefaults(source)
    local copy = {}

    for key, value in pairs(source) do
        if type(value) == "table" then
            local inner = {}
            for innerKey, innerValue in pairs(value) do
                inner[innerKey] = innerValue
            end
            copy[key] = inner
        else
            copy[key] = value
        end
    end

    return copy
end

local DEFAULTS = copyDefaults(settingsData)

local settingsFNs = {}

--- Never raises: a file that cannot be read is kept as config.invalid.json, and the defaults are used
function settingsFNs.load()
    if config.fileExists(PATH) then
        local data, err = config.tryLoadFile(PATH)

        if type(data) == "table" then
            for key, value in pairs(data) do
                -- Only the keys this version knows, with the type they have
                if settingsData[key] ~= nil and type(value) == type(settingsData[key]) then
                    settingsData[key] = value
                end
            end
        else
            os.remove("data/config.invalid.json")
            os.rename(PATH, "data/config.invalid.json")
            print(string.format("[RemovalEditor] Error: config.json cannot be loaded (%s), it was renamed to config.invalid.json and the default settings are used.", tostring(err or "not an object")))
        end
    end

    settingsFNs.save()
end

function settingsFNs.save()
    config.saveFile(PATH, settingsData)
end

--- Puts every setting back to its default, and saves
function settingsFNs.reset()
    for key, value in pairs(copyDefaults(DEFAULTS)) do
        settingsData[key] = value
    end

    settingsFNs.save()
end

---@param key string
---@return any
function settingsFNs.getDefault(key)
    return DEFAULTS[key]
end

local settings = {
    load = settingsFNs.load,
    save = settingsFNs.save,
    reset = settingsFNs.reset,
    getDefault = settingsFNs.getDefault
}

settings = setmetatable(settings, {
    __index = settingsData,
    __newindex = settingsData
})

return settings
