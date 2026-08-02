# Foundation Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the smallest reusable, lifecycle-safe Lua foundation for Cloud Journey using only the five platform surfaces documented by the current NetEase Workshop Manual and reconciled with the current Eggitor export.

**Architecture:** Keep `LuaSource_云上同行/main.lua` limited to assembly, place all direct U5 calls in two adapters, and keep logging, event dispatch, object lookup, and foundation state platform-independent. Each singleton module validates inputs before mutation, supports completed dispose/reinitialize cycles, and exposes explicit failure results; static PowerShell verification runs without external dependencies while Lua behavior and editor integration remain separately reported evidence.

**Tech Stack:** Eggy Party PC Editor, Eggitor, the Eggy Lua 5.4 sandbox, Lua modules under the physical `LuaSource_云上同行/` project root mapped to the logical `script/` namespace, Windows PowerShell 5.1, Git, and GitHub `origin/main`.

---

## Approved Basis and Hard Limits

Implement against the approved design in `docs/superpowers/specs/2026-08-02-foundation-module-design.md` and these official references:

- [Lua sandbox and module rules](https://u5.gsf.netease.com/eggy_manual_3068736/pc_md/lua/lua_environment.html)
- [Eggitor generation, synchronization, exports, and console](https://u5.gsf.netease.com/eggy_manual_3068736/pc_md/lua/lua_eggitor.html)
- [Lua quick start](https://u5.gsf.netease.com/eggy_manual_3068736/pc_md/lua/lua_quickstart.html)
- [API guide](https://u5.gsf.netease.com/eggy_manual_3068736/pc_md/lua/lua_api_structure.html)
- [Current API manual](https://u5.gsf.netease.com/eggy_manual_3068736/pc_md/lua/EggyAPI.html)

The manual establishes that these capabilities are supported: `LuaAPI.log`, `LuaAPI.global_register_trigger_event`, `LuaAPI.global_unregister_trigger_event`, `EVENT.GAME_INIT`, and `EVENT.GAME_END`. The current Eggitor 0.3.9 export confirms `global_register_trigger_event(any[], callback) -> integer`, `global_unregister_trigger_event(integer)`, `log(string, optional integer level)`, `GAME_INIT`, and `GAME_END`. The foundation uses the supported one-argument `log(string)` form. The physical `LuaSource_云上同行/` root is the connected counterpart of the platform's logical `script/` namespace; runtime `require` strings remain root-relative and never contain either root name.

Do not add pair sessions, players, checkpoints, respawn, hints, UI, lighting, camera, archives, chapter logic, timers, Tick handlers, real editor IDs, or any platform surface beyond those five.

## File Map

Create these production files:

| Path | Responsibility |
| --- | --- |
| `LuaSource_云上同行/main.lua` | Assemble modules, own application lifecycle, register game start/end callbacks |
| `LuaSource_云上同行/adapters/u5_log.lua` | Own the only direct `LuaAPI.log` call |
| `LuaSource_云上同行/adapters/u5_event.lua` | Own the only `EVENT` and global trigger registration calls |
| `LuaSource_云上同行/core/logger.lua` | Normalize protected logging independent of U5 |
| `LuaSource_云上同行/core/event_bus.lua` | Dispatch synchronous internal events from a stable snapshot |
| `LuaSource_云上同行/core/object_registry.lua` | Resolve verified logical keys without querying the editor |
| `LuaSource_云上同行/core/game_flow.lua` | Hold the foundation lifecycle state only |
| `LuaSource_云上同行/config/events.lua` | Define the sole internal event name |
| `LuaSource_云上同行/config/objects.lua` | Return an empty mapping until real Eggitor data exists |

Create these verification files:

| Path | Responsibility |
| --- | --- |
| `tests/lua/test_helper.lua` | Dependency-free desktop Lua assertion helper; never loaded by production |
| `tests/lua/adapters/u5_log_test.lua` | Logging-adapter lifecycle and protected-call contract |
| `tests/lua/adapters/u5_event_test.lua` | Platform-event ownership and cleanup-pending contract |
| `tests/lua/core/logger_test.lua` | Logger validation, levels, and failure isolation |
| `tests/lua/core/event_bus_test.lua` | Ordering, snapshot, handler-failure, and lifecycle contract |
| `tests/lua/core/object_registry_test.lua` | Full validation, snapshot ownership, and warning suppression |
| `tests/lua/core/game_flow_test.lua` | State transitions and one-shot readiness notification |
| `tests/lua/main_test.lua` | Assembly order, rollback, cleanup retry, and reinitialization |
| `tests/static/verify-foundation.tests.ps1` | Positive and mutation-based negative tests for the verifier |
| `tools/verify-foundation.ps1` | Repository-local source-contract and export-evidence verifier |

The `tests/lua/` suite may use desktop-only `package` facilities because it is never synchronized as production code. A desktop Lua pass is useful evidence but is never called Eggy sandbox or editor verification.

## Resolved Design Details

- `logger.init()` requires a table with callable `write`; `event_bus.init()` requires a table with callable `error`; `object_registry.init()` requires callable `warn`; `game_flow.init()` requires callable `logger.info`, callable `eventBus.publish`, and a non-empty `events.CORE_READY` string; `u5_event.init()` requires callable `logger.error` plus the export-confirmed platform surfaces.
- `game_flow.init()` compares the outer dependency-table instance on repeated initialization. It still revalidates the table before returning `true`.
- `object_registry` stores a defensive shallow copy while retaining the source table solely for repeated-init identity checks.
- A publish snapshot captures handler functions. A handler removed by an earlier handler still executes during the current publish, but not the next one.
- `game_flow.start()` returns the publish result. A readiness-log failure does not undo `READY` and does not change a successful publish into failure.
- The file-load result from `app.init()` remains private; the public surface stays exactly `app.init()` and `app.dispose()`.
- Static scans ignore Lua comments and quoted-string contents for identifier-boundary checks. Literal `require` targets and project event literals are checked separately.
- Calls outside an initialized lifetime remain inert. Once a module owns a valid logging dependency, invalid or lifetime-mismatched `init()` inputs, invalid event-bus arguments, object-registry keys, event callbacks, and unregister handles emit concise diagnostics before returning failure.

## Common Git Procedure

Every modifying task supplies its complete `git add` and non-interactive Lore commit command. Before running that task-specific block, start with `git status --short --branch`; never use `git add .`, `git add -A`, or `git commit -a`. Every block inspects the cached name-status, full cached diff, and whitespace before committing, pushes immediately to `origin/main`, and verifies that the remote SHA equals local `HEAD`. Each push checks its exit code. On rejection, fetch `origin`, print `HEAD...origin/main` with left/right markers, preserve the local commit, and stop for safe reconciliation; never retry with force.

### Task 0: Record the completed Eggitor and API-export prerequisite gate

**Files:**
- Inspect: current Eggitor-generated Lua project rooted at `D:\eggy\LuaSource_云上同行`
- Inspect: current `EggyAPI.lua` exported to `%LOCALAPPDATA%\EggyCloudJourney\evidence\EggyAPI.lua`
- Inspect: `LuaSource_云上同行/eggy.json`
- Inspect: `LuaSource_云上同行/main.lua`
- Do not stage generated or exported evidence in this task

- [x] **Step 1: Confirm the Git baseline is clean and synchronized**

Run:

```powershell
Set-Location D:\eggy
git status --short --branch
git fetch origin
git rev-parse HEAD
git rev-parse origin/main
```

Recorded evidence: branch `main`; local and remote both resolved to `8fbf7b5ba6550999f1e4d89dcf4a541fba013c0f` before layout classification. The connected generated root was the only untracked path.

- [x] **Step 2: Generate and connect the real Lua project through Eggitor**

In the PC editor, Eggitor 0.3.9 generated and connected `D:\eggy\LuaSource_云上同行` without moving or renaming it. VS Code and the editor completed full synchronization on port `11704`.

Recorded evidence: `LuaSource_云上同行/eggy.json` identifies project ID `6a6f8536abc0fca321ab1fd3`, and `LuaSource_云上同行/main.lua` is the untouched starter with no gameplay. This generated directory is the physical project root; do not create a nested physical `script` directory.

- [x] **Step 3: Export the installed editor's API evidence outside the repository**

Run first:

```powershell
$apiEvidenceDirectory = Join-Path $env:LOCALAPPDATA 'EggyCloudJourney\evidence'
New-Item -ItemType Directory -Force -Path $apiEvidenceDirectory | Out-Null
$apiEvidencePath = Join-Path $apiEvidenceDirectory 'EggyAPI.lua'
$apiEvidencePath
```

In the VS Code Eggy Developer Assistant panel, use `Export API` and select the printed path exactly.

Expected: `%LOCALAPPDATA%\EggyCloudJourney\evidence\EggyAPI.lua` exists and is the export from the currently connected editor/map session.

- [x] **Step 4: Reconcile the five documented surfaces with the export**

Run:

```powershell
$apiEvidencePath = Join-Path $env:LOCALAPPDATA 'EggyCloudJourney\evidence\EggyAPI.lua'
$requiredApiEvidence = @(
    'LuaAPI.log',
    'LuaAPI.global_register_trigger_event',
    'LuaAPI.global_unregister_trigger_event',
    'EVENT.GAME_INIT',
    'EVENT.GAME_END'
)

if (-not (Test-Path -LiteralPath $apiEvidencePath -PathType Leaf)) {
    throw "Current EggyAPI.lua export not found at $apiEvidencePath"
}

$apiText = [System.IO.File]::ReadAllText($apiEvidencePath)
foreach ($symbol in $requiredApiEvidence) {
    if ($apiText.IndexOf($symbol, [System.StringComparison]::Ordinal) -lt 0) {
        throw "Current EggyAPI.lua does not contain $symbol"
    }
}

$requiredApiSignatures = @(
    '---@param _event_desc any\[\]',
    '---@param _callback function',
    '---@return integer',
    'function LuaAPI\.global_register_trigger_event\(_event_desc, _callback\)',
    '---@param _id integer',
    'function LuaAPI\.global_unregister_trigger_event\(_id\)',
    '---@param _content string',
    '---@param _log_level integer\?',
    'function LuaAPI\.log\(_content, _log_level\)'
)
foreach ($signature in $requiredApiSignatures) {
    if ($apiText -notmatch $signature) {
        throw "Current EggyAPI.lua does not match required signature evidence: $signature"
    }
}

Select-String -LiteralPath $apiEvidencePath -Pattern @(
    'LuaAPI\.log',
    'LuaAPI\.global_register_trigger_event',
    'LuaAPI\.global_unregister_trigger_event',
    'EVENT\.GAME_INIT',
    'EVENT\.GAME_END'
) -Context 2,4
```

Recorded evidence: all five names are present. Registration takes an event-description list and callback and returns an integer registration ID; unregistration takes that ID; logging takes a string and an optional integer level. The foundation intentionally calls logging with only the required string argument. If a later installed export conflicts with these signatures, stop before implementation and report the exact conflict.

- [x] **Step 5: Confirm the generated entry point is safe to replace**

Run:

```powershell
Get-Content -Raw -Encoding UTF8 D:\eggy\LuaSource_云上同行\main.lua
git status --short
```

Recorded evidence: `LuaSource_云上同行/main.lua` contains only the untouched Eggitor starter template. It remains unchanged until Task 7 replaces it with the approved assembly entry point.

### Task 0.5: Classify and commit the live connected-project layout

**Files:**
- Modify: `.gitignore`
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/plans/2026-08-02-foundation-module.md`
- Modify: `docs/superpowers/specs/2026-08-02-foundation-module-design.md`
- Add unchanged generated metadata: `LuaSource_云上同行/eggy.json`
- Add unchanged starter: `LuaSource_云上同行/main.lua`

- [x] **Step 1: Preserve the generated root and classify the mapping**

Keep `LuaSource_云上同行/` in place as the sole physical project root. It maps to the manual's logical `script/` namespace, so production files are created directly beneath it and imports remain root-relative, for example `require("core.logger")`.

- [x] **Step 2: Ignore only connected-project local/generated artifacts**

Ignore `.vscode/`, `.codemaker/`, `EggyAPI.lua`, `EggyEditorAPI.lua`, and `DebugTools.lua` beneath `LuaSource_云上同行/`. Keep `eggy.json`, `main.lua`, and all project-owned modules eligible for version control.

- [x] **Step 3: Lock the nested-require synchronization gate**

Task 9 temporarily creates `LuaSource_云上同行/tests/foundation_editor_harness.lua`, waits for synchronization, executes `require("tests.foundation_editor_harness")` in the editor, records the playtest evidence, deletes the harness, and waits for deletion synchronization. Any future root move, rename, or regeneration must repeat connection, full-sync, entry-point, and nested-require validation.

- [x] **Step 4: Commit and push the classified shell**

Stage exactly `.gitignore`, `AGENTS.md`, the plan, the design, `LuaSource_云上同行/eggy.json`, and the untouched `LuaSource_云上同行/main.lua`. Generated API/debug files and local folders remain ignored. Run `git diff --check` across the edited project-owned text and a path-scoped `git diff --cached --check` that excludes only `LuaSource_云上同行/eggy.json`; preserve that generator-owned file byte-for-byte, verify its SHA-256 is `6E6B8D99D60642F9D647BDA89833B07C45F5E9BE35493E356BEF98D2FEE40EF7`, and inspect the full staged diff including the generated formatting. Commit with the Task 0.5 Lore record and push directly to `origin/main` before Task 1.

### Task 1: Add central foundation configuration

**Files:**
- Create: `LuaSource_云上同行/config/events.lua`
- Create: `LuaSource_云上同行/config/objects.lua`

- [ ] **Step 1: Run the configuration RED check**

Run:

```powershell
$missing = @('LuaSource_云上同行/config/events.lua', 'LuaSource_云上同行/config/objects.lua') | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
if ($missing.Count -ne 0) { throw "Missing foundation config: $($missing -join ', ')" }
```

Expected: FAIL and name both missing files.

- [ ] **Step 2: Create the exact event configuration**

Create `LuaSource_云上同行/config/events.lua`:

```lua
-- 项目自定义事件只在此处登记，避免业务模块散落事件字符串。
local events = {
    CORE_READY = "CLOUD_JOURNEY.CORE_READY",
}

return events
```

- [ ] **Step 3: Create the exact empty object configuration**

Create `LuaSource_云上同行/config/objects.lua`:

```lua
-- 基础模块不绑定编辑器对象；真实 ID 必须来自当前地图的 Eggitor 导出。
return {}
```

- [ ] **Step 4: Run the configuration GREEN checks**

Run:

```powershell
$events = Get-Content -Raw -Encoding UTF8 LuaSource_云上同行\config\events.lua
$objects = Get-Content -Raw -Encoding UTF8 LuaSource_云上同行\config\objects.lua
if ($events -notmatch 'CORE_READY\s*=\s*"CLOUD_JOURNEY\.CORE_READY"') { throw 'CORE_READY is not centralized correctly.' }
$objectsCode = [regex]::Replace($objects, '(?m)^\s*--[^\r\n]*', '')
$objectsCode = [regex]::Replace($objectsCode, '\s+', '')
if ($objectsCode -ne 'return{}') { throw 'objects.lua must remain empty in the foundation module.' }
git diff --check -- LuaSource_云上同行/config/events.lua LuaSource_云上同行/config/objects.lua
```

Expected: exit `0` and no Git whitespace output.

- [ ] **Step 5: Commit and push the configuration slice**

Run:

```powershell
git status --short --branch
git add -- LuaSource_云上同行/config/events.lua LuaSource_云上同行/config/objects.lua
git diff --cached --name-status
git diff --cached
git diff --cached --check
@'
Centralize the foundation's verified configuration boundary

Constraint: The first module has one internal event and no editor object identifiers
Rejected: Add placeholder object IDs | current Eggitor map data is the only valid source
Confidence: high
Scope-risk: narrow
Directive: Keep project event literals and verified object mappings centralized
Tested: Configuration source assertions; UTF-8 review; git diff --check; staged diff inspection
Not-tested: Lua execution; Eggitor synchronization; editor runtime integration
'@ | git commit -F -
if ($LASTEXITCODE -ne 0) { throw 'git commit failed; nothing was pushed.' }
git push origin main
if ($LASTEXITCODE -ne 0) {
    git fetch origin
    git status --short --branch
    git log --oneline --left-right --graph HEAD...origin/main
    throw 'Push rejected. Local commit preserved; reconcile with origin/main without force-pushing.'
}
git fetch origin
if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) { throw 'Local HEAD and origin/main differ.' }
git status --short --branch
```

Expected: the commit contains only the two configuration files and `origin/main` matches local `HEAD`.

### Task 2: Add the Lua test helper and synchronous internal event bus

**Files:**
- Create: `tests/lua/test_helper.lua`
- Create: `tests/lua/core/event_bus_test.lua`
- Create: `LuaSource_云上同行/core/event_bus.lua`

- [ ] **Step 1: Create the exact dependency-free Lua test helper**

Create `tests/lua/test_helper.lua`:

```lua
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
```

- [ ] **Step 2: Write the event-bus behavior tests**

Create `tests/lua/core/event_bus_test.lua`:

```lua
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
```

The second publish returns `false` because the remaining first handler attempts to unsubscribe the already-removed second ID and its test assertion raises. This intentionally verifies both snapshot semantics and contained handler failure.

- [ ] **Step 3: Run the event-bus RED gate**

Run:

```powershell
$lua = Get-Command lua54,lua -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $lua) {
    Write-Output '[NOT-RUN] Compatible standalone Lua 5.4 runner unavailable.'
    $global:LASTEXITCODE = 2
} else {
    $version = & $lua.Source -v 2>&1
    if ("$version" -notmatch 'Lua 5\.4') { throw "Lua 5.4 required; found $version" }
    & $lua.Source tests/lua/core/event_bus_test.lua
}
```

Expected: FAIL because `core.event_bus` is absent when a Lua 5.4 runner exists, otherwise `[NOT-RUN] Compatible standalone Lua 5.4 runner unavailable.`

- [ ] **Step 4: Implement the exact event bus**

Create `LuaSource_云上同行/core/event_bus.lua`:

```lua
local event_bus = {}

local initialized = false
local logger = nil
local subscriptions = {}
local next_subscription_id = 1

local function valid_logger(candidate)
    return type(candidate) == "table" and type(candidate.error) == "function"
end

local function valid_event_name(event_name)
    return type(event_name) == "string" and event_name ~= ""
end

local function report(message)
    if initialized then
        logger.error("EventBus", message)
    end
end

function event_bus.init(candidate_logger)
    if not valid_logger(candidate_logger) then
        if initialized then
            report("初始化日志依赖无效")
        end
        return false
    end

    if initialized then
        local same_lifetime = candidate_logger == logger
        if not same_lifetime then
            report("初始化日志依赖与当前生命周期不一致")
        end
        return same_lifetime
    end

    logger = candidate_logger
    subscriptions = {}
    next_subscription_id = 1
    initialized = true
    return true
end


function event_bus.subscribe(event_name, handler)
    if not initialized then
        return nil
    end
    if not valid_event_name(event_name) or type(handler) ~= "function" then
        report("订阅参数无效")
        return nil
    end

    local subscription_id = next_subscription_id
    next_subscription_id = next_subscription_id + 1
    subscriptions[#subscriptions + 1] = {
        id = subscription_id,
        event_name = event_name,
        handler = handler,
        active = true,
    }
    return subscription_id
end

function event_bus.unsubscribe(subscription_id)
    if not initialized then
        return false
    end
    if type(subscription_id) ~= "number" then
        report("订阅编号无效")
        return false
    end

    for _, subscription in ipairs(subscriptions) do
        if subscription.id == subscription_id and subscription.active then
            subscription.active = false
            return true
        end
    end
    report("订阅编号不存在: " .. tostring(subscription_id))
    return false
end


function event_bus.publish(event_name, payload)
    if not initialized then
        return false
    end
    if not valid_event_name(event_name) then
        report("发布事件名无效")
        return false
    end

    -- 快照保存函数本身，使派发期间的取消订阅只影响下一次发布。
    local snapshot = {}
    for _, subscription in ipairs(subscriptions) do
        if subscription.active and subscription.event_name == event_name then
            snapshot[#snapshot + 1] = {
                id = subscription.id,
                handler = subscription.handler,
            }
        end
    end

    local all_succeeded = true
    for _, subscription in ipairs(snapshot) do
        local called = pcall(subscription.handler, payload)
        if not called then
            all_succeeded = false
            report("事件处理器执行失败: " .. event_name .. " #" .. tostring(subscription.id))
        end
    end
    return all_succeeded
end

function event_bus.dispose()
    initialized = false
    logger = nil
    subscriptions = {}
    next_subscription_id = 1
    return true
end

return event_bus
```

- [ ] **Step 5: Run available event-bus checks**

Run the Step 3 command again, then run:

```powershell
$source = Get-Content -Raw -Encoding UTF8 LuaSource_云上同行\core\event_bus.lua
foreach ($surface in @('init', 'subscribe', 'unsubscribe', 'publish', 'dispose')) {
    if ($source -notmatch "function event_bus\.$surface") { throw "Missing event_bus.$surface" }
}
if ($source -notmatch 'pcall\(subscription\.handler, payload\)') { throw 'Handlers are not protected.' }
if ($source -match '\bLuaAPI\b|\bEVENT\b') { throw 'event_bus must remain platform-independent.' }
git diff --check -- tests/lua/test_helper.lua tests/lua/core/event_bus_test.lua LuaSource_云上同行/core/event_bus.lua
```

Expected: source checks exit `0`; Lua result is PASS or explicitly `[NOT-RUN]`.

- [ ] **Step 6: Commit and push the event-bus slice**

Run:

```powershell
git status --short --branch
git add -- tests/lua/test_helper.lua tests/lua/core/event_bus_test.lua LuaSource_云上同行/core/event_bus.lua
git diff --cached --name-status
git diff --cached
git diff --cached --check
@'
Provide deterministic internal event delivery for foundation systems

Constraint: Dispatch must stay synchronous, ordered, and independent of platform events
Rejected: Iterate the live subscription table | unsubscribe during dispatch would corrupt behavior
Confidence: high
Scope-risk: narrow
Directive: Publish from a handler snapshot and continue after contained handler errors
Tested: Source-contract checks; UTF-8 review; git diff --check; staged diff inspection
Not-tested: Lua behavioral suite when runner unavailable; Eggitor synchronization; editor runtime integration
'@ | git commit -F -
if ($LASTEXITCODE -ne 0) { throw 'git commit failed; nothing was pushed.' }
git push origin main
if ($LASTEXITCODE -ne 0) {
    git fetch origin
    git status --short --branch
    git log --oneline --left-right --graph HEAD...origin/main
    throw 'Push rejected. Local commit preserved; reconcile with origin/main without force-pushing.'
}
git fetch origin
if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) { throw 'Local HEAD and origin/main differ.' }
git status --short --branch
```

Expected: the commit contains only the test helper, event-bus test, and event-bus module; local and remote SHAs match.

### Task 3: Add the verified object-registry boundary

**Files:**
- Create: `tests/lua/core/object_registry_test.lua`
- Create: `LuaSource_云上同行/core/object_registry.lua`

- [ ] **Step 1: Write the object-registry behavior tests**

Create `tests/lua/core/object_registry_test.lua`:

```lua
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
```

- [ ] **Step 2: Run the registry RED gate**

Run:

```powershell
$lua = Get-Command lua54,lua -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $lua) {
    Write-Output '[NOT-RUN] Compatible standalone Lua 5.4 runner unavailable.'
    $global:LASTEXITCODE = 2
} else {
    $version = & $lua.Source -v 2>&1
    if ("$version" -notmatch 'Lua 5\.4') { throw "Lua 5.4 required; found $version" }
    & $lua.Source tests/lua/core/object_registry_test.lua
}
```

Expected: FAIL because the module is absent under Lua 5.4, otherwise explicit `[NOT-RUN]`.

- [ ] **Step 3: Implement the exact object registry**

Create `LuaSource_云上同行/core/object_registry.lua`:

```lua
local object_registry = {}

local initialized = false
local source_entries = nil
local entries = {}
local logger = nil
local warned_missing_keys = {}

local function valid_logger(candidate)
    return type(candidate) == "table" and type(candidate.warn) == "function"
end

local function valid_key(logical_key)
    return type(logical_key) == "string" and logical_key ~= ""
end

local function valid_entries(candidate)
    if type(candidate) ~= "table" then
        return false
    end
    for logical_key, _ in pairs(candidate) do
        if not valid_key(logical_key) then
            return false
        end
    end
    return true
end

function object_registry.init(candidate_entries, candidate_logger)
    if not valid_entries(candidate_entries) or not valid_logger(candidate_logger) then
        if initialized then
            logger.warn("ObjectRegistry", "初始化配置或日志依赖无效")
        end
        return false
    end

    if initialized then
        local same_lifetime = candidate_entries == source_entries and candidate_logger == logger
        if not same_lifetime then
            logger.warn("ObjectRegistry", "初始化依赖与当前生命周期不一致")
        end
        return same_lifetime
    end

    -- 完整校验后再复制，失败输入不会留下半份注册表。
    local snapshot = {}
    for logical_key, value in pairs(candidate_entries) do
        snapshot[logical_key] = value
    end

    source_entries = candidate_entries
    entries = snapshot
    logger = candidate_logger
    warned_missing_keys = {}
    initialized = true
    return true
end

function object_registry.has(logical_key)
    if not initialized then
        return false
    end
    if not valid_key(logical_key) then
        logger.warn("ObjectRegistry", "对象逻辑键无效")
        return false
    end
    return entries[logical_key] ~= nil
end

function object_registry.get(logical_key)
    if not initialized then
        return nil
    end
    if not valid_key(logical_key) then
        logger.warn("ObjectRegistry", "对象逻辑键无效")
        return nil
    end

    local value = entries[logical_key]
    if value == nil and not warned_missing_keys[logical_key] then
        warned_missing_keys[logical_key] = true
        logger.warn("ObjectRegistry", "未注册对象逻辑键: " .. logical_key)
    end
    return value
end

function object_registry.dispose()
    initialized = false
    source_entries = nil
    entries = {}
    logger = nil
    warned_missing_keys = {}
    return true
end

return object_registry
```

- [ ] **Step 4: Run available registry checks**

Run the Step 2 command again, then:

```powershell
$source = Get-Content -Raw -Encoding UTF8 LuaSource_云上同行\core\object_registry.lua
foreach ($surface in @('init', 'has', 'get', 'dispose')) {
    if ($source -notmatch "function object_registry\.$surface") { throw "Missing object_registry.$surface" }
}
if ($source -notmatch 'warned_missing_keys\[logical_key\] = true') { throw 'Missing-key warning suppression is absent.' }
if ($source -match '\bLuaAPI\b|\bEVENT\b') { throw 'object_registry must remain platform-independent.' }
git diff --check -- tests/lua/core/object_registry_test.lua LuaSource_云上同行/core/object_registry.lua
```

Expected: source checks exit `0`; Lua result is PASS or explicitly `[NOT-RUN]`.

- [ ] **Step 5: Commit and push the registry slice**

Run:

```powershell
git status --short --branch
git add -- tests/lua/core/object_registry_test.lua LuaSource_云上同行/core/object_registry.lua
git diff --cached --name-status
git diff --cached
git diff --cached --check
@'
Protect gameplay code from unverified editor object data

Constraint: Foundation configuration is empty and future IDs must come from Eggitor evidence
Rejected: Keep a live configuration reference | later mutation would bypass validation
Confidence: high
Scope-risk: narrow
Directive: Resolve editor objects only through validated logical keys and warn once per missing key
Tested: Source-contract checks; UTF-8 review; git diff --check; staged diff inspection
Not-tested: Lua behavioral suite when runner unavailable; Eggitor synchronization; editor runtime integration
'@ | git commit -F -
if ($LASTEXITCODE -ne 0) { throw 'git commit failed; nothing was pushed.' }
git push origin main
if ($LASTEXITCODE -ne 0) {
    git fetch origin
    git status --short --branch
    git log --oneline --left-right --graph HEAD...origin/main
    throw 'Push rejected. Local commit preserved; reconcile with origin/main without force-pushing.'
}
git fetch origin
if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) { throw 'Local HEAD and origin/main differ.' }
git status --short --branch
```

Expected: the commit contains only the object-registry test and module; local and remote SHAs match.

### Task 4: Add protected logging and its behavior specification

**Files:**
- Inspect: `tests/lua/test_helper.lua`
- Create: `tests/lua/adapters/u5_log_test.lua`
- Create: `tests/lua/core/logger_test.lua`
- Create: `LuaSource_云上同行/adapters/u5_log.lua`
- Create: `LuaSource_云上同行/core/logger.lua`

- [ ] **Step 1: Verify the shared Lua test helper is unchanged**

Run:

```powershell
if (-not (Test-Path -LiteralPath tests\lua\test_helper.lua -PathType Leaf)) {
    throw 'Task 2 test helper is missing.'
}
git diff --exit-code -- tests/lua/test_helper.lua
```

Expected: exit `0`; Task 4 does not rewrite shared test infrastructure.

- [ ] **Step 2: Write the logging-adapter tests before production code**

Create `tests/lua/adapters/u5_log_test.lua`:

```lua
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
```

- [ ] **Step 3: Write the logger tests before production code**

Create `tests/lua/core/logger_test.lua`:

```lua
package.path = "tests/lua/?.lua;LuaSource_云上同行/?.lua;" .. package.path

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
```

- [ ] **Step 4: Run the Lua-runner gate and record RED or unavailable evidence**

Run:

```powershell
$lua = Get-Command lua54,lua -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $lua) {
    Write-Output '[NOT-RUN] Compatible standalone Lua 5.4 runner unavailable.'
    $global:LASTEXITCODE = 2
} else {
    $version = & $lua.Source -v 2>&1
    if ("$version" -notmatch 'Lua 5\.4') { throw "Lua 5.4 required; found $version" }
    foreach ($testFile in @('tests/lua/adapters/u5_log_test.lua', 'tests/lua/core/logger_test.lua')) {
        & $lua.Source $testFile
        if ($LASTEXITCODE -ne 0) { throw "Lua test failed: $testFile" }
    }
}
```

Expected now: `[NOT-RUN]` with evidence code `2`, because no compatible runner is installed. If Lua 5.4 becomes available, both tests must FAIL because the production modules are absent; do not treat the unavailable result as a passing behavioral test.

- [ ] **Step 5: Implement the exact U5 logging adapter**

Create `LuaSource_云上同行/adapters/u5_log.lua`:

```lua
local u5_log = {}

local initialized = false
local platform_log = nil

function u5_log.init()
    if initialized then
        return true
    end

    if type(LuaAPI) ~= "table" or type(LuaAPI.log) ~= "function" then
        return false
    end

    platform_log = LuaAPI.log
    initialized = true
    return true
end

function u5_log.write(level, source, message)
    if not initialized or type(platform_log) ~= "function" then
        return false
    end

    -- 显式转换所有字段，避免沙盒禁止的字符串与数字隐式转换。
    local formatted, line = pcall(function()
        return "[" .. tostring(level) .. "][" .. tostring(source) .. "] " .. tostring(message)
    end)
    if not formatted then
        return false
    end

    local called = pcall(platform_log, line)
    return called
end

function u5_log.dispose()
    initialized = false
    platform_log = nil
    return true
end

return u5_log
```

- [ ] **Step 6: Implement the exact platform-independent logger**

Create `LuaSource_云上同行/core/logger.lua`:

```lua
local logger = {}

local initialized = false
local backend = nil

local function is_valid_backend(candidate)
    return type(candidate) == "table" and type(candidate.write) == "function"
end

local function write(level, source, message)
    if not initialized then
        return false
    end

    -- 后端错误不得中断游戏流程，返回值只接受明确的 true。
    local called, result = pcall(backend.write, level, source, message)
    return called and result == true
end

function logger.init(candidate)
    if not is_valid_backend(candidate) then
        if initialized then
            write("ERROR", "Logger", "初始化后端无效")
        end
        return false
    end

    if initialized then
        local same_lifetime = candidate == backend
        if not same_lifetime then
            write("ERROR", "Logger", "初始化后端与当前生命周期不一致")
        end
        return same_lifetime
    end

    backend = candidate
    initialized = true
    return true
end

function logger.info(source, message)
    return write("INFO", source, message)
end

function logger.warn(source, message)
    return write("WARN", source, message)
end

function logger.error(source, message)
    return write("ERROR", source, message)
end

function logger.dispose()
    initialized = false
    backend = nil
    return true
end

return logger
```

- [ ] **Step 7: Run available logging checks**

Run the Lua command from Step 4 again. If no runner exists, retain `[NOT-RUN]` and then run:

```powershell
$adapter = Get-Content -Raw -Encoding UTF8 LuaSource_云上同行\adapters\u5_log.lua
$logger = Get-Content -Raw -Encoding UTF8 LuaSource_云上同行\core\logger.lua
if ($adapter -notmatch 'pcall\(platform_log, line\)') { throw 'u5_log must protect LuaAPI.log.' }
if ($adapter.IndexOf('return "[" .. tostring(level)', [System.StringComparison]::Ordinal) -lt 0) { throw 'u5_log format is not explicit.' }
if ($logger -match '\bLuaAPI\b|\bEVENT\b') { throw 'core.logger must remain platform-independent.' }
if ($logger -notmatch 'function logger\.init' -or $logger -notmatch 'function logger\.dispose') { throw 'logger lifecycle is incomplete.' }
git diff --check -- tests/lua/test_helper.lua tests/lua/adapters/u5_log_test.lua tests/lua/core/logger_test.lua LuaSource_云上同行/adapters/u5_log.lua LuaSource_云上同行/core/logger.lua
```

Expected: source-contract checks exit `0`; Lua behavior is either PASS under compatible Lua 5.4 or explicitly `[NOT-RUN]`.

- [ ] **Step 8: Commit and push the logging slice**

Run:

```powershell
git status --short --branch
git add -- tests/lua/adapters/u5_log_test.lua tests/lua/core/logger_test.lua LuaSource_云上同行/adapters/u5_log.lua LuaSource_云上同行/core/logger.lua
git diff --cached --name-status
git diff --cached
git diff --cached --check
@'
Contain platform logging behind a reusable foundation boundary

Constraint: Eggy logging is a one-string platform call and runtime failures must not escape
Rejected: Call LuaAPI.log from core modules | platform access belongs in adapters
Confidence: high
Scope-risk: narrow
Directive: Keep formatting stable and treat only explicit backend true as success
Tested: Current EggyAPI.lua signature reconciliation; source-contract checks; UTF-8 review; git diff --check; staged diff inspection
Not-tested: Lua behavioral suite when runner unavailable; Eggitor synchronization; editor runtime integration
'@ | git commit -F -
if ($LASTEXITCODE -ne 0) { throw 'git commit failed; nothing was pushed.' }
git push origin main
if ($LASTEXITCODE -ne 0) {
    git fetch origin
    git status --short --branch
    git log --oneline --left-right --graph HEAD...origin/main
    throw 'Push rejected. Local commit preserved; reconcile with origin/main without force-pushing.'
}
git fetch origin
if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) { throw 'Local HEAD and origin/main differ.' }
git status --short --branch
```

Expected: the commit contains only the two logging tests and two logging modules; local and remote SHAs match.

### Task 5: Add the foundation game-flow state holder

**Files:**
- Create: `tests/lua/core/game_flow_test.lua`
- Create: `LuaSource_云上同行/core/game_flow.lua`

- [ ] **Step 1: Write the game-flow behavior tests**

Create `tests/lua/core/game_flow_test.lua`:

```lua
package.path = "tests/lua/?.lua;LuaSource_云上同行/?.lua;" .. package.path

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
```

- [ ] **Step 2: Run the game-flow RED gate**

Run:

```powershell
$lua = Get-Command lua54,lua -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $lua) {
    Write-Output '[NOT-RUN] Compatible standalone Lua 5.4 runner unavailable.'
    $global:LASTEXITCODE = 2
} else {
    $version = & $lua.Source -v 2>&1
    if ("$version" -notmatch 'Lua 5\.4') { throw "Lua 5.4 required; found $version" }
    & $lua.Source tests/lua/core/game_flow_test.lua
}
```

Expected: FAIL because the module is absent under compatible Lua 5.4, otherwise explicit `[NOT-RUN]`.

- [ ] **Step 3: Implement the exact game flow**

Create `LuaSource_云上同行/core/game_flow.lua`:

```lua
local game_flow = {}

local STATE = {
    UNINITIALIZED = "UNINITIALIZED",
    WAITING_GAME_INIT = "WAITING_GAME_INIT",
    READY = "READY",
    DISPOSED = "DISPOSED",
}

local initialized = false
local state = STATE.UNINITIALIZED
local dependency_table = nil
local logger = nil
local event_bus = nil
local events = nil

local function valid_dependencies(candidate)
    return type(candidate) == "table"
        and type(candidate.logger) == "table"
        and type(candidate.logger.info) == "function"
        and type(candidate.eventBus) == "table"
        and type(candidate.eventBus.publish) == "function"
        and type(candidate.events) == "table"
        and type(candidate.events.CORE_READY) == "string"
        and candidate.events.CORE_READY ~= ""
end

function game_flow.init(candidate)
    if not valid_dependencies(candidate) then
        if initialized then
            logger.info("GameFlow", "初始化依赖无效")
        end
        return false
    end

    if initialized then
        local same_lifetime = candidate == dependency_table
            and candidate.logger == logger
            and candidate.eventBus == event_bus
            and candidate.events == events
        if not same_lifetime then
            logger.info("GameFlow", "初始化依赖与当前生命周期不一致")
        end
        return same_lifetime
    end

    dependency_table = candidate
    logger = candidate.logger
    event_bus = candidate.eventBus
    events = candidate.events
    state = STATE.WAITING_GAME_INIT
    initialized = true
    return true
end

function game_flow.start()
    if not initialized or state ~= STATE.WAITING_GAME_INIT then
        return false
    end

    -- 先锁定 READY，订阅者失败也不能导致同一生命周期重复发布。
    state = STATE.READY
    local published = event_bus.publish(events.CORE_READY, nil)
    logger.info("GameFlow", "基础模块已就绪")
    return published == true
end

function game_flow.get_state()
    return state
end

function game_flow.dispose()
    initialized = false
    dependency_table = nil
    logger = nil
    event_bus = nil
    events = nil
    state = STATE.DISPOSED
    return true
end

return game_flow
```

- [ ] **Step 4: Run available game-flow checks**

Run the Step 2 command again, then:

```powershell
$source = Get-Content -Raw -Encoding UTF8 LuaSource_云上同行\core\game_flow.lua
foreach ($surface in @('init', 'start', 'get_state', 'dispose')) {
    if ($source -notmatch "function game_flow\.$surface") { throw "Missing game_flow.$surface" }
}
if ($source -match 'CLOUD_JOURNEY\.CORE_READY') { throw 'Custom event literal escaped config/events.lua.' }
if ($source -match '\bLuaAPI\b|\bEVENT\b') { throw 'game_flow must remain platform-independent.' }
git diff --check -- tests/lua/core/game_flow_test.lua LuaSource_云上同行/core/game_flow.lua
```

Expected: source checks exit `0`; Lua result is PASS or explicitly `[NOT-RUN]`.

- [ ] **Step 5: Commit and push the game-flow slice**

Run:

```powershell
git status --short --branch
git add -- tests/lua/core/game_flow_test.lua LuaSource_云上同行/core/game_flow.lua
git diff --cached --name-status
git diff --cached
git diff --cached --check
@'
Make foundation readiness an explicit one-shot state transition

Constraint: Gameplay cannot start during main.lua load and readiness is driven by GAME_INIT
Rejected: Start from the entry point or a Tick loop | both violate editor lifecycle semantics
Confidence: high
Scope-risk: narrow
Directive: Enter READY before publishing and never republish in the same initialized lifetime
Tested: Source-contract checks; UTF-8 review; git diff --check; staged diff inspection
Not-tested: Lua behavioral suite when runner unavailable; Eggitor synchronization; editor runtime integration
'@ | git commit -F -
if ($LASTEXITCODE -ne 0) { throw 'git commit failed; nothing was pushed.' }
git push origin main
if ($LASTEXITCODE -ne 0) {
    git fetch origin
    git status --short --branch
    git log --oneline --left-right --graph HEAD...origin/main
    throw 'Push rejected. Local commit preserved; reconcile with origin/main without force-pushing.'
}
git fetch origin
if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) { throw 'Local HEAD and origin/main differ.' }
git status --short --branch
```

Expected: the commit contains only the game-flow test and module; local and remote SHAs match.

### Task 6: Add the owned U5 global-event adapter

**Files:**
- Create: `tests/lua/adapters/u5_event_test.lua`
- Create: `LuaSource_云上同行/adapters/u5_event.lua`

- [ ] **Step 1: Write the platform-event behavior tests**

Create `tests/lua/adapters/u5_event_test.lua`:

```lua
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
```

- [ ] **Step 2: Run the event-adapter RED gate**

Run:

```powershell
$lua = Get-Command lua54,lua -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $lua) {
    Write-Output '[NOT-RUN] Compatible standalone Lua 5.4 runner unavailable.'
    $global:LASTEXITCODE = 2
} else {
    $version = & $lua.Source -v 2>&1
    if ("$version" -notmatch 'Lua 5\.4') { throw "Lua 5.4 required; found $version" }
    & $lua.Source tests/lua/adapters/u5_event_test.lua
}
```

Expected: FAIL because the adapter is absent under compatible Lua 5.4, otherwise explicit `[NOT-RUN]`.

- [ ] **Step 3: Implement the exact U5 event adapter**

Create `LuaSource_云上同行/adapters/u5_event.lua`:

```lua
local u5_event = {}

local initialized = false
local cleanup_pending = false
local logger = nil
local register_trigger = nil
local unregister_trigger = nil
local game_init_event = nil
local game_end_event = nil
local owned_handles = {}

local function valid_logger(candidate)
    return type(candidate) == "table" and type(candidate.error) == "function"
end

local function valid_platform()
    return type(LuaAPI) == "table"
        and type(LuaAPI.global_register_trigger_event) == "function"
        and type(LuaAPI.global_unregister_trigger_event) == "function"
        and type(EVENT) == "table"
        and EVENT.GAME_INIT ~= nil
        and EVENT.GAME_END ~= nil
end

local function report(message)
    if logger ~= nil then
        logger.error("U5Event", message)
    end
end

local function register(event_value, callback)
    if not initialized or cleanup_pending then
        return nil
    end
    if type(callback) ~= "function" then
        report("全局事件回调无效")
        return nil
    end

    local called, handle = pcall(register_trigger, { event_value }, callback)
    if not called or type(handle) ~= "number" then
        report("全局事件注册失败")
        return nil
    end

    owned_handles[#owned_handles + 1] = handle
    return handle
end

local function find_owned_handle(handle)
    for index, owned_handle in ipairs(owned_handles) do
        if owned_handle == handle then
            return index
        end
    end
    return nil
end

local function unregister_owned(handle)
    local index = find_owned_handle(handle)
    if index == nil then
        return false
    end

    local called = pcall(unregister_trigger, handle)
    if not called then
        report("全局事件注销调用失败: " .. tostring(handle))
        return false
    end

    table.remove(owned_handles, index)
    return true
end

function u5_event.init(candidate_logger)
    if cleanup_pending then
        report("平台事件清理未完成，拒绝重新初始化")
        return false
    end
    if not valid_logger(candidate_logger) or not valid_platform() then
        if initialized then
            report("初始化日志依赖或平台接口无效")
        end
        return false
    end
    if initialized then
        local same_lifetime = candidate_logger == logger
        if not same_lifetime then
            report("初始化日志依赖与当前生命周期不一致")
        end
        return same_lifetime
    end

    logger = candidate_logger
    register_trigger = LuaAPI.global_register_trigger_event
    unregister_trigger = LuaAPI.global_unregister_trigger_event
    game_init_event = EVENT.GAME_INIT
    game_end_event = EVENT.GAME_END
    owned_handles = {}
    initialized = true
    return true
end

function u5_event.on_game_init(callback)
    return register(game_init_event, callback)
end

function u5_event.on_game_end(callback)
    return register(game_end_event, callback)
end

function u5_event.unregister(handle)
    if not initialized or cleanup_pending then
        return false
    end
    if type(handle) ~= "number" then
        report("全局事件注册编号无效")
        return false
    end
    if find_owned_handle(handle) == nil then
        report("全局事件注册编号不属于当前适配器: " .. tostring(handle))
        return false
    end
    return unregister_owned(handle)
end

function u5_event.dispose()
    if not initialized and not cleanup_pending then
        return true
    end

    cleanup_pending = true
    local snapshot = {}
    for _, handle in ipairs(owned_handles) do
        snapshot[#snapshot + 1] = handle
    end

    -- 失败句柄保留在 owned_handles 中，后续 dispose 会继续重试。
    for _, handle in ipairs(snapshot) do
        unregister_owned(handle)
    end

    if #owned_handles > 0 then
        return false
    end

    initialized = false
    cleanup_pending = false
    logger = nil
    register_trigger = nil
    unregister_trigger = nil
    game_init_event = nil
    game_end_event = nil
    owned_handles = {}
    return true
end

return u5_event
```

- [ ] **Step 4: Run available event-adapter checks**

Run the Step 2 command again, then:

```powershell
$source = Get-Content -Raw -Encoding UTF8 LuaSource_云上同行\adapters\u5_event.lua
foreach ($surface in @('init', 'on_game_init', 'on_game_end', 'unregister', 'dispose')) {
    if ($source -notmatch "function u5_event\.$surface") { throw "Missing u5_event.$surface" }
}
if ($source -notmatch 'pcall\(register_trigger, \{ event_value \}, callback\)') { throw 'Registration signature does not match the documented event list.' }
if ($source -notmatch 'pcall\(unregister_trigger, handle\)') { throw 'Unregistration is not protected.' }
git diff --check -- tests/lua/adapters/u5_event_test.lua LuaSource_云上同行/adapters/u5_event.lua
```

Expected: source checks exit `0`; Lua result is PASS or explicitly `[NOT-RUN]`.

- [ ] **Step 5: Commit and push the event-adapter slice**

Run:

```powershell
git status --short --branch
git add -- tests/lua/adapters/u5_event_test.lua LuaSource_云上同行/adapters/u5_event.lua
git diff --cached --name-status
git diff --cached
git diff --cached --check
@'
Own U5 lifecycle registrations through a retryable adapter

Constraint: The API reports registration IDs but no platform-side unregister success value
Rejected: Drop handles after a Lua error | cleanup would be falsely reported as complete
Confidence: high
Scope-risk: narrow
Directive: Retain failed handles and allow only dispose retries while cleanup is pending
Tested: Current EggyAPI.lua signature reconciliation; source-contract checks; UTF-8 review; git diff --check; staged diff inspection
Not-tested: Lua behavioral suite when runner unavailable; Eggitor synchronization; editor runtime integration
'@ | git commit -F -
if ($LASTEXITCODE -ne 0) { throw 'git commit failed; nothing was pushed.' }
git push origin main
if ($LASTEXITCODE -ne 0) {
    git fetch origin
    git status --short --branch
    git log --oneline --left-right --graph HEAD...origin/main
    throw 'Push rejected. Local commit preserved; reconcile with origin/main without force-pushing.'
}
git fetch origin
if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) { throw 'Local HEAD and origin/main differ.' }
git status --short --branch
```

Expected: the commit contains only the U5 event-adapter test and module; local and remote SHAs match.

### Task 7: Assemble the lifecycle-safe application entry point

**Files:**
- Create: `tests/lua/main_test.lua`
- Replace: `LuaSource_云上同行/main.lua`

- [ ] **Step 1: Write the application assembly tests**

Create `tests/lua/main_test.lua`:

```lua
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
        start_calls = 0,
        error_calls = 0,
        event_dispose_calls = 0,
    }

    local function called(name)
        evidence.calls[#evidence.calls + 1] = name
    end

    local u5_log = {
        init = function() called("u5_log.init") return options.u5_log_init ~= false end,
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
            if options.game_init_registration == false then return nil end
            return 101
        end,
        on_game_end = function(callback)
            called("u5_event.on_game_end")
            evidence.callbacks.game_end = callback
            if options.game_end_registration == false then return nil end
            return 102
        end,
        dispose = function()
            called("u5_event.dispose")
            evidence.event_dispose_calls = evidence.event_dispose_calls + 1
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

for _, module_name in ipairs(module_names) do
    package.preload[module_name] = nil
    package.loaded[module_name] = nil
end

test.run()
```

- [ ] **Step 2: Run the application RED gate**

Run:

```powershell
$lua = Get-Command lua54,lua -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $lua) {
    Write-Output '[NOT-RUN] Compatible standalone Lua 5.4 runner unavailable.'
    $global:LASTEXITCODE = 2
} else {
    $version = & $lua.Source -v 2>&1
    if ("$version" -notmatch 'Lua 5\.4') { throw "Lua 5.4 required; found $version" }
    & $lua.Source tests/lua/main_test.lua
}
```

Expected: FAIL against the untouched Eggitor entry point under compatible Lua 5.4, otherwise explicit `[NOT-RUN]`.

- [ ] **Step 3: Replace the entry point with the exact application assembly**

Replace `LuaSource_云上同行/main.lua` with:

```lua
local u5_log = require("adapters.u5_log")
local u5_event = require("adapters.u5_event")
local logger = require("core.logger")
local event_bus = require("core.event_bus")
local object_registry = require("core.object_registry")
local game_flow = require("core.game_flow")
local events = require("config.events")
local objects = require("config.objects")

local app = {}

local STATE = {
    NEW = "NEW",
    INITIALIZED = "INITIALIZED",
    DISPOSING = "DISPOSING",
    DISPOSED = "DISPOSED",
}

local state = STATE.NEW
local game_init_received = false
local completed = {
    u5_log = false,
    logger = false,
    event_bus = false,
    object_registry = false,
    game_flow = false,
    u5_event = false,
}
local game_flow_dependencies = {
    logger = logger,
    eventBus = event_bus,
    events = events,
}

local function cleanup_completed()
    if completed.u5_event then
        -- 平台事件必须先释放；失败时保留日志和其余依赖供后续重试。
        if not u5_event.dispose() then
            state = STATE.DISPOSING
            logger.error("App", "平台事件清理未完成，将在后续 dispose 重试")
            return false
        end
        completed.u5_event = false
    end

    if completed.game_flow then
        game_flow.dispose()
        completed.game_flow = false
    end
    if completed.object_registry then
        object_registry.dispose()
        completed.object_registry = false
    end
    if completed.event_bus then
        event_bus.dispose()
        completed.event_bus = false
    end
    if completed.logger then
        logger.dispose()
        completed.logger = false
    end
    if completed.u5_log then
        u5_log.dispose()
        completed.u5_log = false
    end

    game_init_received = false
    state = STATE.DISPOSED
    return true
end

local function fail_initialization(message)
    if completed.logger then
        logger.error("App", message)
    end
    state = STATE.DISPOSING
    cleanup_completed()
    return false
end

local function on_game_init()
    if state ~= STATE.INITIALIZED or game_init_received then
        return
    end

    -- 先记录已处理，内部通知失败也不能重复启动同一局。
    game_init_received = true
    if not game_flow.start() then
        logger.error("App", "基础就绪通知失败")
    end
end

local function on_game_end()
    app.dispose()
end

function app.init()
    if state == STATE.INITIALIZED then
        return true
    end
    if state == STATE.DISPOSING then
        return false
    end

    game_init_received = false

    if not u5_log.init() then
        state = STATE.DISPOSED
        return false
    end
    completed.u5_log = true

    if not logger.init(u5_log) then
        return fail_initialization("日志模块初始化失败")
    end
    completed.logger = true

    if not event_bus.init(logger) then
        return fail_initialization("事件总线初始化失败")
    end
    completed.event_bus = true

    if not object_registry.init(objects, logger) then
        return fail_initialization("对象注册表初始化失败")
    end
    completed.object_registry = true

    if not game_flow.init(game_flow_dependencies) then
        return fail_initialization("游戏流程初始化失败")
    end
    completed.game_flow = true

    if not u5_event.init(logger) then
        return fail_initialization("平台事件适配器初始化失败")
    end
    completed.u5_event = true

    if u5_event.on_game_init(on_game_init) == nil then
        return fail_initialization("GAME_INIT 注册失败")
    end
    if u5_event.on_game_end(on_game_end) == nil then
        return fail_initialization("GAME_END 注册失败")
    end

    state = STATE.INITIALIZED
    return true
end

function app.dispose()
    if state == STATE.NEW then
        state = STATE.DISPOSED
        game_init_received = false
        return true
    end
    if state == STATE.DISPOSED then
        return true
    end

    state = STATE.DISPOSING
    return cleanup_completed()
end

local load_init_succeeded = app.init()
if not load_init_succeeded then
    return app
end

return app
```

- [ ] **Step 4: Run available application checks**

Run the Step 2 command again, then:

```powershell
$source = Get-Content -Raw -Encoding UTF8 LuaSource_云上同行\main.lua
if ([regex]::Matches($source, 'local load_init_succeeded = app\.init\(\)').Count -ne 1) { throw 'main.lua must call app.init exactly once during load.' }
if ($source -match '\bLuaAPI\b|\bEVENT\b') { throw 'main.lua must not access platform globals.' }
$requiredOrder = @('u5_log.init', 'logger.init', 'event_bus.init', 'object_registry.init', 'game_flow.init', 'u5_event.init', 'u5_event.on_game_init', 'u5_event.on_game_end')
$lastIndex = -1
foreach ($token in $requiredOrder) {
    $index = $source.IndexOf($token, [System.StringComparison]::Ordinal)
    if ($index -le $lastIndex) { throw "Initialization order is wrong at $token" }
    $lastIndex = $index
}
git diff --check -- tests/lua/main_test.lua LuaSource_云上同行/main.lua
```

Expected: source checks exit `0`; Lua result is PASS or explicitly `[NOT-RUN]`.

- [ ] **Step 5: Commit and push the application slice**

Run:

```powershell
git status --short --branch
git add -- tests/lua/main_test.lua LuaSource_云上同行/main.lua
git diff --cached --name-status
git diff --cached
git diff --cached --check
@'
Assemble foundation services around the documented game lifecycle

Constraint: main.lua loads before game-time objects and owned event cleanup may require retry
Rejected: Continue disposing after failed event cleanup | retry state and logging would be lost
Confidence: high
Scope-risk: moderate
Directive: Keep main.lua assembly-only and preserve reverse cleanup order on every failure path
Tested: Current EggyAPI.lua reconciliation; assembly-order source checks; UTF-8 review; git diff --check; staged diff inspection
Not-tested: Lua behavioral suite when runner unavailable; Eggitor synchronization; editor runtime integration
'@ | git commit -F -
if ($LASTEXITCODE -ne 0) { throw 'git commit failed; nothing was pushed.' }
git push origin main
if ($LASTEXITCODE -ne 0) {
    git fetch origin
    git status --short --branch
    git log --oneline --left-right --graph HEAD...origin/main
    throw 'Push rejected. Local commit preserved; reconcile with origin/main without force-pushing.'
}
git fetch origin
if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) { throw 'Local HEAD and origin/main differ.' }
git status --short --branch
```

Expected: the commit contains only the application test and entry point; local and remote SHAs match.

### Task 8: Add and test the repository-local foundation verifier

**Files:**
- Create: `tests/static/verify-foundation.tests.ps1`
- Create: `tools/verify-foundation.ps1`

- [ ] **Step 1: Write the verifier's positive and mutation-based negative tests**

Create `tests/static/verify-foundation.tests.ps1`:

```powershell
param(
    [string]$EggyApiPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$verifierPath = Join-Path $repoRoot 'tools\verify-foundation.ps1'
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$failures = [System.Collections.Generic.List[string]]::new()
if ([string]::IsNullOrWhiteSpace($EggyApiPath)) {
    $EggyApiPath = Join-Path $repoRoot 'LuaSource_云上同行\EggyAPI.lua'
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Add-LuaBeforeFinalReturn {
    param([string]$Path, [string]$Content)

    $source = [System.IO.File]::ReadAllText($Path, $utf8)
    $finalReturn = [regex]::Match($source, '(?m)^return\s+[A-Za-z_][A-Za-z0-9_]*\s*\r?\n\z')
    if (-not $finalReturn.Success) {
        throw "Final module return not found: $Path"
    }
    if (-not $Content.EndsWith("`n", [System.StringComparison]::Ordinal)) {
        $Content += "`n"
    }
    Write-Utf8File -Path $Path -Content $source.Insert($finalReturn.Index, $Content)
}

function New-FoundationFixture {
    $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('eggy-foundation-' + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LuaSource_云上同行') -Destination (Join-Path $fixture 'LuaSource_云上同行') -Recurse
    return $fixture
}

function Remove-FoundationFixture {
    param([string]$Path)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove non-temporary fixture: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Invoke-FoundationVerifier {
    param([string]$Root)
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifierPath -Root $Root -EggyApiPath $EggyApiPath 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output -join [Environment]::NewLine)
    }
}

function Assert-Pass {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
        Write-Output "[PASS] $Name"
    } catch {
        $failures.Add("${Name}: $($_.Exception.Message)")
        Write-Output "[FAIL] ${Name}: $($_.Exception.Message)"
    }
}

function Assert-RejectedMutation {
    param(
        [string]$Name,
        [scriptblock]$Mutate,
        [string]$ExpectedPattern
    )

    $fixture = New-FoundationFixture
    try {
        & $Mutate $fixture
        $result = Invoke-FoundationVerifier -Root $fixture
        if ($result.ExitCode -eq 0) {
            throw 'Verifier accepted an invalid fixture.'
        }
        if ($result.Output -notmatch $ExpectedPattern) {
            throw "Expected diagnostic '$ExpectedPattern'. Output: $($result.Output)"
        }
    } finally {
        Remove-FoundationFixture -Path $fixture
    }
}

function Assert-AcceptedMutation {
    param(
        [string]$Name,
        [scriptblock]$Mutate
    )

    $fixture = New-FoundationFixture
    try {
        & $Mutate $fixture
        $result = Invoke-FoundationVerifier -Root $fixture
        if ($result.ExitCode -ne 0) {
            throw "Verifier rejected valid fixture '$Name'. Output: $($result.Output)"
        }
    } finally {
        Remove-FoundationFixture -Path $fixture
    }
}

Assert-Pass 'accepts the complete repository fixture' {
    $result = Invoke-FoundationVerifier -Root $repoRoot
    if ($result.ExitCode -ne 0) { throw $result.Output }
}

$requiredFiles = @(
    'LuaSource_云上同行/main.lua',
    'LuaSource_云上同行/adapters/u5_log.lua',
    'LuaSource_云上同行/adapters/u5_event.lua',
    'LuaSource_云上同行/core/logger.lua',
    'LuaSource_云上同行/core/event_bus.lua',
    'LuaSource_云上同行/core/object_registry.lua',
    'LuaSource_云上同行/core/game_flow.lua',
    'LuaSource_云上同行/config/events.lua',
    'LuaSource_云上同行/config/objects.lua'
)

foreach ($relativePath in $requiredFiles) {
    Assert-Pass "rejects missing $relativePath" {
        Assert-RejectedMutation -Name $relativePath -ExpectedPattern '\[missing-file\]' -Mutate {
            param($fixture)
            Remove-Item -LiteralPath (Join-Path $fixture $relativePath)
        }
    }
}

Assert-Pass 'rejects forbidden sandbox libraries' {
    Assert-RejectedMutation -Name 'forbidden library' -ExpectedPattern '\[forbidden-runtime\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\core\logger.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = io.open`n"
    }
}

Assert-Pass 'rejects unresolved require targets' {
    Assert-RejectedMutation -Name 'invalid require' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = require(`"outside.module`")`n"
    }
}

Assert-Pass 'rejects bare unresolved require targets' {
    Assert-RejectedMutation -Name 'bare invalid require' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = require `"outside.module`"`n"
    }
}

Assert-Pass 'rejects require aliases' {
    Assert-RejectedMutation -Name 'require alias' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local loader = require`nlocal leaked = loader(`"outside.module`")`n"
    }
}

Assert-Pass 'rejects bare dynamic loading' {
    Assert-RejectedMutation -Name 'bare dynamic load' -ExpectedPattern '\[forbidden-runtime\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\core\logger.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = load `"return 1`"`n"
    }
}

Assert-Pass 'does not let a closed long comment hide executable code' {
    Assert-RejectedMutation -Name 'long comment bypass' -ExpectedPattern '\[forbidden-runtime\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\core\logger.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "--[=[说明]=] local leaked = io.open(`"x`")`n"
    }
}

Assert-Pass 'accepts platform and loader names inside strings and long comments' {
    Assert-AcceptedMutation -Name 'lexical masking' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\core\logger.lua'
        $content = "local note = [=[LuaAPI EVENT io load require `"outside.module`"]=]`n"
        $content += "--[==[ LuaAPI EVENT os dofile require(`"outside.module`") ]==]`n"
        $content += "local quoted = `"require('outside.module') LuaAPI package debug`"`n"
        Add-LuaBeforeFinalReturn -Path $path -Content $content
    }
}

Assert-Pass 'rejects platform globals outside adapters' {
    Assert-RejectedMutation -Name 'platform leak' -ExpectedPattern '\[platform-boundary\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = LuaAPI.log`n"
    }
}

Assert-Pass 'rejects global-event APIs in the logging adapter' {
    Assert-RejectedMutation -Name 'adapter ownership leak' -ExpectedPattern '\[platform-boundary\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\adapters\u5_log.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = LuaAPI.global_register_trigger_event`n"
    }
}

Assert-Pass 'rejects nonempty object configuration' {
    Assert-RejectedMutation -Name 'object id' -ExpectedPattern '\[objects-empty\]' -Mutate {
        param($fixture)
        Write-Utf8File -Path (Join-Path $fixture 'LuaSource_云上同行\config\objects.lua') -Content "return { THING = 123 }`n"
    }
}

Assert-Pass 'rejects missing lifecycle members' {
    Assert-RejectedMutation -Name 'missing dispose' -ExpectedPattern '\[lifecycle\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\core\logger.lua'
        $content = [System.IO.File]::ReadAllText($path, $utf8).Replace('function logger.dispose()', 'function logger.removed_dispose()')
        Write-Utf8File -Path $path -Content $content
    }
}

Assert-Pass 'rejects unresolved verification markers' {
    Assert-RejectedMutation -Name 'verification marker' -ExpectedPattern '\[verification-marker\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\core\logger.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "-- TODO_VERIFY：此故障注入必须被拒绝。`n"
    }
}

Assert-Pass 'rejects custom event literals outside config' {
    Assert-RejectedMutation -Name 'event literal' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = `"CLOUD_JOURNEY.UNKNOWN`"`n"
    }
}

Assert-Pass 'rejects event keys absent from central configuration' {
    Assert-RejectedMutation -Name 'missing event key' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\config\events.lua'
        $content = [System.IO.File]::ReadAllText($path, $utf8).Replace('CORE_READY', 'RENAMED_READY')
        Write-Utf8File -Path $path -Content $content
    }
}

Assert-Pass 'rejects trailing whitespace' {
    Assert-RejectedMutation -Name 'trailing whitespace' -ExpectedPattern '\[whitespace\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\core\logger.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local trailing = true `n"
    }
}

Assert-Pass 'rejects a missing final newline' {
    Assert-RejectedMutation -Name 'missing final newline' -ExpectedPattern '\[whitespace\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\core\logger.lua'
        $content = [System.IO.File]::ReadAllText($path, $utf8).TrimEnd([char[]]@("`r", "`n"))
        Write-Utf8File -Path $path -Content $content
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Output "[FAIL] $failure" }
    exit 1
}

Write-Output '[PASS] verifier mutation suite'
exit 0
```

- [ ] **Step 2: Run the verifier RED test**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\static\verify-foundation.tests.ps1
```

Expected: exit `1`, with the positive case reporting that `tools/verify-foundation.ps1` cannot be found.

- [ ] **Step 3: Implement the exact verifier**

Create `tools/verify-foundation.ps1`:

```powershell
param(
    [string]$Root = (Get-Location).Path,
    [string]$EggyApiPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$failures = [System.Collections.Generic.List[string]]::new()
$luaLexicalPattern = '(?ms)--\[(?<commentEquals>=*)\[.*?\]\k<commentEquals>\]|--[^\r\n]*|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|\[(?<stringEquals>=*)\[.*?\]\k<stringEquals>\]'
if ([string]::IsNullOrWhiteSpace($EggyApiPath)) {
    $EggyApiPath = Join-Path $rootPath 'LuaSource_云上同行\EggyAPI.lua'
}

function Add-Failure {
    param([string]$Category, [string]$Message)
    $failures.Add("[$Category] $Message")
}

function Read-Utf8File {
    param([string]$Path)
    try {
        return [System.IO.File]::ReadAllText($Path, $utf8)
    } catch {
        Add-Failure -Category 'utf8' -Message "${Path}: $($_.Exception.Message)"
        return ''
    }
}

function Normalize-RelativePath {
    param([string]$Path)
    return $Path.Substring($rootPath.Length).TrimStart('\', '/').Replace('\', '/')
}

function Replace-LuaLexicalTokens {
    param(
        [string]$Text,
        [bool]$RemoveStrings
    )

    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $isComment = $match.Value.StartsWith('--', [System.StringComparison]::Ordinal)
        $isString = -not $isComment
        if ($isComment -or ($RemoveStrings -and $isString)) {
            return [System.String]::new([char]32, $match.Length)
        }
        return $match.Value
    }
    return [regex]::Replace($Text, $luaLexicalPattern, $evaluator)
}

function Get-LuaRequireView {
    param([string]$Text)

    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        if ($match.Value.StartsWith('--', [System.StringComparison]::Ordinal)) {
            return [System.String]::new([char]32, $match.Length)
        }

        $prefix = $Text.Substring(0, $match.Index)
        $prefixCode = Replace-LuaLexicalTokens -Text $prefix -RemoveStrings $true
        if ($prefixCode -match '\brequire\s*(?:\(\s*)?$') {
            return $match.Value
        }
        return [System.String]::new([char]32, $match.Length)
    }
    return [regex]::Replace($Text, $luaLexicalPattern, $evaluator)
}

$requiredFiles = @(
    'LuaSource_云上同行/main.lua',
    'LuaSource_云上同行/adapters/u5_log.lua',
    'LuaSource_云上同行/adapters/u5_event.lua',
    'LuaSource_云上同行/core/logger.lua',
    'LuaSource_云上同行/core/event_bus.lua',
    'LuaSource_云上同行/core/object_registry.lua',
    'LuaSource_云上同行/core/game_flow.lua',
    'LuaSource_云上同行/config/events.lua',
    'LuaSource_云上同行/config/objects.lua'
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $rootPath $relativePath) -PathType Leaf)) {
        Add-Failure -Category 'missing-file' -Message $relativePath
    }
}

$runtimeRoot = Join-Path $rootPath 'LuaSource_云上同行'
$luaFiles = @()
if (Test-Path -LiteralPath $runtimeRoot -PathType Container) {
    $generatedLuaEvidence = @(
        (Join-Path $runtimeRoot 'EggyAPI.lua'),
        (Join-Path $runtimeRoot 'EggyEditorAPI.lua'),
        (Join-Path $runtimeRoot 'DebugTools.lua')
    )
    $luaFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File -Filter '*.lua' | Where-Object {
        $generatedLuaEvidence -notcontains $_.FullName
    })
}

$forbiddenPatterns = @(
    '\bio\b',
    '\bos\b',
    '\bpackage\b',
    '\bdebug\b',
    '\b(?:LuaSocket|socket)\b',
    '\bload\b',
    '\bloadfile\b',
    '\bdofile\b'
)

foreach ($file in $luaFiles) {
    $relativePath = Normalize-RelativePath -Path $file.FullName
    $raw = Read-Utf8File -Path $file.FullName
    $withoutComments = Replace-LuaLexicalTokens -Text $raw -RemoveStrings $false
    $codeOnly = Replace-LuaLexicalTokens -Text $raw -RemoveStrings $true
    $requireView = Get-LuaRequireView -Text $raw

    foreach ($pattern in $forbiddenPatterns) {
        if ($codeOnly -match $pattern) {
            Add-Failure -Category 'forbidden-runtime' -Message "$relativePath matches $pattern"
        }
    }

    if (-not $relativePath.StartsWith('LuaSource_云上同行/adapters/', [System.StringComparison]::Ordinal)) {
        if ($codeOnly -match '\bLuaAPI\b|\bEVENT\b') {
            Add-Failure -Category 'platform-boundary' -Message $relativePath
        }
    }

    if ($raw.IndexOf('TODO_VERIFY', [System.StringComparison]::Ordinal) -ge 0) {
        Add-Failure -Category 'verification-marker' -Message $relativePath
    }

    $allRequireCalls = [regex]::Matches($codeOnly, '\brequire\b')
    $literalRequires = [regex]::Matches(
        $requireView,
        '\brequire\s*(?:\(\s*["'']([A-Za-z0-9_.]+)["'']\s*\)|["'']([A-Za-z0-9_.]+)["''])'
    )
    if ($allRequireCalls.Count -ne $literalRequires.Count) {
        Add-Failure -Category 'require-target' -Message "$relativePath contains a computed or malformed require"
    }
    foreach ($requireMatch in $literalRequires) {
        $target = $requireMatch.Groups[1].Value
        if ($target -eq '') {
            $target = $requireMatch.Groups[2].Value
        }
        $targetPath = Join-Path $runtimeRoot ($target.Replace('.', '\') + '.lua')
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            Add-Failure -Category 'require-target' -Message "$relativePath -> $target"
        }
    }

    if ($relativePath -ne 'LuaSource_云上同行/config/events.lua' -and $withoutComments -match 'CLOUD_JOURNEY\.[A-Z0-9_.]+') {
        Add-Failure -Category 'event-centralization' -Message $relativePath
    }

    if ($raw -match '(?m)[ \t]+(?=\r?$)' -or (-not $raw.EndsWith("`n", [System.StringComparison]::Ordinal))) {
        Add-Failure -Category 'whitespace' -Message $relativePath
    }
}

$lifecycleModules = @{
    'LuaSource_云上同行/main.lua' = 'app'
    'LuaSource_云上同行/adapters/u5_log.lua' = 'u5_log'
    'LuaSource_云上同行/adapters/u5_event.lua' = 'u5_event'
    'LuaSource_云上同行/core/logger.lua' = 'logger'
    'LuaSource_云上同行/core/event_bus.lua' = 'event_bus'
    'LuaSource_云上同行/core/object_registry.lua' = 'object_registry'
    'LuaSource_云上同行/core/game_flow.lua' = 'game_flow'
}

foreach ($entry in $lifecycleModules.GetEnumerator()) {
    $path = Join-Path $rootPath $entry.Key
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $content = Replace-LuaLexicalTokens -Text (Read-Utf8File -Path $path) -RemoveStrings $true
        if ($content -notmatch ("function\s+" + [regex]::Escape($entry.Value) + '\.init\s*\(')) {
            Add-Failure -Category 'lifecycle' -Message "$($entry.Key) missing init"
        }
        if ($content -notmatch ("function\s+" + [regex]::Escape($entry.Value) + '\.dispose\s*\(')) {
            Add-Failure -Category 'lifecycle' -Message "$($entry.Key) missing dispose"
        }
    }
}

$objectsPath = Join-Path $runtimeRoot 'config\objects.lua'
if (Test-Path -LiteralPath $objectsPath -PathType Leaf) {
    $objectsCode = Replace-LuaLexicalTokens -Text (Read-Utf8File -Path $objectsPath) -RemoveStrings $false
    $objectsCode = [regex]::Replace($objectsCode, '\s+', '')
    if ($objectsCode -ne 'return{}') {
        Add-Failure -Category 'objects-empty' -Message 'LuaSource_云上同行/config/objects.lua must return only an empty table'
    }
}

$eventsPath = Join-Path $runtimeRoot 'config\events.lua'
$definedEventKeys = @{}
if (Test-Path -LiteralPath $eventsPath -PathType Leaf) {
    $eventsCode = Replace-LuaLexicalTokens -Text (Read-Utf8File -Path $eventsPath) -RemoveStrings $false
    $eventDefinitions = [regex]::Matches($eventsCode, '([A-Z][A-Z0-9_]*)\s*=\s*"(CLOUD_JOURNEY\.[A-Z0-9_.]+)"')
    foreach ($definition in $eventDefinitions) {
        $definedEventKeys[$definition.Groups[1].Value] = $definition.Groups[2].Value
    }
    if ($definedEventKeys.Count -ne 1 -or $definedEventKeys['CORE_READY'] -ne 'CLOUD_JOURNEY.CORE_READY') {
        Add-Failure -Category 'event-centralization' -Message 'config/events.lua must define only CORE_READY'
    }
}

foreach ($file in $luaFiles) {
    $relativePath = Normalize-RelativePath -Path $file.FullName
    if ($relativePath -ne 'LuaSource_云上同行/config/events.lua') {
        $code = Replace-LuaLexicalTokens -Text (Read-Utf8File -Path $file.FullName) -RemoveStrings $true
        foreach ($eventUse in [regex]::Matches($code, '\bevents\.([A-Z][A-Z0-9_]*)\b')) {
            if (-not $definedEventKeys.ContainsKey($eventUse.Groups[1].Value)) {
                Add-Failure -Category 'event-centralization' -Message "$relativePath uses events.$($eventUse.Groups[1].Value)"
            }
        }
    }
}

$logOwners = @($luaFiles | Where-Object {
    (Replace-LuaLexicalTokens -Text (Read-Utf8File -Path $_.FullName) -RemoveStrings $true) -match '\bLuaAPI\.log\b'
})
if ($logOwners.Count -ne 1 -or (Normalize-RelativePath -Path $logOwners[0].FullName) -ne 'LuaSource_云上同行/adapters/u5_log.lua') {
    Add-Failure -Category 'platform-boundary' -Message 'LuaAPI.log must appear only in LuaSource_云上同行/adapters/u5_log.lua'
}

$eventOwners = @($luaFiles | Where-Object {
    (Replace-LuaLexicalTokens -Text (Read-Utf8File -Path $_.FullName) -RemoveStrings $true) -match '\bEVENT\b|\bLuaAPI\.global_(?:register|unregister)_trigger_event\b'
})
if ($eventOwners.Count -ne 1 -or (Normalize-RelativePath -Path $eventOwners[0].FullName) -ne 'LuaSource_云上同行/adapters/u5_event.lua') {
    Add-Failure -Category 'platform-boundary' -Message 'EVENT and global trigger APIs must appear only in LuaSource_云上同行/adapters/u5_event.lua'
}

if ([string]::IsNullOrWhiteSpace($EggyApiPath) -or -not (Test-Path -LiteralPath $EggyApiPath -PathType Leaf)) {
    Add-Failure -Category 'api-export' -Message "Current Eggitor EggyAPI.lua export not found: $EggyApiPath"
} else {
    $apiText = Read-Utf8File -Path $EggyApiPath
    foreach ($symbol in @(
        'LuaAPI.log',
        'LuaAPI.global_register_trigger_event',
        'LuaAPI.global_unregister_trigger_event',
        'EVENT.GAME_INIT',
        'EVENT.GAME_END'
    )) {
        if ($apiText.IndexOf($symbol, [System.StringComparison]::Ordinal) -lt 0) {
            Add-Failure -Category 'api-export' -Message "Current export is missing $symbol"
        }
    }
    foreach ($signature in @(
        '---@param _event_desc any\[\]',
        '---@param _callback function',
        '---@return integer',
        'function LuaAPI\.global_register_trigger_event\(_event_desc, _callback\)',
        '---@param _id integer',
        'function LuaAPI\.global_unregister_trigger_event\(_id\)',
        '---@param _content string',
        '---@param _log_level integer\?',
        'function LuaAPI\.log\(_content, _log_level\)'
    )) {
        if ($apiText -notmatch $signature) {
            Add-Failure -Category 'api-export' -Message "Current export does not match signature evidence: $signature"
        }
    }
}

if (Test-Path -LiteralPath (Join-Path $rootPath '.git') -PathType Container) {
    $unstagedWhitespace = & git -C $rootPath diff --check -- 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-Failure -Category 'whitespace' -Message ($unstagedWhitespace -join '; ')
    }
    $stagedWhitespace = & git -C $rootPath diff --cached --check -- 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-Failure -Category 'whitespace' -Message ($stagedWhitespace -join '; ')
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Output $failure }
    exit 1
}

Write-Output '[PASS] foundation static verification'
exit 0
```

- [ ] **Step 4: Run the verifier GREEN tests**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\static\verify-foundation.tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-foundation.ps1 -Root (Resolve-Path .)
```

Expected: both commands exit `0`; the first ends with `[PASS] verifier mutation suite`, and the second prints `[PASS] foundation static verification`.

- [ ] **Step 5: Run every Lua behavior test when a compatible runner exists**

Run:

```powershell
$lua = Get-Command lua54,lua -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $lua) {
    Write-Output '[NOT-RUN] Compatible standalone Lua 5.4 runner unavailable.'
} else {
    $version = & $lua.Source -v 2>&1
    if ("$version" -notmatch 'Lua 5\.4') { throw "Lua 5.4 required; found $version" }
    $testFiles = @(Get-ChildItem -LiteralPath tests\lua -Recurse -File -Filter '*_test.lua' | Sort-Object FullName)
    foreach ($testFile in $testFiles) {
        & $lua.Source $testFile.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua test failed: $($testFile.FullName)" }
    }
}
```

Expected in the current environment: one explicit `[NOT-RUN]` line. Do not convert that into PASS. If Lua 5.4 is installed later, every test must print only `[PASS]` cases and exit `0`; this still does not replace the editor checks.

- [ ] **Step 6: Commit and push the verifier slice**

Run:

```powershell
git status --short --branch
git add -- tests/static/verify-foundation.tests.ps1 tools/verify-foundation.ps1
git diff --cached --name-status
git diff --cached
git diff --cached --check
@'
Make foundation source constraints reproducibly verifiable

Constraint: The workstation has PowerShell 5.1 but no compatible standalone Lua runner
Rejected: Treat regex checks as runtime proof | static contracts cannot establish sandbox behavior
Confidence: high
Scope-risk: moderate
Directive: Keep negative verifier fixtures isolated and require current EggyAPI.lua evidence
Tested: Verifier positive fixture; missing-file mutations; forbidden runtime; parenthesized/bare/aliased require rejection; long-bracket lexical masking; platform boundary; empty objects; lifecycle; marker; event centralization; whitespace; staged diff inspection
Not-tested: Lua behavioral suite when runner unavailable; Eggitor synchronization; editor runtime integration
'@ | git commit -F -
if ($LASTEXITCODE -ne 0) { throw 'git commit failed; nothing was pushed.' }
git push origin main
if ($LASTEXITCODE -ne 0) {
    git fetch origin
    git status --short --branch
    git log --oneline --left-right --graph HEAD...origin/main
    throw 'Push rejected. Local commit preserved; reconcile with origin/main without force-pushing.'
}
git fetch origin
if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) { throw 'Local HEAD and origin/main differ.' }
git status --short --branch
```

Expected: the commit contains only the verifier and its mutation suite; local and remote SHAs match.

### Task 9: Perform final static and editor acceptance

**Files:**
- Inspect: all Task 1-8 paths
- Temporarily create, run, and delete: `LuaSource_云上同行/tests/foundation_editor_harness.lua`
- Do not create permanent profiling or developer-mode files
- Do not commit if editor acceptance exposes a failure

- [ ] **Step 1: Re-run repository acceptance from a clean branch**

Run:

```powershell
git status --short --branch
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\static\verify-foundation.tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-foundation.ps1 -Root (Resolve-Path .)
git diff --check
git diff --cached --check
```

Expected: branch `main`, no changed paths, both verification commands PASS, and no whitespace output.

- [ ] **Step 2: Add and synchronize the exact temporary editor harness**

Use `apply_patch` to create `LuaSource_云上同行/tests/foundation_editor_harness.lua` with this exact content:

```lua
local app = require("main")
local logger = require("core.logger")
local event_bus = require("core.event_bus")
local object_registry = require("core.object_registry")
local game_flow = require("core.game_flow")
local events = require("config.events")

local harness = {}
local app_disposal_complete = false

local function expect(condition, message)
    if not condition then
        error("[FOUNDATION_EDITOR_TEST][FAIL] " .. message)
    end
end

local function expect_sequence(actual, expected, message)
    expect(#actual == #expected, message .. " length")
    for index, value in ipairs(expected) do
        expect(actual[index] == value, message .. " index " .. tostring(index))
    end
end

local function run_cases()
    app_disposal_complete = false
    expect(app.init(), "repeated app.init first call")
    expect(app.init(), "repeated app.init second call")
    app_disposal_complete = app.dispose()
    expect(app_disposal_complete, "app.dispose before isolated cases")
    app_disposal_complete = app.dispose()
    expect(app_disposal_complete, "repeated completed app.dispose")

    local event_errors = {}
    local event_logger = {
        error = function(source, message)
            event_errors[#event_errors + 1] = source .. ":" .. message
            return true
        end,
    }

    -- 失败订阅者不得阻止后续订阅者执行。
    expect(event_bus.init(event_logger), "event_bus init for failure case")
    local later_handler_runs = 0
    event_bus.subscribe(events.CORE_READY, function()
        error("expected handler failure")
    end)
    event_bus.subscribe(events.CORE_READY, function()
        later_handler_runs = later_handler_runs + 1
    end)
    expect(not event_bus.publish(events.CORE_READY, nil), "failure publish result")
    expect(later_handler_runs == 1, "later handler continuation")
    expect(#event_errors == 1, "handler failure diagnostic")
    expect(event_bus.dispose(), "event_bus dispose after failure case")

    -- 派发快照保留本轮处理器，取消订阅只影响下一轮。
    event_errors = {}
    event_logger = {
        error = function(source, message)
            event_errors[#event_errors + 1] = source .. ":" .. message
            return true
        end,
    }
    expect(event_bus.init(event_logger), "event_bus init for snapshot case")
    local snapshot_calls = {}
    local second_id = nil
    event_bus.subscribe(events.CORE_READY, function()
        snapshot_calls[#snapshot_calls + 1] = "first"
        event_bus.unsubscribe(second_id)
    end)
    second_id = event_bus.subscribe(events.CORE_READY, function()
        snapshot_calls[#snapshot_calls + 1] = "second"
    end)
    expect(event_bus.publish(events.CORE_READY, nil), "first snapshot publish")
    expect_sequence(snapshot_calls, { "first", "second" }, "current snapshot")
    snapshot_calls = {}
    expect(event_bus.publish(events.CORE_READY, nil), "second snapshot publish")
    expect_sequence(snapshot_calls, { "first" }, "next snapshot")
    expect(event_bus.dispose(), "event_bus dispose after snapshot case")

    local warnings = {}
    local registry_logger = {
        warn = function(source, message)
            warnings[#warnings + 1] = source .. ":" .. message
            return true
        end,
    }
    expect(object_registry.init({}, registry_logger), "object_registry init")
    expect(object_registry.get("HARNESS_MISSING") == nil, "first missing object")
    expect(object_registry.get("HARNESS_MISSING") == nil, "second missing object")
    expect(#warnings == 1, "missing object warning once")
    expect(object_registry.dispose(), "object_registry dispose")

    local publish_count = 0
    local ready_log_count = 0
    local flow_dependencies = {
        logger = {
            info = function()
                ready_log_count = ready_log_count + 1
                return true
            end,
        },
        eventBus = {
            publish = function(event_name, payload)
                expect(event_name == events.CORE_READY, "central ready event")
                expect(payload == nil, "ready payload")
                publish_count = publish_count + 1
                return true
            end,
        },
        events = events,
    }
    expect(game_flow.init(flow_dependencies), "game_flow init")
    expect(game_flow.start(), "game_flow first start")
    expect(not game_flow.start(), "game_flow repeated start")
    expect(game_flow.get_state() == "READY", "game_flow ready state")
    expect(publish_count == 1, "ready publish once")
    expect(ready_log_count == 1, "ready log once")
    expect(game_flow.dispose(), "game_flow dispose")
end

function harness.run()
    local succeeded, failure = pcall(run_cases)

    -- 平台清理未完成时只能重试 app.dispose，不能绕过应用直接释放依赖。
    if not app_disposal_complete then
        app_disposal_complete = app.dispose()
        if not app_disposal_complete then
            logger.error("FoundationEditorTest", tostring(failure))
            error(failure)
        end
    end

    -- 应用已完整释放后，清理可能由测试占用的隔离模块并恢复真实生命周期。
    game_flow.dispose()
    object_registry.dispose()
    event_bus.dispose()
    local restored = app.init()
    local repeated_init = restored and app.init()

    if not succeeded then
        if restored then
            logger.error("FoundationEditorTest", tostring(failure))
        end
        error(failure)
    end

    expect(restored, "app reinitialize after completed dispose")
    expect(repeated_init, "app repeated init after restore")
    expect(
        logger.info("FoundationEditorTest", "[FOUNDATION_EDITOR_TEST][PASS] all cases"),
        "PASS evidence log"
    )
    return true
end

return harness
```

Keep the PC editor, connected Eggitor panel, and VS Code workspace open. Save all Task 1-8 files plus the temporary harness and wait for every synchronization message.

Expected: Eggitor reports successful file synchronization with no Lua compilation error. `git status --short` shows only `?? LuaSource_云上同行/tests/foundation_editor_harness.lua`.

- [ ] **Step 3: Run the first editor lifecycle pass**

Start the map through Eggitor/PC editor and observe the Eggitor console. Keep the map running through Step 4.

Expected evidence:

- no compilation, Trace, or API parameter error;
- exactly one `[INFO][GameFlow] 基础模块已就绪` line for the run;
- no platform-event registration error appears before the harness runs.

- [ ] **Step 4: Exercise the specified behavior matrix with temporary editor-only instrumentation**

In the documented Eggitor console's command input, execute exactly:

```lua
require("tests.foundation_editor_harness").run()
```

The temporary harness uses only production modules in the physical `LuaSource_云上同行/` root (the logical `script/` namespace) and sandbox-available Lua primitives; it does not use desktop-only `package`, replace U5 globals, or invent a platform API.

Expected:

- repeated init returns `true` only for the same configured lifetime;
- readiness publishes once;
- later subscribers still run after one handler fails;
- a subscription removed during dispatch runs in the current snapshot but not the next publish;
- the same missing key logs once per registry lifetime;
- repeated completed dispose returns `true`;
- reinitialization succeeds after completed disposal; and
- the console contains exactly `[FOUNDATION_EDITOR_TEST][PASS] all cases` within the `FoundationEditorTest` log line, with no harness FAIL, compilation, Trace, or parameter error.

Stop the map normally. Confirm that `GAME_END` cleanup produces no Lua error from `global_unregister_trigger_event`. The absence of a Lua error proves only that each protected unregister call completed; it does not invent a platform-side success return that the API does not provide.

Keep the harness synchronized for the second run. The desktop-only `u5_event` test is the exact forced-unregister-failure coverage. Do not mutate cached U5 functions inside the editor to simulate that failure. Any harness case that does not run or any missing PASS evidence prevents editor acceptance.

- [ ] **Step 5: Run a second consecutive editor lifecycle pass**

Start the map again without reloading or editing the Lua project. Confirm exactly one new readiness line, then execute the same console command again:

```lua
require("tests.foundation_editor_harness").run()
```

Expected: a second `[FOUNDATION_EDITOR_TEST][PASS] all cases` line, no duplicate registration behavior, and freshly isolated subscriber and object-warning counts. Stop the map normally and confirm cleanup again produces no Lua error.

Use `apply_patch` to delete `LuaSource_云上同行/tests/foundation_editor_harness.lua`, wait for Eggitor to synchronize the deletion, then run:

```powershell
if (Test-Path -LiteralPath .\LuaSource_云上同行\tests\foundation_editor_harness.lua) {
    throw 'Temporary editor harness still exists.'
}
git status --short --branch
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-foundation.ps1 -Root (Resolve-Path .)
```

Expected: the temporary file is absent, the worktree is clean, and the verifier passes.

The cleanup-pending retry remains the desktop-only `u5_event` case because safely forcing a cached platform function to fail is not part of the documented editor surface. If no compatible Lua 5.4 runner is available, report that exact case under `Not-tested`; editor acceptance may be reported separately, but the foundation must not be described as fully behavior-verified until the case passes.

- [ ] **Step 6: Confirm final Git and remote state**

Run:

```powershell
git status --short --branch
git fetch origin
$localSha = git rev-parse HEAD
$remoteSha = git rev-parse origin/main
if ($localSha -ne $remoteSha) { throw "Remote mismatch: local=$localSha remote=$remoteSha" }
git log -1 --format='%H%n%s%n%b'
```

Expected: clean `main`, identical SHAs, and the Task 8 Lore commit at the tip. Task 9 creates no commit because it changes no repository file.

## Completion Report Contract

Report:

- every changed file grouped by Task 1-8;
- static verifier and mutation-suite results;
- Lua behavior result as PASS or explicit `[NOT-RUN]`;
- Eggitor synchronization, compilation, Trace, parameter, event, cleanup, and two-run evidence;
- each task commit SHA and confirmation that it reached `origin/main`;
- every remaining unavailable check under `Not-tested`.

If the editor steps have not run, the report must include exactly:

```text
Not-tested: Eggitor synchronization and editor runtime integration.
```

Do not describe the foundation as editor-verified until Task 9 passes.
