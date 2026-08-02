# Project: Cloud Journey (`云上同行`)

This file defines durable repository rules for agents and contributors. Keep project-specific chapter designs, object inventories, checkpoint tables, and performance budgets in `docs/` and `data/`; do not duplicate them here.

## Responsibility Boundary

- Codex owns Lua logic, configuration, documentation, static checks, test records, and Git delivery.
- The Eggy Party PC Editor owns world geometry, buildings, imported models, collision, materials, initial lighting, skyboxes, motion paths, and cinematic staging.
- Lua may coordinate editor-created objects, but it must not construct the main architecture at runtime.
- Never blindly edit unknown scene formats, binary assets, editor-generated files, or local editor caches.
- Create scene objects in the editor first, then export their real names, IDs, and platform data before Lua refers to them.

## Supported Toolchain and Sources of Truth

The supported integration loop is the Eggy Party PC Editor, Eggitor, VS Code, and an editor playtest. A standalone Lua interpreter or the mobile editor is not runtime-equivalent.

Official references:

- [Lua introduction](https://u5-creator.s3.game.163.com/manual/pc_md/lua/lua_eggy.html)
- [Eggitor developer assistant](https://u5-creator.s3.game.163.com/manual/pc_md/lua/lua_eggitor.html)
- [Lua sandbox environment](https://u5-creator.s3.game.163.com/manual/pc_md/lua/lua_environment.html)
- [Lua quick start](https://u5-creator.s3.game.163.com/manual/pc_md/lua/lua_quickstart.html)
- [Lua profiling](https://u5-creator.s3.game.163.com/manual/pc_md/lua/lua_profile.html)

Rules:

- Generate and connect the Lua project through Eggitor before implementing runtime features.
- Treat the current editor export of `EggyAPI.lua` as authoritative for the installed editor version's API signatures, types, enums, and constants.
- Treat current Eggitor exports for scene objects, UI nodes, archives, achievements, presets, and skills as authoritative project data for the installed editor version.
- Use official documentation for documented platform semantics, sandbox constraints, and supported workflows.
- Prefer current exports and official documentation over memory, examples from unrelated maps, or assumptions. If an export conflicts with official documentation, stop implementation, keep the affected call behind an adapter, and mark it `TODO_VERIFY` until the discrepancy is resolved through current-editor validation.
- Use only documented platform APIs and events. Never invent a U5 API, platform event name, object ID, UI ID, archive type, preset ID, or parameter order. Project-defined custom events are allowed only when registered centrally in `LuaSource_云上同行/config/events.lua`.
- Put every uncertain platform call behind an adapter and mark it `TODO_VERIFY` until confirmed against the current export and an editor playtest.

## Repository Runtime Root

- `LuaSource_云上同行/` is the only connected physical Lua project root for this repository. Eggitor maps it to the platform's logical `script/` namespace.
- Do not create a nested physical directory named `script` beneath the connected root. Production paths such as `LuaSource_云上同行/core/logger.lua` live directly beneath that root.
- Runtime `require` names are relative to the connected root, for example `require("core.logger")`; never prefix them with `LuaSource_云上同行` or `script`.
- Moving, renaming, or regenerating the connected root requires renewed evidence that Eggitor is connected, full synchronization succeeds, the entry point runs, and a nested root-relative `require` synchronizes and executes.
- `LuaSource_云上同行/EggyAPI.lua`, `LuaSource_云上同行/EggyEditorAPI.lua`, and `LuaSource_云上同行/DebugTools.lua` are generated, read-only local evidence and must not be committed. `LuaSource_云上同行/eggy.json` is required committed project metadata.

## Runtime and Sandbox Rules

- The target runtime is the Eggy Party custom Lua 5.4 sandbox, not standard desktop Lua 5.4.
- All committed production runtime modules must stay under the physical `LuaSource_云上同行/` root, which represents the sandbox's logical `script/` namespace.
- Production logic must not depend on `io`, `os`, `package`, `debug`, LuaSocket, `loadfile`, `dofile`, dynamic code loading, filesystem access, or external Lua libraries.
- In the platform's logical `script/` namespace, `require` may load only project modules beneath the mapped physical `LuaSource_云上同行/` root.
- Do not rely on implicit conversion between strings and numbers.
- Normal table keys must be numbers or strings. Use the platform `dict()` type when another key type is genuinely required.
- Account for the platform's integer and fixed-point semantics, including overflow during conversion.
- Do not use unsupported `__mode` or `__gc` metatable fields.
- When moving rotation code between old and newly created maps, verify the editor/Lua Euler rotation order instead of assuming compatibility.
- Developer mode, `debug` profiling, LuaSocket, or other relaxed sandbox capabilities may be used only as temporary PC-editor playtest instrumentation. Remove that instrumentation before committing or releasing, and never make game logic depend on it.

## Initialization and API Usage

- `LuaSource_云上同行/main.lua` is an assembly and startup entry point. It must not contain chapter gameplay logic.
- `main.lua` executes before the real game start. Do not assume that game-time objects already exist there.
- Acquire or initialize game-time objects through `EVENT.GAME_INIT` or an explicitly justified delayed-frame path.
- Use `LuaAPI.call_delay_frame` when callback order matters. Do not infer ordering from very close second-based delays.
- Call documented Eggy unit methods with dot syntax. Do not change them to colon syntax unless the current API export explicitly requires it.
- Cache results from slow object queries such as `LuaAPI.query_unit()`.
- Prefer exported UI node data over runtime `query_ui_nodes()` calls.
- Add EmmyLua annotations to exported Lua interfaces and platform boundaries where they improve static checking.
- Validate critical API arguments explicitly. A console parameter error may not halt later code and can cause cascading failures.

## Architecture and Data Boundaries

- `LuaSource_云上同行/adapters/` owns all direct platform API access, including event, scene, UI, archive, and camera calls.
- `LuaSource_云上同行/core/` owns shared infrastructure such as game flow, pair sessions, the event bus, the object registry, and logging.
- `LuaSource_云上同行/systems/` owns cross-chapter systems.
- `LuaSource_云上同行/coop/` owns reusable cooperation mechanics.
- `LuaSource_云上同行/chapters/` owns chapter state machines.
- `LuaSource_云上同行/config/` owns runtime configuration derived from verified editor data.
- All runtime references to real editor object IDs must be centralized in `LuaSource_云上同行/config/objects.lua`; raw IDs may also appear in `data/object-registry.csv` as export evidence. Business logic must use stable logical keys through the object registry.
- Event names must be registered centrally in `LuaSource_云上同行/config/events.lua` and follow the naming rules documented later in `docs/event-naming.md`.
- `data/object-registry.csv` is the editor-export evidence source; `LuaSource_云上同行/config/objects.lua` is the verified runtime mapping. If they disagree, stop and report the drift instead of guessing a repair.
- Lighting changes must go through `LightingDirector`.
- Dynamic scene-object changes must go through `DynamicWorld`.
- Camera changes must go through the camera adapter.

## Module and Lifecycle Contract

Ordinary systems must expose at least:

```lua
module.init()
module.dispose()
```

Every chapter module must expose:

```lua
chapter.init()
chapter.enter(pairSession)
chapter.reset(pairSession, checkpointId)
chapter.exit(pairSession)
chapter.dispose()
```

Lifecycle rules:

- Chapters must not call one another directly. They communicate through `game_flow` and registered custom events.
- Every event registration, timer, listener, animation controller, and temporary state allocation must have a matching cleanup path.
- `exit()` cleans resources created by the current chapter entry. `dispose()` cleans module-lifetime resources.
- `reset()` must be idempotent. Repeated calls must not duplicate registrations, rewards, completion events, or transient objects.
- Prefer event-driven logic. Polling is allowed only when the platform has no equivalent event, and it must have a bounded frequency, stop condition, and cleanup path.
- Permanent per-frame Tick loops, unbounded timers, and busy waiting are forbidden.
- Prefix operational logs with the responsible system and chapter, for example `[Checkpoint][CH01]`.
- Handle `nil` objects, players, and adapter results safely and log enough context to diagnose the failure.

## Chinese Comment Policy

- The `AGENTS.md` rules are written in English for reliable agent interpretation.
- New or materially modified project-code comments must be written in Chinese.
- Add comments for intent, lifecycle ownership, boundary conditions, platform limitations, and non-obvious behavior. Do not narrate every line.
- Keep identifiers, module names, event names, object names, API names, and the literal marker `TODO_VERIFY` in English.
- Do not mass-translate untouched files, generated code, exported API files, or third-party code merely to satisfy this rule.
- Every `TODO_VERIFY` must include a Chinese explanation of the uncertainty, expected parameters or behavior, and the source needed for verification. Example:

```lua
-- TODO_VERIFY：需要用当前 EggyAPI.lua 和编辑器试玩确认传送接口的参数顺序。
```

- A feature containing unresolved `TODO_VERIFY` platform calls must not be reported as editor-verified or complete.

## Cooperative Gameplay Invariants

- Key cooperation state may advance only when exactly two valid players are present.
- Assign stable `PlayerA` and `PlayerB` roles for the active pair.
- Protect cooperation mechanics against duplicate completion, out-of-order events, and simultaneous-trigger races.
- A formal checkpoint activates only after both paired players enter it; the first player receives a waiting state.
- A reset must place the two players at separate safe spawn points.
- Preserve collected memories and completed prerequisite mechanisms during a local reset. Reset only the current playable slice.
- A normal failure must not roll back more than 45 seconds of progress.
- Hints escalate at 15, 30, and 45 seconds by default.
- Clear all phase-bound hints on completion, reset, exit, and dispose. The same hint must not spam repeatedly.
- Permanent player archives must not store in-session cooperation-mechanism state.
- Do not invent product behavior for disconnects, reconnects, replacement players, or a third player. Those cases require an explicit feature specification before implementation.

## Performance Rules

- Prefer trigger events over Tick-based range or state polling.
- Cache frequently used API functions, values, exported nodes, and queried units when their lifecycle permits it.
- Split heavy work across frames when one-frame execution would cause a visible hitch.
- Reuse expensive units and effects when safe instead of creating them repeatedly.
- Avoid repeated type conversions, table-length calculations in hot paths, and high-volume per-frame logging.
- Pause nonessential motion and effects outside the active chapter when the editor setup supports it.
- Static review cannot prove runtime performance. Final performance claims require representative two-player editor playtests and editor profiling evidence.

## Verification Requirements

After each Lua change, inspect at minimum:

- forbidden libraries, dynamic loading, and invalid `require` paths;
- hardcoded editor object IDs outside `LuaSource_云上同行/config/objects.lua`;
- undocumented APIs and unresolved `TODO_VERIFY` markers;
- unregistered or inconsistent event names;
- event, timer, listener, and temporary-state cleanup symmetry;
- `nil` player, object, and adapter-return handling;
- duplicate checkpoint IDs and unsafe shared spawn positions;
- infinite timers, permanent per-frame loops, busy waits, and log spam;
- repeatability of `reset()`, `exit()`, and `dispose()`;
- accidental dependence on developer mode or profiling code.

Platform acceptance requires all applicable evidence below:

1. Eggitor reports successful file synchronization.
2. The map starts in the PC editor.
3. The Eggitor console reports no Lua compilation error.
4. The exercised path reports no runtime Trace or API parameter error.
5. The relevant events, cleanup paths, reset behavior, and two-player flow are triggered in an editor playtest.

A local parser or static checker is useful but is not runtime-equivalent to the Eggy sandbox. List every unavailable or unexecuted check under `Not-tested`; never describe it as passed.

## Git Commit and Push Protocol

- This repository uses `origin/main` directly unless the user explicitly changes the policy.
- For every task that modifies repository files, treat one complete, verified, independently reversible logical change as the commit unit.
- "Every modification" means every verified logical task unit, not every file save, formatting pass, or broken debugging intermediate.
- Start each modifying task with `git status --short --branch`. Existing dirty files belong to the user or another agent unless proven to be part of the current task.
- Stage only explicit task-owned paths with `git add -- <paths>` or selected hunks with `git add -p`.
- Do not use `git add .`, `git add -A`, or `git commit -a`.
- Review `git diff --cached --name-status`, the full cached diff, and `git diff --check` before committing.
- Never include unrelated changes, credentials, tokens, local editor paths, caches, temporary logs, generated profiling reports, or agent runtime state.
- Do not create empty commits. Do not commit known-broken work merely to satisfy commit frequency.
- After relevant verification succeeds, create one Lore-formatted commit and immediately push it to `origin/main`.
- Every commit message must begin with the reason for the change and use truthful decision-record trailers. Include `Confidence`, `Scope-risk`, `Tested`, and `Not-tested`; add `Constraint`, `Rejected`, or `Directive` when they preserve useful context.
- Never force-push or rewrite shared history.
- If a push is rejected or the remote moved, keep the local commit, run `git fetch origin`, inspect the divergence, and reconcile safely. Do not automatically overwrite or rebase shared `main`.
- A task is not delivered until the remote commit is confirmed, or the push failure is reported explicitly.
- The final task report must list changed files, verification evidence, commit SHA, push target, and all untested items.

## Documentation Placement

- Put game flow and chapter specifications in `docs/game-flow.md`.
- Put scene contracts and object/event naming rules in `docs/`.
- Put object exports, photo locations, and chapter budgets in `data/`.
- Put the test matrix and editor playtest records in `docs/`.
- Keep this file limited to durable operating rules so implementation details do not drift across duplicate documents.
