param(
    [string]$EggyApiPath,
    [string]$NamePattern = '.*'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$verifierPath = Join-Path $repoRoot 'tools\verify-foundation.ps1'
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$failures = [System.Collections.Generic.List[string]]::new()
$canonicalRootName = 'LuaSource_CloudJourney'
$canonicalProjectName = 'Cloud Journey'
# 通过码点构造禁用名称，避免验证脚本自身触发零字面量规则。
$legacyTitle = -join @(
    [char]0x4E91,
    [char]0x4E0A,
    [char]0x540C,
    [char]0x884C
)
if ([string]::IsNullOrWhiteSpace($EggyApiPath)) {
    $EggyApiPath = Join-Path $repoRoot 'LuaSource_CloudJourney\EggyAPI.lua'
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Write-ByteFile {
    param([string]$Path, [byte[]]$Bytes)
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

function Invoke-FixtureGit {
    param(
        [string]$Fixture,
        [string[]]$Arguments
    )

    $output = @(& git -c core.autocrlf=false -C $Fixture $Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Fixture git command failed: git $($Arguments -join ' '): $($output -join '; ')"
    }
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
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LuaSource_CloudJourney') -Destination (Join-Path $fixture 'LuaSource_CloudJourney') -Recurse
    return $fixture
}

function Remove-FoundationFixture {
    param([string]$Path)

    $trimSeparators = [char[]]@('\', '/')
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd($trimSeparators)
    $resolved = [System.IO.Path]::GetFullPath($Path).TrimEnd($trimSeparators)
    if ($resolved.Equals($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove non-temporary fixture: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "Refusing to remove missing fixture: $resolved"
    }

    $item = Get-Item -LiteralPath $resolved -Force
    $resolved = [System.IO.Path]::GetFullPath($item.FullName).TrimEnd($trimSeparators)
    $parent = [System.IO.Path]::GetDirectoryName($resolved)
    $leaf = [System.IO.Path]::GetFileName($resolved)
    if (-not $parent.Equals($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove non-temporary fixture: $resolved"
    }
    if ($leaf -cnotmatch '^eggy-foundation-[0-9a-f]{32}$') {
        throw "Refusing to remove unexpected fixture name: $resolved"
    }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to remove reparse-point fixture: $resolved"
    }

    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Invoke-FoundationVerifier {
    param(
        [string]$Root,
        [string]$ApiPath = $EggyApiPath
    )
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifierPath -Root $Root -EggyApiPath $ApiPath 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output -join [Environment]::NewLine)
    }
}

function Assert-Pass {
    param([string]$Name, [scriptblock]$Action)
    if ($Name -notmatch $NamePattern) {
        return
    }
    try {
        & $Action
        Write-Output "[PASS] $Name"
    } catch {
        $failures.Add("${Name}: $($_.Exception.Message)")
        Write-Output "[FAIL] ${Name}: $($_.Exception.Message)"
    }
}

function Assert-CleanupRejected {
    param([string]$Path)

    $rejected = $false
    try {
        Remove-FoundationFixture -Path $Path
    } catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw "Cleanup guard accepted invalid path: $Path"
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Cleanup guard deleted rejected path: $Path"
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

Assert-Pass 'rejects malformed project metadata' {
    Assert-RejectedMutation -Name 'malformed project metadata' -ExpectedPattern '\[project-name\]' -Mutate {
        param($fixture)
        $metadataPath = Join-Path $fixture 'LuaSource_CloudJourney\eggy.json'
        Write-Utf8File -Path $metadataPath -Content "{ invalid json`n"
    }
}

Assert-Pass 'rejects the legacy localized title' {
    Assert-RejectedMutation -Name 'legacy title' -ExpectedPattern '\[legacy-title\]' -Mutate {
        param($fixture)
        Write-Utf8File -Path (Join-Path $fixture 'README.md') -Content ("# $legacyTitle`n")
    }
}

Assert-Pass 'rejects the legacy title in a tracked arbitrary text file' {
    Assert-RejectedMutation -Name 'tracked arbitrary text' -ExpectedPattern '\[legacy-title\]' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        Write-Utf8File -Path (Join-Path $fixture 'notes.txt') -Content "$legacyTitle`n"
        Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--', 'notes.txt')
    }
}

Assert-Pass 'rejects invalid UTF-8 in a tracked text file' {
    Assert-RejectedMutation -Name 'tracked invalid UTF-8 text' -ExpectedPattern '\[utf8\].*invalid-utf8\.txt' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        $relativePath = 'invalid-utf8.txt'
        Write-ByteFile -Path (Join-Path $fixture $relativePath) -Bytes ([byte[]]@(0x66, 0x6F, 0x80, 0x0A))
        Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--', $relativePath)
    }
}

Assert-Pass 'rejects UTF-16 NUL text in a tracked text file' {
    Assert-RejectedMutation -Name 'tracked UTF-16 text' -ExpectedPattern '\[utf8\].*utf16\.md' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        $relativePath = 'utf16.md'
        $utf16Bytes = [byte[]](@(0xFF, 0xFE) + [System.Text.Encoding]::Unicode.GetBytes("fixture`n"))
        Write-ByteFile -Path (Join-Path $fixture $relativePath) -Bytes $utf16Bytes
        Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--', $relativePath)
    }
}

Assert-Pass 'accepts an unrelated tracked binary asset' {
    Assert-AcceptedMutation -Name 'tracked binary asset' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        $relativePath = 'evidence.png'
        Write-ByteFile -Path (Join-Path $fixture $relativePath) -Bytes ([byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x80))
        Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--', $relativePath)
    }
}

Assert-Pass 'rejects the legacy title in tracked DebugTools.lua outside the canonical generated path' {
    Assert-RejectedMutation -Name 'tracked external DebugTools' -ExpectedPattern '\[legacy-title\]' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        Write-Utf8File -Path (Join-Path $fixture 'DebugTools.lua') -Content "-- $legacyTitle`n"
        Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--', 'DebugTools.lua')
    }
}

Assert-Pass 'ignores the legacy title in an untracked text file in a real Git fixture' {
    Assert-AcceptedMutation -Name 'untracked legacy text' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        Write-Utf8File -Path (Join-Path $fixture 'notes.txt') -Content "$legacyTitle`n"
    }
}

Assert-Pass 'excludes the exact canonical generated DebugTools.lua path from legacy scanning' {
    Assert-AcceptedMutation -Name 'canonical generated DebugTools' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        $generatedPath = 'LuaSource_CloudJourney/DebugTools.lua'
        Write-Utf8File -Path (Join-Path $fixture $generatedPath) -Content "-- $legacyTitle`n"
        Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--', $generatedPath)
    }
}

Assert-Pass 'rejects a tracked file below a DebugTools.lua directory' {
    Assert-RejectedMutation -Name 'DebugTools directory descendant' -ExpectedPattern '\[legacy-title\].*DebugTools\.lua/notes\.md' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        $generatedPath = Join-Path $fixture 'LuaSource_CloudJourney\DebugTools.lua'
        if (Test-Path -LiteralPath $generatedPath -PathType Leaf) {
            Remove-Item -LiteralPath $generatedPath -Force
        }
        $relativePath = 'LuaSource_CloudJourney/DebugTools.lua/notes.md'
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $fixture $relativePath)) -Force
        Write-Utf8File -Path (Join-Path $fixture $relativePath) -Content "$legacyTitle`n"
        Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--force', '--', $relativePath)
    }
}

Assert-Pass 'rejects an adjacent tracked DebugTools.lua backup' {
    Assert-RejectedMutation -Name 'DebugTools backup' -ExpectedPattern '\[legacy-title\].*DebugTools\.lua\.bak' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        $relativePath = 'LuaSource_CloudJourney/DebugTools.lua.bak'
        Write-Utf8File -Path (Join-Path $fixture $relativePath) -Content "$legacyTitle`n"
        Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--force', '--', $relativePath)
    }
}

Assert-Pass 'rejects a nested tracked generated-directory name' {
    Assert-RejectedMutation -Name 'nested generated directory' -ExpectedPattern '\[legacy-title\].*nested/\.vscode/notes\.md' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        $relativePath = 'LuaSource_CloudJourney/nested/.vscode/notes.md'
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $fixture $relativePath)) -Force
        Write-Utf8File -Path (Join-Path $fixture $relativePath) -Content "$legacyTitle`n"
        Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--force', '--', $relativePath)
    }
}

Assert-Pass 'rejects a lookalike tracked generated-directory name' {
    Assert-RejectedMutation -Name 'lookalike generated directory' -ExpectedPattern '\[legacy-title\].*\.codemaker-copy/notes\.md' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        $relativePath = 'LuaSource_CloudJourney/.codemaker-copy/notes.md'
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $fixture $relativePath)) -Force
        Write-Utf8File -Path (Join-Path $fixture $relativePath) -Content "$legacyTitle`n"
        Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--force', '--', $relativePath)
    }
}

Assert-Pass 'excludes exact canonical generated directories from legacy scanning' {
    Assert-AcceptedMutation -Name 'canonical generated directories' -Mutate {
        param($fixture)
        Invoke-FixtureGit -Fixture $fixture -Arguments @('init', '--quiet')
        foreach ($relativePath in @(
            'LuaSource_CloudJourney/.vscode/legacy-proof.md',
            'LuaSource_CloudJourney/.codemaker/legacy-proof.md'
        )) {
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $fixture $relativePath)) -Force
            Write-Utf8File -Path (Join-Path $fixture $relativePath) -Content "$legacyTitle`n"
            Invoke-FixtureGit -Fixture $fixture -Arguments @('add', '--force', '--', $relativePath)
        }
    }
}

Assert-Pass 'rejects a non-ASCII repository path' {
    Assert-RejectedMutation -Name 'non-ASCII path' -ExpectedPattern '\[path-ascii\]' -Mutate {
        param($fixture)
        $nonAsciiLeaf = (-join @([char]0x6D4B, [char]0x8BD5)) + '.md'
        Write-Utf8File -Path (Join-Path $fixture $nonAsciiLeaf) -Content "fixture`n"
    }
}

$requiredFiles = @(
    'LuaSource_CloudJourney/main.lua',
    'LuaSource_CloudJourney/adapters/u5_log.lua',
    'LuaSource_CloudJourney/adapters/u5_event.lua',
    'LuaSource_CloudJourney/core/logger.lua',
    'LuaSource_CloudJourney/core/event_bus.lua',
    'LuaSource_CloudJourney/core/object_registry.lua',
    'LuaSource_CloudJourney/core/game_flow.lua',
    'LuaSource_CloudJourney/config/events.lua',
    'LuaSource_CloudJourney/config/objects.lua'
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
        $path = Join-Path $fixture 'LuaSource_CloudJourney\core\logger.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = io.open`n"
    }
}

Assert-Pass 'rejects unresolved require targets' {
    Assert-RejectedMutation -Name 'invalid require' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = require(`"outside.module`")`n"
    }
}

Assert-Pass 'rejects bare unresolved require targets' {
    Assert-RejectedMutation -Name 'bare invalid require' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = require `"outside.module`"`n"
    }
}

Assert-Pass 'rejects require aliases' {
    Assert-RejectedMutation -Name 'require alias' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local loader = require`nlocal leaked = loader(`"outside.module`")`n"
    }
}

Assert-Pass 'hardening canonical require rejects leading dots' {
    Assert-RejectedMutation -Name 'leading dots' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\main.lua'
        $content = "local leadingOne = require(`".core.logger`")`n"
        $content += "local leadingMany = require(`"..core.logger`")`n"
        Add-LuaBeforeFinalReturn -Path $path -Content $content
    }
}

Assert-Pass 'hardening canonical require rejects a trailing dot' {
    Assert-RejectedMutation -Name 'trailing dot' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = require(`"core.logger.`")`n"
    }
}

Assert-Pass 'hardening canonical require rejects repeated dots' {
    Assert-RejectedMutation -Name 'repeated dots' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = require(`"core..logger`")`n"
    }
}

Assert-Pass 'rejects bare dynamic loading' {
    Assert-RejectedMutation -Name 'bare dynamic load' -ExpectedPattern '\[forbidden-runtime\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\core\logger.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = load `"return 1`"`n"
    }
}

Assert-Pass 'does not let a closed long comment hide executable code' {
    Assert-RejectedMutation -Name 'long comment bypass' -ExpectedPattern '\[forbidden-runtime\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\core\logger.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "--[=[说明]=] local leaked = io.open(`"x`")`n"
    }
}

Assert-Pass 'accepts platform and loader names inside strings and long comments' {
    Assert-AcceptedMutation -Name 'lexical masking' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\core\logger.lua'
        $content = "local note = [=[LuaAPI EVENT io load require `"outside.module`"]=]`n"
        $content += "--[==[ LuaAPI EVENT os dofile require(`"outside.module`") ]==]`n"
        $content += "local quoted = `"require('outside.module') LuaAPI package debug`"`n"
        Add-LuaBeforeFinalReturn -Path $path -Content $content
    }
}

Assert-Pass 'rejects platform globals outside adapters' {
    Assert-RejectedMutation -Name 'platform leak' -ExpectedPattern '\[platform-boundary\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = LuaAPI.log`n"
    }
}

Assert-Pass 'rejects global-event APIs in the logging adapter' {
    Assert-RejectedMutation -Name 'adapter ownership leak' -ExpectedPattern '\[platform-boundary\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\adapters\u5_log.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = LuaAPI.global_register_trigger_event`n"
    }
}

Assert-Pass 'rejects LuaAPI table type dependency in the logging adapter' {
    Assert-RejectedMutation -Name 'logging LuaAPI table type dependency' -ExpectedPattern '\[luaapi-namespace-type\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\adapters\u5_log.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local namespace_is_table = type ( LuaAPI ) == `"table`"`n"
    }
}

Assert-Pass 'rejects LuaAPI non-table type dependency in the event adapter' {
    Assert-RejectedMutation -Name 'event LuaAPI non-table type dependency' -ExpectedPattern '\[luaapi-namespace-type\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\adapters\u5_event.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local namespace_not_table = type(LuaAPI) ~= 'table'`n"
    }
}

Assert-Pass 'rejects reverse LuaAPI table type dependency in the logging adapter' {
    Assert-RejectedMutation -Name 'reverse logging LuaAPI table type dependency' -ExpectedPattern '\[luaapi-namespace-type\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\adapters\u5_log.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local namespace_is_table = `"table`" == type ( LuaAPI )`n"
    }
}

Assert-Pass 'rejects captured LuaAPI type dependency in the event adapter' {
    Assert-RejectedMutation -Name 'captured event LuaAPI type dependency' -ExpectedPattern '\[luaapi-namespace-type\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\adapters\u5_event.lua'
        $content = "local namespace_type = type ( LuaAPI )`n"
        $content += "local namespace_is_table = namespace_type == `"table`"`n"
        Add-LuaBeforeFinalReturn -Path $path -Content $content
    }
}

Assert-Pass 'rejects nonempty object configuration' {
    Assert-RejectedMutation -Name 'object id' -ExpectedPattern '\[objects-empty\]' -Mutate {
        param($fixture)
        Write-Utf8File -Path (Join-Path $fixture 'LuaSource_CloudJourney\config\objects.lua') -Content "return { THING = 123 }`n"
    }
}

Assert-Pass 'rejects missing lifecycle members' {
    Assert-RejectedMutation -Name 'missing dispose' -ExpectedPattern '\[lifecycle\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\core\logger.lua'
        $content = [System.IO.File]::ReadAllText($path, $utf8).Replace('function logger.dispose()', 'function logger.removed_dispose()')
        Write-Utf8File -Path $path -Content $content
    }
}

Assert-Pass 'rejects unresolved verification markers' {
    Assert-RejectedMutation -Name 'verification marker' -ExpectedPattern '\[verification-marker\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\core\logger.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "-- TODO_VERIFY：此故障注入必须被拒绝。`n"
    }
}

Assert-Pass 'rejects custom event literals outside config' {
    Assert-RejectedMutation -Name 'event literal' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = `"CLOUD_JOURNEY.UNKNOWN`"`n"
    }
}

Assert-Pass 'rejects event keys absent from central configuration' {
    Assert-RejectedMutation -Name 'missing event key' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\config\events.lua'
        $content = [System.IO.File]::ReadAllText($path, $utf8).Replace('CORE_READY', 'RENAMED_READY')
        Write-Utf8File -Path $path -Content $content
    }
}

Assert-Pass 'hardening deceptive quoted event definition is rejected' {
    Assert-RejectedMutation -Name 'quoted fake definition' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\config\events.lua'
        $content = "local events = {}`n"
        $content += 'local fake = [=[CORE_READY = "CLOUD_JOURNEY.CORE_READY"]=]' + "`n"
        $content += "return events`n"
        Write-Utf8File -Path $path -Content $content
    }
}

Assert-Pass 'hardening event literal preserves internal whitespace' {
    Assert-RejectedMutation -Name 'event literal whitespace' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\config\events.lua'
        $content = [System.IO.File]::ReadAllText($path, $utf8).Replace(
            '"CLOUD_JOURNEY.CORE_READY"',
            '"CLOUD_JOURNEY.CORE_ READY"'
        )
        Write-Utf8File -Path $path -Content $content
    }
}

Assert-Pass 'hardening extra lowercase event field is rejected' {
    Assert-RejectedMutation -Name 'lowercase event field' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\config\events.lua'
        $content = [System.IO.File]::ReadAllText($path, $utf8).Replace('CORE_READY =', "extra = true,`n    CORE_READY =")
        Write-Utf8File -Path $path -Content $content
    }
}

Assert-Pass 'hardening bracket event field is rejected' {
    Assert-RejectedMutation -Name 'bracket event field' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\config\events.lua'
        $content = [System.IO.File]::ReadAllText($path, $utf8).Replace('CORE_READY =', "[`"EXTRA`"] = true,`n    CORE_READY =")
        Write-Utf8File -Path $path -Content $content
    }
}

Assert-Pass 'hardening synthetic API evidence requires adjacent annotations' {
    $fixture = New-FoundationFixture
    try {
        $apiPath = Join-Path $fixture 'SyntheticEggyAPI.lua'
        $apiText = @'
LuaAPI = {}
EVENT = {}
EVENT.GAME_INIT = 1
EVENT.GAME_END = 2

---@param _event_desc any[]
---@param _callback function
---@return integer
function LuaAPI.unrelated_register(_event_desc, _callback) end

---@param _id integer
function LuaAPI.unrelated_unregister(_id) end

---@param _content string
---@param _log_level integer?
function LuaAPI.unrelated_log(_content, _log_level) end

---@param wrong string
function LuaAPI.global_register_trigger_event(_event_desc, _callback) end

---@param wrong string
function LuaAPI.global_unregister_trigger_event(_id) end

---@param wrong string
function LuaAPI.log(_content, _log_level) end
'@
        Write-Utf8File -Path $apiPath -Content ($apiText + "`n")
        $result = Invoke-FoundationVerifier -Root $fixture -ApiPath $apiPath
        if ($result.ExitCode -eq 0) {
            throw 'Verifier accepted detached API annotations.'
        }
        if ($result.Output -notmatch '\[api-export\]') {
            throw "Expected diagnostic '[api-export]'. Output: $($result.Output)"
        }
    } finally {
        Remove-FoundationFixture -Path $fixture
    }
}

Assert-Pass 'hardening temp root cleanup is rejected without deletion' {
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    Assert-CleanupRejected -Path $tempRoot
}

Assert-Pass 'hardening unexpected temp child cleanup is rejected without deletion' {
    $unexpected = Join-Path ([System.IO.Path]::GetTempPath()) ('eggy-foundation-invalid-' + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $unexpected | Out-Null
    try {
        Assert-CleanupRejected -Path $unexpected
    } finally {
        if (Test-Path -LiteralPath $unexpected -PathType Container) {
            Remove-Item -LiteralPath $unexpected -Force
        }
    }
}

Assert-Pass 'rejects trailing whitespace' {
    Assert-RejectedMutation -Name 'trailing whitespace' -ExpectedPattern '\[whitespace\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\core\logger.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local trailing = true `n"
    }
}

Assert-Pass 'rejects a missing final newline' {
    Assert-RejectedMutation -Name 'missing final newline' -ExpectedPattern '\[whitespace\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_CloudJourney\core\logger.lua'
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
