local event_bus = {}

local initialized = false
local logger = nil
local subscriptions = {}
local next_subscription_id = 1

local function valid_logger(candidate)
    return type(candidate) == "table" and type(candidate.error) == "function"
end

local function valid_event_name(event_name)
    return type(event_name) == "string" and event_name ~= ""
end

local function report(message)
    if initialized then
        logger.error("EventBus", message)
    end
end

function event_bus.init(candidate_logger)
    if not valid_logger(candidate_logger) then
        if initialized then
            report("初始化日志依赖无效")
        end
        return false
    end

    if initialized then
        local same_lifetime = candidate_logger == logger
        if not same_lifetime then
            report("初始化日志依赖与当前生命周期不一致")
        end
        return same_lifetime
    end

    logger = candidate_logger
    subscriptions = {}
    next_subscription_id = 1
    initialized = true
    return true
end


function event_bus.subscribe(event_name, handler)
    if not initialized then
        return nil
    end
    if not valid_event_name(event_name) or type(handler) ~= "function" then
        report("订阅参数无效")
        return nil
    end

    local subscription_id = next_subscription_id
    next_subscription_id = next_subscription_id + 1
    subscriptions[#subscriptions + 1] = {
        id = subscription_id,
        event_name = event_name,
        handler = handler,
        active = true,
    }
    return subscription_id
end

function event_bus.unsubscribe(subscription_id)
    if not initialized then
        return false
    end
    if type(subscription_id) ~= "number" then
        report("订阅编号无效")
        return false
    end

    for _, subscription in ipairs(subscriptions) do
        if subscription.id == subscription_id and subscription.active then
            subscription.active = false
            return true
        end
    end
    report("订阅编号不存在: " .. tostring(subscription_id))
    return false
end


function event_bus.publish(event_name, payload)
    if not initialized then
        return false
    end
    if not valid_event_name(event_name) then
        report("发布事件名无效")
        return false
    end

    -- 快照保存函数本身，使派发期间的取消订阅只影响下一次发布。
    local snapshot = {}
    for _, subscription in ipairs(subscriptions) do
        if subscription.active and subscription.event_name == event_name then
            snapshot[#snapshot + 1] = {
                id = subscription.id,
                handler = subscription.handler,
            }
        end
    end

    local all_succeeded = true
    for _, subscription in ipairs(snapshot) do
        local called = pcall(subscription.handler, payload)
        if not called then
            all_succeeded = false
            report("事件处理器执行失败: " .. event_name .. " #" .. tostring(subscription.id))
        end
    end
    return all_succeeded
end

function event_bus.dispose()
    initialized = false
    logger = nil
    subscriptions = {}
    next_subscription_id = 1
    return true
end

return event_bus
