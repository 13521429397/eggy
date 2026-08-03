package.path = "tests/lua/?.lua;LuaSource_CloudJourney/?.lua;" .. package.path

local test = require("test_helper")

local function dependencies(publish_result, log_result)
    local evidence = { publishes = 0, logs = 0 }
    local deps = {
        logger = {
            info = function()
                evidence.logs = evidence.logs + 1
                return log_result ~= false
            end,
        },
        eventBus = {
            publish = function(event_name, payload)
                evidence.publishes = evidence.publishes + 1
                evidence.event_name = event_name
                evidence.payload = payload
                return publish_result ~= false
            end,
        },
        events = { CORE_READY = "CLOUD_JOURNEY.CORE_READY" },
    }
    return deps, evidence
end

test.test("game_flow validates the complete dependency contract", function()
    local flow = test.reload("core.game_flow")
    local deps, evidence = dependencies(true, true)

    test.equal(flow.get_state(), "UNINITIALIZED")
    test.falsy(flow.start())
    test.falsy(flow.init({}))
    test.truthy(flow.init(deps))
    test.truthy(flow.init(deps))
    test.falsy(flow.init(dependencies(true, true)))
    test.falsy(flow.init({}))
    test.equal(evidence.logs, 2)
    test.equal(flow.get_state(), "WAITING_GAME_INIT")
end)

test.test("game_flow publishes readiness once", function()
    local flow = test.reload("core.game_flow")
    local deps, evidence = dependencies(true, true)

    test.truthy(flow.init(deps))
    test.truthy(flow.start())
    test.equal(flow.get_state(), "READY")
    test.equal(evidence.event_name, "CLOUD_JOURNEY.CORE_READY")
    test.nil_value(evidence.payload)
    test.equal(evidence.publishes, 1)
    test.equal(evidence.logs, 1)
    test.falsy(flow.start())
    test.equal(evidence.publishes, 1)
end)

test.test("game_flow remains ready when notification fails", function()
    local flow = test.reload("core.game_flow")
    local deps, evidence = dependencies(false, true)

    test.truthy(flow.init(deps))
    test.falsy(flow.start())
    test.equal(flow.get_state(), "READY")
    test.equal(evidence.publishes, 1)
end)

test.test("game_flow return value follows publish rather than logging", function()
    local flow = test.reload("core.game_flow")
    local deps, evidence = dependencies(true, false)

    test.truthy(flow.init(deps))
    test.truthy(flow.start())
    test.equal(evidence.logs, 1)
end)

test.test("game_flow tolerates reentrant dispose during readiness publication", function()
    local flow = test.reload("core.game_flow")
    local evidence = { publishes = 0, logs = 0 }
    local deps = {
        logger = {
            info = function()
                evidence.logs = evidence.logs + 1
                return true
            end,
        },
        eventBus = {
            publish = function()
                evidence.publishes = evidence.publishes + 1
                flow.dispose()
                return true
            end,
        },
        events = { CORE_READY = "CLOUD_JOURNEY.CORE_READY" },
    }

    test.truthy(flow.init(deps))
    test.truthy(flow.start())
    test.equal(flow.get_state(), "DISPOSED")
    test.equal(evidence.publishes, 1)
    test.equal(evidence.logs, 0)
end)

test.test("game_flow isolates its lifetime from mutable dependency fields", function()
    local flow = test.reload("core.game_flow")
    local deps, evidence = dependencies(true, true)

    test.truthy(flow.init(deps))
    deps.logger.info = function()
        error("mutated logger must not be used")
    end
    deps.eventBus.publish = function()
        error("mutated event bus must not be used")
    end
    deps.events.CORE_READY = "CLOUD_JOURNEY.MUTATED"

    test.falsy(flow.init(deps))
    test.truthy(flow.start())
    test.equal(evidence.event_name, "CLOUD_JOURNEY.CORE_READY")
    test.equal(evidence.publishes, 1)
    test.equal(evidence.logs, 2)
end)

test.test("game_flow supports completed dispose and reinitialize", function()
    local flow = test.reload("core.game_flow")
    local deps = dependencies(true, true)

    test.truthy(flow.dispose())
    test.equal(flow.get_state(), "DISPOSED")
    test.truthy(flow.init(deps))
    test.equal(flow.get_state(), "WAITING_GAME_INIT")
    test.truthy(flow.dispose())
    test.falsy(flow.start())
end)

test.run()
