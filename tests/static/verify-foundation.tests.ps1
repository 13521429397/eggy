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
