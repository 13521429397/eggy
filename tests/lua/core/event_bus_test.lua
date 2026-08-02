package.path = "tests/lua/?.lua;LuaSource_云上同行/?.lua;" .. package.path

local test = require("test_helper")

local function fresh(error_lines)
    local bus = test.reload("core.event_bus")
    local logger = {
        error = function(source, message)
            error_lines[#error_lines + 1] = source .. ":" .. message
            return true
        end,
    }
    return bus, logger
end

test.test("event_bus validates initialization identity", function()
    local errors = {}
    local bus, logger = fresh(errors)
    test.falsy(bus.init({}))
    test.truthy(bus.init(logger))
    test.truthy(bus.init(logger))
    test.falsy(bus.init({ error = logger.error }))
    test.falsy(bus.init({}))
    test.equal(#errors, 2)
end)

test.test("event_bus publishes in registration order from a stable snapshot", function()
    local errors = {}
    local bus, logger = fresh(errors)
    local calls = {}
    local second_id = nil

    test.truthy(bus.init(logger))
    local first_id = bus.subscribe("READY", function()
        calls[#calls + 1] = "first"
        test.truthy(bus.unsubscribe(second_id))
    end)
    second_id = bus.subscribe("READY", function()
        calls[#calls + 1] = "second"
    end)

    test.equal(first_id, 1)
    test.equal(second_id, 2)
    test.truthy(bus.publish("READY", { value = 1 }))
    test.sequence(calls, { "first", "second" })

    calls = {}
    test.falsy(bus.publish("READY", { value = 2 }))
    test.sequence(calls, { "first" })
end)

test.test("event_bus continues after handler failure and aggregates failure", function()
    local errors = {}
    local bus, logger = fresh(errors)
    local later_handler_ran = false

    test.truthy(bus.init(logger))
    bus.subscribe("READY", function()
        error("handler failed")
    end)
    bus.subscribe("READY", function()
        later_handler_ran = true
    end)

    test.falsy(bus.publish("READY", nil))
    test.truthy(later_handler_ran)
    test.equal(#errors, 1)
    test.truthy(bus.publish("EMPTY", nil))
end)

test.test("event_bus logs invalid operational arguments while initialized", function()
    local errors = {}
    local bus, logger = fresh(errors)

    test.falsy(bus.unsubscribe("bad"))
    test.equal(#errors, 0)
    test.truthy(bus.init(logger))
    test.nil_value(bus.subscribe("", function() end))
    test.nil_value(bus.subscribe("READY", "bad"))
    test.falsy(bus.unsubscribe("bad"))
    test.falsy(bus.unsubscribe(999))
    test.falsy(bus.publish("", nil))
    test.equal(#errors, 5)
end)

test.test("event_bus resets its lifetime on dispose", function()
    local errors = {}
    local bus, logger = fresh(errors)

    test.nil_value(bus.subscribe("READY", function() end))
    test.falsy(bus.publish("READY", nil))
    test.truthy(bus.dispose())
    test.truthy(bus.init(logger))
    test.equal(bus.subscribe("READY", function() end), 1)
    test.truthy(bus.dispose())
    test.nil_value(bus.subscribe("READY", function() end))
end)

test.run()
