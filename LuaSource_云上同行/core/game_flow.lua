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
            logger.info("GameFlow", "初始化依赖无效")
        end
        return false
    end

    if initialized then
        local same_lifetime = candidate == dependency_table
            and candidate.logger == logger
            and candidate.eventBus == event_bus
            and candidate.events == events
        if not same_lifetime then
            logger.info("GameFlow", "初始化依赖与当前生命周期不一致")
        end
        return same_lifetime
    end

    dependency_table = candidate
    logger = candidate.logger
    event_bus = candidate.eventBus
    events = candidate.events
    state = STATE.WAITING_GAME_INIT
    initialized = true
    return true
end

function game_flow.start()
    if not initialized or state ~= STATE.WAITING_GAME_INIT then
        return false
    end

    -- 先锁定 READY，订阅者失败也不能导致同一生命周期重复发布。
    state = STATE.READY
    local published = event_bus.publish(events.CORE_READY, nil)
    logger.info("GameFlow", "基础模块已就绪")
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
    state = STATE.DISPOSED
    return true
end

return game_flow
