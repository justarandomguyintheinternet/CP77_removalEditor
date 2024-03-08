local config = require("modules/config")
local utils = require("modules/utils")

local target = nil

local removal = {
    runtimeData = {
        cetOpen = false,
        rhtInstalled = false,
    },

    uiData = {
        newPresetName = "",
        newNote = "",
        switchToEdit = false
    },

    presets = {},
    notes = {},
    currentFile = "",
    directAdd = true,
    searchText = ""
}

local styles = {}

-- Credits to psiberx for most of the styling choices and techniques
local function initStyles()
    styles.scale = ImGui.GetFontSize() / 13
    styles.width = 400 * styles.scale
    styles.paddingX = 8 * styles.scale
    styles.paddingY = 8 * styles.scale
    styles.buttonY = 21 * styles.scale
end

-- Also "inspired" by psiberx's UI
local function drawProp(name, value)
    if not name or not value then return end

    ImGui.PushStyleColor(ImGuiCol.Text, 0xff9f9f9f)
    ImGui.TextWrapped(name .. ": ")
    ImGui.PopStyleColor()

    ImGui.SameLine()

    ImGui.TextWrapped(tostring(value))

    if ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
        ImGui.SetClipboardText(value)
    end
end

local function pushGreyedOut(state)
    if not state then return end

    ImGui.PushStyleColor(ImGuiCol.Button, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0xff777777)
end

local function popGreyedOut(state)
    if not state then return end

    ImGui.PopStyleColor(3)
end

local function pushFrameStyle()
    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
end

local function popFrameStyle()
    ImGui.PopStyleColor()
    ImGui.PopStyleVar(2)
end

local function spacedSeparator()
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

local function hasSectorRemoval(sector, index)
    if not sector or not index then return false end

    for _, removal in pairs(sector.nodeDeletions) do
        if removal.index == index then return true end
    end
    return false
end

function removal:getEditFlag()
    if self.uiData.switchToEdit then
        self.uiData.switchToEdit = false
        return ImGuiTabItemFlags.SetSelected
    end
    return ImGuiTabItemFlags.None
end

function removal:drawPresetUI()
    for _, file in pairs(dir("data")) do
        if file.name:match("^.+(%..+)$") == ".xl" then
            if not self.presets[file.name] then
                self.presets[file.name] = config.loadFile("data/" .. file.name)
            end
        end
    end

    self.uiData.newPresetName =  ImGui.InputTextWithHint("##newName", "Name...", self.uiData.newPresetName, 100)
    self.uiData.newPresetName = utils.sanitizeFileName(self.uiData.newPresetName) -- Sanitize
    local validName = #self.uiData.newPresetName > 0

    ImGui.SameLine()

    pushGreyedOut(not validName)

    if ImGui.Button("Create") and validName then
        config.tryCreateConfig("data/" .. self.uiData.newPresetName .. ".xl", {streaming = {sectors = {}}})
        self.uiData.newPresetName = ""
    end

    popGreyedOut(not validName)
    spacedSeparator()
    pushFrameStyle()

    local elements = math.max(5, math.min(15, utils.countTableSize(self.presets))) -- Guh
    ImGui.BeginChildFrame(1, 0, elements * ImGui.GetFrameHeightWithSpacing()) -- What

    for name, preset in pairs(self.presets) do
        if ImGui.TreeNodeEx(name:match("(.+)%..+$"), ImGuiTreeNodeFlags.SpanFullWidth) then
            drawProp("Sectors", #preset.streaming.sectors)
            drawProp("Removals", utils.getTotalRemovals(preset))

            ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 5, 2)

            if ImGui.Button("Edit") then
                self.currentFile = name
                self.uiData.switchToEdit = true
            end
            ImGui.SameLine()
            if ImGui.Button("Delete") then
                os.remove("data/" .. name)
                self.presets[name] = nil
                if self.currentFile == name then
                    self.currentFile = ""
                end
            end
            ImGui.PopStyleVar(1)

            ImGui.TreePop()
        end
    end

    ImGui.EndChildFrame()

    popFrameStyle()
end

--- Get the removal table to be used in the .xl file for a specific node
---@param nodeType string
---@param index number
---@param object worldNode
---@return table, boolean
local function getNodeRemoval(nodeType, index)
    if nodeType ~= "worldCollisionNode" then
        return {type = nodeType, index = index}, true
    end

    if not IsDefined(target.nodeDefinition) then
        return {}, false
    end

    local actorDeletions = {}
    for i = 0, target.nodeDefinition.numActors - 1 do
        table.insert(actorDeletions, i)
    end

    return {
        type = nodeType,
        index = index,
        expectedActors = target.nodeDefinition.numActors,
        actorDeletions = actorDeletions
    }, true
end

function removal:drawDirectTarget()
    pushGreyedOut(not target)
    ImGui.Spacing()

    if not target then
        ImGui.Text("No node selected, send one here first from the RedHotTools window!")
    else
        drawProp("Collision", target.collisionGroup)
        drawProp("Node Type", target.nodeType)
        drawProp("Node Index", target.instanceIndex .. " / " .. target.instanceCount)
        drawProp("Sector Path", target.path)
        drawProp("World Sector", target.sectorPath)
        drawProp("Mesh", target.meshPath)
        drawProp("Material", target.materialPath)
        drawProp("Entity Template", target.templatePath)

        ImGui.PushStyleColor(ImGuiCol.Text, 0xff9f9f9f)
        ImGui.TextWrapped("Note:")
        ImGui.PopStyleColor()
        ImGui.SameLine()

        local sectorName = target.sectorPath:match("(.+)%..+$"):match("[^\\]*.$")
        local note = self.notes[tostring(sectorName .. "_" .. target.instanceIndex)] or ""
        local text, changed = ImGui.InputTextWithHint("##noteAdd", "Note...", note, 100)
        if changed and #text > 0 then
            self.notes[tostring(sectorName .. "_" .. target.instanceIndex)] = text
            config.saveFile("data/notes.json", self.notes)
        elseif changed then
            self.notes[tostring(sectorName .. "_" .. target.instanceIndex)] = nil
            config.saveFile("data/notes.json", self.notes)
        end
    end

    ImGui.Spacing()

    if ImGui.Button("Add Staged Node", styles.width, styles.buttonY) then
        if target then
            self:addRemoval(target)
        end
    end

    popGreyedOut(not target)
end

function removal:addRemoval(nodeData)
    local preset = self.presets[self.currentFile]
    if not preset then return end
    local sector = utils.findSectorByPath(preset.streaming.sectors, nodeData.sectorPath)

    if not sector then
        sector = {
            path = nodeData.sectorPath,
            nodeDeletions = {},
            expectedNodes = nodeData.instanceCount
        }
        table.insert(preset.streaming.sectors, sector)
    end

    if hasSectorRemoval(sector, nodeData.instanceIndex) then
        return
    end

    local removal, success = getNodeRemoval(nodeData.nodeType, nodeData.instanceIndex)
    if not success then
        print("[RemovalThing] Error: Node to be removed was streamed out, re-send it from RHT!")
        return
    end
    table.insert(sector.nodeDeletions, 1, removal)
    config.saveFile("data/" .. self.currentFile, preset)

    if self.uiData.newNote ~= "" then
        local sectorName = nodeData.sectorData.sectorPath:match("(.+)%..+$"):match("[^\\]*.$")
        self.notes[tostring(sectorName .. "_" .. nodeData.sectorData.instanceIndex)] = self.uiData.newNote
        config.saveFile("data/notes.json", self.notes)
        self.uiData.newNote = ""
    end
end

function removal:drawEditUI()
    if not self.presets[self.currentFile] then
        ImGui.Text("No preset loaded.")
        return
    end

    local mode = "Direct Add [Add directly to preset when clicking button in RHT]"
    if not self.directAdd then
        mode = "Add with confirmation [Node to be removed gets staged here first]"
    end
    drawProp("Staging Mode", mode)
    self.directAdd = ImGui.Checkbox("Add nodes directly from RedHotTools window", self.directAdd)

    if ImGui.Button("Add all scanned nodes") then
        local nodes = GetMod("RedHotTools").GetScannerTargets()

        for _, node in pairs(nodes) do
            target = node
            self:addRemoval(node)
        end
    end

    if not self.directAdd then
        spacedSeparator()
        self:drawDirectTarget()
    end
    spacedSeparator()

    ImGui.PushItemWidth(400)
    self.searchText = ImGui.InputTextWithHint("##searchForNode", "Search for node (Type, Sector, Index, Note)", self.searchText, 100)
    if self.searchText ~= "" then
        ImGui.SameLine()
        if ImGui.Button("X") then
            self.searchText = ""
        end
    end

    spacedSeparator()

    self:drawRemovals(self.presets[self.currentFile])
end

function removal:getRemovalName(entry, sector)
    local sectorName = sector.path:match("(.+)%..+$"):match("[^\\]*.$")
    local name = self.notes[tostring(sectorName .. "_" .. entry.index)]
    if name then
        name = name
    else
        name = entry.type
    end
    return name .. " | " .. sectorName .. " | " .. entry.index .. " / " .. sector.expectedNodes
end

function removal:isRemovalSearched(sector, entry)
    if self.searchText == "" then return true end

    local text = string.lower(self.searchText)
    if string.match(string.lower(sector.path), text) then return true end
    if string.match(string.lower(tostring(entry.index)), text) then return true end
    if string.match(string.lower(tostring(entry.type)), text) then return true end

    local sectorName = sector.path:match("(.+)%..+$"):match("[^\\]*.$")
    local note = self.notes[tostring(sectorName .. "_" .. entry.index)]
    if note ~= nil and string.match(string.lower(note), text) ~= nil then return true end

    return false
end

function removal:drawRemovals(preset)
    pushFrameStyle()

    local elements = math.max(7, math.min(15, utils.getTotalRemovals(preset)))
    ImGui.BeginChildFrame(1, 0, elements * ImGui.GetFrameHeightWithSpacing())

    for sectorKey, sector in pairs(preset.streaming.sectors) do
        for entryKey, entry in pairs(sector.nodeDeletions) do
            if self:isRemovalSearched(sector, entry) then
                if ImGui.TreeNodeEx("##" .. tostring(entry.index) .. tostring(sector.path), ImGuiTreeNodeFlags.SpanFullWidth, self:getRemovalName(entry, sector)) then
                    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 5, 2)

                    if not self:drawRemoval(sector, entry) then
                        table.remove(sector.nodeDeletions, entryKey)
                        if #sector.nodeDeletions == 0 then
                            table.remove(preset.streaming.sectors, sectorKey)
                        end

                        config.saveFile("data/" .. self.currentFile, preset)
                    end

                    ImGui.PopStyleVar(1)
                    ImGui.TreePop()
                end
            end
        end
    end

    ImGui.EndChildFrame()
    popFrameStyle()
end

function removal:drawRemoval(sector, entry)
    drawProp("Type", entry.type)
    drawProp("Sector Path", sector.path)
    drawProp("Node Index", tostring(entry.index .. "/" .. sector.expectedNodes))

    ImGui.PushStyleColor(ImGuiCol.Text, 0xff9f9f9f)
    ImGui.TextWrapped("Note:")
    ImGui.PopStyleColor()
    ImGui.SameLine()

    popFrameStyle()

    local sectorName = sector.path:match("(.+)%..+$"):match("[^\\]*.$")
    local note = self.notes[tostring(sectorName .. "_" .. entry.index)] or ""
    local text, changed = ImGui.InputTextWithHint("##noteRemoval", "Note...", note, 100)
    if changed and #text > 0 then
        self.notes[tostring(sectorName .. "_" .. entry.index)] = text
        config.saveFile("data/notes.json", self.notes)
    elseif changed then
        self.notes[tostring(sectorName .. "_" .. entry.index)] = nil
        config.saveFile("data/notes.json", self.notes)
    end

    pushFrameStyle()

    if ImGui.Button("Remove", 65, 20) then
        return false
    end

    return true
end

function removal:drawUI()
    ImGui.SetNextWindowSize(styles.width + styles.paddingX * 2, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, styles.paddingX, styles.paddingY)

    if ImGui.Begin("Removal Editor", ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoScrollbar) then
        if not self.runtimeData.rhtInstalled then
            ImGui.Text("RedHotTools is not installed!")
            ImGui.End()
            return
        end

        ImGui.BeginTabBar("Tabbar", ImGuiTabItemFlags.NoTooltip)

        if ImGui.BeginTabItem(" Presets ") then
            ImGui.Spacing()
            self:drawPresetUI()
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem(" Edit ", self:getEditFlag()) then
            ImGui.Spacing()
            self:drawEditUI()
            ImGui.EndTabItem()
        end
    end
    ImGui.End()
end

local function isWorldNode(node)
    return node and node.sectorPath and node.instanceIndex
end

local function sendNode(node)
    target = node

    if removal.directAdd then
        removal:addRemoval(target)
    end
end

function removal:new()
    registerForEvent("onInit", function()
        self.runtimeData.rhtInstalled = Game.GetInspectionSystem() ~= nil

        config.tryCreateConfig("data/notes.json", self.notes)
        self.notes = config.loadFile("data/notes.json")

        GetMod("RedHotTools").RegisterExtension({
            getTargetActions = function(node)
                if isWorldNode(node) then
                    return {
                        type = "button",
                        label = ("Send node to Removal Editor"),
                        callback = sendNode,
                    }
                end
            end
        })
    end)

    registerForEvent("onDraw", function()
        if #styles == 0 then
            initStyles()
        end

        if removal.runtimeData.cetOpen then
            self:drawUI()
        end
    end)

    registerForEvent("onOverlayOpen", function()
        self.runtimeData.cetOpen = true
    end)

    registerForEvent("onOverlayClose", function()
        self.runtimeData.cetOpen = false
    end)

    return removal
end

registerHotkey("addNode", "Add [Inspect] node", function()
    local node = GetMod("RedHotTools").GetInspectorTarget()
    if not node then return end
    target = node
    removal:addRemoval(target)
end)

return removal:new()