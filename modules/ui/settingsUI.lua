-- The Settings tab, laid out as Dialogue Browser's: a sidebar of pages, a search that fades what it does not match,
-- and the page itself.
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local about = require("modules/utils/about")
local settingsSearch = require("modules/ui/settingsSearch")

local settingsUI = {
    baseUI = nil
}

local DEFAULT_SIDEBAR_WIDTH = 150
local MIN_SIDEBAR_WIDTH = 44
local MAX_SIDEBAR_WIDTH_RATIO = 0.4
local DIVIDER_SIZE = 7.5
local DATA_FOLDER = "bin\\x64\\plugins\\cyber_engine_tweaks\\mods\\removalEditor\\data"

local state = {
    confirmReset = false,
    divider = { hovered = false, dragging = false }
}

local search = settingsSearch.new("reSettings")

-- Everything the search can reach, and the page each is on
---@type table<string, settingDef>
local defs = {
    directAdd = {
        label = "Add nodes sent from RedHotTools right away",
        category = "editing",
        searchTerms = "direct add stage staging confirmation note rht send",
        tooltip = "On: a node sent from RHT is added to the opened preset at once.\nOff: it is staged in the Edit tab first, to write its note before adding it.",
        widget = { kind = "checkbox" }
    },
    defaultPresetFormat = {
        label = "Format of new presets",
        category = "presets",
        searchTerms = "yaml json format file type default new preset create comments game version",
        tooltip = "The format a preset is created in. An existing preset is always saved in the format it was read in.",
        widget = { kind = "combo", values = { "yaml", "json" }, labels = { "YAML", "JSON" } }
    },
    deleteConfirm = {
        label = "Ask before deleting a preset",
        category = "presets",
        searchTerms = "confirm delete popup remove file",
        tooltip = "Shows a confirmation popup before a preset file is deleted.",
        widget = { kind = "checkbox" }
    },
    teleportOnReload = {
        label = "Teleport back after Install & Reload",
        category = "presets",
        searchTerms = "install reload teleport position player save checkpoint",
        tooltip = "Puts the player back where they were once Install & Reload has reloaded the last save.",
        widget = { kind = "checkbox" }
    },

    dataFolder = {
        label = "Data folder",
        category = "advanced",
        searchTerms = "folder path presets files xl data location copy",
        tooltip = "Where the presets are read from and saved to, relative to the game folder."
    },
    resetSettings = {
        label = "Reset settings",
        category = "advanced",
        searchTerms = "reset defaults restore",
        tooltip = "Puts every setting back to its default, the window size included. The presets are left alone."
    },

    aboutMod = {
        label = "About",
        category = "about",
        searchTerms = "version author credits thanks maintainer"
    },

    dependencies = {
        label = "Dependencies",
        category = "dependencies",
        searchTerms = "requirements installed missing outdated redhottools archivexl cet window utils integrations"
    }
}

-- Every field of these pages has the same width, so that they line up
local FIELD_WIDTH = 120

-- Each returns the new value and whether it changed
local WIDGETS = {
    checkbox = function(key, def)
        return ImGui.Checkbox(def.label, settings[key] == true)
    end,

    combo = function(key, def)
        local widget = def.widget
        local index = 0
        for i, value in ipairs(widget.values) do
            if value == settings[key] then index = i - 1 end
        end

        style.setNextItemWidth(FIELD_WIDTH)
        local newIndex, changed = ImGui.Combo("##" .. key, index, widget.labels, #widget.labels)
        return widget.values[newIndex + 1], changed
    end
}

--- One setting: faded when the search misses it, saved when it changes
---@param key string
---@param after fun()? Drawn under it, faded with it
local function drawSetting(key, after)
    local def = defs[key]

    search:beginDimKey(key, defs)

    local value, changed = WIDGETS[def.widget.kind](key, def)
    if changed then
        settings[key] = value
        settings.save()
    end

    if def.widget.kind ~= "checkbox" then
        ImGui.SameLine()
        ImGui.Text(def.label)
    end

    if def.tooltip then
        style.tooltip(def.tooltip)
    end

    if after then
        after()
    end

    search:endDim()
end

--- A hand-drawn control, faded with its neighbours
---@param key string
---@param draw fun()
local function drawCustomSetting(key, draw)
    search:beginDimKey(key, defs)
    draw()
    search:endDim()
end

-- Presets

-- Pros (true) and cons (false) of each format
local FORMAT_DESCRIPTIONS = {
    {
        name = "YAML",
        points = {
            { true, "Readable and editable by hand, one entry per line." },
            { true, "Keeps its comments, e.g. those ArchiveXL Sector Updater writes." },
            { true, "Records the game version the preset was made for, so that an outdated preset is detected." },
        }
    },
    {
        name = "JSON",
        points = {
            { true, "20 to 30% smaller than YAML" },
            { false, "Written on a single line, hard to read or edit by hand." },
            { false, "Cannot hold comments: its game version stays unknown, and an outdated preset cannot be detected." }
        }
    }
}

---@param format table From FORMAT_DESCRIPTIONS
local function drawFormatDescription(format)
    style.styledText(format.name, style.highlightColor)
    ImGui.Indent(12 * style.viewSize)

    for _, point in ipairs(format.points) do
        local isPro, text = point[1], point[2]
        style.styledText(isPro and IconGlyphs.PlusThick or IconGlyphs.MinusThick, isPro and style.successColor or style.errorColor)
        ImGui.SameLine()
        -- Wrapped lines start under the text, not under the icon
        style.styledTextWrapped(text, style.mutedColor)
    end

    ImGui.Unindent(12 * style.viewSize)
end

local function drawPresetsPage()
    drawSetting("defaultPresetFormat", function()
        style.spacing(4)
        for _, format in ipairs(FORMAT_DESCRIPTIONS) do
            drawFormatDescription(format)
        end
        style.spacing(8)
    end)

    drawSetting("deleteConfirm")
    drawSetting("teleportOnReload")
end

-- Editing

local function drawEditingPage()
    drawSetting("directAdd")
end

-- Advanced

local function drawAdvancedPage()
    drawCustomSetting("dataFolder", function()
        style.mutedText(defs.dataFolder.label)
        style.tooltip(defs.dataFolder.tooltip)
        ImGui.SameLine()
        ImGui.Text(DATA_FOLDER)
        ImGui.SameLine()
        style.copyButton("dataFolder", DATA_FOLDER, { what = "the data folder path", tooltip = "Copy the path" })
    end)

    style.spacing(8)

    drawCustomSetting("resetSettings", function()
        if not state.confirmReset then
            if style.warnButton(style.actionLabel(IconGlyphs.Refresh, "Reset settings", "resetSettings"), {
                tooltip = defs.resetSettings.tooltip
            }) then
                state.confirmReset = true
            end

            return
        end

        style.styledTextWrapped("Put every setting back to its default? The presets are kept.", style.errorColor)

        if style.dangerButton("Reset##confirmResetSettings") then
            settings.reset()
            settingsUI.baseUI.loadWindowSize = true
            state.confirmReset = false
        end

        ImGui.SameLine()
        if ImGui.Button("Cancel##cancelResetSettings") then
            state.confirmReset = false
        end
    end)
end

-- About

local function drawAboutPage()
    search:beginDimKey("aboutMod", defs)

    local labels = { "Version", "Author", "Maintainer" }
    local labelWidth = 0
    for _, label in ipairs(labels) do
        labelWidth = math.max(labelWidth, (ImGui.CalcTextSize(label)))
    end
    labelWidth = labelWidth + ImGui.GetStyle().ItemSpacing.x * 2

    local function row(label, value)
        local startX = ImGui.GetCursorPosX()
        style.mutedText(label)
        ImGui.SameLine(startX + labelWidth)
        ImGui.TextWrapped(value)
    end

    style.styledText(about.name, style.activeColor)
    style.spacing(4)

    row("Version", about.version)
    row("Author", about.author)
    if about.maintainer then
        row("Maintainer", about.maintainer)
    end

    style.panelSectionHeader("Thanks")
    style.styledTextWrapped(about.thanks, style.mutedColor)

    search:endDim()
end

-- Dependencies

local stateDisplay = {
    ok = { icon = IconGlyphs.CheckCircleOutline, label = "Installed" },
    outdated = { icon = IconGlyphs.AlertCircleOutline, label = "Outdated" },
    missing = { icon = IconGlyphs.CloseCircleOutline, label = "Not installed" },
    unknown = { icon = IconGlyphs.HelpCircleOutline, label = "Could not be detected" }
}

---@param status aboutDependencyStatus
---@return number
local function getDependencyColor(status)
    if status.state == about.states.ok then
        return style.successColor
    end
    if status.state == about.states.outdated then
        return style.warnColor
    end
    if status.state == about.states.missing and status.required then
        return style.errorColor
    end
    return style.mutedColor
end

---@param status aboutDependencyStatus
---@return string
local function getDependencyStateText(status)
    local text = (stateDisplay[status.state] or stateDisplay.unknown).label

    if status.detectedVersion and status.detectedVersion ~= "" then
        text = text .. " (" .. status.detectedVersion .. ")"
    end
    if status.minVersion and status.state ~= about.states.ok then
        text = text .. " - requires " .. status.minVersion
    end

    return text
end

---@param status aboutDependencyStatus
local function drawDependencyRow(status)
    local color = getDependencyColor(status)
    local display = stateDisplay[status.state] or stateDisplay.unknown

    ImGui.PushID(status.id)

    ImGui.BeginGroup()
    style.styledText(display.icon, color)
    ImGui.SameLine()
    ImGui.Text(status.name)
    ImGui.SameLine()
    style.styledText(getDependencyStateText(status), color)
    ImGui.EndGroup()

    local hovered = ImGui.IsItemHovered()

    if status.satisfied then
        style.wrappedTooltipHovered(hovered, status.provides)
        ImGui.PopID()
        return
    end

    if status.url then
        ImGui.SameLine()
        style.copyButton("dependencyUrl", status.url, { what = "the link", tooltip = "Copy the link:\n" .. status.url })
    end

    ImGui.Indent(20 * style.viewSize)
    style.styledTextWrapped(status.provides, style.mutedColor)
    ImGui.Unindent(20 * style.viewSize)

    ImGui.PopID()
end

local function drawDependenciesPage()
    search:beginDimKey("dependencies", defs)

    local required, optional = {}, {}
    local missingRequired, missingOptional = 0, 0
    for _, status in ipairs(about.getDependencies()) do
        if status.required then
            required[#required + 1] = status
            if not status.satisfied then missingRequired = missingRequired + 1 end
        else
            optional[#optional + 1] = status
            if not status.satisfied then missingOptional = missingOptional + 1 end
        end
    end

    if missingRequired > 0 then
        style.styledTextWrapped(string.format("%d required %s missing or outdated.", missingRequired, missingRequired == 1 and "dependency is" or "dependencies are"), style.errorColor)
    elseif missingOptional > 0 then
        style.styledTextWrapped("Everything required is in place, some optional integrations are not installed.", style.successColor)
    else
        style.styledTextWrapped("Everything is in place.", style.successColor)
    end

    style.panelSectionHeader("Required", { tooltip = "Hover a row for what it brings to Removal Editor." })
    for _, status in ipairs(required) do
        drawDependencyRow(status)
    end

    style.panelSectionHeader("Optional integrations", { tooltip = "Other mods Removal Editor works with when they are installed. Everything keeps working without them." })
    for _, status in ipairs(optional) do
        drawDependencyRow(status)
    end

    search:endDim()
end

-- Pages

local pages = {
    { id = "presets", label = "Presets", icon = IconGlyphs.FileDocumentMultipleOutline, category = "presets", draw = drawPresetsPage },
    { id = "editing", label = "Editing", icon = IconGlyphs.PencilOutline, category = "editing", draw = drawEditingPage },
    { id = "advanced", label = "Advanced", icon = IconGlyphs.Tune, category = "advanced", draw = drawAdvancedPage },
    { id = "about", label = "About", icon = IconGlyphs.InformationOutline, category = "about", draw = drawAboutPage },
    { id = "dependencies", label = "Dependencies", icon = IconGlyphs.PuzzleOutline, category = "dependencies", draw = drawDependenciesPage }
}

---@return integer
local function getSelectedPage()
    local index = math.floor(tonumber(settings.settingsSection) or 1)
    if index < 1 or index > #pages then
        return 1
    end
    return index
end

---@param index integer
local function setSelectedPage(index)
    if index == getSelectedPage() then return end

    settings.settingsSection = index
    settings.save()
end

-- Layout

--- Either every entry is named, or every one is an icon
---@param width number Already scaled
---@return boolean
local function isIconOnly(width)
    for _, page in ipairs(pages) do
        if style.buttonWidth(style.actionLabel(page.icon, page.label)) > width then
            return true
        end
    end
    return false
end

local function drawSidebar()
    local selected = getSelectedPage()
    local width = math.max((ImGui.GetContentRegionAvail()), 1)
    local iconOnly = isIconOnly(width)

    for index, page in ipairs(pages) do
        search:beginDimCategory(page.category, defs)

        if style.navButton(page.icon, page.label, index == selected, {
            id = "settingsNav" .. page.id,
            width = width,
            iconOnly = iconOnly
        }) then
            setSelectedPage(index)
            state.confirmReset = false
        end

        search:endDim()
    end
end

local function drawSearchRow()
    local text, changed, cleared = style.drawSearchFilterRow("##settingsSearch" .. search.id, search:getQuery(), {
        fill = true,
        hint = "Search settings...",
        maxLength = 256,
        searchTooltip = "Search the settings",
        -- Settings are matched on plain words: no syntax to explain
        help = false
    })

    if changed or cleared then
        search:setQuery(text)
    end
end

---@param width number Already scaled
---@param height number Already scaled
local function drawContentColumn(width, height)
    if ImGui.BeginChild("##settingsContentColumn", width, height, false, ImGuiWindowFlags.NoScrollbar) then
        local searchHeight = ImGui.GetFrameHeight() + ImGui.GetStyle().WindowPadding.y * 2

        if style.beginPanel("##settingsSearchPanel", 0, searchHeight, { flags = ImGuiWindowFlags.NoScrollbar }) then
            drawSearchRow()
        end
        style.endPanel()

        ImGui.Spacing()

        if style.beginPanel("##settingsPage", 0, 0) then
            ImGui.PushItemWidth(120 * style.viewSize)
            pages[getSelectedPage()].draw()
            ImGui.PopItemWidth()
        end
        style.endPanel()
    end

    ImGui.EndChild()
end

--- Opens a settings page, by its id
---@param pageId string
---@return boolean found
function settingsUI.selectPage(pageId)
    for index, page in ipairs(pages) do
        if page.id == pageId then
            setSelectedPage(index)
            return true
        end
    end

    return false
end

--- Empties the search, so that the tab is not left filtered by an older query
function settingsUI.clearSearch()
    search:clear()
end

function settingsUI.draw()
    local xSpace, ySpace = ImGui.GetContentRegionAvail()
    if xSpace <= 0 or ySpace <= 0 then return end

    local dividerSize = DIVIDER_SIZE * style.viewSize
    local spacingX = ImGui.GetStyle().ItemSpacing.x

    -- The sidebar keeps the width it was dragged to, within what the tab can spare
    local maxWidth = math.max(MIN_SIDEBAR_WIDTH * style.viewSize, xSpace * MAX_SIDEBAR_WIDTH_RATIO)
    local sidebarWidth = math.min(
        math.max((tonumber(settings.settingsSidebarWidth) or DEFAULT_SIDEBAR_WIDTH) * style.viewSize, MIN_SIDEBAR_WIDTH * style.viewSize),
        maxWidth
    )
    settings.settingsSidebarWidth = sidebarWidth / style.viewSize

    local contentWidth = xSpace - sidebarWidth - dividerSize - spacingX * 2

    if style.beginPanel("##settingsNavPanel", sidebarWidth, ySpace) then
        drawSidebar()
    end
    style.endPanel()

    ImGui.SameLine()

    style.dragSetting("##settingsVerticalDivider", "vertical", ySpace, state.divider, {
        settings = settings,
        key = "settingsSidebarWidth",
        default = DEFAULT_SIDEBAR_WIDTH
    })

    ImGui.SameLine()

    if contentWidth > 0 then
        drawContentColumn(contentWidth, ySpace)
    end
end

return settingsUI
