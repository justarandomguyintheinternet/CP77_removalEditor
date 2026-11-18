-- The window and its tabs (as World Builder's baseUI.lua). The window has one size for all its tabs, kept in the
-- settings as Dialogue Browser does, and its version is drawn in the title bar.
local settings = require("modules/utils/settings")
local about = require("modules/utils/about")
local style = require("modules/ui/style")
local presetsUI = require("modules/ui/presetsUI")
local editUI = require("modules/ui/editUI")
local settingsUI = require("modules/ui/settingsUI")

-- The window keeps the name, and so the position, it always had
local WINDOW_NAME = "Removal Editor"
local DEFAULT_SIZE = { 560, 700 } -- Unscaled
local MIN_SIZE = { 380, 300 } -- Unscaled
-- A resize reports a new size every frame it is dragged: the size is saved once it settled
local SIZE_SETTLE_FRAMES = 30

---@class baseUI
local baseUI = {
    presetsUI = presetsUI,
    editUI = editUI,
    settingsUI = settingsUI,

    activeTab = 1,
    requestedTab = nil,
    loadWindowSize = true,
    requirementsIssues = {}
}

local sizeSettleFrames = -1

-- Window Utils draws the window when it is installed (snapping, docking, taskbar), ImGui otherwise.
-- Its Begin / End keep a stack of the windows it tracks: End is only called for a Begin that reported the window visible.
local wu = nil

-- Tabs that need everything the mod relies on, unlike Settings, which says what is missing
local tabs = {
    { id = "presets", name = "Presets", needsRequirements = true, draw = presetsUI.draw },
    { id = "edit", name = "Edit", needsRequirements = true, draw = editUI.draw },
    { id = "settings", name = "Settings", draw = settingsUI.draw }
}

function baseUI.init()
    -- Read here rather than when this file is loaded: Window Utils may not have registered yet then
    wu = about.getMod("WindowUtils") or ImGui

    presetsUI.baseUI = baseUI
    settingsUI.baseUI = baseUI

    baseUI.activeTab = math.max(1, math.min(#tabs, math.floor(tonumber(settings.activeTab) or 1)))
    baseUI.requestedTab = baseUI.activeTab

    baseUI.requirementsIssues = about.getBlockingIssues()
    for _, issue in ipairs(baseUI.requirementsIssues) do
        print("[RemovalEditor] Error: " .. issue .. ", Removal Editor needs it!")
    end
end

---@return boolean
function baseUI.hasRequirements()
    return #baseUI.requirementsIssues == 0
end

--- Opens a tab on the next frame
---@param tabId string
function baseUI.selectTab(tabId)
    for index, tab in ipairs(tabs) do
        if tab.id == tabId then
            baseUI.requestedTab = index
            return
        end
    end
end

-- As World Builder's requirements error
local function drawRequirementsIssues()
    style.mutedText(string.format("The following issues are preventing %s from running:", about.name))

    for _, issue in pairs(baseUI.requirementsIssues) do
        ImGui.Text(issue)
    end

    ImGui.Spacing()
    style.mutedText("Settings > Dependencies says where to get them.")
end

--- The version on the right of the (centered) title bar, left out when it would cover the title (World Builder 2.0)
local function drawTitleBarVersion()
    local drawList = ImGui.GetWindowDrawList()
    if not drawList then return end

    local windowX, windowY = ImGui.GetWindowPos()
    local windowWidth = ImGui.GetWindowWidth()
    local titleBarHeight = ImGui.GetFrameHeight()
    local styleData = ImGui.GetStyle()

    local titleWidth = ImGui.CalcTextSize(WINDOW_NAME)
    local versionWidth, versionHeight = ImGui.CalcTextSize(about.version)
    local titleRight = windowX + windowWidth * 0.5 + titleWidth * 0.5
    local versionLeft = windowX + windowWidth - styleData.WindowPadding.x - versionWidth

    if versionLeft <= titleRight + styleData.ItemSpacing.x then return end

    -- The window draw list is clipped to its content, the title bar is taken in for a moment
    ImGui.PushClipRect(windowX, windowY, windowX + windowWidth, windowY + titleBarHeight, false)
    ImGui.ImDrawListAddText(drawList, versionLeft, windowY + (titleBarHeight - versionHeight) * 0.5, style.mutedColor, about.version)
    ImGui.PopClipRect()
end

--- Keeps the window size in the settings, saved once the resize is over
local function trackWindowSize()
    local width, height = ImGui.GetWindowSize()

    if width ~= settings.mainWindowWidth or height ~= settings.mainWindowHeight then
        settings.mainWindowWidth = width
        settings.mainWindowHeight = height
        sizeSettleFrames = 0
    elseif sizeSettleFrames >= 0 then
        sizeSettleFrames = sizeSettleFrames + 1

        if sizeSettleFrames > SIZE_SETTLE_FRAMES then
            sizeSettleFrames = -1
            settings.save()
        end
    end
end

local function drawTabBar()
    if not ImGui.BeginTabBar("Tabbar", ImGuiTabBarFlags.NoTooltip) then return end

    for index, tab in ipairs(tabs) do
        local flags = ImGuiTabItemFlags.None
        if baseUI.requestedTab == index then
            flags = ImGuiTabItemFlags.SetSelected
            baseUI.requestedTab = nil
        end

        if ImGui.BeginTabItem(tab.name, flags) then
            if baseUI.activeTab ~= index then
                baseUI.activeTab = index
                settings.activeTab = index
                settings.save()

                if tab.id ~= "settings" then
                    settingsUI.clearSearch()
                end
            end

            ImGui.Spacing()

            if tab.needsRequirements and not baseUI.hasRequirements() then
                drawRequirementsIssues()
            else
                tab.draw()
            end

            ImGui.EndTabItem()
        end
    end

    ImGui.EndTabBar()
end

function baseUI.draw()
    if not wu then return end

    if baseUI.loadWindowSize then
        local width = tonumber(settings.mainWindowWidth) or 0
        local height = tonumber(settings.mainWindowHeight) or 0

        if width <= 0 or height <= 0 then
            width, height = DEFAULT_SIZE[1] * style.viewSize, DEFAULT_SIZE[2] * style.viewSize
        end

        ImGui.SetNextWindowSize(width, height, ImGuiCond.Always)
        baseUI.loadWindowSize = false
    end
    ImGui.SetNextWindowSizeConstraints(MIN_SIZE[1] * style.viewSize, MIN_SIZE[2] * style.viewSize, 100000, 100000)

    style.pushStyleVar(true, ImGuiStyleVar.WindowTitleAlign, 0.5, 0.5)

    if wu.Begin(WINDOW_NAME, ImGuiWindowFlags.None) then
        drawTitleBarVersion()
        trackWindowSize()
        drawTabBar()

        wu.End()
    end

    style.popStyleVar(true)
end

return baseUI
