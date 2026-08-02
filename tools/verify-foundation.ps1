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
$canonicalRequireTarget = '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*'
$literalRequirePattern = '\brequire\s*(?:\(\s*["''](' + $canonicalRequireTarget + ')["'']\s*\)|["''](' + $canonicalRequireTarget + ')["''])'
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

function Normalize-LuaCodeWhitespace {
    param([string]$Text)

    $builder = [System.Text.StringBuilder]::new()
    $offset = 0
    foreach ($match in [regex]::Matches($Text, $luaLexicalPattern)) {
        if ($match.Index -gt $offset) {
            $codeSpan = $Text.Substring($offset, $match.Index - $offset)
            $null = $builder.Append([regex]::Replace($codeSpan, '\s+', ''))
        }
        if (-not $match.Value.StartsWith('--', [System.StringComparison]::Ordinal)) {
            $null = $builder.Append($match.Value)
        }
        $offset = $match.Index + $match.Length
    }
    if ($offset -lt $Text.Length) {
        $null = $builder.Append([regex]::Replace($Text.Substring($offset), '\s+', ''))
    }
    return $builder.ToString()
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

function Get-LuaApiDeclarationEvidence {
    param(
        [string]$Text,
        [string]$FunctionName
    )

    $declarationPattern = '(?m)^function[ \t]+LuaAPI\.' + [regex]::Escape($FunctionName) + '[ \t]*\([^\r\n]*\)[ \t]+end[ \t]*(?=\r?$)'
    $declarations = [regex]::Matches($Text, $declarationPattern)
    if ($declarations.Count -ne 1) {
        Add-Failure -Category 'api-export' -Message "Current export must contain exactly one LuaAPI.$FunctionName declaration"
        return $null
    }

    $declaration = $declarations[0]
    $prefix = $Text.Substring(0, $declaration.Index)
    $blockMatch = [regex]::Match($prefix, '(?m)(?<block>(?:^---[^\r\n]*\r?\n)+)\z')
    if (-not $blockMatch.Success) {
        Add-Failure -Category 'api-export' -Message "LuaAPI.$FunctionName is missing an adjacent Emmy annotation block"
        return $null
    }

    $annotationLines = @([regex]::Matches($blockMatch.Groups['block'].Value, '(?m)^---@[^\r\n]*(?=\r?$)') | ForEach-Object {
        $_.Value
    })
    return [pscustomobject]@{
        Declaration = $declaration.Value
        Annotations = $annotationLines
    }
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
$runtimeRootFull = [System.IO.Path]::GetFullPath($runtimeRoot).TrimEnd([char[]]@('\', '/'))
$runtimeRootPrefix = $runtimeRootFull + [System.IO.Path]::DirectorySeparatorChar
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

    if ($relativePath -eq 'LuaSource_云上同行/adapters/u5_log.lua' -or $relativePath -eq 'LuaSource_云上同行/adapters/u5_event.lua') {
        if ($codeOnly -match '\btype\s*\(\s*LuaAPI\s*\)') {
            Add-Failure -Category 'luaapi-namespace-type' -Message "$relativePath must validate callable LuaAPI members without assuming a table namespace"
        }
    }

    if ($raw.IndexOf('TODO_VERIFY', [System.StringComparison]::Ordinal) -ge 0) {
        Add-Failure -Category 'verification-marker' -Message $relativePath
    }

    $allRequireCalls = [regex]::Matches($codeOnly, '\brequire\b')
    $literalRequires = [regex]::Matches(
        $requireView,
        $literalRequirePattern
    )
    if ($allRequireCalls.Count -ne $literalRequires.Count) {
        Add-Failure -Category 'require-target' -Message "$relativePath contains a computed or malformed require"
    }
    foreach ($requireMatch in $literalRequires) {
        $target = $requireMatch.Groups[1].Value
        if ($target -eq '') {
            $target = $requireMatch.Groups[2].Value
        }
        $targetPath = [System.IO.Path]::GetFullPath((Join-Path $runtimeRootFull ($target.Replace('.', '\') + '.lua')))
        if (-not $targetPath.StartsWith($runtimeRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure -Category 'require-target' -Message "$relativePath escapes the runtime root: $target"
            continue
        }
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
    $eventsCode = Read-Utf8File -Path $eventsPath
    $normalizedEventsCode = Normalize-LuaCodeWhitespace -Text $eventsCode
    $expectedEventsCode = 'localevents={CORE_READY="CLOUD_JOURNEY.CORE_READY",}returnevents'
    if ($normalizedEventsCode -cne $expectedEventsCode) {
        Add-Failure -Category 'event-centralization' -Message 'config/events.lua must define only CORE_READY'
    } else {
        $definedEventKeys['CORE_READY'] = 'CLOUD_JOURNEY.CORE_READY'
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
    $apiSpecs = @(
        @{
            Name = 'global_register_trigger_event'
            DeclarationPattern = '^function LuaAPI\.global_register_trigger_event\(_event_desc, _callback\) end$'
            AnnotationPatterns = @(
                '^---@param _event_desc any\[\](?:[ \t].*)?$',
                '^---@param _callback function(?:[ \t].*)?$',
                '^---@return integer(?:[ \t].*)?$'
            )
        },
        @{
            Name = 'global_unregister_trigger_event'
            DeclarationPattern = '^function LuaAPI\.global_unregister_trigger_event\(_id\) end$'
            AnnotationPatterns = @(
                '^---@param _id integer(?:[ \t].*)?$'
            )
        },
        @{
            Name = 'log'
            DeclarationPattern = '^function LuaAPI\.log\(_content, _log_level\) end$'
            AnnotationPatterns = @(
                '^---@param _content string(?:[ \t].*)?$',
                '^---@param _log_level integer\?(?:[ \t].*)?$'
            )
        }
    )
    foreach ($spec in $apiSpecs) {
        $evidence = Get-LuaApiDeclarationEvidence -Text $apiText -FunctionName $spec.Name
        if ($null -eq $evidence) {
            continue
        }
        if ($evidence.Declaration -notmatch $spec.DeclarationPattern) {
            Add-Failure -Category 'api-export' -Message "LuaAPI.$($spec.Name) declaration does not match current signature evidence"
        }
        if ($evidence.Annotations.Count -ne $spec.AnnotationPatterns.Count) {
            Add-Failure -Category 'api-export' -Message "LuaAPI.$($spec.Name) has an unexpected annotation count"
            continue
        }
        for ($index = 0; $index -lt $spec.AnnotationPatterns.Count; $index += 1) {
            if ($evidence.Annotations[$index] -notmatch $spec.AnnotationPatterns[$index]) {
                Add-Failure -Category 'api-export' -Message "LuaAPI.$($spec.Name) annotation $($index + 1) does not match current signature evidence"
            }
        }
    }
}

if (Test-Path -LiteralPath (Join-Path $rootPath '.git') -PathType Container) {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $unstagedWhitespace = & git -C $rootPath diff --check -- 2>&1
        $unstagedExitCode = $LASTEXITCODE
        $stagedWhitespace = & git -C $rootPath diff --cached --check -- 2>&1
        $stagedExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($unstagedExitCode -ne 0) {
        Add-Failure -Category 'whitespace' -Message ($unstagedWhitespace -join '; ')
    }
    if ($stagedExitCode -ne 0) {
        Add-Failure -Category 'whitespace' -Message ($stagedWhitespace -join '; ')
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Output $failure }
    exit 1
}

Write-Output '[PASS] foundation static verification'
exit 0
