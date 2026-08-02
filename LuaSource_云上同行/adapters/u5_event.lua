local u5_event = {}

local initialized = false
local cleanup_pending = false
local platform_call_active = false
local logger = nil
local logger_error = nil
local register_trigger = nil
local unregister_trigger = nil
local game_init_event = nil
local game_end_event = nil
local owned_handles = {}

local function valid_logger(candidate)
    return type(candidate) == "table" and type(candidate.error) == "function"
end

local function valid_platform()
    return type(LuaAPI) == "table"
        and type(LuaAPI.global_register_trigger_event) == "function"
        and type(LuaAPI.global_unregister_trigger_event) == "function"
        and type(EVENT) == "table"
        and EVENT.GAME_INIT ~= nil
        and EVENT.GAME_END ~= nil
end

local function report(message)
    if logger_error ~= nil then
        logger_error("U5Event", message)
    end
end

local function register(event_value, callback)
    if not initialized or cleanup_pending or platform_call_active then
        return nil
    end
    if type(callback) ~= "function" then
        report("全局事件回调无效")
        return nil
    end

    -- 平台函数可能同步回调 Lua；句柄归属确定前拒绝重入生命周期操作。
    platform_call_active = true
    local called, handle = pcall(register_trigger, { event_value }, callback)
    if not called or type(handle) ~= "number" then
        platform_call_active = false
        report("全局事件注册失败")
        return nil
    end

    owned_handles[#owned_handles + 1] = handle
    platform_call_active = false
    return handle
end

local function find_owned_handle(handle)
    for index, owned_handle in ipairs(owned_handles) do
        if owned_handle == handle then
            return index
        end
    end
    return nil
end

local function unregister_owned(handle)
    if platform_call_active then
        return false
    end

    local index = find_owned_handle(handle)
    if index == nil then
        return false
    end

    -- 注销完成并更新句柄表前，不允许平台同步回调再次进入清理流程。
    platform_call_active = true
    local called = pcall(unregister_trigger, handle)
    if not called then
        platform_call_active = false
        report("全局事件注销调用失败: " .. tostring(handle))
        return false
    end

    table.remove(owned_handles, index)
    platform_call_active = false
    return true
end

function u5_event.init(candidate_logger)
    if platform_call_active then
        return false
    end
    if cleanup_pending then
        report("平台事件清理未完成，拒绝重新初始化")
        return false
    end
    if initialized then
        local same_lifetime = candidate_logger == logger
        if not same_lifetime then
            report("初始化日志依赖与当前生命周期不一致")
        end
        return same_lifetime
    end
    if not valid_logger(candidate_logger) or not valid_platform() then
        return false
    end

    -- 同一生命周期固定依赖快照，避免外部全局表或日志表被修改后改变适配器行为。
    logger = candidate_logger
    logger_error = candidate_logger.error
    register_trigger = LuaAPI.global_register_trigger_event
    unregister_trigger = LuaAPI.global_unregister_trigger_event
    game_init_event = EVENT.GAME_INIT
    game_end_event = EVENT.GAME_END
    owned_handles = {}
    initialized = true
    return true
end

function u5_event.on_game_init(callback)
    return register(game_init_event, callback)
end

function u5_event.on_game_end(callback)
    return register(game_end_event, callback)
end

function u5_event.unregister(handle)
    if not initialized or cleanup_pending or platform_call_active then
        return false
    end
    if type(handle) ~= "number" then
        report("全局事件注册编号无效")
        return false
    end
    if find_owned_handle(handle) == nil then
        report("全局事件注册编号不属于当前适配器: " .. tostring(handle))
        return false
    end
    return unregister_owned(handle)
end

function u5_event.dispose()
    if platform_call_active then
        return false
    end
    if not initialized and not cleanup_pending then
        return true
    end

    cleanup_pending = true
    local snapshot = {}
    for _, handle in ipairs(owned_handles) do
        snapshot[#snapshot + 1] = handle
    end

    -- 失败句柄保留在 owned_handles 中，后续 dispose 会继续重试。
    for _, handle in ipairs(snapshot) do
        unregister_owned(handle)
    end

    if #owned_handles > 0 then
        return false
    end

    initialized = false
    cleanup_pending = false
    platform_call_active = false
    logger = nil
    logger_error = nil
    register_trigger = nil
    unregister_trigger = nil
    game_init_event = nil
    game_end_event = nil
    owned_handles = {}
    return true
end

return u5_event
