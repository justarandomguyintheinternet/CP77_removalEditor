-- The nodes of a YAML preset that ArchiveXL Sector Updater commented out, when it could not convert them to another
-- game version: ArchiveXL ignores them, Removal Editor keeps them and lists them, with the reason it gave.
local yaml = require("modules/utils/yaml")

local commentedNodes = {}

local KINDS = { "nodeDeletions", "nodeMutations" }

--- What a node commented out is, from the first note of ArchiveXL Sector Updater above it. Best first.
commentedNodes.statuses = {
    {
        id = "notFound",
        label = "Not found",
        pattern = "^not found",
        description = "No such object in the new game version, neither in its sector nor around it."
    },
    {
        id = "mismatch",
        label = "Source mismatch",
        pattern = "^does not match",
        description = "The node does not match the game version the file was converted from: the file was made for another one."
    },
    {
        id = "moved",
        label = "Moved",
        pattern = "^moved to",
        description = "Found in another sector, where ArchiveXL Sector Updater added it: nothing to do."
    },
    {
        id = "commented",
        label = "Commented out",
        description = "Commented out without a reason from ArchiveXL Sector Updater (e.g. by hand)."
    }
}

local statusById = {}
for _, status in ipairs(commentedNodes.statuses) do
    statusById[status.id] = status
end

---@param id string
---@return table
function commentedNodes.getStatus(id)
    return statusById[id] or statusById.commented
end

--- The reasons of ArchiveXL Sector Updater in comment lines ("# axl_sector_updater: not found in 2.5" -> "not found in 2.5")
---@param lines string[]
---@return string[]
local function getNotes(lines)
    local notes = {}
    for _, text in ipairs(lines or {}) do
        local note = text:match("^#%s*axl_sector_updater:%s*(.-)%s*$")
        if note and note ~= "" then
            notes[#notes + 1] = note
        end
    end
    return notes
end

---@param notes string[]
---@return string
local function getStatusId(notes)
    for _, note in ipairs(notes) do
        for _, status in ipairs(commentedNodes.statuses) do
            if status.pattern and note:match(status.pattern) then
                return status.id
            end
        end
    end
    return "commented"
end

---@param value table
---@return boolean
local function isArray(value)
    return value[1] ~= nil or next(value) == nil
end

---@class commentedNode
---@field kind string nodeDeletions or nodeMutations
---@field sectorPath string?
---@field index any
---@field type string?
---@field debugName any
---@field resource any
---@field nodeRef any
---@field note any Note of Removal Editor
---@field position table?
---@field elements number Actors / instances it lists
---@field notes string[] Reasons of ArchiveXL Sector Updater
---@field status string

--- Collects the nodes of what was read back from the comments: lists of nodes, sectors, or a "nodeDeletions:" key
---@param value any
---@param context {sectorPath: string?, kind: string?}
---@param notes string[]? Of value itself
---@param out commentedNode[]
local function collect(value, context, notes, out)
    if type(value) ~= "table" then return end

    if isArray(value) then
        for i, item in ipairs(value) do
            local itemNotes = getNotes(yaml.getCommentsBefore(value, item))
            if i == 1 and notes then
                for n = #notes, 1, -1 do table.insert(itemNotes, 1, notes[n]) end
            end
            collect(item, context, itemNotes, out)
        end
        return
    end

    if value.index ~= nil then
        notes = notes or {}
        local elements = 0
        for _, key in ipairs({ "actorDeletions", "instanceDeletions" }) do
            if type(value[key]) == "table" then elements = elements + #value[key] end
        end

        out[#out + 1] = {
            kind = context.kind or "nodeDeletions",
            sectorPath = context.sectorPath,
            index = value.index,
            type = type(value.type) == "string" and value.type or nil,
            debugName = value.debugName,
            resource = value.resource,
            nodeRef = value.nodeRef,
            note = value.note,
            position = type(value.position) == "table" and value.position or nil,
            elements = elements,
            notes = notes,
            status = getStatusId(notes)
        }
        return
    end

    local sectorPath = type(value.path) == "string" and value.path or context.sectorPath
    for _, kind in ipairs(KINDS) do
        if type(value[kind]) == "table" then
            collect(value[kind], { sectorPath = sectorPath, kind = kind }, nil, out)
        end
    end
    if type(value.sectors) == "table" then
        collect(value.sectors, { sectorPath = sectorPath }, nil, out)
    end
end

--- The nodes commented out in the comments of one collection of the preset
local function visit(collection, context, out)
    for _, entry in ipairs(yaml.getCommentedEntries(collection)) do
        if entry.value ~= nil then
            collect(entry.value, context, getNotes(yaml.getHeader(entry.value)), out)
        end
    end
end

--- The nodes ArchiveXL Sector Updater commented out in a preset: in a list of nodes, in a sector (a whole list
--- commented out with its key), or in the list of sectors (a whole sector commented out)
---@param preset table
---@return commentedNode[]
function commentedNodes.find(preset)
    local out = {}
    local streaming = type(preset) == "table" and preset.streaming
    if type(streaming) ~= "table" then return out end

    visit(preset, {}, out)
    visit(streaming, {}, out)

    local sectors = streaming.sectors
    if type(sectors) ~= "table" then return out end
    visit(sectors, {}, out)

    for _, sector in ipairs(sectors) do
        if type(sector) == "table" then
            visit(sector, { sectorPath = sector.path }, out)
            for _, kind in ipairs(KINDS) do
                if type(sector[kind]) == "table" then
                    visit(sector[kind], { sectorPath = sector.path, kind = kind }, out)
                end
            end
        end
    end

    return out
end

--- How many nodes have each status
---@param nodes commentedNode[]
---@return table<string, number>
function commentedNodes.countByStatus(nodes)
    local counts = {}
    for _, node in ipairs(nodes) do
        counts[node.status] = (counts[node.status] or 0) + 1
    end
    return counts
end

--- "3 not found, 1 moved", in the order of the statuses
---@param nodes commentedNode[]
---@return string
function commentedNodes.summary(nodes)
    local counts = commentedNodes.countByStatus(nodes)
    local parts = {}
    for _, status in ipairs(commentedNodes.statuses) do
        if counts[status.id] then
            parts[#parts + 1] = string.format("%d %s", counts[status.id], status.label:lower())
        end
    end
    return table.concat(parts, ", ")
end

--- Whether some of the nodes are to be looked at (not found, source mismatch, commented out by hand)
---@param nodes commentedNode[]
---@return boolean
function commentedNodes.needsAttention(nodes)
    for _, node in ipairs(nodes) do
        if node.status ~= "moved" then return true end
    end
    return false
end

return commentedNodes
