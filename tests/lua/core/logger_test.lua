package.path = "tests/lua/?.lua;LuaSource_CloudJourney/?.lua;" .. package.path

local test = require("test_helper")

local function fresh()
    return test.reload("core.logger")
end

test.test("logger validates identity and forwards fixed levels", function()
    local calls = {}
    local backend = {
        write = function(level, source, message)
            calls[#calls + 1] = level .. ":" .. source .. ":" .. message
            return true
        end,
    }
    local logger = fresh()

    test.falsy(logger.init({}))
    test.truthy(logger.init(backend))
    test.truthy(logger.init(backend))
    test.falsy(logger.init({ write = backend.write }))
    test.falsy(logger.init({}))
    test.truthy(logger.info("Core", "ready"))
    test.truthy(logger.warn("Core", "slow"))
    test.truthy(logger.error("Core", "failed"))
    test.sequence(calls, {
        "ERROR:Logger:初始化后端与当前生命周期不一致",
        "ERROR:Logger:初始化后端无效",
        "INFO:Core:ready",
        "WARN:Core:slow",
        "ERROR:Core:failed",
    })
end)

test.test("logger contains backend errors and resets on dispose", function()
    local logger = fresh()
    local failing = {
        write = function()
            error("backend failed")
        end,
    }

    test.falsy(logger.info("Core", "before init"))
    test.truthy(logger.init(failing))
    test.falsy(logger.info("Core", "failure"))
    test.truthy(logger.dispose())
    test.truthy(logger.dispose())
    test.falsy(logger.error("Core", "after dispose"))
    test.truthy(logger.init({ write = function() return true end }))
end)

test.run()
