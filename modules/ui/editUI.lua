-- The Edit tab: the nodes the opened preset removes, and the node sent from RHT
local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local logger = require("modules/utils/logger")
local presets = require("modules/utils/presets")
local removals = require("modules/utils/removals")
local commentedNodes = require("modules/utils/commentedNodes")
local rht = require("modules/utils/rhtPlugin")
local style = require("modules/ui/style")
local presetsUI = require("modules/ui/presetsUI")

local elementKinds = removals.elementKinds

local editUI = {
    target = nil, -- Node sent from RHT
    stagedNote = "", -- Note written for target before it is added
    searchText = "",
    pendingOpen = nil -- true / false: open / close every removal shown, on the next frame
}

-- Elements shown for removals whose element count is unknown, so that an unticked element stays listed
local knownElements = setmetatable({}, { __mode = "k" })

--- The node sent from RHT, shown in the staged node section
---@param node table RHT target data
function editUI.stage(node)
    if editUI.target ~= node then
        editUI.stagedNote = ""
    end
    editUI.target = node
end

---@param id string
---@param note string?
---@param valueX number? Cursor X of the input, from style.getPropertiesX
---@return string note, boolean changed
local function drawNoteInput(id, note, valueX)
    style.propertyName("Note", valueX)
    ImGui.SetNextItemWidth(-1)

    return style.inputTextWithHint(id, "Note...", note or "", 100)
end

--- Actor / instance list of a removal
---@param preset table
---@param entry removalEntry
---@param kind table
local function drawElements(preset, entry, kind)
    local list = entry[kind.list]
    local expected = entry[kind.expected]

    local label = string.format("%s (%d / %s)##elements", kind.label, #list, expected and tostring(expected) or "?")
    if not ImGui.TreeNodeEx(label, ImGuiTreeNodeFlags.SpanFullWidth) then return end

    if not expected then
        style.styledTextWrapped(string.format("No %s set: ArchiveXL removes the whole node. Re-send it from RHT's Inspect tab to fix it.", kind.expected), style.errorColor)
    end

    -- Without a known count, list the elements this removal ever had
    local indices = {}
    if expected then
        for index = 0, expected - 1 do table.insert(indices, index) end
    else
        local known = knownElements[entry] or {}
        for _, index in ipairs(list) do
            if not utils.has_value(known, index) then table.insert(known, index) end
        end
        table.sort(known)
        knownElements[entry] = known
        indices = known
    end

    local changed = false
    ImGui.BeginChild("##elements", -1, math.max(1, math.min(8, #indices)) * ImGui.GetFrameHeightWithSpacing())

    for _, index in ipairs(indices) do
        local value = utils.has_value(list, index)
        local newValue, toggled = ImGui.Checkbox(tostring(index), value)
        if toggled then
            if newValue then
                table.insert(list, index)
            else
                utils.removeItem(list, index)
            end
            changed = true
        end
    end

    ImGui.EndChild()

    if ImGui.Button("Remove whole node") then
        removals.removeWholeNode(preset, entry, kind)
        changed = true
    elseif changed then
        removals.setProxyDiff(preset, entry, removals.getProxyDiff(entry))
    end
    style.tooltip("Remove the node with all its " .. string.lower(kind.label) .. ", instead of a selection of them.")

    if changed then
        presets.saveCurrent()
    end

    ImGui.TreePop()
end

local function drawStagedNode()
    local target = editUI.target
    style.pushGreyedOut(not target)

    if not target then
        style.mutedText("No node staged, send one here first from the RedHotTools window!")
    else
        local valueX = style.getPropertiesX({ "Collision", "Node Type", "Node Index", "World Sector", "Mesh", "Material",
            "Entity Template", "Node Ref", "Debug Name", "Position", "Collision Actor", "Instance", "Note" })
        style.drawProp("Collision", target.collisionGroup, valueX)
        style.drawProp("Node Type", target.nodeType, valueX)
        style.drawProp("Node Index", target.instanceIndex .. " / " .. target.instanceCount, valueX)
        style.drawProp("World Sector", target.sectorPath, valueX)
        style.drawProp("Mesh", target.meshPath, valueX)
        style.drawProp("Material", target.materialPath, valueX)
        style.drawProp("Entity Template", target.templatePath, valueX)
        style.drawProp("Node Ref", target.nodeRef, valueX)
        style.drawProp("Debug Name", target.debugName, valueX)

        local position = target.nodePosition or target.entityPosition
        if position then
            style.drawProp("Position", string.format("X: %.2f Y: %.2f Z: %.2f", position.x, position.y, position.z), valueX)
        end

        local kind = removals.getElementKind(target.nodeType)
        if kind then
            local count = removals.getElementCount(target, kind)
            local element = removals.getTargetElement(target, kind, count)
            style.drawProp(kind == elementKinds.actor and "Collision Actor" or "Instance",
                (element and tostring(element) or "All") .. " / " .. (count and tostring(count) or "?"), valueX)
        end

        -- Note of its removal if the node is already in the preset, else kept until the node is added
        local entry = removals.find(target)
        local note, changed = drawNoteInput("##noteAdd", entry and entry.note or editUI.stagedNote, valueX)
        if changed then
            if entry then
                entry.note = #note > 0 and note or nil
                presets.saveCurrent()
            else
                editUI.stagedNote = note
            end
        end
    end

    ImGui.Spacing()

    if ImGui.Button("Add Staged Node", -1, 0) and target then
        if removals.add(target, { note = editUI.stagedNote }) then
            editUI.stagedNote = ""
        end
    end

    style.popGreyedOut(not target)
end

---@param sector table
---@param entry removalEntry
---@return boolean
local function isSearched(sector, entry)
    if editUI.searchText == "" then return true end

    local text = table.concat({ tostring(sector.path), tostring(entry.index), tostring(entry.type),
        tostring(entry.debugName or ""), tostring(entry.resource or ""), tostring(entry.note or "") }, "\n")
    return utils.matchSearchPlain(text, editUI.searchText)
end

---@return boolean kept false once "Remove" is pressed
local function drawRemoval(preset, sector, entry)
    local valueX = style.getPropertiesX({ "Type", "Sector Path", "Node Index", "Position", "Debug Name", "Resource", "NodeRef", "Note" })
    style.drawProp("Type", entry.type, valueX)
    style.drawProp("Sector Path", sector.path, valueX)
    style.drawProp("Node Index", tostring(entry.index) .. " / " .. tostring(sector.expectedNodes), valueX)
    -- { x, y, z } from Removal Editor, [x, y, z, w] from other tools
    local position = type(entry.position) == "table" and entry.position or {}
    local x, y, z = position.x or position[1], position.y or position[2], position.z or position[3]
    if type(x) == "number" and type(y) == "number" and type(z) == "number" then
        style.drawProp("Position", string.format("X: %.2f Y: %.2f Z: %.2f", x, y, z), valueX)
    end
    -- Written by other tools too: only shown when they are text
    local function isText(value) return (type(value) == "string" and value ~= "") or type(value) == "number" end
    if isText(entry.debugName) then
        style.drawProp("Debug Name", entry.debugName, valueX)
    end
    if isText(entry.resource) then
        style.drawProp("Resource", entry.resource, valueX)
    end
    if isText(entry.nodeRef) then
        style.drawProp("NodeRef", entry.nodeRef, valueX)
    end

    local note, changed = drawNoteInput("##noteRemoval", entry.note, valueX)
    if changed then
        entry.note = #note > 0 and note or nil
        presets.saveCurrent()
    end

    local kind = removals.getEntryElementKind(entry)
    if kind then
        drawElements(preset, entry, kind)
    end

    if ImGui.Button("Remove") then
        return false
    end
    style.tooltip("Removes this node from the preset: the game keeps it.")

    return true
end

-- Icon and color of each status of a node commented out
local STATUS_LOOKS = {
    notFound = { icon = IconGlyphs.CloseCircleOutline, color = style.errorColor },
    mismatch = { icon = IconGlyphs.AlertOutline, color = style.warnColor },
    moved = { icon = IconGlyphs.ArrowRightCircleOutline, color = style.mutedColor },
    commented = { icon = IconGlyphs.CommentOutline, color = style.mutedColor }
}

---@param node commentedNode
---@return boolean
local function isCommentedSearched(node)
    if editUI.searchText == "" then return true end

    local text = table.concat({ tostring(node.sectorPath or ""), tostring(node.index), tostring(node.type or ""),
        tostring(node.debugName or ""), tostring(node.resource or ""), tostring(node.note or ""),
        commentedNodes.getStatus(node.status).label, table.concat(node.notes, "\n") }, "\n")
    return utils.matchSearchPlain(text, editUI.searchText)
end

---@param node commentedNode
local function drawCommentedNode(node)
    local status = commentedNodes.getStatus(node.status)
    local looks = STATUS_LOOKS[node.status] or STATUS_LOOKS.commented

    style.styledText(looks.icon, looks.color)
    style.tooltip(status.label)
    ImGui.SameLine()

    local sector = node.sectorPath and utils.getSectorName(node.sectorPath) or "?"
    local label = string.format("%s | %s | %s", node.type or "?", sector, tostring(node.index))
    if not ImGui.TreeNodeEx("##commentedNode", ImGuiTreeNodeFlags.SpanFullWidth, label) then return end

    local valueX = style.getPropertiesX({ "Status", "Reason", "List", "Sector Path", "Node Index", "Type", "Debug Name",
        "Resource", "NodeRef", "Position", "Note", "Actors / Instances" })

    style.drawProp("Status", status.label, valueX)
    style.wrappedTooltip(status.description)
    if #node.notes > 0 then
        style.drawProp("Reason", table.concat(node.notes, "\n"), valueX)
    end
    style.drawProp("List", node.kind == "nodeMutations" and "Mutation" or "Removal", valueX)
    style.drawProp("Sector Path", node.sectorPath, valueX)
    style.drawProp("Node Index", node.index, valueX)
    style.drawProp("Type", node.type, valueX)

    local function isText(value) return (type(value) == "string" and value ~= "") or type(value) == "number" end
    if isText(node.debugName) then style.drawProp("Debug Name", node.debugName, valueX) end
    if isText(node.resource) then style.drawProp("Resource", node.resource, valueX) end
    if isText(node.nodeRef) then style.drawProp("NodeRef", node.nodeRef, valueX) end

    local position = node.position or {}
    local x, y, z = position.x or position[1], position.y or position[2], position.z or position[3]
    if type(x) == "number" and type(y) == "number" and type(z) == "number" then
        style.drawProp("Position", string.format("X: %.2f Y: %.2f Z: %.2f", x, y, z), valueX)
    end
    if isText(node.note) then style.drawProp("Note", node.note, valueX) end
    if node.elements > 0 then style.drawProp("Actors / Instances", node.elements, valueX) end

    ImGui.TreePop()
    ImGui.Spacing()
end

-- Divider under the list of nodes commented out
local commentedDivider = { hovered = false, dragging = false }

--- The nodes of the preset ArchiveXL Sector Updater commented out (ArchiveXL ignores them), filtered by the search
local function drawCommentedSection()
    local nodes = presets.getCommented(presets.currentFile)
    if #nodes == 0 then return end

    local shown = {}
    for _, node in ipairs(nodes) do
        if isCommentedSearched(node) then shown[#shown + 1] = node end
    end

    style.sectionHeaderStart("COMMENTED OUT BY AXLSU", "Nodes ArchiveXL Sector Updater could not convert to the game version, and commented out with the reason.\nArchiveXL ignores them: they are not removed. The search of the removals below filters them too.")

    local count = #shown == #nodes and string.format("%d node%s", #nodes, #nodes == 1 and "" or "s")
        or string.format("%d / %d nodes", #shown, #nodes)
    local summary = #shown > 0 and (" (" .. commentedNodes.summary(shown) .. ")") or ""

    style.pushStyleColor(commentedNodes.needsAttention(shown), ImGuiCol.Text, style.warnColor)
    local open = ImGui.TreeNodeEx(count .. summary .. "###commentedNodes", ImGuiTreeNodeFlags.SpanFullWidth)
    style.popStyleColor(commentedNodes.needsAttention(shown))

    if open then
        -- The height the divider under it was dragged to, within what leaves the removals some room
        local _, available = ImGui.GetContentRegionAvail()
        local minHeight = ImGui.GetFrameHeightWithSpacing() * 2
        local maxHeight = math.max(minHeight, available - ImGui.GetFrameHeightWithSpacing() * 6)
        local height = math.max(minHeight, math.min((tonumber(settings.commentedListHeight) or 160) * style.viewSize, maxHeight))
        settings.commentedListHeight = height / style.viewSize

        ImGui.BeginChild("##commentedNodes", -1, height)

        for i, node in ipairs(shown) do
            ImGui.PushID(i)
            drawCommentedNode(node)
            ImGui.PopID()
        end
        if #shown == 0 then
            style.mutedText("No commented out node matches the search.")
        end

        ImGui.EndChild()
        ImGui.TreePop()

        -- Out of the tree node, so that it is as wide as the section it resizes.
        -- Dragged to resize the list, double-clicked to put it back to its default height.
        style.dragSetting("##commentedNodesDivider", "horizontal", nil, commentedDivider, {
            settings = settings,
            key = "commentedListHeight",
            default = settings.getDefault("commentedListHeight")
        })
        style.tooltip("Drag to resize the list, double-click to reset it")
    end

    style.sectionHeaderEnd()
end

--- The removals of the preset the search matches
---@param preset table
---@return {sector: table, entry: removalEntry}[]
local function getShownRemovals(preset)
    local shown = {}

    for _, sector in pairs(preset.streaming.sectors) do
        for _, entry in pairs(sector.nodeDeletions) do
            if isSearched(sector, entry) then
                shown[#shown + 1] = { sector = sector, entry = entry }
            end
        end
    end

    return shown
end

--- Expand all / collapse all, and how many removals are shown (as World Builder's list bars)
---@param shown table
---@param total number
local function drawListBar(shown, total)
    style.drawExpandCollapseButtons("removals",
        function() editUI.pendingOpen = true end,
        function() editUI.pendingOpen = false end,
        {
            disabled = #shown == 0,
            expandTooltip = "Expand all the removals shown",
            collapseTooltip = "Collapse all the removals shown"
        })

    ImGui.SameLine()
    ImGui.AlignTextToFramePadding()
    if #shown == total then
        style.mutedText(string.format("%d removal%s", total, total == 1 and "" or "s"))
    else
        style.mutedText(string.format("%d / %d removals", #shown, total))
    end

    ImGui.Separator()
end

---@param preset table
---@param shown table From getShownRemovals
local function drawRemovals(preset, shown)
    ImGui.BeginChild("##removals", -1, 0)

    local deleted = nil

    for _, item in ipairs(shown) do
        local sector, entry = item.sector, item.entry

        if editUI.pendingOpen ~= nil then
            ImGui.SetNextItemOpen(editUI.pendingOpen)
        end

        if ImGui.TreeNodeEx("##" .. tostring(entry.index) .. tostring(sector.path), ImGuiTreeNodeFlags.SpanFullWidth, removals.getName(entry, sector)) then
            if not drawRemoval(preset, sector, entry) then
                deleted = { sector = sector, entry = entry }
            end

            ImGui.TreePop()
            ImGui.Spacing()
        end
    end
    editUI.pendingOpen = nil

    if #shown == 0 then
        style.mutedText(editUI.searchText == "" and "No node removed yet." or "No removal matches the search.")
    end

    ImGui.EndChild()

    -- Deleted once the lists are no longer iterated
    if deleted then
        removals.delete(preset, deleted.sector, deleted.entry)
    end
end

function editUI.draw()
    local preset = presets.getCurrent()
    if not preset then
        style.mutedText("No preset opened, open one from the Presets tab.")
        return
    end

    style.sectionHeaderStart("PRESET")
    local commented = presets.getCommented(presets.currentFile)
    local valueX = style.getPropertiesX({ "Name", "Commented Out" })
    style.drawProp("Name", utils.removeExtension(presets.currentFile), valueX)
    if #commented > 0 then
        style.drawProp("Commented Out", string.format("%d (%s)", #commented, commentedNodes.summary(commented)), valueX)
        style.wrappedTooltip(presetsUI.getCommentedTooltip(commented))
    end
    presetsUI.drawVersionWarning(presets.currentFile, preset)
    style.sectionHeaderEnd()

    style.sectionHeaderStart("ADD NODES")

    local directAdd, changed = ImGui.Checkbox("Add nodes directly from RedHotTools window", settings.directAdd)
    if changed then
        settings.directAdd = directAdd
        settings.save()
    end
    style.tooltip("On: a node sent from RHT is added to the preset right away.\nOff: it is staged below first, to write its note before adding it.")

    if ImGui.Button("Add all scanned & filtered nodes") then
        local added, skipped, last = removals.addAll(rht.getScannedNodes())
        if last then
            editUI.stage(last)
        end

        local message = string.format("Added %d scanned node(s), skipped %d (not world nodes, already in the preset or invalid).", added, skipped)
        if added > 0 then
            logger.success(message)
        else
            logger.warn(message)
        end
    end
    style.tooltip("Adds every result of RHT's Scan tab matching its current filter.")

    style.sectionHeaderEnd()

    if not settings.directAdd then
        style.sectionHeaderStart("STAGED NODE")
        drawStagedNode()
        style.sectionHeaderEnd()
    end

    drawCommentedSection()

    style.sectionHeaderStart("REMOVALS")

    editUI.searchText = style.drawSearchFilterRow("##searchForNode", editUI.searchText, {
        fill = true,
        hint = "Search by type, sector, index, name, resource, note...",
        searchTooltip = "Searches the type, sector, index, debug name, resource and note of the removals"
    })

    local shown = getShownRemovals(preset)
    drawListBar(shown, utils.getTotalRemovals(preset))
    drawRemovals(preset, shown)

    style.sectionHeaderEnd(true)
end

return editUI
