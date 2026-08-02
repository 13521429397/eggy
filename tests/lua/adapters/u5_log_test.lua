package.path = "tests/lua/?.lua;LuaSource_云上同行/?.lua;" .. package.path

local test = require("test_helper")

local function fresh(lua_api)
    LuaAPI = lua_api
    return test.reload("adapters.u5_log")
end

test.test("u5_log validates the platform function before mutation", function()
    local adapter = fresh(nil)
    test.falsy(adapter.init())
    test.falsy(adapter.write("INFO", "Test", "message"))
    test.truthy(adapter.dispose())
end)

test.test("u5_log formats explicitly and supports reinitialization", function()
    local lines = {}
    local adapter = fresh({
        log = function(content)
            lines[#lines + 1] = content
        end,
    })

    test.truthy(adapter.init())
    test.truthy(adapter.init())
    test.truthy(adapter.write("INFO", "Foundation", 42))
    test.equal(lines[1], "[INFO][Foundation] 42")
    test.truthy(adapter.dispose())
    test.falsy(adapter.write("INFO", "Foundation", "after dispose"))
    test.truthy(adapter.init())
end)

test.test("u5_log contains platform logging failures", function()
    local adapter = fresh({
        log = function()
            error("platform log failed")
        end,
    })

    test.truthy(adapter.init())
    test.falsy(adapter.write("ERROR", "Foundation", "failure"))
end)

test.run()
