# Foundation Module Design

Status: Approved
Project: Cloud Journey (`云上同行`)
Date: 2026-08-02

## Goal

Create the smallest reusable Lua foundation for the map before implementing pair logic, checkpoints, UI, lighting, or chapter gameplay. The module must use only capabilities documented by the current NetEase Workshop Manual, keep every platform call inside an adapter, and contain no fabricated map data.

The accepted approach is a strict foundation-first slice. Combining pair gameplay with the foundation was rejected because it would mix platform bootstrapping with unresolved player-role behavior. Building the Windmill Island vertical slice first was rejected because scene, UI, and preset identifiers are not available yet.

## Official Platform Basis

The implementation may rely on these currently documented capabilities:

- the [Lua 5.4 sandbox and `script/` module rules](https://u5.gsf.netease.com/eggy_manual_3068736/pc_md/lua/lua_environment.html);
- the [Eggitor project, synchronization, API export, and map-data workflow](https://u5.gsf.netease.com/eggy_manual_3068736/pc_md/lua/lua_eggitor.html);
- the [Lua quick-start event and module examples](https://u5.gsf.netease.com/eggy_manual_3068736/pc_md/lua/lua_quickstart.html);
- the [current API guide](https://u5.gsf.netease.com/eggy_manual_3068736/pc_md/lua/lua_api_structure.html); and
- the [current generated API reference](https://u5.gsf.netease.com/eggy_manual_3068736/pc_md/lua/EggyAPI.html).

The manual explicitly documents `EVENT.GAME_INIT`, `EVENT.GAME_END`, `LuaAPI.global_register_trigger_event`, `LuaAPI.global_unregister_trigger_event`, and `LuaAPI.log`. These are the only platform surfaces required by this module.

The connected Eggitor project and its current `EggyAPI.lua` export are runtime-implementation prerequisites. This design may be completed before they exist, but platform-facing Lua must not be reported as version-matched or editor-ready until the export is present and reconciled. If the export conflicts with the manual, the affected adapter call must be marked `TODO_VERIFY` and excluded from editor-verified completion until resolved.

## Scope and Boundaries

The module will add:

- a minimal `script/main.lua` application entry point;
- logging and global-event adapters;
- a platform-independent logger, event bus, object registry, and game-flow state holder;
- central event and object configuration files; and
- a repository-local static verification script.

The module will not add:

- player discovery, PlayerA/PlayerB assignment, pair sessions, or disconnect behavior;
- checkpoints, respawning, hints, UI, lighting, camera, archives, cooperation mechanics, or chapter modules;
- scene queries or any real object, UI, preset, archive, achievement, or skill identifier;
- external Lua libraries, developer-mode dependencies, or a desktop-Lua runtime assumption.

## Component Contracts

### Uniform initialization contract

Every `init()` function in this module returns a boolean and validates all inputs before mutating state. On the first valid call it enters the initialized state and returns `true`. While already initialized, a repeated call returns `true` only when it supplies the same dependency and configuration table instances; a call with different or invalid inputs returns `false` without changing existing state. After completed disposal, a valid `init()` call resets module-lifetime state and returns `true`. While cleanup is pending, `init()` returns `false` and only `dispose()` may make progress.

`u5_log.init()` has no injected dependency; it returns `true` when `LuaAPI.log` is callable, returns `true` on repeated initialized calls, and returns `false` without changing state when that platform function is unavailable. For the other modules, required inputs are exactly those shown in their signatures: `u5_event` requires a logger; `logger` requires a backend; `event_bus` requires a logger; `object_registry` requires an entries table and logger; and `game_flow` requires its documented dependency table.

Except for `app.dispose()` and `u5_event.dispose()`, which report pending event cleanup, every module's `dispose()` returns `true` after clearing its owned state and also returns `true` when called before initialization or after completed disposal.

### Application entry point

`script/main.lua` owns assembly only. It creates one application instance, calls `app.init()` exactly once during file load, records the returned status, and then returns the application table. `main.lua` does not continue into gameplay startup after a `false` result. A failed initialization whose cleanup completes enters `DISPOSED` and may be retried with `app.init()`. A failed cleanup enters `DISPOSING`; in that state only repeated `app.dispose()` calls are accepted until cleanup completes.

Public surface:

```lua
app.init()
app.dispose()
```

`app.init()` is idempotent within one loaded module instance. It returns `true` after a successful first initialization and on repeated calls while initialized. It initializes the logging adapter, logger, event bus, object registry, game flow, and event adapter, then registers `GAME_INIT` and `GAME_END`. It must not query or mutate game-time objects.

`app.init()` checks the boolean result of every dependency initialization and both lifecycle registrations. On any failure, it disposes only the dependencies that completed initialization, in reverse order. Completed cleanup leaves the application `DISPOSED`, returns `false`, and permits a later clean retry. If event cleanup cannot unregister an owned handle without a Lua error, the application remains `DISPOSING`, returns `false`, and permits only later `app.dispose()` retries.

On `GAME_INIT`, the callback starts `game_flow` exactly once and logs an error if the start notification fails. On `GAME_END`, the callback calls `app.dispose()`. Application states are `NEW`, `INITIALIZED`, `DISPOSING`, and `DISPOSED`. `app.init()` returns `false` while `DISPOSING`. Calling `app.dispose()` in `NEW` or `DISPOSED` returns `true`; in `NEW` it enters `DISPOSED` without initializing dependencies.

During active cleanup, `app.dispose()` first calls the event adapter's `dispose()`. If any owned handle remains, the application logs the failure, stays `DISPOSING`, returns `false`, and does not dispose the remaining dependencies so logging and retry state remain usable. Once event cleanup returns `true`, the application disposes game flow, object registry, event bus, logger, and the logging adapter in that order, enters `DISPOSED`, and returns `true`. After successful disposal, a later `app.init()` performs a clean reinitialization so consecutive runs in one loaded module instance are supported.

### Platform adapters

`script/adapters/u5_log.lua` is the only module that calls `LuaAPI.log`.

```lua
u5_log.init()
u5_log.write(level, source, message)
u5_log.dispose()
```

It emits a stable line format: `[LEVEL][Source] message`. Values are converted explicitly rather than relying on implicit string/number conversion. `write()` calls `LuaAPI.log` through `pcall`, never raises a logging error to its caller, and returns `true` only when the protected call completes without a Lua error. Before initialization and after disposal it returns `false`. Reinitialization after disposal is supported.

`script/adapters/u5_event.lua` is the only module that refers to `EVENT` values or trigger-registration APIs.

```lua
u5_event.init(logger)
u5_event.on_game_init(callback)
u5_event.on_game_end(callback)
u5_event.unregister(handle)
u5_event.dispose()
```

The adapter records every successful registration handle. `on_game_init()` and `on_game_end()` return a registration handle or `nil` on failure. Before initialization or while cleanup is pending they return `nil` without calling the platform.

`unregister()` returns `true` only when the handle is owned and the protected `LuaAPI.global_unregister_trigger_event` call completes without a Lua error. The official API does not provide platform-side success confirmation, so this result means only that the local protected call completed. A handle is removed from local ownership only in that case. Unknown handles return `false`; calls that raise a Lua error return `false` and remain tracked for retry and reporting.

`dispose()` attempts every tracked handle and returns `true` only when none remain. If any remain, the adapter stays cleanup-pending and later `dispose()` calls retry them. After successful disposal, `init()` may reinitialize the adapter.

### Logger

`script/core/logger.lua` contains no platform calls.

```lua
logger.init(backend)
logger.info(source, message)
logger.warn(source, message)
logger.error(source, message)
logger.dispose()
```

Logging before initialization or after disposal returns `false` without calling a backend. The logger accepts only a backend with `write(level, source, message)`. `info()`, `warn()`, and `error()` call the backend through `pcall`, never propagate a backend error, and return the backend's boolean result. It does not expose formatting choices to callers. `init()` after disposal is supported.

### Internal event bus

`script/core/event_bus.lua` is a synchronous, platform-independent bus.

```lua
event_bus.init(logger)
event_bus.subscribe(eventName, handler)
event_bus.unsubscribe(subscriptionId)
event_bus.publish(eventName, payload)
event_bus.dispose()
```

Before initialization and after disposal, `subscribe()` returns `nil`, `unsubscribe()` returns `false`, and `publish()` returns `false`. `init()` after disposal resets the bus and is supported.

Event names must be non-empty strings and handlers must be functions. `subscribe()` returns a numeric subscription ID or `nil` for invalid input. Subscription IDs are unique for the current bus lifetime. Handlers run in ascending subscription-ID order, which is registration order. `unsubscribe()` returns whether it removed an existing subscription. Publishing takes a snapshot of current subscribers so a handler may unsubscribe during dispatch without corrupting iteration. Each handler runs through `pcall`; one failure is logged and does not prevent later handlers from running. `publish()` returns `true` when there are zero subscribers and otherwise returns `true` only when every invoked handler succeeds.

### Object registry

`script/core/object_registry.lua` provides a stable logical-key boundary without querying the editor.

```lua
object_registry.init(entries, logger)
object_registry.has(logicalKey)
object_registry.get(logicalKey)
object_registry.dispose()
```

Before initialization and after disposal, `has()` returns `false` and `get()` returns `nil` without logging. `init()` after disposal resets the registry and is supported.

Keys must be non-empty strings. `init()` validates the complete input before mutating registry state, rejects a non-table configuration or any invalid key, and returns `false` without retaining partial entries. Otherwise it returns `true`. `has()` returns a boolean. `get()` returns the configured value or `nil` for an unknown key and logs one warning per missing key per registry lifetime. The initial `script/config/objects.lua` returns an empty table and contains no placeholder numeric IDs. Real values will be added only after they are copied or exported from the connected map and verified.

### Game flow

`script/core/game_flow.lua` owns only the foundation lifecycle state.

```lua
game_flow.init(dependencies)
game_flow.start()
game_flow.get_state()
game_flow.dispose()
```

The `dependencies` table must contain `logger`, `eventBus`, and `events`. States are `UNINITIALIZED`, `WAITING_GAME_INIT`, `READY`, and `DISPOSED`. Before initialization, `get_state()` returns `UNINITIALIZED` and `start()` returns `false`. `init()` validates all dependencies before changing state, enters `WAITING_GAME_INIT`, and returns whether initialization succeeded. `init()` after disposal resets the flow and is supported.

The first `start()` transitions to `READY`, publishes the internal event `CLOUD_JOURNEY.CORE_READY`, and logs readiness. The state remains `READY` even if a subscriber fails; in that case `start()` returns `false` to surface the failed notification. A successful publish returns `true`. Repeated or otherwise out-of-state `start()` calls return `false` and do not republish the event. `dispose()` enters `DISPOSED`, is idempotent, and leaves `get_state()` returning `DISPOSED`.

`script/config/events.lua` is the only source for `CLOUD_JOURNEY.CORE_READY`. This is a project-defined internal event, not an invented platform event.

## Runtime Flow

1. The editor loads `script/main.lua`, which constructs the application and calls `app.init()` exactly once.
2. `app.init()` assembles foundation modules without accessing game-time objects; `main.lua` records failure and does not start gameplay if initialization returns `false`.
3. The event adapter registers documented `GAME_INIT` and `GAME_END` callbacks.
4. `GAME_INIT` calls `game_flow.start()` once.
5. `game_flow` enters `READY`, emits `CLOUD_JOURNEY.CORE_READY`, and writes a readiness log.
6. `GAME_END` calls `app.dispose()`, which attempts to unregister platform events and clears other module-owned state in reverse order. Cleanup is reported as complete only when no locally owned registration handle remains.

No timer, Tick loop, scene lookup, UI lookup, or dynamic object creation occurs in this flow.

## Error and Lifecycle Rules

- Invalid public arguments fail safely, log a concise diagnostic when logging is available, and do not mutate module state.
- Initialization and disposal are idempotent for every module; initialization after completed disposal is supported and resets module-lifetime state.
- A failed platform registration is not stored as an active handle.
- Event registrations and unregister operations remain paired in the event adapter.
- No module may call another module's private state or refer directly to `LuaAPI` or `EVENT` outside `script/adapters/`.
- Code comments explain non-obvious intent and lifecycle ownership in Chinese; identifiers and APIs remain English.
- Before platform-facing Lua is implemented, the current `EggyAPI.lua` export must confirm the five manual-documented surfaces. A mismatch or unavailable version proof requires `TODO_VERIFY`; any additional platform call is out of scope unless it is documented and added to this design.

## Verification and Acceptance

The implementation will include `tools/verify-foundation.ps1`. It must fail when:

- a required foundation file is missing;
- runtime code references `io`, `os`, `package`, `debug`, LuaSocket, dynamic loading, or an invalid `require` target;
- `LuaAPI` or `EVENT` appears outside `script/adapters/`;
- during the empty foundation phase, `script/config/objects.lua` contains any object entry or numeric identifier;
- a foundation module omits its required `init()` or `dispose()` contract; or
- a runtime module contains an unresolved `TODO_VERIFY` marker or an event name that is not defined in `script/config/events.lua`; or
- whitespace checks fail.

When verified map object data is introduced in a later module, the empty-object rule must be replaced rather than bypassed: the verifier will then require every runtime object ID to match its evidence row in `data/object-registry.csv` and will reject drift or IDs outside `script/config/objects.lua`.

Static acceptance requires:

1. the verification script exits successfully;
2. full staged-diff inspection and `git diff --cached --check` pass;
3. no map-specific identifier or undocumented platform API exists; and
4. the connected Eggitor project and current `EggyAPI.lua` export have been inspected before any platform-facing Lua is committed; and
5. if no compatible Lua runner or editor session is available, the verification report explicitly lists behavioral execution as unavailable.

Editor acceptance, once the project is generated and connected, requires:

1. Eggitor reports successful synchronization;
2. the map starts without compilation, Trace, or parameter errors;
3. the console records exactly one foundation-ready transition per run;
4. `GAME_END` executes cleanup without a Lua error from the unregister calls; this does not claim platform-side confirmation beyond the documented API; and
5. repeat-init, repeat-start, handler-failure, unsubscribe-during-publish, missing-object, and repeat-dispose cases behave as specified; and
6. two consecutive editor runs do not retain duplicate registrations or stale state.

Until those editor checks run, delivery must report `Not-tested: Eggitor synchronization and editor runtime integration`.

## Deferred Inputs

The following are explicit inputs to later gameplay modules:

- the connected Eggitor project and generated `EggyAPI.lua`, which are prerequisites before this design's platform-facing Lua is implemented;
- real scene object names and IDs copied from the connected map;
- exported UI, archive, achievement, preset, and skill data;
- the PlayerA/PlayerB assignment rule and disconnect/third-player behavior; and
- CH00/CH01 checkpoint, reset, hint, lighting, and mechanism contracts.

The next design cycle after this foundation is editor-validated will cover pair-session and game-flow behavior. It must not be folded into this module during implementation.
