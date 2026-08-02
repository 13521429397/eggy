package.path = "tests/lua/?.lua;LuaSource_云上同行/?.lua;" .. package.path

local test = require("test_helper")

local function fresh(lua_api)
    LuaAPI = lua_api
    return test.reload("adapters.u5_log")
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

test.test("u5_log accepts the runtime LuaAPI namespace type", function()
    local lines = {}
    local lua_api = {
        log = function(content)
            lines[#lines + 1] = content
        end,
    }

    with_lua_api_type(lua_api, function()
        local adapter = fresh(lua_api)
        test.truthy(adapter.init())
        test.truthy(adapter.write("INFO", "RuntimeType", "accepted"))
        test.sequence(lines, { "[INFO][RuntimeType] accepted" })
        test.truthy(adapter.dispose())
    end)
end)

test.run()
