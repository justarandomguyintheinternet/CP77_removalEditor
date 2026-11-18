-- The Presets tab: creating, opening, deleting and installing presets
local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local presets = require("modules/utils/presets")
local commentedNodes = require("modules/utils/commentedNodes")
local style = require("modules/ui/style")

local DELETE_POPUP = "Delete preset?"

local presetsUI = {
    baseUI = nil,
    newPresetName = "",
    pendingInstall = nil, -- Outdated preset waiting for its second click
    deleteFile = nil, -- Preset the delete popup is about
    openDeletePopup = false
}

--- Warning when the preset was not made for the running game version, and the button that records it
---@param name string
---@param preset table
function presetsUI.drawVersionWarning(name, preset)
    local version = presets.getOutdatedVersion(preset)
    if not version then return end

    local current = presets.gameVersion
    -- The version is a comment, which JSON cannot hold
    local isYaml = presets.isYaml(name)

    style.styledText(IconGlyphs.AlertOutline, style.warnColor)
    ImGui.SameLine()
    if version == "unknown" then
        style.styledTextWrapped(string.format("Game version unknown%s: if this preset was made before %s, its node indices are probably wrong. Convert it with ArchiveXL Sector Updater.",
            isYaml and "" or " (a JSON preset cannot record it)", current), style.warnColor)
    else
        style.styledTextWrapped(string.format("Made for %s, the game is %s: node indices may have changed. Convert it with ArchiveXL Sector Updater.", version, current), style.warnColor)
    end

    if not isYaml then return end

    if ImGui.Button("Mark as made for " .. current) then
        presets.setGameVersion(preset, current)
        presets.save(name)
    end
    style.tooltip("Writes \"# Game version: " .. current .. "\" at the start of the file, once its nodes have been checked or converted for " .. current .. ".")
end

---@param name string
local function requestDelete(name)
    if settings.deleteConfirm then
        presetsUI.deleteFile = name
        presetsUI.openDeletePopup = true
    else
        presets.delete(name)
    end
end

-- As World Builder's "Delete Data?" popup
local function drawDeletePopup()
    if presetsUI.openDeletePopup then
        ImGui.OpenPopup(DELETE_POPUP)
        presetsUI.openDeletePopup = false
    end

    if not ImGui.BeginPopupModal(DELETE_POPUP, ImGuiWindowFlags.AlwaysAutoResize) then return end

    local name = presetsUI.deleteFile or ""
    ImGui.Text(string.format("\"%s\" will be deleted from the data folder.", utils.removeExtension(name)))
    ImGui.Spacing()

    local again, changed = ImGui.Checkbox("Don't ask again", not settings.deleteConfirm)
    if changed then
        settings.deleteConfirm = not again
        settings.save()
    end
    style.tooltip("Can be turned back on in Settings")

    ImGui.Spacing()

    if ImGui.Button("Cancel") then
        presetsUI.deleteFile = nil
        ImGui.CloseCurrentPopup()
    end

    ImGui.SameLine()

    if style.dangerButton("Delete") then
        if presetsUI.deleteFile and presets.list[presetsUI.deleteFile] then
            presets.delete(presetsUI.deleteFile)
        end
        presetsUI.deleteFile = nil
        ImGui.CloseCurrentPopup()
    end

    ImGui.EndPopup()
end

--- What the commented out nodes of a preset are, for its tooltips
---@param nodes commentedNode[]
---@return string
function presetsUI.getCommentedTooltip(nodes)
    return string.format("%d node%s commented out by ArchiveXL Sector Updater: %s.\nArchiveXL ignores them. They are listed in the Edit tab, with the reason.",
        #nodes, #nodes == 1 and "" or "s", commentedNodes.summary(nodes))
end

-- The columns of the list, on the right of the name of each preset
local COLUMNS = {
    { key = "commented", header = "Ignored", tooltip = "Nodes commented out by ArchiveXL Sector Updater (ArchiveXL ignores them).\nOrange when some were not found or do not match, grey when they all moved." },
    { key = "version", header = "Game\nVersion", tooltip = "Game version the preset was made for, orange when it is not the running one." },
    { key = "format", header = "Format", tooltip = "Format of the .xl file." }
}

--- What the columns of a preset show
---@param name string
---@param preset table
---@return table<string, {text: string, color: number?, tooltip: string?}>
local function getCells(name, preset)
    local cells = {}

    local commented = presets.getCommented(name)
    if #commented > 0 then
        cells.commented = {
            text = IconGlyphs.CommentAlertOutline .. " " .. #commented,
            color = commentedNodes.needsAttention(commented) and style.warnColor or style.mutedColor,
            tooltip = presetsUI.getCommentedTooltip(commented)
        }
    else
        cells.commented = { text = "-", color = style.mutedColor }
    end

    local version = presets.getGameVersion(preset)
    if presets.getOutdatedVersion(preset) then
        cells.version = {
            text = version and (IconGlyphs.AlertOutline .. " " .. version) or IconGlyphs.HelpRhombusOutline,
            color = style.warnColor,
            tooltip = version and string.format("Made for %s, the game is %s: node indices may have changed.", version, presets.gameVersion)
                or "Game version unknown: if this preset was made before " .. presets.gameVersion .. ", its node indices are probably wrong."
        }
    else
        cells.version = {
            text = version or IconGlyphs.HelpRhombusOutline,
            color = version == nil and style.mutedColor or nil,
            tooltip = version == nil and "Game version unknown" or nil
        }
    end

    cells.format = { text = presets.isYaml(name) and "YAML" or "JSON" }

    return cells
end

--- Where each column starts, in screen coordinates, from the right edge of the list
---@param rows table[] Cells of each preset
---@param right number
---@return table<string, number>, number Column starts, and the space between columns
local function getColumnsX(rows, right)
    local gap = 20 * style.viewSize
    local xs = {}

    for i = #COLUMNS, 1, -1 do
        local column = COLUMNS[i]
        local width = ImGui.CalcTextSize(column.header)
        for _, cells in ipairs(rows) do
            width = math.max(width, ImGui.CalcTextSize(cells[column.key].text))
        end

        right = right - width
        xs[column.key] = right
        right = right - gap
    end

    return xs, gap
end

--- Text on the current line, from screen position x
---@param x number
---@param text string
---@param color number?
---@param tooltip string?
---@param y number? Screen position, the current line if nil
local function drawCell(x, text, color, tooltip, y)
    ImGui.SameLine()
    y = y or select(2, ImGui.GetCursorScreenPos())
    ImGui.SetCursorScreenPos(x, y)
    style.styledText(text, color)

    if tooltip then
        -- A header under it takes the hover: the rectangle of the text is read instead
        local minX, minY = ImGui.GetItemRectMin()
        local maxX, maxY = ImGui.GetItemRectMax()
        style.wrappedTooltipHovered(ImGui.IsMouseHoveringRect(minX, minY, maxX, maxY), tooltip)
    end
end

--- The header of the list, aligned on the columns of its rows
---@param left number Screen position of the names
---@param xs table<string, number>
local function drawListHeader(left, xs)
    -- Headers can span several lines: each one is centered vertically on the tallest
    local function countLines(text)
        return select(2, text:gsub("\n", "")) + 1
    end
    local lines = 1
    for _, column in ipairs(COLUMNS) do
        lines = math.max(lines, countLines(column.header))
    end
    local lineHeight = ImGui.GetTextLineHeight()

    local startX, y = ImGui.GetCursorScreenPos()
    ImGui.SetCursorScreenPos(left, y + (lines - 1) * lineHeight / 2)
    style.mutedText("Name")

    for _, column in ipairs(COLUMNS) do
        drawCell(xs[column.key], column.header, style.mutedColor, column.tooltip,
            y + (lines - countLines(column.header)) * lineHeight / 2)
    end

    -- The line under the header goes below its tallest cell
    ImGui.SetCursorScreenPos(startX, y + lines * lineHeight + ImGui.GetStyle().ItemSpacing.y)
    ImGui.Separator()
end

---@param name string
---@param preset table
---@param cells table
---@param xs table<string, number>
---@param gap number
local function drawPreset(name, preset, cells, xs, gap)
    -- The name stops before the first column
    local fullName = utils.removeExtension(name)
    local labelX = ImGui.GetCursorScreenPos() + ImGui.GetTreeNodeToLabelSpacing()
    local shownName = style.truncateText(fullName, xs[COLUMNS[1].key] - gap - labelX)

    local open = ImGui.TreeNodeEx(shownName .. "##" .. name, ImGuiTreeNodeFlags.SpanFullWidth)
    if shownName ~= fullName then
        local mouseX = ImGui.GetMousePos()
        style.wrappedTooltipHovered(ImGui.IsItemHovered() and mouseX < xs[COLUMNS[1].key] - gap, fullName)
    end

    for _, column in ipairs(COLUMNS) do
        local cell = cells[column.key]
        drawCell(xs[column.key], cell.text, cell.color, cell.tooltip)
    end

    if not open then return end

    -- The counters share one line, each behind its icon
    local counters = {
        { icon = IconGlyphs.SelectionMultipleMarker, name = "Sectors", value = #preset.streaming.sectors },
        { icon = IconGlyphs.DeleteVariant, name = "Removals", value = utils.getTotalRemovals(preset) },
        { icon = IconGlyphs.CursorMove, name = "Mutations", value = utils.getTotalMutations(preset) }
    }
    for index, counter in ipairs(counters) do
        if index > 1 then
            ImGui.SameLine()
            ImGui.SetCursorPosX(ImGui.GetCursorPosX() + ImGui.GetStyle().ItemSpacing.x * 2)
        end
        -- Plain text: the SameLine of the next counter does not hold after the TextWrapped of style.drawProp
        style.mutedText(counter.icon .. " " .. counter.name)
        ImGui.SameLine()
        ImGui.Text(tostring(counter.value))
        if ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
            ImGui.SetClipboardText(tostring(counter.value))
            ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, "Copied " .. counter.name .. " to the clipboard"))
        end
    end

    local commented = presets.getCommented(name)
    if #commented > 0 then
        style.drawProp("Commented Out", string.format("%d (%s)", #commented, commentedNodes.summary(commented)))
        style.wrappedTooltip(presetsUI.getCommentedTooltip(commented))
    end

    presetsUI.drawVersionWarning(name, preset)

    if ImGui.Button(style.actionLabel(IconGlyphs.PencilOutline, "Edit")) then
        presets.open(name)
        presetsUI.baseUI.selectTab("edit")
    end
    style.tooltip("Opens the preset in the Edit tab")
    ImGui.SameLine()

    if style.dangerButton(style.actionLabel(IconGlyphs.DeleteOutline, "Delete")) then
        requestDelete(name)
    end
    ImGui.SameLine()

    local inGame = IsDefined(GetPlayer())
    -- A preset made for another game version is only installed on a second click
    local outdated = presets.getOutdatedVersion(preset) ~= nil
    local confirming = outdated and presetsUI.pendingInstall == name
    local installLabel = style.actionLabel(IconGlyphs.DownloadCircleOutline, confirming and "Install anyway" or "Install & Reload")
    if style.warnButton(installLabel, {
        disabled = not inGame,
        tooltip = confirming and "This preset was not made for this game version: ArchiveXL may remove the wrong objects."
            or "Installs the preset and reloads the last save. Make a Quick-Save first, to keep your progress and speed up the reload."
    }) then
        if outdated and not confirming then
            presetsUI.pendingInstall = name
        else
            presetsUI.pendingInstall = nil
            presets.install(name)
        end
    end

    ImGui.TreePop()
    ImGui.Spacing()
end

function presetsUI.draw()
    presets.refresh()

    style.sectionHeaderStart("NEW PRESET")

    style.setNextItemWidth(250)
    presetsUI.newPresetName = style.inputTextWithHint("##newName", "Name...", presetsUI.newPresetName, 100)
    presetsUI.newPresetName = utils.sanitizeFileName(presetsUI.newPresetName)
    local validName = presetsUI.newPresetName:match("%S") ~= nil

    ImGui.SameLine()

    style.pushGreyedOut(not validName)
    if ImGui.Button("Create") and validName then
        if presets.create(presetsUI.newPresetName:match("^%s*(.-)%s*$")) then
            presetsUI.newPresetName = ""
        end
    end
    style.popGreyedOut(not validName)
    style.tooltip(string.format("Creates an empty %s preset in the data folder (Settings > Presets to change the format).\nCharacters a file name cannot hold become \"_\".",
        settings.defaultPresetFormat == "json" and "JSON" or "YAML"))

    style.sectionHeaderEnd()
    style.sectionHeaderStart("PRESETS")

    local names = presets.getSortedNames()
    local rows = {}
    for i, name in ipairs(names) do
        rows[i] = getCells(name, presets.list[name])
    end

    -- The header stays above the list when it scrolls. It is drawn before the list, with the edges the list had on
    -- the last frame (its scrollbar takes some of its width)
    if #names > 0 then
        local windowX = ImGui.GetWindowPos()
        local cursorX = ImGui.GetCursorScreenPos()
        local left = presetsUI.listLeft or cursorX
        local right = presetsUI.listRight or (windowX + ImGui.GetWindowContentRegionMax())
        drawListHeader(left + ImGui.GetTreeNodeToLabelSpacing(), (getColumnsX(rows, right)))
    end

    ImGui.BeginChild("##presets", -1, 0)

    local childX = ImGui.GetWindowPos()
    presetsUI.listLeft = ImGui.GetCursorScreenPos()
    presetsUI.listRight = childX + ImGui.GetWindowContentRegionMax()
    local xs, gap = getColumnsX(rows, presetsUI.listRight)

    for i, name in ipairs(names) do
        drawPreset(name, presets.list[name], rows[i], xs, gap)
    end

    -- Files that could not be read stay listed, instead of breaking the whole window
    for name, err in pairs(presets.invalid) do
        ImGui.PushID(name)
        if style.iconButton(IconGlyphs.Reload, "Load it again, once fixed") then
            presets.invalid[name] = nil
        end
        ImGui.SameLine()
        style.styledTextWrapped(string.format("%s: cannot be loaded (%s)", name, err), style.errorColor)
        ImGui.PopID()
    end

    if utils.tableLength(presets.list) == 0 and utils.tableLength(presets.invalid) == 0 then
        style.mutedText("No preset yet, create one above.")
    end

    ImGui.EndChild()
    style.sectionHeaderEnd(true)

    drawDeletePopup()
end

return presetsUI
