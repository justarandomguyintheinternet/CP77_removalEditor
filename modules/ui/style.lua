-- Most of the colors and style has been taken from https://github.com/psiberx/cp2077-red-hot-tools
-- Taken from World Builder (modules/ui/style.lua), so that its UI code can be reused as it is.
-- Left out: the tracked* widgets (they record World Builder's undo history), the light channels selector and spawnableInfo.
-- Then the parts taken from Dialogue Browser (panels, sidebar, dividers, search row, colored buttons), which its
-- Settings tab layout is built with, and the parts specific to Removal Editor.

local utils = require("modules/utils/utils")

local style = {
    mutedColor = 0xFFA5A19B,
    extraMutedColor = 0x96A5A19B,
    highlightColor = 0xFFDCD8D1,
    elementIndent = 35,
    draggedColor = 0xFF00007F,
    targetedColor = 0xFF00007F,
    regularColor = 0xFFFFFFFF,

    -- Dialogue Browser
    activeColor = 0xFFB2FF00,
    selectedColor = 0xFFFF9900,
    warnColor = 0xFF0099FF,
    successColor = 0xFF007F00,
    errorColor = 0xFF2525E5,
    activeTextColor = 0xFF000000,
    greyedColor = 0xff777777,

    viewSize = 1
}

local initialized = false

function style.initialize(force)
    if not force and initialized then return end
    style.viewSize = ImGui.GetFontSize() / 15
    initialized = true
end

function style.pushGreyedOut(state)
    if not state then return end

    ImGui.PushStyleColor(ImGuiCol.Button, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0xff777777)

    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 0xff777777)
end

function style.popGreyedOut(state)
    if not state then return end

    ImGui.PopStyleColor(6)
end

function style.pushStyleColor(state, style, ...)
    if not state then return end

    ImGui.PushStyleColor(style, ...)
end

function style.pushStyleVar(state, style, ...)
    if not state then return end

    ImGui.PushStyleVar(style, ...)
end

---@param state boolean
---@param count number?
function style.popStyleVar(state, count)
    if not state then return end

    ImGui.PopStyleVar(count or 1)
end

---@param state boolean
---@param count number?
function style.popStyleColor(state, count)
    if not state then return end

    ImGui.PopStyleColor(count or 1)
end

function style.tooltip(text)
    if ImGui.IsItemHovered() then
        style.setCursorRelative(8, 8)

        ImGui.SetTooltip(text)
    end
end

function style.setCursorRelative(x, y)
    local xC, yC = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(xC + x * style.viewSize, yC + y * style.viewSize, ImGuiCond.Always)
end

function style.setCursorRelativeAppearing(x, y)
    local xC, yC = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(xC + x * style.viewSize, yC + y * style.viewSize, ImGuiCond.Appearing)
end

function style.lightToolTip(text)
    if ImGui.IsItemHovered() then
        local x, y = ImGui.GetMousePos()
        ImGui.SetNextWindowPos(x + 5 * style.viewSize, y + 5 * style.viewSize, ImGuiCond.Always)
        if ImGui.Begin("##tooltip", ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoBackground) then
            style.mutedText(text)
            ImGui.End()
        end
    end
end

function style.spacedSeparator()
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

---@param text string
---@param tooltip string?
function style.sectionHeaderStart(text, tooltip)
    ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
    ImGui.SetWindowFontScale(0.85)
    ImGui.Text(text)

    if tooltip then
        style.tooltip(tooltip)
    end

    ImGui.SetWindowFontScale(1)
    ImGui.PopStyleColor()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.BeginGroup()
    ImGui.AlignTextToFramePadding()
end

function style.sectionHeaderEnd(noSpacing)
    ImGui.EndGroup()

    if not noSpacing then
        ImGui.Spacing()
        ImGui.Spacing()
    end
end

function style.mutedText(text)
    style.styledText(text, style.mutedColor)
end

---@param text string
---@param color number|table?
---@param size number?
function style.styledText(text, color, size)
    style.pushStyleColor(color ~= nil, ImGuiCol.Text, color)
    ImGui.SetWindowFontScale(size or 1)

    ImGui.Text(text)

    style.popStyleColor(color ~= nil)
    ImGui.SetWindowFontScale(1)
end

function style.pushButtonNoBG(push)
    if push then
        ImGui.PushStyleColor(ImGuiCol.Button, 0)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1, 1, 1, 0.2)
        ImGui.PushStyleVar(ImGuiStyleVar.ButtonTextAlign, 0.5, 0.5)
    else
        ImGui.PopStyleColor(2)
        ImGui.PopStyleVar()
    end
end

function style.toggleButton(text, state)
    style.pushStyleColor(not state, ImGuiCol.Text, style.mutedColor)
    style.pushButtonNoBG(true)
	ImGui.Button(text)
	style.popStyleColor(not state)
	style.pushButtonNoBG(false)
	if ImGui.IsItemClicked() then
		return not state, true
	end
    return state, false
end

function style.setNextItemWidth(width)
    ImGui.SetNextItemWidth(width * style.viewSize)
end

function style.getMaxWidth(min)
    local width = (ImGui.GetWindowContentRegionWidth() - ImGui.GetCursorPosX())
    width = math.max(width, min)

    return width / style.viewSize
end

function style.drawNoBGConditionalButton(condition, text, greyed)
    local push = false
    local greyed = greyed ~= nil and greyed or false

    if condition then
        ImGui.SameLine()
        style.pushButtonNoBG(true)
        style.pushGreyedOut(greyed)
        if ImGui.Button(text) then
            push = true
        end
        style.popGreyedOut(greyed)
        style.pushButtonNoBG(false)
    end

    return push
end

-- Dialogue Browser

style.panelCardBg = { 0.65, 0.70, 1.00, 0.045 }
style.panelFrameBg = { 0.12, 0.26, 0.42, 0.30 }
style.panelFrameBorder = { 0.24, 0.59, 1.00, 0.35 }
style.panelFrameBorderHi = { 0.45, 0.72, 1.00, 0.75 }
style.panelSplitterHover = { 0.30, 0.50, 0.70, 0.50 }
style.panelSplitterDrag = { 0.00, 1.00, 0.70, 0.60 }
style.panelSplitterIcon = { 0.60, 0.60, 0.70, 1.00 }
style.panelSplitterIconHi = { 1.00, 1.00, 1.00, 1.00 }
style.panelAccent = { 0.26, 0.59, 0.98, 1.00 }
style.panelAccentPressed = { 0.06, 0.53, 0.98, 1.00 }
style.panelAccentIdleAlpha = 0.43

---@param col number ImGuiCol.*
---@param color number[] {r, g, b, a}
---@param alpha number? Used instead of the color's own
local function pushColor(col, color, alpha)
    ImGui.PushStyleColor(col, color[1], color[2], color[3], alpha or color[4] or 1.0)
end

--- The color under the cursor, dimmed at rest and dimmed further while held
---@param color number
---@param textColor number?
local function pushFilledButton(color, textColor)
    local rgb = color % 0x1000000

    ImGui.PushStyleColor(ImGuiCol.Button, 0xCC000000 + rgb)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, color)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0x99000000 + rgb)

    if textColor then
        ImGui.PushStyleColor(ImGuiCol.Text, textColor)
    end
end

---@param textColor number? The one given to pushFilledButton
local function popFilledButton(textColor)
    ImGui.PopStyleColor(textColor and 4 or 3)
end

--- Vertical space, scaled
---@param height number
function style.spacing(height)
    ImGui.Dummy(0, height * style.viewSize)
end

---@param text string
---@param color number?
---@param size number?
function style.styledTextWrapped(text, color, size)
    style.pushStyleColor(color ~= nil, ImGuiCol.Text, color)
    ImGui.SetWindowFontScale(size or 1)

    ImGui.TextWrapped(text)

    style.popStyleColor(color ~= nil)
    ImGui.SetWindowFontScale(1)
end

--- Cuts text down to what fits in width pixels, ending it with "..." when it had to
---@param text string
---@param width number Already scaled
---@return string
function style.truncateText(text, width)
    text = tostring(text or "")

    if width <= 0 or ImGui.CalcTextSize(text) <= width then
        return text
    end

    local ellipsis = "..."
    local budget = width - ImGui.CalcTextSize(ellipsis)

    if budget <= 0 then
        return ellipsis
    end

    local low, high = 0, #text
    while low < high do
        local mid = math.floor((low + high + 1) / 2)

        if ImGui.CalcTextSize(text:sub(1, mid)) <= budget then
            low = mid
        else
            high = mid - 1
        end
    end

    -- Not in the middle of a UTF-8 character
    while low > 0 and text:byte(low + 1) and text:byte(low + 1) >= 0x80 and text:byte(low + 1) <= 0xBF do
        low = low - 1
    end

    return text:sub(1, low) .. ellipsis
end

--- An icon and its label, as one label
---@param icon string?
---@param text string
---@param id string? Stable ImGui id, appended as ###id
---@return string
function style.actionLabel(icon, text, id)
    local label = text

    if icon and icon ~= "" then
        label = icon .. " " .. text
    end

    if type(id) == "string" and id ~= "" then
        return label .. "###" .. id
    end

    return label
end

--- Width of a button with this label
---@param label string
---@return number width Already scaled
function style.buttonWidth(label)
    return ImGui.CalcTextSize(label) + ImGui.GetStyle().FramePadding.x * 2
end

--- Tooltip for a text long enough to need wrapping
---@param hovered boolean
---@param text string
---@param width number? Wrap width, unscaled (default 340)
function style.wrappedTooltipHovered(hovered, text, width)
    if not hovered then return end

    ImGui.BeginTooltip()
    ImGui.PushStyleColor(ImGuiCol.Text, style.regularColor)
    ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + (width or 340) * style.viewSize)
    ImGui.TextUnformatted(text)
    ImGui.PopTextWrapPos()
    ImGui.PopStyleColor()
    ImGui.EndTooltip()
end

---@param text string
---@param width number?
function style.wrappedTooltip(text, width)
    style.wrappedTooltipHovered(ImGui.IsItemHovered(), text, width)
end

--- Full-width entry of a sidebar: its icon and its name, the name gives way when it does not fit
---@param icon string?
---@param text string
---@param selected boolean
---@param opts {width: number?, height: number?, id: string?, tooltip: string?, iconOnly: boolean?}?
---@return boolean clicked
function style.navButton(icon, text, selected, opts)
    opts = opts or {}

    local width = opts.width or ImGui.GetContentRegionAvail()
    if width <= 0 then
        width = ImGui.GetContentRegionAvail()
    end
    width = math.max(width, 1)

    local padding = ImGui.GetStyle().FramePadding.x * 2
    local glyph = (type(icon) == "string" and icon ~= "") and icon or text:sub(1, 1)
    local full = style.actionLabel(icon, text)

    local iconThreshold = math.min(ImGui.GetFrameHeight() * 1.5, ImGui.CalcTextSize(text) + padding)
    local label = glyph
    local iconMode = opts.iconOnly or width < iconThreshold

    if not iconMode then
        label = style.truncateText(full, width - padding)
    end

    if selected then
        pushFilledButton(style.activeColor, style.activeTextColor)
    else
        pushColor(ImGuiCol.Button, style.panelAccent, style.panelAccentIdleAlpha)
        pushColor(ImGuiCol.ButtonHovered, style.panelAccent)
        pushColor(ImGuiCol.ButtonActive, style.panelAccentPressed)
        ImGui.PushStyleColor(ImGuiCol.Text, style.regularColor)
    end

    ImGui.PushStyleVar(ImGuiStyleVar.ButtonTextAlign, 0.5, 0.5)

    local clicked = ImGui.Button(label .. "###" .. (opts.id or text), width, opts.height or 0)

    ImGui.PopStyleVar()
    ImGui.PopStyleColor(4)

    if iconMode or label ~= full then
        style.tooltip(opts.tooltip or text)
    end

    return clicked
end

--- A card: child window on the panel background, padded like a window
---@param id string
---@param width number? 0 fills the width left
---@param height number? 0 fills the height left
---@param opts {bg: number[]?, border: boolean?, flags: number?}?
---@return boolean visible
function style.beginPanel(id, width, height, opts)
    opts = opts or {}

    pushColor(ImGuiCol.ChildBg, opts.bg or style.panelCardBg)

    local visible = ImGui.BeginChild(id, width or 0, height or 0, opts.border == true,
        ImGuiWindowFlags.AlwaysUseWindowPadding + (opts.flags or 0))

    ImGui.PopStyleColor()

    return visible
end

function style.endPanel()
    ImGui.EndChild()
end

--- A block inside a settings page: a rule across the panel with its name under it
---@param text string
---@param opts {tooltip: string?, spacingBefore: number?, spacingAfter: number?}?
function style.panelSectionHeader(text, opts)
    opts = opts or {}

    style.spacing(opts.spacingBefore or 10)
    ImGui.Separator()
    ImGui.Text(text)

    if opts.tooltip then
        style.tooltip(opts.tooltip)
    end

    if opts.spacingAfter and opts.spacingAfter > 0 then
        style.spacing(opts.spacingAfter)
    else
        ImGui.Dummy(0, 0)
    end
end

-- World Builder 2.0: outlined inputs, search row, expand / collapse buttons

-- Border thickness of an outlined input, shared by the resting frame and the active overdraw
local INPUT_BORDER_SIZE = 2.0

--- The outlined-input look: a tinted frame behind a 2px blue border, for whatever input is drawn until popOutlinedInput
function style.pushOutlinedInput()
    local bg = style.panelFrameBg
    local border = style.panelFrameBorder

    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.26, 0.59, 0.98, 1.00)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, bg[1], bg[2], bg[3], bg[4])
    ImGui.PushStyleColor(ImGuiCol.Border, border[1], border[2], border[3], border[4])
    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, INPUT_BORDER_SIZE)
end

--- Widget label without its ImGui id
---@param value any
---@return string
local function stripWidgetId(value)
    local text = tostring(value or "")
    local idStart = text:find("##", 1, true)
    if idStart then
        text = text:sub(1, idStart - 1)
    end
    return (text:gsub("%s+$", ""))
end

--- Pops pushOutlinedInput, and draws the border of the active / hovered field over it. Called right after the widget.
---@param label string? Widget label: a visible label is part of the item, not of the frame, so it is left out of the border
function style.popOutlinedInput(label)
    ImGui.PopStyleVar(1)
    ImGui.PopStyleColor(3)

    local overdraw, alpha
    if ImGui.IsItemActive() then
        overdraw, alpha = style.panelSplitterDrag, 1.0
    elseif ImGui.IsItemHovered() then
        overdraw = style.panelFrameBorderHi
        alpha = overdraw[4]
    else
        return
    end

    local drawList = ImGui.GetWindowDrawList()
    if not drawList then return end

    local minX, minY = ImGui.GetItemRectMin()
    local maxX, maxY = ImGui.GetItemRectMax()
    local visibleLabel = stripWidgetId(label)

    if visibleLabel ~= "" then
        local styleData = ImGui.GetStyle()
        local labelGap = (styleData.ItemInnerSpacing and styleData.ItemInnerSpacing.x) or styleData.ItemSpacing.x
        maxX = math.max(minX, maxX - ImGui.CalcTextSize(visibleLabel) - labelGap)
    end

    ImGui.ImDrawListAddRect(drawList, minX, minY, maxX, maxY,
        ImGui.GetColorU32(overdraw[1], overdraw[2], overdraw[3], alpha), ImGui.GetStyle().FrameRounding, 0, INPUT_BORDER_SIZE)
end

--- ImGui.InputTextWithHint in the outlined styling: the standard text field
---@param ... any id, hint, value, maxLength, flags?
---@return string newValue, boolean changed
function style.inputTextWithHint(...)
    local label = select(1, ...)
    style.pushOutlinedInput()
    local newValue, changed = ImGui.InputTextWithHint(...)
    style.popOutlinedInput(label)

    return newValue, changed
end

--- ImGui.InputText in the outlined styling
---@param ... any id, value, maxLength, flags?
---@return string newValue, boolean changed
function style.inputText(...)
    local label = select(1, ...)
    style.pushOutlinedInput()
    local newValue, changed = ImGui.InputText(...)
    style.popOutlinedInput(label)

    return newValue, changed
end

-- While an input is edited, ImGui keeps its own copy of the text: changing its id is how a value emptied from outside shows
---@type table<string, {count: integer, refocus: boolean}>
local searchInputState = {}

---@param id string
---@param refocus boolean?
function style.clearSearchInput(id, refocus)
    local entry = searchInputState[id]
    searchInputState[id] = { count = ((entry and entry.count) or 0) + 1, refocus = refocus == true }
end

--- inputTextWithHint for search fields, cleared by right-clicking it
---@param id string
---@param hint string
---@param value string
---@param maxLength number
---@param flags number?
---@return string newValue, boolean changed, boolean cleared
function style.searchInputTextWithHint(id, hint, value, maxLength, flags)
    value = tostring(value or "")

    local entry = searchInputState[id]
    if entry and entry.refocus then
        entry.refocus = false
        ImGui.SetKeyboardFocusHere()
    end

    style.pushOutlinedInput()

    local widgetId = id .. "##take" .. (entry and entry.count or 0)
    local newValue, changed
    if flags ~= nil then
        newValue, changed = ImGui.InputTextWithHint(widgetId, hint, value, maxLength, flags)
    else
        newValue, changed = ImGui.InputTextWithHint(widgetId, hint, value, maxLength)
    end

    style.popOutlinedInput(widgetId)

    local cleared = false

    if newValue ~= "" and ImGui.IsItemClicked(ImGuiMouseButton.Right) then
        if ImGui.IsItemActive() then
            style.clearSearchInput(id, true)
        end

        newValue = ""
        changed = false
        cleared = true
    end

    return newValue, changed, cleared
end

style.searchQuerySyntaxTooltip = "Supports custom search query syntax:\n- | (OR), includes any terms including the word after the |\n- ! (NOT), excludes any terms including the word after the !\n- & (AND), terms must include the word after the &\n- E.g. collision|mesh!foliage&exterior_7 to match any terms that include 'collision' or 'mesh', but not 'foliage', and must include 'exterior_7'\nRight-click the field to clear it."

--- The glyph in front of a search input: a magnifier while it is empty, a clear button once there is a query
---@param id string Button id, ## prefixed
---@param hasQuery boolean
---@param searchTooltip string?
---@return boolean cleared
function style.drawSearchClearButton(id, hasQuery, searchTooltip)
    local cleared = false

    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4 * style.viewSize, ImGui.GetStyle().ItemSpacing.y)
    style.pushButtonNoBG(true)
    if ImGui.Button((hasQuery and IconGlyphs.CloseCircleOutline or IconGlyphs.Magnify) .. id) and hasQuery then
        cleared = true
    end
    style.pushButtonNoBG(false)
    style.tooltip(hasQuery and "Clear the search" or (searchTooltip or "Search"))

    ImGui.SameLine()
    ImGui.PopStyleVar()

    return cleared
end

--- The search row: clear / search glyph, outlined input and syntax help glyph. Right-clicking the input clears it.
---@param id string Input id, e.g. ##filter
---@param value string
---@param opts {width: number?, fill: boolean?, maxLength: number?, hint: string?, searchTooltip: string?, help: string|boolean?}?
--- width: unscaled (default 300), fill: takes the rest of the row, help: syntax tooltip (default the query syntax), false for none
---@return string value, boolean changed, boolean cleared
function style.drawSearchFilterRow(id, value, opts)
    opts = opts or {}
    value = tostring(value or "")

    local cleared = style.drawSearchClearButton(id .. "Clear", value ~= "", opts.searchTooltip)
    if cleared then
        value = ""
        style.clearSearchInput(id, true)
    end

    local help = opts.help
    if help == nil then help = style.searchQuerySyntaxTooltip end

    local width = (opts.width or 300) * style.viewSize
    if opts.fill then
        local helpWidth = help and (ImGui.CalcTextSize(IconGlyphs.InformationOutline) + ImGui.GetStyle().ItemSpacing.x) or 0
        width = math.max(ImGui.GetContentRegionAvail() - helpWidth, 1)
    end
    ImGui.SetNextItemWidth(width)

    local changed, inputCleared
    value, changed, inputCleared = style.searchInputTextWithHint(id, opts.hint or "Search...", value, opts.maxLength or 100)
    cleared = cleared or inputCleared

    if help then
        ImGui.SameLine()
        style.mutedText(IconGlyphs.InformationOutline)
        style.tooltip(help)
    end

    return value, changed, cleared
end

--- The expand all / collapse all icon buttons shown above collapsible lists
---@param idScope string
---@param onExpand fun()
---@param onCollapse fun()
---@param opts {disabled: boolean?, expandTooltip: string?, collapseTooltip: string?}?
function style.drawExpandCollapseButtons(idScope, onExpand, onCollapse, opts)
    opts = opts or {}

    ImGui.BeginDisabled(opts.disabled == true)

    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.ExpandAllOutline .. "##" .. idScope .. "ExpandAll") then
        onExpand()
    end
    style.pushButtonNoBG(false)
    style.tooltip(opts.expandTooltip or "Expand all")

    ImGui.SameLine()

    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.CollapseAllOutline .. "##" .. idScope .. "CollapseAll") then
        onCollapse()
    end
    style.pushButtonNoBG(false)
    style.tooltip(opts.collapseTooltip or "Collapse all")

    ImGui.EndDisabled()
end

---@param childId string
---@param width number
---@param height number
---@param icon string
---@param active boolean
---@param dragging boolean
---@return boolean hovered
local function drawSplitterBar(childId, width, height, icon, active, dragging)
    local bg = dragging and style.panelSplitterDrag or active and style.panelSplitterHover or nil
    local iconColor = (active or dragging) and style.panelSplitterIconHi or style.panelSplitterIcon

    if bg then
        pushColor(ImGuiCol.ChildBg, bg)
    else
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0)
    end
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 0, 0)

    if ImGui.BeginChild(childId, width, height, false, ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoScrollbar + ImGuiWindowFlags.NoScrollWithMouse) then
        local availableX, availableY = ImGui.GetWindowSize()
        local textWidth, textHeight = ImGui.CalcTextSize(icon)

        ImGui.SetCursorPosX((availableX - textWidth) / 2)
        ImGui.SetCursorPosY((availableY - textHeight) / 2)
        pushColor(ImGuiCol.Text, iconColor)
        ImGui.Text(icon)
        ImGui.PopStyleColor()
    end
    ImGui.EndChild()

    local hovered = ImGui.IsItemHovered()

    ImGui.PopStyleVar()
    ImGui.PopStyleColor()

    return hovered
end

---@class dividerState
---@field hovered boolean
---@field dragging boolean

local DIVIDER_AXES = {
    horizontal = {
        icon = function() return IconGlyphs.DragHorizontal end,
        cursor = function() return ImGuiMouseCursor.ResizeNS end,
        size = function(thickness, length) return length or 0, thickness end,
        delta = function() return select(2, ImGui.GetMouseDragDelta(0, 0)) end
    },
    vertical = {
        icon = function() return IconGlyphs.DragVertical end,
        cursor = function() return ImGuiMouseCursor.ResizeEW end,
        size = function(thickness, length) return thickness, length or 0 end,
        delta = function() return (ImGui.GetMouseDragDelta(0, 0)) end
    }
}

--- Drag bar between two panels
---@param id string
---@param axis string horizontal or vertical
---@param length number? Already scaled
---@param state dividerState
---@return number delta Unscaled
---@return boolean reset Double-clicked
function style.drawDivider(id, axis, length, state)
    local spec = DIVIDER_AXES[axis] or DIVIDER_AXES.horizontal
    local thickness = 7.5 * style.viewSize
    local reset = state.hovered and ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left)
    local width, height = spec.size(thickness, length)

    state.hovered = drawSplitterBar(id, width, height, spec.icon(), state.hovered, state.dragging)

    if state.hovered and ImGui.IsMouseDragging(0, 0) then
        state.dragging = true
    end
    if state.dragging and not ImGui.IsMouseDragging(0, 0) then
        state.dragging = false
    end

    local delta = 0
    if state.dragging then
        delta = spec.delta() / style.viewSize
        ImGui.ResetMouseDragDelta()
    end

    if state.hovered or state.dragging then
        ImGui.SetMouseCursor(spec.cursor())
    end

    return delta, reset
end

--- A divider that owns a setting: dragging moves it, a double-click resets it, the file is written once the drag ends
---@param id string
---@param axis string
---@param length number? Already scaled
---@param state dividerState
---@param bound {settings: table, key: string, default: number, sign: number?}
function style.dragSetting(id, axis, length, state, bound)
    local wasDragging = state.dragging
    local delta, reset = style.drawDivider(id, axis, length, state)
    local settings = bound.settings

    if reset then
        settings[bound.key] = bound.default
        settings.save()
    elseif delta ~= 0 then
        settings[bound.key] = settings[bound.key] + delta * (bound.sign or 1)
    elseif wasDragging and not state.dragging then
        settings.save()
    end
end

---Draw a red "danger" button.
---@param text string Button label / ID.
---@param ... any Optional size args forwarded to `ImGui.Button`.
---@return boolean clicked
function style.dangerButton(text, ...)
    ImGui.PushStyleColor(ImGuiCol.Button, 0.65, 0.15, 0.15, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.80, 0.20, 0.20, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.55, 0.10, 0.10, 1.0)
    local clicked = ImGui.Button(text, ...)
    ImGui.PopStyleColor(3)
    return clicked
end

--- Green button
---@param text string
---@param ... any
---@return boolean clicked
function style.successButton(text, ...)
    pushFilledButton(style.successColor)
    local clicked = ImGui.Button(text, ...)
    popFilledButton()

    return clicked
end

---@class warnButtonOpts
---@field disabled boolean? Draw as disabled and suppress click handling.
---@field tooltip string? Tooltip shown when enabled.
---@field disabledTooltip string? Tooltip shown when disabled (falls back to `tooltip` when omitted).
---@field tooltipOffsetX number? Optional cursor-relative X offset before drawing tooltip.
---@field tooltipOffsetY number? Optional cursor-relative Y offset before drawing tooltip.

---Draw an orange warning button.
---Supports optional disable state and tooltip handling through a trailing options table.
---Usage: `style.warnButton(text, [w], [h], { disabled = bool, tooltip = "...", disabledTooltip = "..." })`.
---@param text string Button label / ID.
---@param opts warnButtonOpts? Optional flags. See `warnButtonOpts` for details.
---@return boolean clicked
function style.warnButton(text, opts)
    opts = opts or {}
    local disabled = opts.disabled == true or false
    local tooltipText = disabled and opts.disabledTooltip or opts.tooltip
    local tooltipOffsetX = opts.tooltipOffsetX
    local tooltipOffsetY = opts.tooltipOffsetY

    local rgb = style.warnColor % 0x1000000
    local defaultColor = disabled and style.greyedColor or 0xCC000000 + rgb
    local hoveredColor = disabled and style.greyedColor or style.warnColor
    local activeColor = disabled and style.greyedColor or 0x99000000 + rgb
    local clicked = false


    ImGui.PushStyleColor(ImGuiCol.Button, defaultColor)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, hoveredColor)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, activeColor)
    clicked = ImGui.Button(text)
    ImGui.PopStyleColor(3)

    if tooltipText then
        if tooltipOffsetX and tooltipOffsetY and ImGui.IsItemHovered() then
            style.setCursorRelative(tooltipOffsetX, tooltipOffsetY)
        end
        style.tooltip(tooltipText)
    end

    return (not disabled) and clicked
end

--- Button without background that copies value to the clipboard, and says so
---@param id string
---@param value string
---@param opts {what: string?, tooltip: string?}?
---@return boolean copied
function style.copyButton(id, value, opts)
    opts = opts or {}

    local clicked = style.iconButton(IconGlyphs.ContentCopy .. "##" .. id, opts.tooltip or "Copy to the clipboard")
    if not clicked then
        return false
    end

    ImGui.SetClipboardText(value)
    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, "Copied " .. (opts.what or "it") .. " to the clipboard"))

    return true
end

-- Removal Editor

--- Cursor X at which to draw the values of a list of properties, for them to be aligned (as in World Builder)
---@param names table Names of the properties
---@return number
function style.getPropertiesX(names)
    return utils.getTextMaxWidth(names) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
end

--- Muted name of a property, the cursor is then where its value goes
---@param name string
---@param valueX number? Cursor X of the value, from style.getPropertiesX
function style.propertyName(name, valueX)
    style.mutedText(name)
    ImGui.SameLine()
    if valueX then
        ImGui.SetCursorPosX(valueX)
    end
end

--- Read-only property, middle click copies its value
---@param name string
---@param value any Not drawn if nil
---@param valueX number? Cursor X of the value, from style.getPropertiesX
function style.drawProp(name, value, valueX)
    if not name or value == nil then return end

    style.propertyName(name, valueX)
    ImGui.TextWrapped(tostring(value))

    if ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
        ImGui.SetClipboardText(tostring(value))
        ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, "Copied " .. name .. " to the clipboard"))
    end
end

--- Button without background, with a tooltip
---@param label string Icon (IconGlyphs.*), and its id if there are several
---@param tooltip string?
---@return boolean pressed
function style.iconButton(label, tooltip)
    style.pushButtonNoBG(true)
    local pressed = ImGui.Button(label)
    style.pushButtonNoBG(false)

    if tooltip then
        style.tooltip(tooltip)
    end

    return pressed
end

return style
