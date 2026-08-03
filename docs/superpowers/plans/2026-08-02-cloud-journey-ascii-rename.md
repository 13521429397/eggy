# Cloud Journey ASCII Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the connected Eggitor Lua root to `LuaSource_CloudJourney`, use `Cloud Journey` as the display name, and permanently reject the legacy localized title or non-ASCII repository paths.

**Architecture:** Add verifier mutations before changing the root, then move the complete physical project atomically and update only path/title references. Preserve root-relative Lua imports and `CLOUD_JOURNEY`, reconnect Eggitor to the renamed root, and repeat two-run editor acceptance before publishing the implementation commit.

**Tech Stack:** Eggy Party PC Editor, Eggitor, Lua 5.4 sandbox modules, Windows PowerShell 5.1, Git, GitHub `origin/main`, and the existing dependency-free verifier suite.

---

## File Structure

- Rename complete directory: `LuaSource_CloudJourney/`
- Modify metadata: `LuaSource_CloudJourney/eggy.json`
- Modify repository rules: `.gitignore`, `AGENTS.md`
- Modify Lua desktop paths: `tests/lua/main_test.lua`, `tests/lua/adapters/*.lua`, `tests/lua/core/*.lua`
- Modify verification: `tools/verify-foundation.ps1`, `tests/static/verify-foundation.tests.ps1`
- Modify current documentation: `docs/superpowers/specs/2026-08-02-foundation-module-design.md`, `docs/superpowers/plans/2026-08-02-foundation-module.md`
- Inspect but never stage: `.vscode/`, `.codemaker/`, `EggyAPI.lua`, `EggyEditorAPI.lua`, `DebugTools.lua`, `log.txt`
- Temporarily create and delete: `LuaSource_CloudJourney/tests/ascii_rename_editor_harness.lua`

### Task 1: Add the failing ASCII identity mutations

**Files:**
- Modify: `tests/static/verify-foundation.tests.ps1`
- Test: `tests/static/verify-foundation.tests.ps1`

- [ ] **Step 1: Define the canonical values without embedding the forbidden title**

After the existing `$failures` declaration, add:

```powershell
$canonicalRootName = 'LuaSource_CloudJourney'
$canonicalProjectName = 'Cloud Journey'
$legacyTitle = -join @(
    [char]0x4E91,
    [char]0x4E0A,
    [char]0x540C,
    [char]0x884C
)
```

- [ ] **Step 2: Add three mutation tests after the complete-fixture assertion**

```powershell
Assert-Pass 'rejects a noncanonical project name' {
    Assert-RejectedMutation -Name 'project name' -ExpectedPattern '\[project-name\]' -Mutate {
        param($fixture)
        $metadataFiles = @(Get-ChildItem -LiteralPath $fixture -Recurse -File -Filter 'eggy.json')
        if ($metadataFiles.Count -ne 1) { throw 'Fixture must contain exactly one eggy.json.' }
        $metadataPath = $metadataFiles[0].FullName
        $metadata = Get-Content -Raw -Encoding UTF8 -LiteralPath $metadataPath | ConvertFrom-Json
        $metadata.projectName = 'Not Cloud Journey'
        Write-Utf8File -Path $metadataPath -Content (($metadata | ConvertTo-Json -Depth 10) + "`n")
    }
}

Assert-Pass 'rejects the legacy localized title' {
    Assert-RejectedMutation -Name 'legacy title' -ExpectedPattern '\[legacy-title\]' -Mutate {
        param($fixture)
        Write-Utf8File -Path (Join-Path $fixture 'README.md') -Content ("# $legacyTitle`n")
    }
}

Assert-Pass 'rejects a non-ASCII repository path' {
    Assert-RejectedMutation -Name 'non-ASCII path' -ExpectedPattern '\[path-ascii\]' -Mutate {
        param($fixture)
        $nonAsciiLeaf = (-join @([char]0x6D4B, [char]0x8BD5)) + '.md'
        Write-Utf8File -Path (Join-Path $fixture $nonAsciiLeaf) -Content "fixture`n"
    }
}
```

- [ ] **Step 3: Run only the new tests and verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\static\verify-foundation.tests.ps1 -NamePattern 'noncanonical project name|legacy localized title|non-ASCII repository path'
```

Expected: all three tests report `[FAIL]` because the current verifier accepts the invalid fixtures. Do not commit the failing state.

### Task 2: Stop synchronization and capture the move inventory

**Files:**
- Inspect: complete current Lua root
- Do not modify tracked files during this task

- [ ] **Step 1: Stop the current playtest and disconnect Eggitor**

Use the PC editor and Eggitor UI. Confirm the action panel shows `运行游戏`, stop any active playtest, then disconnect or close the Eggitor connection. Do not rename while synchronization is active.

- [ ] **Step 2: Capture generated-file hashes and resolve both absolute roots**

Run:

```powershell
$legacyTitle = -join @([char]0x4E91, [char]0x4E0A, [char]0x540C, [char]0x884C)
$repoRoot = (Resolve-Path -LiteralPath .).Path
$oldRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ('LuaSource_' + $legacyTitle)))
$newRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'LuaSource_CloudJourney'))
if ([System.IO.Path]::GetDirectoryName($oldRoot) -ne $repoRoot) { throw 'Legacy root escaped the repository.' }
if ([System.IO.Path]::GetDirectoryName($newRoot) -ne $repoRoot) { throw 'Canonical root escaped the repository.' }
if (-not (Test-Path -LiteralPath $oldRoot -PathType Container)) { throw 'Legacy root is missing.' }
if (Test-Path -LiteralPath $newRoot) { throw 'Canonical root already exists.' }
$generatedEvidence = @('.vscode\launch.json', 'DebugTools.lua', 'EggyAPI.lua', 'EggyEditorAPI.lua')
$beforeHashes = @{}
foreach ($relativePath in $generatedEvidence) {
    $path = Join-Path $oldRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing generated evidence: $relativePath" }
    $beforeHashes[$relativePath] = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
}
```

Expected: both roots resolve directly beneath `D:\eggy`; all four generated evidence files have recorded hashes.

### Task 3: Implement the ASCII root and verifier contract

**Files:**
- Rename: complete Lua project root to `LuaSource_CloudJourney/`
- Modify: `.gitignore`
- Modify: `AGENTS.md`
- Modify: `LuaSource_CloudJourney/eggy.json`
- Modify: seven `tests/lua/**` files that define `package.path`
- Modify: `tools/verify-foundation.ps1`
- Modify: `tests/static/verify-foundation.tests.ps1`
- Modify: the existing foundation design and plan

- [ ] **Step 1: Protect generated content at the destination**

Update `.gitignore` first so it contains exactly these project-root exclusions:

```gitignore
LuaSource_CloudJourney/.vscode/
LuaSource_CloudJourney/.codemaker/
LuaSource_CloudJourney/EggyAPI.lua
LuaSource_CloudJourney/EggyEditorAPI.lua
LuaSource_CloudJourney/DebugTools.lua
LuaSource_CloudJourney/log.txt
```

- [ ] **Step 2: Move the complete root with Git-aware filesystem semantics**

Run from `D:\eggy`; the move command repeats every path and hash check so it does not depend on shell state from Task 2:

```powershell
$legacyTitle = -join @([char]0x4E91, [char]0x4E0A, [char]0x540C, [char]0x884C)
$repoRoot = (Resolve-Path -LiteralPath .).Path
$oldRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ('LuaSource_' + $legacyTitle)))
$newRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'LuaSource_CloudJourney'))
if ([System.IO.Path]::GetDirectoryName($oldRoot) -ne $repoRoot) { throw 'Legacy root escaped the repository.' }
if ([System.IO.Path]::GetDirectoryName($newRoot) -ne $repoRoot) { throw 'Canonical root escaped the repository.' }
if (-not (Test-Path -LiteralPath $oldRoot -PathType Container)) { throw 'Legacy root is missing.' }
if (Test-Path -LiteralPath $newRoot) { throw 'Canonical root already exists.' }
$generatedEvidence = @('.vscode\launch.json', 'DebugTools.lua', 'EggyAPI.lua', 'EggyEditorAPI.lua')
$beforeHashes = @{}
foreach ($relativePath in $generatedEvidence) {
    $path = Join-Path $oldRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing generated evidence: $relativePath" }
    $beforeHashes[$relativePath] = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
}
git mv -- $oldRoot $newRoot
if ($LASTEXITCODE -ne 0) { throw 'Root move failed.' }
if (Test-Path -LiteralPath $oldRoot) { throw 'Legacy root remains after the move.' }
if (-not (Test-Path -LiteralPath $newRoot -PathType Container)) { throw 'Canonical root is missing after the move.' }
foreach ($relativePath in $generatedEvidence) {
    $path = Join-Path $newRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Generated evidence did not move: $relativePath" }
    $afterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    if ($afterHash -ne $beforeHashes[$relativePath]) { throw "Generated evidence changed during move: $relativePath" }
}
```

- [ ] **Step 3: Perform the mechanical title and root replacements without changing encoding**

Use the constructed legacy value and replace the root token before the display title:

```powershell
$legacyTitle = -join @([char]0x4E91, [char]0x4E0A, [char]0x540C, [char]0x884C)
$repoRoot = (Resolve-Path -LiteralPath .).Path
$canonicalRootName = 'LuaSource_CloudJourney'
$canonicalProjectName = 'Cloud Journey'
$legacyRootName = 'LuaSource_' + $legacyTitle
$paths = @(& git grep -Il -- $legacyTitle)
foreach ($relativePath in $paths) {
    $path = Join-Path $repoRoot $relativePath
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $encoding = [System.Text.UTF8Encoding]::new($hasBom, $true)
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    $updated = $text.Replace($legacyRootName, $canonicalRootName).Replace($legacyTitle, $canonicalProjectName)
    if ($updated -ne $text) {
        [System.IO.File]::WriteAllText($path, $updated, $encoding)
    }
}
```

This is a bulk mechanical rewrite. Do not translate Chinese intent comments that do not contain the game title.

- [ ] **Step 4: Add the canonical verifier checks**

In `tools/verify-foundation.ps1`, define the same canonical root, project name, and dynamically constructed legacy title. Add checks with these diagnostics:

```powershell
$canonicalRootName = 'LuaSource_CloudJourney'
$canonicalProjectName = 'Cloud Journey'
$legacyTitle = -join @(
    [char]0x4E91,
    [char]0x4E0A,
    [char]0x540C,
    [char]0x884C
)

# 路径必须保持 ASCII，避免编辑器和命令行在不同编码下解析不一致。
$gitMetadataRoot = Join-Path $rootPath '.git'
$repositoryItems = @(Get-ChildItem -LiteralPath $rootPath -Force -Recurse | Where-Object {
    -not $_.FullName.StartsWith($gitMetadataRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
})
foreach ($item in $repositoryItems) {
    $relativePath = Normalize-RelativePath -Path $item.FullName
    if ($relativePath -match '[^\u0000-\u007F]') {
        Add-Failure -Category 'path-ascii' -Message $relativePath
    }
}
```

Read `LuaSource_CloudJourney/eggy.json` as UTF-8 JSON and require `projectName -ceq 'Cloud Journey'`, otherwise add `[project-name]`. Scan repository-owned tracked text in a real Git checkout, or `.md`, `.lua`, `.json`, `.ps1`, and `.gitignore` fixture files when `.git` is absent; exclude generated evidence and add `[legacy-title]` whenever `IndexOf($legacyTitle, Ordinal)` is non-negative.

Update every existing required-file, runtime-root, adapter, lifecycle, event, object, and diagnostic path to `LuaSource_CloudJourney`.

- [ ] **Step 5: Repair documentation statements after the mechanical pass**

Make these current-state corrections:

- simplify duplicated headers to `Project: Cloud Journey`;
- state that initial connection evidence predates the ASCII-root migration;
- state that the root rename requires the new connection evidence recorded in this task;
- replace the obsolete `eggy.json` hash with `4AF2697E64CE7F0472A2263CE9D424E5EB0EE64467CC7CFBA577AFD48ACFA852`;
- keep all executable commands on `LuaSource_CloudJourney`;
- do not reintroduce the forbidden title literal.

### Task 4: Verify GREEN statically

**Files:**
- Inspect: all changed paths
- Test: `tests/static/verify-foundation.tests.ps1`
- Test: `tools/verify-foundation.ps1`

- [ ] **Step 1: Run the three focused mutations**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\static\verify-foundation.tests.ps1 -NamePattern 'noncanonical project name|legacy localized title|non-ASCII repository path'
```

Expected: three `[PASS]` lines and exit `0`.

- [ ] **Step 2: Run the complete mutation suite and direct verifier**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\static\verify-foundation.tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\verify-foundation.ps1 -Root (Resolve-Path .)
```

Expected: 43 mutation cases pass, followed by `[PASS] verifier mutation suite` and `[PASS] foundation static verification`.

- [ ] **Step 3: Prove the name, path, ignore, encoding, and metadata invariants**

Run:

```powershell
$legacyTitle = -join @([char]0x4E91, [char]0x4E0A, [char]0x540C, [char]0x884C)
$repoRoot = (Resolve-Path -LiteralPath .).Path
$oldRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ('LuaSource_' + $legacyTitle)))
$newRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'LuaSource_CloudJourney'))
$legacyMatches = @(& git grep -n -- $legacyTitle)
if ($LASTEXITCODE -eq 0 -or $legacyMatches.Count -ne 0) { throw 'Legacy title remains in tracked content.' }
$nonAsciiTracked = @(git -c core.quotepath=false ls-files | Where-Object { $_ -match '[^\x00-\x7F]' })
if ($nonAsciiTracked.Count -ne 0) { throw "Non-ASCII tracked paths remain: $($nonAsciiTracked -join ', ')" }
if (Test-Path -LiteralPath $oldRoot) { throw 'Legacy root remains.' }
$metadataHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $newRoot 'eggy.json')).Hash
if ($metadataHash -ne '4AF2697E64CE7F0472A2263CE9D424E5EB0EE64467CC7CFBA577AFD48ACFA852') { throw "Unexpected metadata hash: $metadataHash" }
git check-ignore -v -- LuaSource_CloudJourney/.vscode/launch.json LuaSource_CloudJourney/EggyAPI.lua LuaSource_CloudJourney/EggyEditorAPI.lua LuaSource_CloudJourney/DebugTools.lua LuaSource_CloudJourney/log.txt
git diff --check
git diff --cached --check
```

Expected: zero legacy matches, zero non-ASCII tracked paths, the expected metadata hash, five ignore-rule matches, and no whitespace errors. Confirm both PowerShell verifier files retain their original UTF-8 BOM state.

### Task 5: Reconnect Eggitor and perform two-run acceptance

**Files:**
- Temporarily create and delete: `LuaSource_CloudJourney/tests/ascii_rename_editor_harness.lua`
- Inspect: Eggitor synchronization console and generated `log.txt`

- [ ] **Step 1: Reopen the renamed folder and reconnect**

Open `D:\eggy\LuaSource_CloudJourney` in VS Code, reconnect Eggitor to the same physical root, and perform a full synchronization. Confirm `main.lua` and all nested modules synchronize with no compilation error.

- [ ] **Step 2: Create the exact temporary nested-require harness with `apply_patch`**

```lua
local app = require("main")
local logger = require("core.logger")

local harness = {}

local function expect(condition, message)
    if not condition then
        error("[ASCII_RENAME_EDITOR_TEST][FAIL] " .. message)
    end
end

function harness.run()
    -- 重复初始化必须复用当前配置生命周期，证明根目录重命名未破坏模块缓存。
    expect(app.init(), "repeated app.init")
    expect(
        logger.info("AsciiRenameEditorTest", "[ASCII_RENAME_EDITOR_TEST][PASS] root imports"),
        "PASS evidence log"
    )
    return true
end

return harness
```

Wait for successful synchronization, then verify Git reports only the temporary harness in addition to the intended migration changes.

- [ ] **Step 3: Run the first editor pass**

Start the map and require exactly one `[INFO][GameFlow] 基础模块已就绪` line. Execute exactly:

```lua
require("tests.ascii_rename_editor_harness").run()
```

Expected: exactly one `[ASCII_RENAME_EDITOR_TEST][PASS] root imports`, no FAIL, compilation, Trace, parameter, registration, unregistration, or error-level diagnostics. Stop normally.

- [ ] **Step 4: Run the second pass without reload or edit**

Start again without reloading or editing the project. Require exactly one new readiness line, execute the same command, require exactly one new PASS, and stop normally with no cleanup error.

- [ ] **Step 5: Remove and synchronize the harness**

Delete the harness with `apply_patch`, wait for Eggitor's deletion synchronization, and verify the file is absent. Leave `log.txt` ignored and unstaged.

### Task 6: Review, commit, push, and verify delivery

**Files:**
- Stage only the approved rename, verifier, test, rule, metadata, and documentation paths
- Never stage generated evidence or `log.txt`

- [ ] **Step 1: Re-run all completion gates fresh**

Run the complete mutation suite, direct verifier, dynamic legacy-title scan, ASCII tracked-path scan, metadata hash check, `git diff --check`, and `git diff --cached --check`. Inspect `git status --short --branch` and the full diff.

- [ ] **Step 2: Stage explicit scope and inspect the staged rename**

Run:

```powershell
git add -- .gitignore AGENTS.md LuaSource_CloudJourney docs/superpowers/specs/2026-08-02-foundation-module-design.md docs/superpowers/plans/2026-08-02-foundation-module.md tests/lua tests/static/verify-foundation.tests.ps1 tools/verify-foundation.ps1
git diff --cached --name-status
git diff --cached
git diff --cached --check
```

Do not use `git add -A`. Confirm generated files and `log.txt` are absent from `git diff --cached --name-only`. Confirm Git records the ten production files as renames beneath `LuaSource_CloudJourney`.

- [ ] **Step 3: Create the Lore commit**

```text
Make Cloud Journey paths portable across the toolchain

Constraint: The connected Eggitor project must use ASCII-only paths while preserving root-relative Lua imports
Rejected: Keep localized path aliases | duplicate physical roots would create synchronization ambiguity
Confidence: high
Scope-risk: moderate
Directive: Keep Cloud Journey for display, LuaSource_CloudJourney for the physical root, and CLOUD_JOURNEY for runtime events
Tested: 43-case verifier mutation suite; direct verifier; legacy-title and ASCII-path scans; metadata hash; Eggitor full sync; two consecutive editor acceptance runs; staged diff inspection
Not-tested: Standalone Lua 5.4 behavior suite because no compatible runner is installed
```

- [ ] **Step 4: Push directly and prove final equality**

Run `git push origin main`, then require local `HEAD`, `origin/main`, GitHub's live `main`, and the working tree to agree. Do not force-push and do not create a PR.
