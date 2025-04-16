utils = {}

function utils.deepcopy(origin)
	local orig_type = type(origin)
    local copy
    if orig_type == 'table' then
        copy = {}
        for origin_key, origin_value in next, origin, nil do
            copy[utils.deepcopy(origin_key)] = utils.deepcopy(origin_value)
        end
        setmetatable(copy, utils.deepcopy(getmetatable(origin)))
    else
        copy = origin
    end
    return copy
end

function utils.countTableSize(table)
    local n = 0
    for k, v in pairs(table) do
        n = n + 1
    end
    return n
end

function utils.indexValue(table, value)
    local index={}
    for k,v in pairs(table) do
        index[v]=k
    end
    return index[value] or 1
end

function utils.has_value(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function utils.getIndex(tab, val)
    local index = nil
    for i, v in ipairs(tab) do
		if v == val then
			index = i
		end
    end
    return index
end

function utils.hasIndex(tab, index)
    local exists = false
    for k, _ in pairs(tab) do
        if k == index then
            exists = true
        end
    end
    return exists
end

function utils.removeItem(tab, val)
    table.remove(tab, utils.getIndex(tab, val))
end

function utils.addVector(v1, v2)
    return Vector4.new(v1.x + v2.x, v1.y + v2.y, v1.z + v2.z, v1.w + v2.w)
end

function utils.subVector(v1, v2)
    return Vector4.new(v1.x - v2.x, v1.y - v2.y, v1.z - v2.z, v1.w - v2.w)
end

function utils.multVector(v1, factor)
    return Vector4.new(v1.x * factor, v1.y * factor, v1.z * factor, v1.w * factor)
end

function utils.multVecXVec(v1, v2)
    return Vector4.new(v1.x * v2.x, v1.y * v2.y, v1.z * v2.z, v1.w * v2.w)
end

function utils.addEuler(e1, e2)
    return EulerAngles.new(e1.roll + e2.roll, e1.pitch + e2.pitch, e1.yaw + e2.yaw)
end

function utils.subEuler(e1, e2)
    return EulerAngles.new(e1.roll - e2.roll, e1.pitch - e2.pitch, e1.yaw - e2.yaw)
end

function utils.multEuler(e1, factor)
    return EulerAngles.new(e1.roll * factor, e1.pitch * factor, e1.yaw * factor)
end

function utils.sanitizeFileName(name)
    name = name:gsub("<", "_")
    name = name:gsub(">", "_")
    name = name:gsub(":", "_")
    name = name:gsub("\"", "_")
    name = name:gsub("/", "_")
    name = name:gsub("\\", "_")
    name = name:gsub("|", "_")
    name = name:gsub("?", "_")
    name = name:gsub("*", "_")

    return name
end

function utils.round(num, precision)
    precision = precision or 1
    return tonumber(string.format(tostring("%." .. precision .. "f"), num))
end

--- Returns the total amount of node removals within a .xl file
---@param preset table
---@return number
function utils.getTotalRemovals(preset)
    local num = 0

    for _, sector in pairs(preset.streaming.sectors) do
        num = num + #sector.nodeDeletions
    end

    return num
end

--- Returns the total amount of node mutations within a .xl file
---@param preset table
---@return number
function utils.getTotalMutations(preset)
    local num = 0

    for _, sector in pairs(preset.streaming.sectors) do
        num = num + #sector.nodeMutations
    end

    return num
end

--- Returns the sector table of a given list of sectors, based on its resource path
---@param sectors table
---@param path string
---@return table | nil
function utils.findSectorByPath(sectors, path)
    for _, sector in pairs(sectors) do
        if sector.path == path then return sector end
    end
end

function utils.tooltip(text)
    if ImGui.IsItemHovered() then
        utils.setCursorRelative(8, 8)

        ImGui.SetTooltip(text)
    end
end

function utils.setCursorRelative(x, y)
    local xC, yC = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(xC + x * ImGui.GetFontSize() / 15, yC + y * ImGui.GetFontSize() / 15, ImGuiCond.Always)
end

return utils