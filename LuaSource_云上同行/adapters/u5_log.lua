local u5_log = {}

local initialized = false
local platform_log = nil

function u5_log.init()
    if initialized then
        return true
    end

    if type(LuaAPI) ~= "table" or type(LuaAPI.log) ~= "function" then
        return false
    end

    platform_log = LuaAPI.log
    initialized = true
    return true
end

function u5_log.write(level, source, message)
    if not initialized or type(platform_log) ~= "function" then
        return false
    end

    -- 显式转换所有字段，避免沙盒禁止的字符串与数字隐式转换。
    local formatted, line = pcall(function()
        return "[" .. tostring(level) .. "][" .. tostring(source) .. "] " .. tostring(message)
    end)
    if not formatted then
        return false
    end

    local called = pcall(platform_log, line)
    return called
end

function u5_log.dispose()
    initialized = false
    platform_log = nil
    return true
end

return u5_log
