local u5_log = require("adapters.u5_log")
local u5_event = require("adapters.u5_event")
local logger = require("core.logger")
local event_bus = require("core.event_bus")
local object_registry = require("core.object_registry")
local game_flow = require("core.game_flow")
local events = require("config.events")
local objects = require("config.objects")

local app = {}

local STATE = {
    NEW = "NEW",
    INITIALIZING = "INITIALIZING",
    INITIALIZED = "INITIALIZED",
    DISPOSING = "DISPOSING",
    DISPOSED = "DISPOSED",
}

local state = STATE.NEW
local game_init_received = false
local pending_game_init = false
local pending_game_end = false
local active_lifetime_token = nil
local cleanup_in_progress = false
local completed = {
    u5_log = false,
    logger = false,
    event_bus = false,
    object_registry = false,
    game_flow = false,
    u5_event = false,
}
local game_flow_dependencies = {
    logger = logger,
    eventBus = event_bus,
    events = events,
}

local function invalidate_active_lifetime()
    -- 清理前先使本轮令牌失效，避免迟到回调影响下一轮生命周期。
    active_lifetime_token = nil
    pending_game_init = false
    pending_game_end = false
    game_init_received = false
end

local function cleanup_completed()
    if cleanup_in_progress then
        return false
    end

    cleanup_in_progress = true
    invalidate_active_lifetime()

    if completed.u5_event then
        -- 平台事件必须先释放；失败时保留日志和其余依赖供后续重试。
        if not u5_event.dispose() then
            state = STATE.DISPOSING
            logger.error("App", "平台事件清理未完成，将在后续 dispose 重试")
            cleanup_in_progress = false
            return false
        end
        completed.u5_event = false
    end

    if completed.game_flow then
        game_flow.dispose()
        completed.game_flow = false
    end
    if completed.object_registry then
        object_registry.dispose()
        completed.object_registry = false
    end
    if completed.event_bus then
        event_bus.dispose()
        completed.event_bus = false
    end
    if completed.logger then
        logger.dispose()
        completed.logger = false
    end
    if completed.u5_log then
        u5_log.dispose()
        completed.u5_log = false
    end

    state = STATE.DISPOSED
    cleanup_in_progress = false
    return true
end

local function fail_initialization(message)
    invalidate_active_lifetime()
    if completed.logger then
        logger.error("App", message)
    end
    state = STATE.DISPOSING
    cleanup_completed()
    return false
end

local function on_game_init(lifetime_token)
    if lifetime_token ~= active_lifetime_token then
        return
    end
    if state == STATE.INITIALIZING then
        if not pending_game_end then
            pending_game_init = true
        end
        return
    end
    if state ~= STATE.INITIALIZED or game_init_received then
        return
    end

    -- 先记录已处理，内部通知失败也不能重复启动同一局。
    game_init_received = true
    if not game_flow.start() then
        logger.error("App", "基础就绪通知失败")
    end
end

local function on_game_end(lifetime_token)
    if lifetime_token ~= active_lifetime_token then
        return
    end
    if state == STATE.INITIALIZING then
        -- 注册期间 GAME_END 优先，阻止尚未重放的 GAME_INIT 启动游戏。
        pending_game_end = true
        pending_game_init = false
        return
    end
    if state ~= STATE.INITIALIZED then
        return
    end

    app.dispose()
end

function app.init()
    if state == STATE.INITIALIZED then
        return true
    end
    if state == STATE.INITIALIZING or state == STATE.DISPOSING then
        return false
    end

    state = STATE.INITIALIZING
    game_init_received = false
    pending_game_init = false
    pending_game_end = false
    local lifetime_token = {}
    active_lifetime_token = lifetime_token

    if not u5_log.init() then
        invalidate_active_lifetime()
        state = STATE.DISPOSED
        return false
    end
    completed.u5_log = true

    if not logger.init(u5_log) then
        return fail_initialization("日志模块初始化失败")
    end
    completed.logger = true

    if not event_bus.init(logger) then
        return fail_initialization("事件总线初始化失败")
    end
    completed.event_bus = true

    if not object_registry.init(objects, logger) then
        return fail_initialization("对象注册表初始化失败")
    end
    completed.object_registry = true

    if not game_flow.init(game_flow_dependencies) then
        return fail_initialization("游戏流程初始化失败")
    end
    completed.game_flow = true

    if not u5_event.init(logger) then
        return fail_initialization("平台事件适配器初始化失败")
    end
    completed.u5_event = true

    if u5_event.on_game_init(function()
        on_game_init(lifetime_token)
    end) == nil then
        return fail_initialization("GAME_INIT 注册失败")
    end
    if u5_event.on_game_end(function()
        on_game_end(lifetime_token)
    end) == nil then
        return fail_initialization("GAME_END 注册失败")
    end

    state = STATE.INITIALIZED
    if pending_game_end then
        state = STATE.DISPOSING
        cleanup_completed()
        return false
    end
    if pending_game_init then
        pending_game_init = false
        on_game_init(lifetime_token)
    end
    return true
end

function app.dispose()
    if state == STATE.NEW then
        state = STATE.DISPOSED
        game_init_received = false
        return true
    end
    if state == STATE.DISPOSED then
        return true
    end
    if cleanup_in_progress then
        return false
    end

    state = STATE.DISPOSING
    return cleanup_completed()
end

local load_init_succeeded = app.init()
if not load_init_succeeded then
    return app
end

return app
