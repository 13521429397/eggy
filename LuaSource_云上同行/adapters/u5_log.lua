local u5_log = {}

local initialized = false
local platform_log = nil

local function resolve_platform_log()
    -- LuaAPI 在编辑器运行时是专用命名空间类型，只按成员是否可调用来验证边界。
    local accessed, candidate = pcall(function()
        return LuaAPI.log
    end)
    if not accessed or type(candidate) ~= "function" then
        return nil
    end
    return candidate
end

function u5_log.init()
    if initialized then
        return true
    end

    local candidate = resolve_platform_log()
    if candidate == nil then
        return false
    end

    platform_log = candidate
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
