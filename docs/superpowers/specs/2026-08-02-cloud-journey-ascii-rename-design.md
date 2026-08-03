# Cloud Journey ASCII Name Migration Design

Date: 2026-08-02
Status: Design and implementation plan approved; Eggitor/editor acceptance pending

## Goal

Standardize the game's English identity as **Cloud Journey** and remove the legacy localized game title from repository content and tracked paths. The physical Eggitor project root becomes `LuaSource_CloudJourney`, preventing non-ASCII path handling problems while preserving runtime behavior.

## Canonical Naming Contract

- Human-facing game name: `Cloud Journey`
- Physical Eggitor project root: `LuaSource_CloudJourney`
- Existing runtime event namespace: `CLOUD_JOURNEY`
- Existing root-relative Lua imports, such as `require("core.logger")`, remain unchanged.
- Chinese intent comments remain valid. Only the legacy game title and path segment are replaced.

## Migration Scope

The migration updates the repository atomically:

1. Rename the complete physical Lua root to `LuaSource_CloudJourney`, including local generated evidence that is ignored by Git.
2. Set `eggy.json`'s `projectName` to `Cloud Journey` without changing the project ID or unrelated generator metadata.
3. Update `.gitignore`, `AGENTS.md`, Lua desktop tests, the static verifier, its mutation suite, and current project documentation.
4. Remove every legacy game-title occurrence from tracked text content.
5. Ensure every tracked path is ASCII-only.
6. Ignore the editor-generated `LuaSource_CloudJourney/log.txt` so repeated playtests do not dirty the repository.

The generated `EggyAPI.lua`, `EggyEditorAPI.lua`, `DebugTools.lua`, `.vscode/`, and `.codemaker/` content remains local evidence and must not be staged. Existing generated files move with the physical root; their contents are not rewritten or scanned for the legacy title unless Eggitor regenerates them.

## Documentation Integrity

The existing foundation design and implementation plan contain both current path contracts and pre-migration evidence. Current commands and contracts will use `LuaSource_CloudJourney`. Historical statements will be reworded to identify them as pre-migration evidence without retaining the legacy localized title or pretending the renamed path was already connected at that time.

The previous fixed `eggy.json` hash applies only to the pre-migration metadata. It will be replaced with verification of the updated metadata and a freshly calculated hash where a byte-level assertion remains useful.

## Static Verification Design

The test-first migration adds failing coverage before moving production files. The verifier and mutation suite will then enforce:

- the required root is exactly `LuaSource_CloudJourney`;
- `eggy.json` declares `Cloud Journey`;
- the legacy game title does not appear in repository-owned text;
- tracked project paths contain no non-ASCII characters;
- generated exports and logs remain excluded from commits;
- all existing sandbox, module-resolution, platform-boundary, lifecycle, and whitespace checks continue to pass.

The forbidden localized title must not appear literally in the verifier or its tests, because that would violate the zero-occurrence rule it enforces. Verification code constructs the forbidden value at runtime from Unicode code points or UTF-8 bytes, and mutation fixtures use that constructed value.

The RED phase must fail because the ASCII root and English metadata do not yet exist. The GREEN phase consists only of the root move and reference updates required by those assertions.

## Editor Migration and Acceptance

Renaming the physical root invalidates the previous root-connection evidence. The playtest must be stopped and Eggitor disconnected or closed before the move so it cannot recreate or synchronize against the legacy root. The migration then verifies that the old root is absent and that the new root contains the previously inventoried generated evidence before reconnecting.

After those move-safety checks:

1. Reconnect Eggitor and VS Code to `D:\eggy\LuaSource_CloudJourney`.
2. Perform a full synchronization and confirm that `main.lua` compiles.
3. Synchronize a temporary nested-require harness beneath the renamed root.
4. Run two consecutive editor playtests without a reload or edit between them.
5. Require exactly one readiness line and one harness PASS per run, with no compilation, Trace, parameter, registration, unregistration, or error-level diagnostics.
6. Delete the temporary harness, synchronize its deletion, and leave the worktree clean.

If editor reconnection or either playtest fails, the migration is not accepted and must not be described as editor-verified.

## Git and Delivery

The design, implementation plan, and implementation are separate reviewable Lore commits. Each completed commit is pushed directly to `origin/main`, following the repository's established no-PR policy. Implementation staging is explicit: generated files, editor logs, and unrelated worktree content are never included.

## Acceptance Criteria

- The canonical display name is `Cloud Journey` everywhere.
- `LuaSource_CloudJourney` is the only physical Lua project root.
- The legacy physical root is absent after the move.
- No tracked path contains non-ASCII characters.
- No tracked file contains the legacy game title.
- Runtime Lua module names and the `CLOUD_JOURNEY` event namespace are unchanged.
- The full static mutation suite and direct verifier pass.
- Eggitor reconnects and synchronizes the renamed root.
- Two consecutive editor acceptance runs pass.
- The temporary harness is removed, the worktree is clean, and local, tracking, and live remote SHAs agree.
