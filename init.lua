local config = require("modules/config")
local utils = require("modules/utils")
local GameUI = require("modules/GameUI")
local style = require("modules/style")

local target = nil

---@class removalEntry
---@field type string
---@field index number
---@field actorDeletions table?
---@field expectedActors number?
---@field nbNodesUnderProxyDiff number?
---@field proxyHash string?
---@field proxyDiff number?
---@field nodeRefHash string?
---@field nodeRef string
---@field resource string
---@field position table
---@field orientation table
---@field debugName string

---@class proxyMutation
---@field type string
---@field index number
---@field nodeRefHash string
---@field nbNodesUnderProxyDiff number

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
    searchText = "",
    reload = false,
    reloadTransform = {}
}

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

                for  _, sector in pairs(self.presets[file.name].streaming.sectors) do
                    if not sector.nodeDeletions then
                        sector.nodeDeletions = {}
                    end
                    if not sector.nodeMutations then
                        sector.nodeMutations = {}
                    end
                end
            end
        end
    end

    self.uiData.newPresetName =  ImGui.InputTextWithHint("##newName", "Name...", self.uiData.newPresetName, 100)
    self.uiData.newPresetName = utils.sanitizeFileName(self.uiData.newPresetName) -- Sanitize
    local validName = #self.uiData.newPresetName > 0

    ImGui.SameLine()

    style.pushGreyedOut(not validName)

    if ImGui.Button("Create") and validName then
        config.tryCreateConfig("data/" .. self.uiData.newPresetName .. ".xl", {streaming = {sectors = {}}})
        self.uiData.newPresetName = ""
    end

    style.popGreyedOut(not validName)
    style.spacedSeparator()

    local elements = math.max(5, math.min(20, utils.countTableSize(self.presets))) -- Guh
    ImGui.BeginChild("##presets", -1, elements * ImGui.GetFrameHeightWithSpacing()) -- What

    for name, preset in pairs(self.presets) do
        if ImGui.TreeNodeEx(name:match("(.+)%..+$"), ImGuiTreeNodeFlags.SpanFullWidth) then
            style.drawProp("Sectors", #preset.streaming.sectors)
            style.drawProp("Removals", utils.getTotalRemovals(preset))
            style.drawProp("Mutations", utils.getTotalMutations(preset))

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
            ImGui.SameLine()
            if ImGui.Button("Install & Reload") then
                RedHotTools.HotInstall(string.format("bin\\x64\\plugins\\cyber_engine_tweaks\\mods\\removalEditor\\data\\%s", name))
                self.reloadTransform.position = GetPlayer():GetWorldPosition()
                self.reloadTransform.rotation = GetPlayer():GetWorldOrientation():ToEulerAngles()
                self.reload = true

                Game.GetSystemRequestsHandler():LoadLastCheckpoint(true)
            end
            utils.tooltip("Make a Quick-Save to speed up the reload process.")
            ImGui.PopStyleVar(1)

            ImGui.TreePop()
        end
    end

    ImGui.EndChild()
end

function removal:drawActors(entry)
    if ImGui.TreeNodeEx("Collision Actors" , ImGuiTreeNodeFlags.SpanFullWidth) then
        if ImGui.BeginChild("##test", -1, 120 * style.scale, false) then

            for index = 0, entry.expectedActors - 1 do
                local value = utils.has_value(entry.actorDeletions, index)
                local newValue, changed = ImGui.Checkbox(tostring(index), value)
                if changed then
                    if newValue then
                        table.insert(entry.actorDeletions, index)
                    else
                        utils.removeItem(entry.actorDeletions, index)
                    end

                    config.saveFile("data/" .. self.currentFile, self.presets[self.currentFile])
                end
            end
            ImGui.EndChild()
        end

        ImGui.TreePop()
    end
end

function removal:drawDirectTarget()
    style.pushGreyedOut(not target)
    ImGui.Spacing()

    if not target then
        ImGui.Text("No node selected, send one here first from the RedHotTools window!")
    else
        style.drawProp("Collision", target.collisionGroup)
        style.drawProp("Node Type", target.nodeType)
        style.drawProp("Node Index", target.instanceIndex .. " / " .. target.instanceCount)
        style.drawProp("World Sector", target.sectorPath)
        style.drawProp("Mesh", target.meshPath)
        style.drawProp("Material", target.materialPath)
        style.drawProp("Entity Template", target.templatePath)

        if target.nodeRef then
            style.drawProp("Node Ref", target.nodeRef)
        end
        if target.debugName then
            style.drawProp("Debug Name", target.debugName)
        end

        local position = target.nodePosition or target.entityPosition
        if position then
            style.drawProp("Position", string.format("X: %.2f Y: %.2f Z: %.2f", position.x, position.y, position.z))
        end

        if target.physicsActorOffset and target.physicsActorIndex then
            style.drawProp("Physics Actor", target.physicsActorOffset + target.physicsActorIndex .. "/" .. target.nodeDefinition.numActors)
        end

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

    if ImGui.Button("Add Staged Node", style.width, style.buttonY) then
        if target then
            self:addRemoval(target)
        end
    end

    style.popGreyedOut(not target)
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
    style.drawProp("Staging Mode", mode)
    self.directAdd = ImGui.Checkbox("Add nodes directly from RedHotTools window", self.directAdd)

    if ImGui.Button("Add all scanned & filtered nodes") then
        local nodes = GetMod("RedHotTools").GetWorldScannerFilteredResults()

        for _, node in pairs(nodes) do
            target = node
            self:addRemoval(node)
        end
    end

    if not self.directAdd then
        style.spacedSeparator()
        self:drawDirectTarget()
    end
    style.spacedSeparator()

    ImGui.PushItemWidth(400)
    self.searchText = ImGui.InputTextWithHint("##searchForNode", "Search for node (Type, Sector, Index, Note)", self.searchText, 100)
    if self.searchText ~= "" then
        ImGui.SameLine()
        if ImGui.Button("X") then
            self.searchText = ""
        end
    end

    style.spacedSeparator()

    self:drawRemovals(self.presets[self.currentFile])
end

function removal:drawRemovals(preset)
    local elements = math.max(7, math.min(20, utils.getTotalRemovals(preset)))
    ImGui.BeginChild("##removals", -1, elements * ImGui.GetFrameHeightWithSpacing())

    for sectorKey, sector in pairs(preset.streaming.sectors) do
        for entryKey, entry in pairs(sector.nodeDeletions) do
            if self:isRemovalSearched(sector, entry) then
                if ImGui.TreeNodeEx("##" .. tostring(entry.index) .. tostring(sector.path), ImGuiTreeNodeFlags.SpanFullWidth, self:getRemovalName(entry, sector)) then
                    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 5, 2)

                    if not self:drawRemoval(sector, entry) then
                        self:deleteRemoval(preset, sector, entry, entryKey, sectorKey)
                    end

                    ImGui.PopStyleVar(1)
                    ImGui.TreePop()
                end
            end
        end
    end

    ImGui.EndChild()
end

function removal:drawRemoval(sector, entry)
    style.drawProp("Type", entry.type)
    style.drawProp("Sector Path", sector.path)
    style.drawProp("Node Index", tostring(entry.index .. "/" .. sector.expectedNodes))
    if entry.position then
        style.drawProp("Position", string.format("X: %.2f Y: %.2f Z: %.2f", entry.position.x, entry.position.y, entry.position.z))
    end
    if entry.debugName ~= "" then
        style.drawProp("Debug Name", entry.debugName)
    end
    if entry.resource ~= "" then
        style.drawProp("Resource", entry.resource)
    end
    if entry.nodeRef ~= "" then
        style.drawProp("NodeRef", entry.nodeRef)
    end

    if entry.actorDeletions then
        self:drawActors(entry)
    end

    ImGui.PushStyleColor(ImGuiCol.Text, 0xff9f9f9f)
    ImGui.TextWrapped("Note:")
    ImGui.PopStyleColor()
    ImGui.SameLine()

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

    if ImGui.Button("Remove") then
        return false
    end

    return true
end

function removal:drawUI()
    ImGui.SetNextWindowSize(style.width + style.paddingX * 2, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, style.paddingX, style.paddingY)

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

--- Get the removal table to be used in the .xl file for a specific node
---@param nodeType string
---@param index number
---@param object worldNode
---@return removalEntry, boolean
local function getNodeRemoval(nodeType, index)
    local result = {}
    local proxyID = target.nodeInstance:GetProxyNodeID()

    if proxyID and proxyID.hash ~= 0 then
        local proxy = removal:createProxyMutation(proxyID.hash)

        if proxy then
            local diff = 1

            if target.nodeDefinition:IsA("worldInstancedMeshNode") then
                diff = target.nodeDefinition.worldTransformsBuffer.numElements
            end

            proxy.nbNodesUnderProxyDiff = proxy.nbNodesUnderProxyDiff - diff
            result.proxyHash = proxy.nodeRefHash
            result.proxyDiff = diff
        end
    end

    result.type = nodeType
    result.index = index

    if nodeType ~= "worldCollisionNode" then
        return result, true
    end

    if not IsDefined(target.nodeDefinition) then
        return result, false
    end

    local actorDeletions = {}

    if not target.collision then
        for i = 0, target.nodeDefinition.numActors - 1 do
            table.insert(actorDeletions, i)
        end
    else
        actorDeletions = { target.physicsActorOffset + target.physicsActorIndex }
    end

    result.expectedActors = target.nodeDefinition.numActors
    result.actorDeletions = actorDeletions
    return result, true
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

---Excludes collision nodes, as they can be expanded
---@param sector table
---@param index number
---@return boolean, removalEntry?
local function hasSectorRemoval(sector, index)
    if not sector or not index then return false end

    for _, removal in pairs(sector.nodeDeletions) do
        if removal.index == index then return true, removal end
    end

    return false
end

function removal:addSector(preset, sectorPath, instanceCount)
    local sector = utils.findSectorByPath(preset.streaming.sectors, sectorPath)
    if not sector then
        sector = {
            path = sectorPath,
            nodeDeletions = {},
            nodeMutations = {},
            expectedNodes = instanceCount,
        }
        table.insert(preset.streaming.sectors, sector)
    end

    return sector
end

---@param hash number
---@return proxyMutation?
function removal:createProxyMutation(hash)
    local proxy = nil
    local preset = self.presets[self.currentFile]
    if not preset then return end

    local hashString = tostring(hash):gsub("ULL", "")
    for _, sector in pairs(preset.streaming.sectors) do
        for _, node in pairs(sector.nodeMutations) do
            if node.nodeRefHash == hashString then
                return node
            end
        end
    end

    if not proxy then
        local proxyNode = Game.GetWorldInspector():FindStreamedNode(hash)

        if not proxyNode or not proxyNode.nodeDefinition then
            print("[RemovalEditor] Error: Proxy node of this removal not found or streamed in!")
            return
        end

        local sectorData = Game.GetWorldInspector():ResolveSectorDataFromNodeID(hash)
        local sectorPath = RedHotTools.GetResourcePath(sectorData.sectorHash)

        proxy = {
            type = proxyNode.nodeDefinition:GetClassName().value,
            index = sectorData.instanceIndex,
            nodeRefHash = tostring(hash):gsub("ULL", ""),
            nbNodesUnderProxyDiff = 0
        }

        local sector = removal:addSector(preset, sectorPath, sectorData.instanceCount)
        table.insert(sector.nodeMutations, proxy)
    end

    return proxy
end

function removal:addRemoval(nodeData)
    local preset = self.presets[self.currentFile]
    if not preset then return end

    local sector = self:addSector(preset, nodeData.sectorPath, nodeData.instanceCount)

    local hasRemoval, data = hasSectorRemoval(sector, nodeData.instanceIndex)

    if hasRemoval then
        if data and data.actorDeletions then
            local actor = target.physicsActorOffset + target.physicsActorIndex

            if not utils.has_value(data.actorDeletions, actor) then
                table.insert(data.actorDeletions, actor)
            end

            config.saveFile("data/" .. self.currentFile, self.presets[self.currentFile])
        end
        return
    end

    local removal, success = getNodeRemoval(nodeData.nodeType, nodeData.instanceIndex)
    if not success then
        print("[RemovalEditor] Error: Node to be removed was streamed out, re-send it from RHT!")
        return
    end

    local position = nodeData.nodePosition or nodeData.entityPosition
    local orientation = nodeData.nodeOrientation or nodeData.entityOrientation
    removal.position = { x = position.x, y = position.y, z = position.z }
    removal.orientation = { i = orientation.i, j = orientation.j, k = orientation.k, r = orientation.r }
    removal.nodeRef = nodeData.nodeRef or ""
    removal.resource = nodeData.meshPath or nodeData.templatePath or nodeData.materialPath or nodeData.effectPath or nodeData.recordID or ""
    removal.debugName = nodeData.debugName or ""

    table.insert(sector.nodeDeletions, 1, removal)
    config.saveFile("data/" .. self.currentFile, preset)

    if self.uiData.newNote ~= "" then
        local sectorName = nodeData.sectorData.sectorPath:match("(.+)%..+$"):match("[^\\]*.$")
        self.notes[tostring(sectorName .. "_" .. nodeData.sectorData.instanceIndex)] = self.uiData.newNote
        config.saveFile("data/notes.json", self.notes)
        self.uiData.newNote = ""
    end
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

function removal:updateProxyMutation(preset, entry)
    if not entry.proxyHash then return end

    for sectorKey, sector in pairs(preset.streaming.sectors) do
        for proxyIndex, node in pairs(sector.nodeMutations) do
            if node.nodeRefHash == entry.proxyHash then
                node.nbNodesUnderProxyDiff = node.nbNodesUnderProxyDiff + entry.proxyDiff

                if node.nbNodesUnderProxyDiff >= 0 then
                    table.remove(sector.nodeMutations, proxyIndex)
                end

                if #sector.nodeMutations == 0 and #sector.nodeDeletions == 0 then
                    table.remove(preset.streaming.sectors, sectorKey)
                end
            end
        end
    end
end

function removal:deleteRemoval(preset, sector, entry, entryKey, sectorKey)
    table.remove(sector.nodeDeletions, entryKey)
    if #sector.nodeDeletions == 0 and #sector.nodeMutations then
        table.remove(preset.streaming.sectors, sectorKey)
    end

    self:updateProxyMutation(preset, entry)

    config.saveFile("data/" .. self.currentFile, preset)
end

function removal:new()
    registerForEvent("onInit", function()
        self.runtimeData.rhtInstalled = Game.GetWorldInspector() ~= nil

        config.tryCreateConfig("data/notes.json", self.notes)
        self.notes = config.loadFile("data/notes.json")

        GameUI.OnSessionStart(function()
            if self.reload then
                self.reload = false
                Game.GetTeleportationFacility():Teleport(GetPlayer(), self.reloadTransform.position, self.reloadTransform.rotation)
            end
        end)

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
        style.initStyles()

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
    local node = GetMod("RedHotTools").GetWorldInspectorTarget()
    if not node then return end
    target = node
    removal:addRemoval(target)
end)

return removal:new()