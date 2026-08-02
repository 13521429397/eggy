package.path = "tests/lua/?.lua;LuaSource_云上同行/?.lua;" .. package.path

local test = require("test_helper")

local function fresh(warnings)
    local registry = test.reload("core.object_registry")
    local logger = {
        warn = function(source, message)
            warnings[#warnings + 1] = source .. ":" .. message
            return true
        end,
    }
    return registry, logger
end

test.test("object_registry validates every key before mutation", function()
    local warnings = {}
    local registry, logger = fresh(warnings)
    local valid_entries = { WINDMILL = 17 }

    test.falsy(registry.init({ [true] = 99 }, logger))
    test.truthy(registry.init(valid_entries, logger))
    test.truthy(registry.init(valid_entries, logger))
    test.falsy(registry.init({ OTHER = 18 }, logger))
    test.falsy(registry.init({ [true] = 99 }, logger))
    test.equal(#warnings, 2)
    test.truthy(registry.has("WINDMILL"))
    test.equal(registry.get("WINDMILL"), 17)
end)

test.test("object_registry owns a shallow snapshot", function()
    local warnings = {}
    local registry, logger = fresh(warnings)
    local entries = { WINDMILL = 17 }

    test.truthy(registry.init(entries, logger))
    entries.WINDMILL = 99
    entries.NEW_OBJECT = 100
    test.equal(registry.get("WINDMILL"), 17)
    test.falsy(registry.has("NEW_OBJECT"))
end)

test.test("object_registry warns once per missing key and lifetime", function()
    local warnings = {}
    local registry, logger = fresh(warnings)

    test.truthy(registry.init({}, logger))
    test.nil_value(registry.get("MISSING"))
    test.nil_value(registry.get("MISSING"))
    test.equal(#warnings, 1)
    test.truthy(registry.dispose())
    test.truthy(registry.init({}, logger))
    test.nil_value(registry.get("MISSING"))
    test.equal(#warnings, 2)
end)

test.test("object_registry logs invalid keys while initialized", function()
    local warnings = {}
    local registry, logger = fresh(warnings)

    test.falsy(registry.has(""))
    test.equal(#warnings, 0)
    test.truthy(registry.init({}, logger))
    test.falsy(registry.has(""))
    test.nil_value(registry.get(nil))
    test.equal(#warnings, 2)
end)

test.test("object_registry is inert outside its initialized lifetime", function()
    local warnings = {}
    local registry, logger = fresh(warnings)

    test.falsy(registry.has("MISSING"))
    test.nil_value(registry.get("MISSING"))
    test.equal(#warnings, 0)
    test.truthy(registry.dispose())
    test.truthy(registry.init({}, logger))
    test.truthy(registry.dispose())
    test.falsy(registry.has("MISSING"))
end)

test.run()
