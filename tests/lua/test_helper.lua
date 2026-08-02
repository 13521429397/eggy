local helper = {}
local cases = {}

-- 测试辅助代码只服务桌面 Lua，不会被生产入口加载。
function helper.test(name, callback)
    cases[#cases + 1] = { name = name, callback = callback }
end

function helper.equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

function helper.truthy(value, message)
    helper.equal(value, true, message)
end

function helper.falsy(value, message)
    helper.equal(value, false, message)
end

function helper.nil_value(value, message)
    helper.equal(value, nil, message)
end

function helper.sequence(actual, expected, message)
    helper.equal(#actual, #expected, (message or "sequence length differs"))
    for index = 1, #expected do
        helper.equal(actual[index], expected[index], (message or "sequence differs") .. " at " .. tostring(index))
    end
end

function helper.reload(module_name)
    package.loaded[module_name] = nil
    return require(module_name)
end

function helper.run()
    local failures = 0
    for _, case in ipairs(cases) do
        local ok, failure = pcall(case.callback)
        if ok then
            print("[PASS] " .. case.name)
        else
            failures = failures + 1
            print("[FAIL] " .. case.name .. ": " .. tostring(failure))
        end
    end

    if failures > 0 then
        error(tostring(failures) .. " test(s) failed")
    end
end

return helper
