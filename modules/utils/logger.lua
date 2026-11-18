-- Messages for the user, as in Dialogue Browser's logger: the CET console and the mod's own log (spdlog),
-- plus a toast, since most actions come from a button (RHT's included) while the overlay is open.

local logger = {}

local PREFIX = "[RemovalEditor] "
local TOAST_DURATION = 4000

local LEVELS = {
    info = { label = "", toast = "Info", write = function() return spdlog.info end },
    success = { label = "", toast = "Success", write = function() return spdlog.info end },
    warn = { label = "Warning: ", toast = "Warning", write = function() return spdlog.warning or spdlog.error end },
    error = { label = "Error: ", toast = "Error", write = function() return spdlog.error end }
}

---@param level table
---@param message string
---@param toast boolean?
local function write(level, message, toast)
    message = tostring(message)

    print(PREFIX .. level.label .. message)
    pcall(function() level.write()(level.label .. message) end)

    if toast ~= false then
        pcall(function()
            ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType[level.toast], TOAST_DURATION, message))
        end)
    end
end

--- Each takes the message and whether to show it as a toast too (default true)
for name, level in pairs(LEVELS) do
    ---@param message string
    ---@param toast boolean?
    logger[name] = function(message, toast)
        write(level, message, toast)
    end
end

return logger
