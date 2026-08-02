package.path = "tests/lua/?.lua;LuaSource_云上同行/?.lua;" .. package.path

local test = require("test_helper")

local function logger(errors)
    return {
        error = function(source, message)
            errors[#errors + 1] = source .. ":" .. message
            return true
        end,
    }
end

local function fresh(lua_api, event_values)
    LuaAPI = lua_api
    EVENT = event_values
    return test.reload("adapters.u5_event")
end

test.test("u5_event validates dependency and platform surfaces", function()
    local errors = {}
    local adapter = fresh(nil, nil)
    test.falsy(adapter.init(logger(errors)))
    test.nil_value(adapter.on_game_init(function() end))
    test.truthy(adapter.dispose())
end)

test.test("u5_event registers documented event-description lists", function()
    local errors = {}
    local registrations = {}
    local next_handle = 10
    local adapter = fresh({
        global_register_trigger_event = function(event_description, callback)
            registrations[#registrations + 1] = { event_description[1], callback }
            local handle = next_handle
            next_handle = next_handle + 1
            return handle
        end,
        global_unregister_trigger_event = function() end,
    }, {
        GAME_INIT = "GAME_INIT",
        GAME_END = "GAME_END",
    })
    local current_logger = logger(errors)

    test.truthy(adapter.init(current_logger))
    test.truthy(adapter.init(current_logger))
    test.falsy(adapter.init(logger(errors)))
    test.falsy(adapter.init({}))
    test.equal(adapter.on_game_init(function() end), 10)
    test.equal(adapter.on_game_end(function() end), 11)
    test.nil_value(adapter.on_game_init("bad"))
    test.equal(#errors, 3)
    test.equal(registrations[1][1], "GAME_INIT")
    test.equal(registrations[2][1], "GAME_END")
end)

test.test("u5_event unregisters an owned handle exactly once", function()
    local errors = {}
    local unregistered = {}
    local adapter = fresh({
        global_register_trigger_event = function()
            return 20
        end,
        global_unregister_trigger_event = function(handle)
            unregistered[#unregistered + 1] = handle
        end,
    }, {
        GAME_INIT = "GAME_INIT",
        GAME_END = "GAME_END",
    })

    test.truthy(adapter.init(logger(errors)))
    test.equal(adapter.on_game_init(function() end), 20)
    test.truthy(adapter.unregister(20))
    test.falsy(adapter.unregister("bad"))
    test.falsy(adapter.unregister(20))
    test.equal(#errors, 2)
    test.sequence(unregistered, { 20 })
    test.truthy(adapter.dispose())
end)

test.test("u5_event stores no failed registration", function()
    local errors = {}
    local adapter = fresh({
        global_register_trigger_event = function()
            error("registration failed")
        end,
        global_unregister_trigger_event = function()
            error("must not unregister")
        end,
    }, {
        GAME_INIT = "GAME_INIT",
        GAME_END = "GAME_END",
    })

    test.truthy(adapter.init(logger(errors)))
    test.nil_value(adapter.on_game_init(function() end))
    test.truthy(adapter.dispose())
end)

test.test("u5_event retains failed cleanup for dispose retry", function()
    local errors = {}
    local should_fail = true
    local next_handle = 30
    local unregister_calls = {}
    local adapter = fresh({
        global_register_trigger_event = function()
            local handle = next_handle
            next_handle = next_handle + 1
            return handle
        end,
        global_unregister_trigger_event = function(handle)
            unregister_calls[#unregister_calls + 1] = handle
            if should_fail and handle == 30 then
                error("unregister failed")
            end
        end,
    }, {
        GAME_INIT = "GAME_INIT",
        GAME_END = "GAME_END",
    })
    local current_logger = logger(errors)

    test.truthy(adapter.init(current_logger))
    test.equal(adapter.on_game_init(function() end), 30)
    test.equal(adapter.on_game_end(function() end), 31)
    test.falsy(adapter.unregister(999))
    test.falsy(adapter.dispose())
    test.sequence(unregister_calls, { 30, 31 })
    test.nil_value(adapter.on_game_end(function() end))
    test.falsy(adapter.init(current_logger))
    should_fail = false
    test.truthy(adapter.dispose())
    test.sequence(unregister_calls, { 30, 31, 30 })
    test.truthy(adapter.init(current_logger))
end)

test.run()
