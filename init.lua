-- Removal Editor, created by keanuWheeze from CP2077 Modding Tools Discord.
-- Creates ArchiveXL .xl files that remove world nodes, picked in game with RedHotTools.
-- Laid out as World Builder: modules/utils holds the logic, modules/ui the window.

local settings = require("modules/utils/settings")
local presets = require("modules/utils/presets")
local rht = require("modules/utils/rhtPlugin")
local GameUI = require("modules/utils/GameUI")
local style = require("modules/ui/style")

---@class removalEditor
---@field runtimeData {cetOpen: boolean}
local removalEditor = {
    runtimeData = {
        cetOpen = false
    },

    baseUI = require("modules/ui/baseUI"),
    presets = presets
}

function removalEditor:new()
    registerForEvent("onInit", function()
        settings.load()

        local okVersion, version = pcall(function() return Game.GetSystemRequestsHandler():GetGameVersion() end)
        if okVersion and type(version) == "string" and version ~= "" then
            presets.gameVersion = version
        end

        presets.migrateNotes()
        presets.refresh()
        self.baseUI.init()

        if not self.baseUI.hasRequirements() then return end

        GameUI.OnSessionStart(presets.onSessionStart)
        rht.init(self.baseUI.editUI)
    end)

    registerForEvent("onDraw", function()
        style.initialize(true) -- Every frame, as in World Builder: follows the font size

        if self.runtimeData.cetOpen then
            self.baseUI.draw()
        end
    end)

    registerForEvent("onOverlayOpen", function()
        self.runtimeData.cetOpen = true
    end)

    registerForEvent("onOverlayClose", function()
        self.runtimeData.cetOpen = false
        self.baseUI.settingsUI.clearSearch()
    end)

    return self
end

registerHotkey("addNode", "Add [Inspect] node", function()
    if not removalEditor.baseUI.hasRequirements() then return end

    rht.addInspectedNode()
end)

return removalEditor:new()
