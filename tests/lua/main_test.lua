package.path = "tests/lua/?.lua;LuaSource_云上同行/?.lua;" .. package.path

local test = require("test_helper")

local module_names = {
    "adapters.u5_log",
    "adapters.u5_event",
    "core.logger",
    "core.event_bus",
    "core.object_registry",
    "core.game_flow",
    "config.events",
    "config.objects",
}

local function install_module(name, value)
    package.loaded[name] = nil
    package.preload[name] = function()
        return value
    end
end

local function load_app(options)
    options = options or {}
    local evidence = {
        calls = {},
        callbacks = {},
        callback_history = {
            game_init = {},
            game_end = {},
        },
        start_calls = 0,
        error_calls = 0,
        event_dispose_calls = 0,
    }

    local function called(name)
        evidence.calls[#evidence.calls + 1] = name
    end

    local u5_log = {
        init = function()
            called("u5_log.init")
            if options.u5_log_init_hook then options.u5_log_init_hook() end
            return options.u5_log_init ~= false
        end,
        dispose = function() called("u5_log.dispose") return true end,
    }
    local logger = {
        init = function() called("logger.init") return options.logger_init ~= false end,
        error = function() evidence.error_calls = evidence.error_calls + 1 return true end,
        dispose = function() called("logger.dispose") return true end,
    }
    local event_bus = {
        init = function() called("event_bus.init") return options.event_bus_init ~= false end,
        dispose = function() called("event_bus.dispose") return true end,
    }
    local object_registry = {
        init = function() called("object_registry.init") return options.object_registry_init ~= false end,
        dispose = function() called("object_registry.dispose") return true end,
    }
    local game_flow = {
        init = function() called("game_flow.init") return options.game_flow_init ~= false end,
        start = function()
            called("game_flow.start")
            evidence.start_calls = evidence.start_calls + 1
            return options.start_result ~= false
        end,
        dispose = function() called("game_flow.dispose") return true end,
    }
    local u5_event = {
        init = function() called("u5_event.init") return options.u5_event_init ~= false end,
        on_game_init = function(callback)
            called("u5_event.on_game_init")
            evidence.callbacks.game_init = callback
            evidence.callback_history.game_init[#evidence.callback_history.game_init + 1] = callback
            if options.sync_game_init then callback() end
            if options.game_init_registration == false then return nil end
            return 101
        end,
        on_game_end = function(callback)
            called("u5_event.on_game_end")
            evidence.callbacks.game_end = callback
            evidence.callback_history.game_end[#evidence.callback_history.game_end + 1] = callback
            if options.sync_game_end then callback() end
            if options.game_end_registration == false then return nil end
            return 102
        end,
        dispose = function()
            called("u5_event.dispose")
            evidence.event_dispose_calls = evidence.event_dispose_calls + 1
            if options.event_dispose_hook then options.event_dispose_hook() end
            local results = options.event_dispose_results or { true }
            local result = results[evidence.event_dispose_calls]
            if result == nil then return true end
            return result
        end,
    }

    install_module("adapters.u5_log", u5_log)
    install_module("adapters.u5_event", u5_event)
    install_module("core.logger", logger)
    install_module("core.event_bus", event_bus)
    install_module("core.object_registry", object_registry)
    install_module("core.game_flow", game_flow)
    install_module("config.events", { CORE_READY = "CLOUD_JOURNEY.CORE_READY" })
    install_module("config.objects", {})
    package.loaded.main = nil

    return require("main"), evidence
end

test.test("main initializes once in dependency order and starts once", function()
    local app, evidence = load_app({ start_result = false })
    test.sequence(evidence.calls, {
        "u5_log.init",
        "logger.init",
        "event_bus.init",
        "object_registry.init",
        "game_flow.init",
        "u5_event.init",
        "u5_event.on_game_init",
        "u5_event.on_game_end",
    })

    test.truthy(app.init())
    evidence.callbacks.game_init()
    evidence.callbacks.game_init()
    test.equal(evidence.start_calls, 1)
    test.equal(evidence.error_calls, 1)
end)

test.test("main rolls back only completed dependencies in reverse order", function()
    local app, evidence = load_app({ object_registry_init = false })
    test.sequence(evidence.calls, {
        "u5_log.init",
        "logger.init",
        "event_bus.init",
        "object_registry.init",
        "event_bus.dispose",
        "logger.dispose",
        "u5_log.dispose",
    })
    test.falsy(app.init())
end)

test.test("main retains dependencies while event cleanup is pending", function()
    local app, evidence = load_app({
        game_end_registration = false,
        event_dispose_results = { false, true },
    })

    test.equal(evidence.calls[#evidence.calls], "u5_event.dispose")
    local call_count = #evidence.calls
    test.falsy(app.init())
    test.equal(#evidence.calls, call_count)
    test.truthy(app.dispose())
    test.sequence({
        evidence.calls[#evidence.calls - 5],
        evidence.calls[#evidence.calls - 4],
        evidence.calls[#evidence.calls - 3],
        evidence.calls[#evidence.calls - 2],
        evidence.calls[#evidence.calls - 1],
        evidence.calls[#evidence.calls],
    }, {
        "u5_event.dispose",
        "game_flow.dispose",
        "object_registry.dispose",
        "event_bus.dispose",
        "logger.dispose",
        "u5_log.dispose",
    })
end)

test.test("main disposes on GAME_END and can initialize a new lifetime", function()
    local app, evidence = load_app()
    evidence.callbacks.game_end()
    test.sequence({
        evidence.calls[#evidence.calls - 5],
        evidence.calls[#evidence.calls - 4],
        evidence.calls[#evidence.calls - 3],
        evidence.calls[#evidence.calls - 2],
        evidence.calls[#evidence.calls - 1],
        evidence.calls[#evidence.calls],
    }, {
        "u5_event.dispose",
        "game_flow.dispose",
        "object_registry.dispose",
        "event_bus.dispose",
        "logger.dispose",
        "u5_log.dispose",
    })
    test.truthy(app.dispose())
    test.truthy(app.init())
    test.equal(evidence.calls[#evidence.calls], "u5_event.on_game_end")
end)

test.test("main replays synchronous GAME_INIT after both registrations are owned", function()
    local options = {}
    local app, evidence = load_app(options)
    test.truthy(app.dispose())
    options.sync_game_init = true

    test.truthy(app.init())
    test.equal(evidence.start_calls, 1)
    test.sequence({
        evidence.calls[#evidence.calls - 2],
        evidence.calls[#evidence.calls - 1],
        evidence.calls[#evidence.calls],
    }, {
        "u5_event.on_game_init",
        "u5_event.on_game_end",
        "game_flow.start",
    })
    evidence.callbacks.game_init()
    test.equal(evidence.start_calls, 1)
end)

test.test("main lets synchronous GAME_END cancel pending GAME_INIT", function()
    local options = {}
    local app, evidence = load_app(options)
    test.truthy(app.dispose())
    options.sync_game_init = true
    options.sync_game_end = true

    test.falsy(app.init())
    test.equal(evidence.start_calls, 0)
    test.sequence({
        evidence.calls[#evidence.calls - 5],
        evidence.calls[#evidence.calls - 4],
        evidence.calls[#evidence.calls - 3],
        evidence.calls[#evidence.calls - 2],
        evidence.calls[#evidence.calls - 1],
        evidence.calls[#evidence.calls],
    }, {
        "u5_event.dispose",
        "game_flow.dispose",
        "object_registry.dispose",
        "event_bus.dispose",
        "logger.dispose",
        "u5_log.dispose",
    })

    options.sync_game_init = false
    options.sync_game_end = false
    test.truthy(app.init())
    test.equal(evidence.calls[#evidence.calls], "u5_event.on_game_end")
end)

test.test("main ignores callbacks retained from an earlier lifetime", function()
    local app, evidence = load_app()
    local old_game_init = evidence.callback_history.game_init[1]
    local old_game_end = evidence.callback_history.game_end[1]

    test.truthy(app.dispose())
    test.truthy(app.init())
    local new_game_init = evidence.callback_history.game_init[2]
    local new_game_end = evidence.callback_history.game_end[2]
    local call_count = #evidence.calls
    local event_dispose_calls = evidence.event_dispose_calls

    old_game_init()
    old_game_end()
    test.equal(#evidence.calls, call_count)
    test.equal(evidence.start_calls, 0)
    test.equal(evidence.event_dispose_calls, event_dispose_calls)

    new_game_init()
    test.equal(evidence.start_calls, 1)
    new_game_end()
    test.equal(evidence.event_dispose_calls, event_dispose_calls + 1)
    test.sequence({
        evidence.calls[#evidence.calls - 5],
        evidence.calls[#evidence.calls - 4],
        evidence.calls[#evidence.calls - 3],
        evidence.calls[#evidence.calls - 2],
        evidence.calls[#evidence.calls - 1],
        evidence.calls[#evidence.calls],
    }, {
        "u5_event.dispose",
        "game_flow.dispose",
        "object_registry.dispose",
        "event_bus.dispose",
        "logger.dispose",
        "u5_log.dispose",
    })
end)

test.test("main rejects reentrant initialization and cleanup calls", function()
    local options = {}
    local app = load_app(options)
    local initializing_init_result = nil
    local disposing_init_result = nil
    local reentrant_dispose_result = nil

    test.truthy(app.dispose())
    options.u5_log_init_hook = function()
        initializing_init_result = app.init()
    end
    test.truthy(app.init())
    test.falsy(initializing_init_result)
    options.u5_log_init_hook = nil

    options.event_dispose_hook = function()
        disposing_init_result = app.init()
        reentrant_dispose_result = app.dispose()
    end
    test.truthy(app.dispose())
    test.falsy(disposing_init_result)
    test.falsy(reentrant_dispose_result)
end)

for _, module_name in ipairs(module_names) do
    package.preload[module_name] = nil
    package.loaded[module_name] = nil
end

test.run()
