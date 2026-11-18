-- Mod metadata, and the state of everything Removal Editor relies on (same layout as Dialogue Browser's about.lua).
-- States are read when asked for: plugins and mods register at different points of the startup.

---@alias aboutState "ok"|"outdated"|"missing"|"unknown"

---@class aboutDependency
---@field id string
---@field name string
---@field required boolean
---@field blocking boolean? The mod does not start without it
---@field minVersion string?
---@field provides string What it brings to Removal Editor
---@field url string?
---@field missingIssue string? Message of getBlockingIssues
---@field check fun(): aboutState, string? State, and the version found

---@class aboutDependencyStatus
---@field id string
---@field name string
---@field required boolean
---@field blocking boolean
---@field minVersion string?
---@field provides string
---@field url string?
---@field state aboutState
---@field detectedVersion string?
---@field satisfied boolean

local about = {
    name = "Removal Editor",
    version = "1.4.0",
    author = "NexusGuy999 (keanuWheeze)",
    maintainer = "Akiway",
    thanks = "psiberx, for RedHotTools, which finds the nodes, and ArchiveXL, which removes them.",
    states = {
        ok = "ok",
        outdated = "outdated",
        missing = "missing",
        unknown = "unknown"
    }
}

---@param version string?
---@return number[]
local function parseVersion(version)
    local parts = {}
    for number in tostring(version or ""):gmatch("%d+") do
        parts[#parts + 1] = tonumber(number)
    end
    return parts
end

--- Whether version is at least minVersion ("1.3.0" >= "1.3")
---@param version string
---@param minVersion string
---@return boolean
function about.isAtLeast(version, minVersion)
    local a, b = parseVersion(version), parseVersion(minVersion)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return true
end

--- A global that may not exist (reading a missing one can raise in CET). Read by its name in the function given:
--- the globals of RED4ext plugins are not in _G, CET resolves them when they are read.
---@param read fun(): any
---@return any
local function getGlobal(read)
    local ok, value = pcall(read)
    if ok then return value end
end

---@param name string
---@return any
function about.getMod(name)
    local ok, mod = pcall(GetMod, name)
    if ok then return mod end
end

--- State of a RED4ext plugin with a Version() (and Require(), which not all of them have)
---@param plugin any
---@param minVersion string?
---@return aboutState, string?
local function checkPlugin(plugin, minVersion)
    if not plugin then
        return about.states.missing
    end

    local okVersion, version = pcall(function() return plugin.Version() end)
    version = okVersion and version ~= nil and tostring(version) or nil

    if minVersion then
        local okRequire, satisfied = pcall(function() return plugin.Require(minVersion) end)
        if okRequire then
            return satisfied and about.states.ok or about.states.outdated, version
        end
        if version then
            return about.isAtLeast(version, minVersion) and about.states.ok or about.states.outdated, version
        end
    end

    return about.states.ok, version
end

--- The minimum versions are those of game version 2.5, older game versions work with older plugins
---@param minVersion string
---@return string?
local function minVersionForGame(minVersion)
    local ok, gameVersion = pcall(function() return Game.GetSystemRequestsHandler():GetGameVersion() end)
    if ok and type(gameVersion) == "string" and about.isAtLeast(gameVersion, "2.5") then
        return minVersion
    end
end

---@type aboutDependency[]
about.dependencies = {
    {
        id = "cyberEngineTweaks",
        name = "Cyber Engine Tweaks",
        required = true,
        provides = "Hosts the mod: its Lua runtime, the ImGui window and the game bindings.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/107",
        check = function()
            local ok, version = pcall(GetVersion)
            return about.states.ok, ok and version ~= nil and tostring(version) or nil
        end
    },
    {
        id = "redHotTools",
        name = "RedHotTools",
        required = true,
        blocking = true,
        minVersion = "1.3.0",
        missingIssue = "RedHotTools is not installed",
        provides = "Finds the nodes to remove (Inspect and Scan tabs, \"Send node to Removal Editor\"), and installs a preset without restarting the game.\nVersion 1.3.0 or later is needed for game version 2.5.",
        url = "https://github.com/psiberx/cp2077-red-hot-tools",
        check = function()
            local plugin = getGlobal(function() return RedHotTools end)
            -- Game.GetWorldInspector raises an error when the plugin is not loaded
            local hasInspector = pcall(function() return Game.GetWorldInspector() end) and IsDefined(Game.GetWorldInspector())
            if not plugin or not hasInspector or not about.getMod("RedHotTools") then
                return about.states.missing
            end
            return checkPlugin(plugin, minVersionForGame("1.3.0"))
        end
    },
    {
        id = "archiveXL",
        name = "ArchiveXL",
        required = true,
        minVersion = "1.28.6",
        provides = "Removes the nodes of a preset, once installed in archive\\pc\\mod or with Install & Reload. Removal Editor itself works without it.\nVersion 1.28.6 or later is needed for game version 2.5.",
        url = "https://github.com/psiberx/cp2077-archive-xl",
        check = function()
            return checkPlugin(getGlobal(function() return ArchiveXL end), minVersionForGame("1.28.6"))
        end
    },
    {
        id = "windowUtils",
        name = "Window Utils",
        required = false,
        provides = "Takes over drawing the Removal Editor window, adding its own window handling (snapping, docking, the taskbar) to the plain CET one.",
        check = function()
            if about.getMod("WindowUtils") then
                return about.states.ok
            end
            return about.states.missing
        end
    }
}

---@param dependency aboutDependency
---@return aboutDependencyStatus
function about.getDependencyStatus(dependency)
    local ok, state, detectedVersion = pcall(dependency.check)
    if not ok or state == nil then
        state, detectedVersion = about.states.unknown, nil
    end

    return {
        id = dependency.id,
        name = dependency.name,
        required = dependency.required == true,
        blocking = dependency.blocking == true,
        minVersion = dependency.minVersion,
        provides = dependency.provides,
        url = dependency.url,
        state = state,
        detectedVersion = detectedVersion,
        satisfied = state == about.states.ok
    }
end

---@return aboutDependencyStatus[]
function about.getDependencies()
    local statuses = {}
    for _, dependency in ipairs(about.dependencies) do
        statuses[#statuses + 1] = about.getDependencyStatus(dependency)
    end
    return statuses
end

--- Messages for the dependencies the mod cannot run without
---@return string[]
function about.getBlockingIssues()
    local issues = {}

    for _, dependency in ipairs(about.dependencies) do
        if dependency.blocking then
            local status = about.getDependencyStatus(dependency)

            if status.state == about.states.missing then
                issues[#issues + 1] = dependency.missingIssue or (dependency.name .. " is not installed")
            elseif status.state == about.states.outdated then
                issues[#issues + 1] = dependency.name .. " version is outdated, please update to " .. tostring(dependency.minVersion)
            end
        end
    end

    return issues
end

return about
