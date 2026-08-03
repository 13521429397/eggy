local logger = {}

local initialized = false
local backend = nil

local function is_valid_backend(candidate)
    return type(candidate) == "table" and type(candidate.write) == "function"
end

local function write(level, source, message)
    if not initialized then
        return false
    end

    -- 后端错误不得中断游戏流程，返回值只接受明确的 true。
    local called, result = pcall(backend.write, level, source, message)
    return called and result == true
end

function logger.init(candidate)
    if not is_valid_backend(candidate) then
        if initialized then
            write("ERROR", "Logger", "初始化后端无效")
        end
        return false
    end

    if initialized then
        local same_lifetime = candidate == backend
        if not same_lifetime then
            write("ERROR", "Logger", "初始化后端与当前生命周期不一致")
        end
        return same_lifetime
    end

    backend = candidate
    initialized = true
    return true
end

function logger.info(source, message)
    return write("INFO", source, message)
end

function logger.warn(source, message)
    return write("WARN", source, message)
end

function logger.error(source, message)
    return write("ERROR", source, message)
end

function logger.dispose()
    initialized = false
    backend = nil
    return true
end

return logger
