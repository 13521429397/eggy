local game_flow = {}

local STATE = {
    UNINITIALIZED = "UNINITIALIZED",
    WAITING_GAME_INIT = "WAITING_GAME_INIT",
    READY = "READY",
    DISPOSED = "DISPOSED",
}

local initialized = false
local state = STATE.UNINITIALIZED
local dependency_table = nil
local logger = nil
local event_bus = nil
local events = nil
local logger_info = nil
local event_publish = nil
local ready_event_name = nil
local lifetime_token = nil

local function valid_dependencies(candidate)
    return type(candidate) == "table"
        and type(candidate.logger) == "table"
        and type(candidate.logger.info) == "function"
        and type(candidate.eventBus) == "table"
        and type(candidate.eventBus.publish) == "function"
        and type(candidate.events) == "table"
        and type(candidate.events.CORE_READY) == "string"
        and candidate.events.CORE_READY ~= ""
end

function game_flow.init(candidate)
    if not valid_dependencies(candidate) then
        if initialized then
            logger_info("GameFlow", "初始化依赖无效")
        end
        return false
    end

    if initialized then
        local same_lifetime = candidate == dependency_table
            and candidate.logger == logger
            and candidate.eventBus == event_bus
            and candidate.events == events
            and candidate.logger.info == logger_info
            and candidate.eventBus.publish == event_publish
            and candidate.events.CORE_READY == ready_event_name
        if not same_lifetime then
            logger_info("GameFlow", "初始化依赖与当前生命周期不一致")
        end
        return same_lifetime
    end

    dependency_table = candidate
    logger = candidate.logger
    event_bus = candidate.eventBus
    events = candidate.events
    -- 固化已验证的依赖值，避免外部原地修改依赖表改变当前生命周期行为。
    logger_info = candidate.logger.info
    event_publish = candidate.eventBus.publish
    ready_event_name = candidate.events.CORE_READY
    lifetime_token = {}
    state = STATE.WAITING_GAME_INIT
    initialized = true
    return true
end

function game_flow.start()
    if not initialized or state ~= STATE.WAITING_GAME_INIT then
        return false
    end

    local active_lifetime = lifetime_token
    local current_logger_info = logger_info
    local current_event_publish = event_publish
    local current_ready_event_name = ready_event_name

    -- 同步发布可重入销毁当前生命周期，后续动作必须使用快照并校验生命周期令牌。
    state = STATE.READY
    local published = current_event_publish(current_ready_event_name, nil)
    if initialized and lifetime_token == active_lifetime then
        current_logger_info("GameFlow", "基础模块已就绪")
    end
    return published == true
end

function game_flow.get_state()
    return state
end

function game_flow.dispose()
    initialized = false
    dependency_table = nil
    logger = nil
    event_bus = nil
    events = nil
    logger_info = nil
    event_publish = nil
    ready_event_name = nil
    lifetime_token = nil
    state = STATE.DISPOSED
    return true
end

return game_flow
