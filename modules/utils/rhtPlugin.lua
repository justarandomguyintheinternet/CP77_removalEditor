-- The "Send node to Removal Editor" button of RHT's Inspect and Scan tabs (as World Builder's rhtPlugin.lua)
local settings = require("modules/utils/settings")
local removals = require("modules/utils/removals")

---@class rht
---@field public editUI table?
local rht = {
    editUI = nil
}

--- Stages the node in the Edit tab, and adds it to the preset when settings.directAdd is on
---@param node table RHT target data
function rht.sendNode(node)
    rht.editUI.stage(node)

    if settings.directAdd then
        removals.add(node)
    end
end

--- Adds the node targeted in RHT's Inspect tab (hotkey)
function rht.addInspectedNode()
    local mod = GetMod("RedHotTools")
    if not mod then return end

    local node = mod.GetWorldInspectorTarget()
    if not node then return end

    if removals.add(node) then
        rht.editUI.stage(node)
    end
end

---@return table
function rht.getScannedNodes()
    return GetMod("RedHotTools").GetWorldScannerFilteredResults() or {}
end

---@param editUI table
function rht.init(editUI)
    rht.editUI = editUI

    local mod = GetMod("RedHotTools")
    if not mod then return end

    mod.RegisterExtension({
        getTargetActions = function(node)
            if removals.isWorldNode(node) then
                return {
                    type = "button",
                    label = "Send node to Removal Editor",
                    callback = rht.sendNode
                }
            end
        end
    })
end

return rht
