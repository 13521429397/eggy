package.path = "tests/lua/?.lua;LuaSource_CloudJourney/?.lua;" .. package.path

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

local function with_lua_api_type(lua_api, callback)
    local original_type = type
    type = function(value)
        if value == lua_api then
            return "LuaAPI"
        end
        return original_type(value)
    end

    local results = table.pack(pcall(callback))
    type = original_type
    if not results[1] then
        error(results[2], 0)
    end
    return table.unpack(results, 2, results.n)
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

test.test("u5_event retains a handle when registration reenters lifecycle methods", function()
    local errors = {}
    local nested_dispose_results = {}
    local nested_registration_calls = 0
    local nested_registration_result = true
    local unregistered = {}
    local adapter
    adapter = fresh({
        global_register_trigger_event = function()
            nested_dispose_results[#nested_dispose_results + 1] = adapter.dispose()
            nested_registration_calls = nested_registration_calls + 1
            nested_registration_result = adapter.on_game_end(function() end)
            return 40
        end,
        global_unregister_trigger_event = function(handle)
            unregistered[#unregistered + 1] = handle
        end,
    }, {
        GAME_INIT = "GAME_INIT",
        GAME_END = "GAME_END",
    })

    test.truthy(adapter.init(logger(errors)))
    test.equal(adapter.on_game_init(function() end), 40)
    test.sequence(nested_dispose_results, { false })
    test.equal(nested_registration_calls, 1)
    test.nil_value(nested_registration_result)
    test.truthy(adapter.dispose())
    test.sequence(unregistered, { 40 })
end)

test.test("u5_event prevents recursive cleanup and retains a failed handle", function()
    local errors = {}
    local should_fail = true
    local unregister_calls = {}
    local nested_dispose_results = {}
    local adapter
    adapter = fresh({
        global_register_trigger_event = function()
            return 50
        end,
        global_unregister_trigger_event = function(handle)
            unregister_calls[#unregister_calls + 1] = handle
            nested_dispose_results[#nested_dispose_results + 1] = adapter.dispose()
            if should_fail then
                error("unregister failed")
            end
        end,
    }, {
        GAME_INIT = "GAME_INIT",
        GAME_END = "GAME_END",
    })
    local current_logger = logger(errors)

    test.truthy(adapter.init(current_logger))
    test.equal(adapter.on_game_init(function() end), 50)
    test.falsy(adapter.dispose())
    test.sequence(unregister_calls, { 50 })
    test.sequence(nested_dispose_results, { false })
    should_fail = false
    test.truthy(adapter.dispose())
    test.sequence(unregister_calls, { 50, 50 })
    test.sequence(nested_dispose_results, { false, false })
    test.truthy(adapter.init(current_logger))
end)

test.test("u5_event uses captured dependencies for an initialized lifetime", function()
    local errors = {}
    local registrations = {}
    local adapter = fresh({
        global_register_trigger_event = function(event_description)
            registrations[#registrations + 1] = event_description[1]
            return 60
        end,
        global_unregister_trigger_event = function() end,
    }, {
        GAME_INIT = "CAPTURED_GAME_INIT",
        GAME_END = "CAPTURED_GAME_END",
    })
    local current_logger = logger(errors)

    test.truthy(adapter.init(current_logger))
    LuaAPI = nil
    EVENT = nil
    current_logger.error = nil
    test.truthy(adapter.init(current_logger))
    test.falsy(adapter.init(logger(errors)))
    test.equal(adapter.on_game_init(function() end), 60)
    test.nil_value(adapter.on_game_end("bad"))
    test.sequence(registrations, { "CAPTURED_GAME_INIT" })
    test.equal(#errors, 2)
    test.truthy(adapter.dispose())
end)

test.test("u5_event accepts the runtime LuaAPI namespace type", function()
    local errors = {}
    local unregistered = {}
    local lua_api = {
        global_register_trigger_event = function(event_description)
            test.equal(event_description[1], "GAME_INIT")
            return 70
        end,
        global_unregister_trigger_event = function(handle)
            unregistered[#unregistered + 1] = handle
        end,
    }

    with_lua_api_type(lua_api, function()
        local adapter = fresh(lua_api, {
            GAME_INIT = "GAME_INIT",
            GAME_END = "GAME_END",
        })
        test.truthy(adapter.init(logger(errors)))
        test.equal(adapter.on_game_init(function() end), 70)
        test.truthy(adapter.unregister(70))
        test.sequence(unregistered, { 70 })
        test.truthy(adapter.dispose())
    end)
end)

test.run()
