local style = {
    initialized = false
}

-- Credits to psiberx for most of the styling choices and techniques
function style.initStyles()
    if style.initialized then return end

    style.initialized = true

    style.scale = ImGui.GetFontSize() / 13
    style.width = 400 * style.scale
    style.paddingX = 8 * style.scale
    style.paddingY = 8 * style.scale
    style.buttonY = 21 * style.scale
end

-- Also "inspired" by psiberx's UI
function style.drawProp(name, value)
    if not name or not value then return end

    ImGui.PushStyleColor(ImGuiCol.Text, 0xff9f9f9f)
    ImGui.TextWrapped(name .. ": ")
    ImGui.PopStyleColor()

    ImGui.SameLine()

    ImGui.TextWrapped(tostring(value))

    if ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
        ImGui.SetClipboardText(value)
    end
end

function style.pushGreyedOut(state)
    if not state then return end

    ImGui.PushStyleColor(ImGuiCol.Button, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0xff777777)
end

function style.popGreyedOut(state)
    if not state then return end

    ImGui.PopStyleColor(3)
end

function style.pushFrameStyle()
    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
end

function style.popFrameStyle()
    ImGui.PopStyleColor()
    ImGui.PopStyleVar(2)
end

function style.spacedSeparator()
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

return style