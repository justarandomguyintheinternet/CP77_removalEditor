-- The removals of the opened preset: what ArchiveXL is told to remove for a node RHT points at, and the proxy
-- mutations that go with it.
local utils = require("modules/utils/utils")
local yaml = require("modules/utils/yaml")
local logger = require("modules/utils/logger")
local presets = require("modules/utils/presets")

---@class removalEntry
---@field type string
---@field index number
---@field actorDeletions table?
---@field expectedActors number?
---@field instanceDeletions table?
---@field expectedInstances number?
---@field nbNodesUnderProxyDiff number?
---@field proxyHash string?
---@field proxyDiff number?
---@field nodeRefHash string?
---@field nodeRef string
---@field resource string
---@field position table
---@field orientation table
---@field debugName string
---@field note string?

---@class proxyMutation
---@field type string
---@field index number
---@field nodeRefHash string
---@field nbNodesUnderProxyDiff number

local removals = {}

--- Parts of a node that ArchiveXL can remove one by one, and the node types that have them.
--- Since 2.5 the collisions of a sector are cooked into worldCookedCollisionNode: one nodeData entry per former collision node.
removals.elementKinds = {
    actor = {
        list = "actorDeletions",
        expected = "expectedActors",
        label = "Collision Actors",
        types = { worldCollisionNode = true, worldCookedCollisionNode = true }
    },
    instance = {
        list = "instanceDeletions",
        expected = "expectedInstances",
        label = "Instances",
        types = { worldInstancedMeshNode = true, worldInstancedDestructibleMeshNode = true, worldInstancedOccluderNode = true }
    }
}
local elementKinds = removals.elementKinds

--- Calls fn and returns its result, or nil if it fails (e.g. a property that does not exist in this game version)
local function try(fn)
    local ok, value = pcall(fn)
    if ok then return value end
end

local function positiveInt(value)
    value = tonumber(value)
    if value and value > 0 then return math.floor(value) end
end

---@param nodeType string
---@return table?
function removals.getElementKind(nodeType)
    for _, kind in pairs(elementKinds) do
        if kind.types[nodeType] then return kind end
    end
end

---@param entry removalEntry
---@return table?
function removals.getEntryElementKind(entry)
    for _, kind in pairs(elementKinds) do
        if entry[kind.list] then return kind end
    end
end

--- Number of actors / instances of the targeted node (of its inner node for cooked nodes), nil if unknown
---@param nodeData table RHT target data
---@param kind table
---@return number?
function removals.getElementCount(nodeData, kind)
    local node = nodeData.nodeDefinition
    -- Index of the cooked inner node (2.5), only used when RHT gives a valid one
    local inner = nodeData.innerIndex
    local hasInner = type(inner) == "number" and type(nodeData.innerCount) == "number" and inner >= 0 and inner < nodeData.innerCount

    if kind == elementKinds.actor then
        -- worldCookedCollisionNode (2.5) does not expose its actors to scripts: RHT's actorCount (set when the
        -- collision is hit in Inspect) is the actor count of the targeted inner node, checked against the sectors.
        -- actorOffset only splits a node into physics proxies of 64 actors.
        return (IsDefined(node) and positiveInt(try(function() return node.numActors end))) -- worldCollisionNode (2.31)
            or positiveInt(nodeData.actorCount)
    end

    if IsDefined(node) then
        local count = (hasInner and positiveInt(try(function() return node.transformRanges[inner + 1].numTransforms end))) -- worldInstancedMeshNode (2.5)
            or positiveInt(try(function() return node.worldTransformsBuffer.numElements end)) -- worldInstancedMeshNode (2.31)
            or positiveInt(try(function() return #node.instanceTransforms end)) -- worldInstancedDestructibleMeshNode
            or positiveInt(try(function() return node.cookedInstanceTransforms.numElements end)) -- worldInstancedDestructibleMeshNode
        if count then return count end
    end

    return positiveInt(nodeData.actorCount) -- RHT: instance count of the targeted mesh
end

--- Index of the actor / instance the target points at, nil if the whole node is targeted
---@param nodeData table RHT target data
---@param kind table
---@param count number?
---@return number?, string?
function removals.getTargetElement(nodeData, kind, count)
    -- Collisions not hit by a physics trace (e.g. from the Scanner) target the whole node
    if kind == elementKinds.actor and not nodeData.collision then return nil end

    local index = nodeData.actorIndex
    if type(index) ~= "number" and nodeData.physicsActorOffset and nodeData.physicsActorIndex then
        index = nodeData.physicsActorOffset + nodeData.physicsActorIndex
    end
    if type(index) ~= "number" or index < 0 then return nil end

    if kind == elementKinds.instance and not positiveInt(nodeData.actorCount) then return nil end
    if count and index >= count then
        return nil, string.format("%s %d is out of range (%d), re-send the node from RHT!", kind.label, index, count)
    end

    return index
end

--- Value of nbNodesUnderProxyDiff this removal accounts for
---@param entry removalEntry
---@param nodeData table? RHT target data, only needed for a whole worldInstancedMeshNode
---@return number
function removals.getProxyDiff(entry, nodeData)
    local kind = removals.getEntryElementKind(entry)
    local isInstancedMesh = entry.type == "worldInstancedMeshNode"

    if kind then
        local listed, expected = #entry[kind.list], entry[kind.expected]
        if isInstancedMesh then return listed end -- Each instance counts as a node under the proxy
        if expected and listed >= expected then return 1 end
        return 0 -- The node itself stays
    end

    if isInstancedMesh then
        local count = nodeData and removals.getElementCount(nodeData, elementKinds.instance)
        if not count then
            logger.warn("Instance count of this worldInstancedMeshNode is unknown, its proxy might not hide properly.")
        end
        return count or 1
    end

    return 1
end

--- The removal table to be used in the .xl file for a specific node. Changes nothing in the preset.
---@param nodeData table RHT target data
---@return removalEntry?, string?
local function getNodeRemoval(nodeData)
    local result = {
        type = nodeData.nodeType,
        index = nodeData.instanceIndex
    }

    local kind = removals.getElementKind(nodeData.nodeType)
    if not kind then return result end

    local count = removals.getElementCount(nodeData, kind)
    local element, err = removals.getTargetElement(nodeData, kind, count)
    if err then return nil, err end

    if element and not count then
        -- ArchiveXL removes the whole node when a list comes without its expected count (tested in 2.5)
        return nil, string.format("%s count of this node is unknown, target it in RHT's Inspect tab and re-send it!", kind.label)
    end

    if element and not (kind == elementKinds.instance and count == 1) then
        -- A single actor / instance
        result[kind.list] = { element }
        result[kind.expected] = count
    elseif kind == elementKinds.actor and count then
        -- Whole collision node, listing its actors so that they can be un-removed one by one
        local actors = {}
        for i = 0, count - 1 do
            table.insert(actors, i)
        end
        result[kind.list] = actors
        result[kind.expected] = count
    end

    return result
end

---@param node table?
---@return boolean
function removals.isWorldNode(node)
    return node ~= nil and node.sectorPath ~= nil and node.instanceIndex ~= nil
end

---Excludes collision nodes, as they can be expanded
---@param sector table
---@param index number
---@return boolean, removalEntry?
local function hasSectorRemoval(sector, index)
    if not sector or not index then return false end

    for _, entry in pairs(sector.nodeDeletions) do
        if entry.index == index then return true, entry end
    end

    return false
end

--- The removal of a node in the opened preset, if it has one
---@param nodeData table RHT target data
---@return removalEntry?
function removals.find(nodeData)
    local preset = presets.getCurrent()
    if not preset or not nodeData then return nil end

    local sector = utils.findSectorByPath(preset.streaming.sectors, nodeData.sectorPath)
    if not sector then return nil end

    local _, entry = hasSectorRemoval(sector, nodeData.instanceIndex)
    return entry
end

local function addSector(preset, sectorPath, instanceCount)
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

---@param preset table
---@param hashString string
---@return proxyMutation?
local function findProxyMutation(preset, hashString)
    for _, sector in pairs(preset.streaming.sectors) do
        for _, node in pairs(sector.nodeMutations) do
            if node.nodeRefHash == hashString then
                return node
            end
        end
    end
end

---@param preset table
---@param hash number
---@return proxyMutation?
local function createProxyMutation(preset, hash)
    local hashString = tostring(hash):gsub("ULL", "")
    local proxy = findProxyMutation(preset, hashString)
    if proxy then return proxy end

    local sectorData = Game.GetWorldInspector():ResolveSectorDataFromNodeID(hash)

    if not sectorData or sectorData.sectorHash == 0 then
        logger.error("Proxy node of this removal not found!")
        return
    end

    proxy = {
        type = sectorData.nodeType.value,
        index = sectorData.instanceIndex,
        nodeRefHash = hashString,
        nbNodesUnderProxyDiff = 0
    }

    local sectorPath = RedHotTools.GetResourcePath(sectorData.sectorHash)
    local sector = addSector(preset, sectorPath, sectorData.instanceCount)
    table.insert(sector.nodeMutations, proxy)

    return proxy
end

--- Sets the share of the proxy's nbNodesUnderProxyDiff this removal accounts for
---@param preset table
---@param entry removalEntry
---@param diff number
function removals.setProxyDiff(preset, entry, diff)
    if not entry.proxyHash then return end

    local delta = diff - (entry.proxyDiff or 0)
    if delta == 0 then return end

    local proxy = findProxyMutation(preset, entry.proxyHash)
    if proxy then
        proxy.nbNodesUnderProxyDiff = proxy.nbNodesUnderProxyDiff - delta
    elseif diff > 0 then
        logger.error("Proxy mutation of this removal is missing, re-send the node from RHT!")
        return
    end

    entry.proxyDiff = diff
end

--- Links a new removal to the proxy mesh it is part of, once the removal is in the preset
---@param preset table
---@param entry removalEntry
---@param nodeData table RHT target data
local function attachProxy(preset, entry, nodeData)
    local proxyID = nodeData.nodeProxyID
    if not proxyID or proxyID == 0 then return end

    local proxy = createProxyMutation(preset, proxyID)
    if not proxy then return end

    entry.proxyHash = proxy.nodeRefHash
    entry.proxyDiff = 0
    removals.setProxyDiff(preset, entry, removals.getProxyDiff(entry, nodeData))
end

--- Removes the proxy mutations no removal uses anymore, then the empty sectors
---@param preset table
local function cleanupPreset(preset)
    local used = {}
    for _, sector in pairs(preset.streaming.sectors) do
        for _, entry in pairs(sector.nodeDeletions) do
            if entry.proxyHash then used[entry.proxyHash] = true end
        end
    end

    for sectorKey = #preset.streaming.sectors, 1, -1 do
        local sector = preset.streaming.sectors[sectorKey]

        for mutationKey = #sector.nodeMutations, 1, -1 do
            local mutation = sector.nodeMutations[mutationKey]
            if mutation.nodeRefHash and not used[mutation.nodeRefHash]
                and mutation.nbNodesUnderProxyDiff and mutation.nbNodesUnderProxyDiff >= 0 then
                table.remove(sector.nodeMutations, mutationKey)
            end
        end

        -- A sector whose YAML still lists entries commented out (e.g. by ArchiveXL Sector Updater) is kept with them
        -- or a whole list commented out with its key ("# nodeDeletions:"), which is in the comments of the sector itself
        if #sector.nodeDeletions == 0 and #sector.nodeMutations == 0 and not yaml.hasCommentedEntries(sector)
            and not yaml.hasCommentedEntries(sector.nodeDeletions) and not yaml.hasCommentedEntries(sector.nodeMutations) then
            table.remove(preset.streaming.sectors, sectorKey)
        end
    end
end

--- Adds an actor / instance to an existing removal of the same node
---@param preset table
---@param entry removalEntry
---@param nodeData table RHT target data
---@return boolean changed
local function addElementToRemoval(preset, entry, nodeData)
    local kind = removals.getEntryElementKind(entry)
    if not kind then return false end -- The whole node is already removed

    local count = entry[kind.expected] or removals.getElementCount(nodeData, kind)
    local element, err = removals.getTargetElement(nodeData, kind, count)
    if err then logger.error(err) end
    if not element then return false end

    local changed = false
    if not entry[kind.expected] and count then
        entry[kind.expected] = count -- Fills in the count missing from an older removal
        changed = true
    end
    if utils.has_value(entry[kind.list], element) then return changed end

    table.insert(entry[kind.list], element)
    removals.setProxyDiff(preset, entry, removals.getProxyDiff(entry))
    return true
end

--- Adds a node (or one of its actors / instances) to the opened preset
---@param nodeData table RHT target data
---@param opts {save: boolean?, note: string?, quiet: boolean?}? save: saves the file (default true), note: of a new removal, quiet: no toast for errors
---@return boolean changed
function removals.add(nodeData, opts)
    opts = opts or {}
    local toast = not opts.quiet

    local preset = presets.getCurrent()
    if not preset then
        logger.error("No preset is opened, open one from the Presets tab first!", toast)
        return false
    end
    if not removals.isWorldNode(nodeData) then
        logger.error("The target is not a world node, it cannot be removed!", toast)
        return false
    end

    local function saveIfWanted()
        if opts.save ~= false then
            presets.saveCurrent()
        end
    end

    local existingSector = utils.findSectorByPath(preset.streaming.sectors, nodeData.sectorPath)
    local hasRemoval, data = hasSectorRemoval(existingSector, nodeData.instanceIndex)

    if hasRemoval then
        if data and addElementToRemoval(preset, data, nodeData) then
            saveIfWanted()
            return true
        end
        return false
    end

    -- Everything is validated before the preset is touched
    local removal, err = getNodeRemoval(nodeData)
    if not removal then
        logger.error(err, toast)
        return false
    end

    local position = nodeData.nodePosition or nodeData.entityPosition
    local orientation = nodeData.nodeOrientation or nodeData.entityOrientation
    if position then
        removal.position = { x = position.x, y = position.y, z = position.z }
    end
    if orientation then
        removal.orientation = { i = orientation.i, j = orientation.j, k = orientation.k, r = orientation.r }
    end
    removal.nodeRef = nodeData.nodeRef or ""
    removal.resource = nodeData.meshPath or nodeData.templatePath or nodeData.materialPath or nodeData.effectPath
        or nodeData.particlePath or nodeData.foliagePath or nodeData.workspotPath or nodeData.recordID or ""
    removal.debugName = nodeData.debugName or ""
    if opts.note and opts.note ~= "" then
        removal.note = opts.note
    end

    local sector = addSector(preset, nodeData.sectorPath, nodeData.instanceCount)
    table.insert(sector.nodeDeletions, 1, removal)
    attachProxy(preset, removal, nodeData)

    saveIfWanted()
    return true
end

--- Removes a node from the opened preset (the game keeps it)
---@param preset table
---@param sector table
---@param entry removalEntry
function removals.delete(preset, sector, entry)
    removals.setProxyDiff(preset, entry, 0)
    utils.removeItem(sector.nodeDeletions, entry)
    cleanupPreset(preset)
    presets.saveCurrent()
end

--- Removes a whole node instead of a selection of its actors / instances
---@param preset table
---@param entry removalEntry
---@param kind table
function removals.removeWholeNode(preset, entry, kind)
    local diff = entry.type == "worldInstancedMeshNode" and (entry[kind.expected] or #entry[kind.list]) or 1
    entry[kind.list] = nil
    entry[kind.expected] = nil
    removals.setProxyDiff(preset, entry, diff)
end

---@param entry removalEntry
---@param sector table
---@return string
function removals.getName(entry, sector)
    local name = (type(entry.note) == "string" and entry.note ~= "") and entry.note or tostring(entry.type)
    return string.format("%s | %s | %s / %s", name, utils.getSectorName(sector.path), tostring(entry.index), tostring(sector.expectedNodes))
end

--- Adds a list of nodes (RHT scan results), the file is saved once
---@param nodes table
---@return number added, number skipped, table? last The last node added
function removals.addAll(nodes)
    local added, skipped, last = 0, 0, nil

    for _, node in pairs(nodes) do
        if removals.add(node, { save = false, quiet = true }) then
            last = node
            added = added + 1
        else
            skipped = skipped + 1
        end
    end

    if added > 0 then
        presets.saveCurrent()
    end

    return added, skipped, last
end

return removals
