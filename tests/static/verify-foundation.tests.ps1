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

Assert-Pass 'hardening canonical require rejects leading dots' {
    Assert-RejectedMutation -Name 'leading dots' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\main.lua'
        $content = "local leadingOne = require(`".core.logger`")`n"
        $content += "local leadingMany = require(`"..core.logger`")`n"
        Add-LuaBeforeFinalReturn -Path $path -Content $content
    }
}

Assert-Pass 'hardening canonical require rejects a trailing dot' {
    Assert-RejectedMutation -Name 'trailing dot' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = require(`"core.logger.`")`n"
    }
}

Assert-Pass 'hardening canonical require rejects repeated dots' {
    Assert-RejectedMutation -Name 'repeated dots' -ExpectedPattern '\[require-target\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\main.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local leaked = require(`"core..logger`")`n"
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

Assert-Pass 'rejects LuaAPI table type dependency in the logging adapter' {
    Assert-RejectedMutation -Name 'logging LuaAPI table type dependency' -ExpectedPattern '\[luaapi-namespace-type\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\adapters\u5_log.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local namespace_is_table = type ( LuaAPI ) == `"table`"`n"
    }
}

Assert-Pass 'rejects LuaAPI non-table type dependency in the event adapter' {
    Assert-RejectedMutation -Name 'event LuaAPI non-table type dependency' -ExpectedPattern '\[luaapi-namespace-type\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\adapters\u5_event.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local namespace_not_table = type(LuaAPI) ~= 'table'`n"
    }
}

Assert-Pass 'rejects reverse LuaAPI table type dependency in the logging adapter' {
    Assert-RejectedMutation -Name 'reverse logging LuaAPI table type dependency' -ExpectedPattern '\[luaapi-namespace-type\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\adapters\u5_log.lua'
        Add-LuaBeforeFinalReturn -Path $path -Content "local namespace_is_table = `"table`" == type ( LuaAPI )`n"
    }
}

Assert-Pass 'rejects captured LuaAPI type dependency in the event adapter' {
    Assert-RejectedMutation -Name 'captured event LuaAPI type dependency' -ExpectedPattern '\[luaapi-namespace-type\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\adapters\u5_event.lua'
        $content = "local namespace_type = type ( LuaAPI )`n"
        $content += "local namespace_is_table = namespace_type == `"table`"`n"
        Add-LuaBeforeFinalReturn -Path $path -Content $content
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

Assert-Pass 'hardening deceptive quoted event definition is rejected' {
    Assert-RejectedMutation -Name 'quoted fake definition' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\config\events.lua'
        $content = "local events = {}`n"
        $content += 'local fake = [=[CORE_READY = "CLOUD_JOURNEY.CORE_READY"]=]' + "`n"
        $content += "return events`n"
        Write-Utf8File -Path $path -Content $content
    }
}

Assert-Pass 'hardening event literal preserves internal whitespace' {
    Assert-RejectedMutation -Name 'event literal whitespace' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\config\events.lua'
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
        $path = Join-Path $fixture 'LuaSource_云上同行\config\events.lua'
        $content = [System.IO.File]::ReadAllText($path, $utf8).Replace('CORE_READY =', "extra = true,`n    CORE_READY =")
        Write-Utf8File -Path $path -Content $content
    }
}

Assert-Pass 'hardening bracket event field is rejected' {
    Assert-RejectedMutation -Name 'bracket event field' -ExpectedPattern '\[event-centralization\]' -Mutate {
        param($fixture)
        $path = Join-Path $fixture 'LuaSource_云上同行\config\events.lua'
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
