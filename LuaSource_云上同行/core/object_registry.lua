local object_registry = {}

local initialized = false
local source_entries = nil
local entries = {}
local logger = nil
local warned_missing_keys = {}

local function valid_logger(candidate)
    return type(candidate) == "table" and type(candidate.warn) == "function"
end

local function valid_key(logical_key)
    return type(logical_key) == "string" and logical_key ~= ""
end

local function valid_entries(candidate)
    if type(candidate) ~= "table" then
        return false
    end
    for logical_key, _ in pairs(candidate) do
        if not valid_key(logical_key) then
            return false
        end
    end
    return true
end

function object_registry.init(candidate_entries, candidate_logger)
    if not valid_entries(candidate_entries) or not valid_logger(candidate_logger) then
        if initialized then
            logger.warn("ObjectRegistry", "初始化配置或日志依赖无效")
        end
        return false
    end

    if initialized then
        local same_lifetime = candidate_entries == source_entries and candidate_logger == logger
        if not same_lifetime then
            logger.warn("ObjectRegistry", "初始化依赖与当前生命周期不一致")
        end
        return same_lifetime
    end

    -- 完整校验后再复制，失败输入不会留下半份注册表。
    local snapshot = {}
    for logical_key, value in pairs(candidate_entries) do
        snapshot[logical_key] = value
    end

    source_entries = candidate_entries
    entries = snapshot
    logger = candidate_logger
    warned_missing_keys = {}
    initialized = true
    return true
end

function object_registry.has(logical_key)
    if not initialized then
        return false
    end
    if not valid_key(logical_key) then
        logger.warn("ObjectRegistry", "对象逻辑键无效")
        return false
    end
    return entries[logical_key] ~= nil
end

function object_registry.get(logical_key)
    if not initialized then
        return nil
    end
    if not valid_key(logical_key) then
        logger.warn("ObjectRegistry", "对象逻辑键无效")
        return nil
    end

    local value = entries[logical_key]
    if value == nil and not warned_missing_keys[logical_key] then
        warned_missing_keys[logical_key] = true
        logger.warn("ObjectRegistry", "未注册对象逻辑键: " .. logical_key)
    end
    return value
end

function object_registry.dispose()
    initialized = false
    source_entries = nil
    entries = {}
    logger = nil
    warned_missing_keys = {}
    return true
end

return object_registry
