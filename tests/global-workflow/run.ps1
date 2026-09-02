[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:Passes = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$schemaPaths = [ordered]@{
    Context  = Join-Path $root 'schemas/context-chain.schema.json'
    State    = Join-Path $root 'schemas/global-workflow-state.schema.json'
    Evidence = Join-Path $root 'schemas/evidence-envelope.schema.json'
}

function Invoke-TestCase {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Passes++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    catch {
        $stack = if ($_.ScriptStackTrace) { " | $($_.ScriptStackTrace)" } else { '' }
        $message = "$Name :: $($_.Exception.Message)$stack"
        $script:Failures.Add($message) | Out-Null
        Write-Host "[FAIL] $message" -ForegroundColor Red
    }
}

function New-Err { return New-Object 'System.Collections.Generic.List[string]' }
function Add-Err { param($E, [string]$M) $E.Add($M) | Out-Null }
function Eq {
    param($Expected, $Actual, [string]$Message = 'Values differ.')
    if ($Expected -ne $Actual) { throw "$Message Expected='$Expected' Actual='$Actual'" }
}
function SeqEq {
    param([object[]]$Expected = @(), [object[]]$Actual = @(), [string]$Message = 'Sequences differ.')
    $e = (@($Expected) | ForEach-Object { if ($null -eq $_) { '<null>' } else { [string]$_ } }) -join '|'
    $a = (@($Actual) | ForEach-Object { if ($null -eq $_) { '<null>' } else { [string]$_ } }) -join '|'
    Eq $e $a $Message
}
function Json { param([string]$Path) Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json }
function P { param($Object, [string]$Name) ($Object.PSObject.Properties[$Name]).Value }
function N {
    param($Object, [string[]]$Path)
    $current = $Object
    foreach ($segment in $Path) { $current = P $current $segment }
    return $current
}
function DT {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$') { return $false }
    $parsed = [datetimeoffset]::MinValue
    return [datetimeoffset]::TryParse(
        $Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )
}
function Hex64 { param($Value) [string]$Value -match '^[0-9a-fA-F]{64}$' }

function Shape {
    param($Errors, $Value, [string]$Label, [string[]]$Required, [string[]]$Allowed)
    if ($null -eq $Value) { Add-Err $Errors "$Label is missing."; return }
    $names = @($Value.PSObject.Properties.Name)
    foreach ($r in $Required) { if ($names -notcontains $r) { Add-Err $Errors "$Label missing required property '$r'." } }
    foreach ($n in $names) { if ($Allowed -notcontains $n) { Add-Err $Errors "$Label contains unknown property '$n'." } }
}

function StrArr {
    param($Errors, $Value, [string]$Label)
    if ($null -eq $Value) { Add-Err $Errors "$Label is missing."; return }
    if ($Value -isnot [System.Array]) { Add-Err $Errors "$Label must be an array of strings."; return }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in @($Value)) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) { Add-Err $Errors "$Label contains a non-empty string violation."; continue }
        if (-not $seen.Add([string]$item)) { Add-Err $Errors "$Label contains a duplicate value '$item'." }
    }
}

function OptStrArr { param($Errors, $Value, [string]$Label) if ($null -ne $Value) { StrArr $Errors $Value $Label } }

function CF {
    param($Value, [string]$Label, [string]$Role, [string]$PathPattern)
    $e = New-Err
    Shape $e $Value $Label @('role', 'path', 'exists', 'observedAt', 'sha256', 'parseStatus') @('role', 'path', 'exists', 'observedAt', 'sha256', 'parseStatus')
    if ($null -eq $Value) { return $e }
    if ($Value.role -ne $Role) { Add-Err $e "$Label role must be '$Role'." }
    if (-not ([regex]::IsMatch([string]$Value.path, $PathPattern))) { Add-Err $e "$Label path must match '$PathPattern'." }
    if (-not (DT $Value.observedAt)) { Add-Err $e "$Label observedAt must be an RFC 3339 date-time." }
    switch ([string]$Value.parseStatus) {
        'missing' { if ($Value.exists -ne $false) { Add-Err $e "$Label parseStatus=missing requires exists=false." }; if ($null -ne $Value.sha256) { Add-Err $e "$Label parseStatus=missing requires sha256=null." } }
        'parsed'  { if ($Value.exists -ne $true)  { Add-Err $e "$Label parseStatus=parsed requires exists=true." };  if (-not (Hex64 $Value.sha256)) { Add-Err $e "$Label parseStatus=parsed requires a 64-hex sha256." } }
        'invalid' { if ($Value.exists -ne $true)  { Add-Err $e "$Label parseStatus=invalid requires exists=true." }; if (-not (Hex64 $Value.sha256)) { Add-Err $e "$Label parseStatus=invalid requires a 64-hex sha256." } }
        default   { Add-Err $e "$Label parseStatus must be parsed, missing, or invalid." }
    }
    return $e
}

function Validate-ContextChain {
    param($Value)
    $e = New-Err
    Shape $e $Value 'context-chain' @('schemaVersion', 'files', 'verifiedFacts', 'unverifiedAssumptions', 'currentBlockers', 'taskScope', 'protectedPaths', 'recentAcceptanceEvidence', 'taskBinding', 'worktree', 'auditDir', 'nextGate') @('schemaVersion', 'files', 'verifiedFacts', 'unverifiedAssumptions', 'currentBlockers', 'taskScope', 'protectedPaths', 'recentAcceptanceEvidence', 'taskBinding', 'worktree', 'auditDir', 'nextGate')
    if ($null -eq $Value) { return $e }
    if ($Value.schemaVersion -ne '0.12.9') { Add-Err $e 'context-chain schemaVersion must be 0.12.9.' }
    if ($Value.files -isnot [System.Array] -or @($Value.files).Count -ne 3) { Add-Err $e 'context-chain files must contain exactly three entries.' }
    else {
        $rules = @(
            @{ Role = 'current';   PathPattern = '^(?:.*[\\/])?context\.md$' },
            @{ Role = 'previous';  PathPattern = '^(?:.*[\\/])?context\.prev\.md$' },
            @{ Role = 'previous2'; PathPattern = '^(?:.*[\\/])?context\.prev2\.md$' }
        )
        for ($i = 0; $i -lt 3; $i++) {
            foreach ($m in (CF $Value.files[$i] "context-chain.files[$i]" $rules[$i].Role $rules[$i].PathPattern)) {
                Add-Err $e $m
            }
        }
    }
    foreach ($n in @('verifiedFacts', 'unverifiedAssumptions', 'currentBlockers', 'protectedPaths', 'recentAcceptanceEvidence')) { StrArr $e $Value.$n "context-chain.$n" }
    Shape $e $Value.taskScope 'context-chain.taskScope' @('summary') @('summary', 'inScope', 'outOfScope')
    if ($null -ne $Value.taskScope) {
        if ([string]::IsNullOrWhiteSpace([string]$Value.taskScope.summary)) { Add-Err $e 'context-chain.taskScope.summary must be a non-empty string.' }
        OptStrArr $e $Value.taskScope.inScope 'context-chain.taskScope.inScope'
        OptStrArr $e $Value.taskScope.outOfScope 'context-chain.taskScope.outOfScope'
    }
    Shape $e $Value.taskBinding 'context-chain.taskBinding' @('status', 'observedAt') @('taskId', 'runId', 'sessionId', 'status', 'observedAt')
    if ($null -ne $Value.taskBinding) {
        foreach ($n in @('taskId', 'runId', 'sessionId')) { if ($null -ne $Value.taskBinding.$n -and [string]::IsNullOrWhiteSpace([string]$Value.taskBinding.$n)) { Add-Err $e "context-chain.taskBinding.$n must be a non-empty string when present." } }
        if ($Value.taskBinding.status -notin @('pending', 'linked', 'stale', 'broken')) { Add-Err $e 'context-chain.taskBinding.status must be pending, linked, stale, or broken.' }
        if (-not (DT $Value.taskBinding.observedAt)) { Add-Err $e 'context-chain.taskBinding.observedAt must be an RFC 3339 date-time.' }
    }
    Shape $e $Value.worktree 'context-chain.worktree' @('path', 'branch') @('path', 'branch', 'head', 'status')
    if ($null -ne $Value.worktree) {
        if ([string]::IsNullOrWhiteSpace([string]$Value.worktree.path)) { Add-Err $e 'context-chain.worktree.path must be a non-empty string.' }
        if ([string]::IsNullOrWhiteSpace([string]$Value.worktree.branch)) { Add-Err $e 'context-chain.worktree.branch must be a non-empty string.' }
        if ($null -ne $Value.worktree.head -and [string]$Value.worktree.head -notmatch '^(unborn|[0-9a-fA-F]{40})$') { Add-Err $e 'context-chain.worktree.head must be unborn or a 40-character SHA.' }
        if ($null -ne $Value.worktree.status -and $Value.worktree.status -notin @('clean', 'dirty', 'untracked', 'mixed')) { Add-Err $e 'context-chain.worktree.status must be clean, dirty, untracked, or mixed.' }
    }
    Shape $e $Value.auditDir 'context-chain.auditDir' @('path') @('path')
    if ($null -ne $Value.auditDir -and [string]::IsNullOrWhiteSpace([string]$Value.auditDir.path)) { Add-Err $e 'context-chain.auditDir.path must be a non-empty string.' }
    Shape $e $Value.nextGate 'context-chain.nextGate' @('name', 'status') @('name', 'status', 'blockingReason')
    if ($null -ne $Value.nextGate) {
        if ([string]::IsNullOrWhiteSpace([string]$Value.nextGate.name)) { Add-Err $e 'context-chain.nextGate.name must be a non-empty string.' }
        if ($Value.nextGate.status -notin @('pending', 'ready', 'blocked', 'complete')) { Add-Err $e 'context-chain.nextGate.status must be pending, ready, blocked, or complete.' }
        if ($null -ne $Value.nextGate.blockingReason -and [string]::IsNullOrWhiteSpace([string]$Value.nextGate.blockingReason)) { Add-Err $e 'context-chain.nextGate.blockingReason must be a non-empty string when present.' }
    }
    return $e
}

function L {
    param($Value, [string]$Label)
    $e = New-Err
    Shape $e $Value $Label @('status', 'observedAt') @('status', 'observedAt', 'notes', 'evidence')
    if ($null -eq $Value) { return $e }
    if ($Value.status -notin @('pending', 'ready', 'blocked', 'complete', 'unknown')) { Add-Err $e "$Label status must be pending, ready, blocked, complete, or unknown." }
    if (-not (DT $Value.observedAt)) { Add-Err $e "$Label observedAt must be an RFC 3339 date-time." }
    if ($null -ne $Value.notes -and [string]::IsNullOrWhiteSpace([string]$Value.notes)) { Add-Err $e "$Label notes must be a non-empty string when present." }
    OptStrArr $e $Value.evidence "$Label.evidence"
    return $e
}

function Validate-State {
    param($Value)
    $e = New-Err
    Shape $e $Value 'global-workflow-state' @('schemaVersion', 'layers') @('schemaVersion', 'layers')
    if ($null -eq $Value) { return $e }
    if ($Value.schemaVersion -ne '0.12.9') { Add-Err $e 'global-workflow-state schemaVersion must be 0.12.9.' }
    Shape $e $Value.layers 'global-workflow-state.layers' @('taskBinding', 'contextChain', 'mcpRegistration', 'mcpInventory', 'preflight', 'coordinator', 'workflow', 'worker', 'result', 'acceptance', 'nextGate') @('taskBinding', 'contextChain', 'mcpRegistration', 'mcpInventory', 'preflight', 'coordinator', 'workflow', 'worker', 'result', 'acceptance', 'nextGate')
    if ($null -ne $Value.layers) {
        foreach ($n in @('taskBinding', 'contextChain', 'mcpRegistration', 'mcpInventory', 'preflight', 'coordinator', 'workflow', 'worker', 'result', 'acceptance', 'nextGate')) {
            foreach ($m in (L $Value.layers.$n "global-workflow-state.layers.$n")) {
                Add-Err $e $m
            }
        }
    }
    return $e
}

function Validate-Envelope {
    param($Value)
    $e = New-Err
    Shape $e $Value 'evidence-envelope' @('schemaVersion', 'source', 'observedAt', 'redaction', 'advisoryOnly', 'authority') @('schemaVersion', 'source', 'observedAt', 'redaction', 'advisoryOnly', 'authority')
    if ($null -eq $Value) { return $e }
    if ($Value.schemaVersion -ne '0.12.9') { Add-Err $e 'evidence-envelope schemaVersion must be 0.12.9.' }
    if (-not (DT $Value.observedAt)) { Add-Err $e 'evidence-envelope observedAt must be an RFC 3339 date-time.' }
    if ($Value.advisoryOnly -isnot [bool]) { Add-Err $e 'evidence-envelope advisoryOnly must be a boolean.' }
    if ($Value.authority -notin @('canonical', 'observed', 'advisory', 'historical', 'unverified')) { Add-Err $e 'evidence-envelope authority must be canonical, observed, advisory, historical, or unverified.' }
    Shape $e $Value.source 'evidence-envelope.source' @('kind', 'identifier') @('kind', 'identifier', 'path', 'sha256', 'summary')
    if ($null -ne $Value.source) {
        if ($Value.source.kind -notin @('file', 'workflow', 'task', 'log', 'manual')) { Add-Err $e 'evidence-envelope.source.kind must be file, workflow, task, log, or manual.' }
        if ([string]::IsNullOrWhiteSpace([string]$Value.source.identifier)) { Add-Err $e 'evidence-envelope.source.identifier must be a non-empty string.' }
        if ($null -ne $Value.source.path -and [string]::IsNullOrWhiteSpace([string]$Value.source.path)) { Add-Err $e 'evidence-envelope.source.path must be a non-empty string when present.' }
        if ($null -ne $Value.source.sha256 -and -not (Hex64 $Value.source.sha256)) { Add-Err $e 'evidence-envelope.source.sha256 must be a 64-hex string when present.' }
        if ($null -ne $Value.source.summary -and [string]::IsNullOrWhiteSpace([string]$Value.source.summary)) { Add-Err $e 'evidence-envelope.source.summary must be a non-empty string when present.' }
    }
    Shape $e $Value.redaction 'evidence-envelope.redaction' @('level') @('level', 'notes', 'paths')
    if ($null -ne $Value.redaction) {
        if ($Value.redaction.level -notin @('none', 'partial', 'full')) { Add-Err $e 'evidence-envelope.redaction.level must be none, partial, or full.' }
        if ($null -ne $Value.redaction.notes -and [string]::IsNullOrWhiteSpace([string]$Value.redaction.notes)) { Add-Err $e 'evidence-envelope.redaction.notes must be a non-empty string when present.' }
        OptStrArr $e $Value.redaction.paths 'evidence-envelope.redaction.paths'
    }
    return $e
}

function FailIfErrors { param($Errors, [string]$Label) if ($Errors.Count -gt 0) { throw "$Label :: $(@($Errors) -join ' | ')" } }
function ExpectErrors {
    param($Errors, [string]$Label, [string]$Pattern)
    if ($Errors.Count -eq 0) { throw "$Label :: expected a validation failure." }
    $joined = @($Errors) -join ' | '
    if ($joined -notmatch $Pattern) { throw "$Label :: expected pattern '$Pattern' in '$joined'" }
}
function Missing-Message {
    param($Errors, [string]$Label, [string]$Pattern)
    if ($Errors.Count -eq 0) { throw "$Label :: expected a validation failure." }
    $joined = @($Errors) -join ' | '
    if ($joined -notmatch $Pattern) { throw "$Label :: expected pattern '$Pattern' in '$joined'" }
}

function New-ContextChainFixture {
    [pscustomobject][ordered]@{
        schemaVersion = '0.12.9'
        files = @(
            [pscustomobject][ordered]@{ role = 'current';   path = 'docs/context.md';      exists = $true;  observedAt = '2026-09-02T00:00:00Z'; sha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; parseStatus = 'parsed' }
            [pscustomobject][ordered]@{ role = 'previous';  path = 'docs/context.prev.md'; exists = $true;  observedAt = '2026-09-02T00:00:00Z'; sha256 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'; parseStatus = 'invalid' }
            [pscustomobject][ordered]@{ role = 'previous2'; path = 'docs/context.prev2.md'; exists = $false; observedAt = '2026-09-02T00:00:00Z'; sha256 = $null; parseStatus = 'missing' }
        )
        verifiedFacts = @('Task 1 is limited to the four approved paths.')
        unverifiedAssumptions = @('No extra files are needed for this slice.')
        currentBlockers = @()
        taskScope = [pscustomobject][ordered]@{ summary = 'Converge the global workflow contracts.'; inScope = @('schemas', 'tests'); outOfScope = @('runtime') }
        protectedPaths = @('D:/cc-pane/.worktrees/method-layer-production-runtime-20260828')
        recentAcceptanceEvidence = @('The RED regression failed when the schemas were absent.')
        taskBinding = [pscustomobject][ordered]@{ taskId = 'task-global-workflow-001'; runId = 'run-global-workflow-001'; sessionId = 'session-global-workflow-001'; status = 'linked'; observedAt = '2026-09-02T00:00:00Z' }
        worktree = [pscustomobject][ordered]@{ path = 'D:/cc-pane/.worktrees/method-layer-production-runtime-20260828'; branch = 'codex/method-layer-production-runtime-20260828'; head = '0123456789abcdef0123456789abcdef01234567'; status = 'dirty' }
        auditDir = [pscustomobject][ordered]@{ path = 'D:/cc-pane/.worktrees/method-layer-production-runtime-20260828/audit/global-workflow' }
        nextGate = [pscustomobject][ordered]@{ name = 'schema-green'; status = 'ready'; blockingReason = 'none' }
    }
}

function New-StateFixture {
    [pscustomobject][ordered]@{
        schemaVersion = '0.12.9'
        layers = [pscustomobject][ordered]@{
            taskBinding    = [pscustomobject][ordered]@{ status = 'ready';    observedAt = '2026-09-02T00:00:00Z'; notes = 'Task binding is available.' }
            contextChain   = [pscustomobject][ordered]@{ status = 'pending';  observedAt = '2026-09-02T00:00:00Z' }
            mcpRegistration= [pscustomobject][ordered]@{ status = 'blocked';  observedAt = '2026-09-02T00:00:00Z' }
            mcpInventory   = [pscustomobject][ordered]@{ status = 'complete'; observedAt = '2026-09-02T00:00:00Z' }
            preflight      = [pscustomobject][ordered]@{ status = 'pending';  observedAt = '2026-09-02T00:00:00Z' }
            coordinator    = [pscustomobject][ordered]@{ status = 'pending';  observedAt = '2026-09-02T00:00:00Z' }
            workflow       = [pscustomobject][ordered]@{ status = 'pending';  observedAt = '2026-09-02T00:00:00Z' }
            worker         = [pscustomobject][ordered]@{ status = 'pending';  observedAt = '2026-09-02T00:00:00Z' }
            result         = [pscustomobject][ordered]@{ status = 'pending';  observedAt = '2026-09-02T00:00:00Z' }
            acceptance     = [pscustomobject][ordered]@{ status = 'pending';  observedAt = '2026-09-02T00:00:00Z' }
            nextGate       = [pscustomobject][ordered]@{ status = 'pending';  observedAt = '2026-09-02T00:00:00Z' }
        }
    }
}

function New-EnvelopeFixture {
    param([string]$Authority, [bool]$AdvisoryOnly = $true)
    [pscustomobject][ordered]@{
        schemaVersion = '0.12.9'
        source = [pscustomobject][ordered]@{
            kind = 'file'
            identifier = 'context.md'
            path = 'D:/cc-pane/.worktrees/method-layer-production-runtime-20260828/context.md'
            sha256 = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
            summary = 'Observed from the active worktree.'
        }
        observedAt = '2026-09-02T00:00:00Z'
        redaction = [pscustomobject][ordered]@{
            level = 'partial'
            notes = 'Names and opaque identifiers are redacted.'
            paths = @('D:/cc-pane/.worktrees/method-layer-production-runtime-20260828/context.md')
        }
        advisoryOnly = $AdvisoryOnly
        authority = $Authority
    }
}

function Check-ContextSchema {
    $s = Json $schemaPaths.Context
    Eq '0.12.9' (N $s @('properties', 'schemaVersion', 'const')) 'context-chain version changed.'
    SeqEq @('schemaVersion', 'files', 'verifiedFacts', 'unverifiedAssumptions', 'currentBlockers', 'taskScope', 'protectedPaths', 'recentAcceptanceEvidence', 'taskBinding', 'worktree', 'auditDir', 'nextGate') @($s.required) 'context-chain top-level required set changed.'
    Eq $false (P $s 'additionalProperties') 'context-chain must reject unknown top-level fields.'
    Eq $false (N $s @('properties', 'files', 'items')) 'context-chain must reject extra file entries.'
    $pi = @(N $s @('properties', 'files', 'prefixItems'))
    Eq 3 $pi.Count 'context-chain must keep three positional file entries.'
    SeqEq @('#/$defs/currentContextFile', '#/$defs/previousContextFile', '#/$defs/previous2ContextFile') @($pi | ForEach-Object { P $_ '$ref' }) 'context-chain files must bind to positional schemas.'
    SeqEq @('role', 'path', 'exists', 'observedAt', 'sha256', 'parseStatus') @(N $s @('$defs', 'contextFileBase', 'required')) 'context file base required set changed.'
    Eq $false (N $s @('$defs', 'contextFileBase', 'additionalProperties')) 'context file base must reject nested unknown fields.'
    SeqEq @('missing', 'parsed', 'invalid') @(N $s @('$defs', 'contextFileParseStatusRules', 'allOf') | ForEach-Object { N $_ @('if', 'properties', 'parseStatus', 'const') }) 'shared parse-status rules changed.'
    $defs = @(
        @{ Name = 'currentContextFile'; Role = 'current';   Path = '^(?:.*[\\/])?context\.md$' },
        @{ Name = 'previousContextFile'; Role = 'previous'; Path = '^(?:.*[\\/])?context\.prev\.md$' },
        @{ Name = 'previous2ContextFile'; Role = 'previous2'; Path = '^(?:.*[\\/])?context\.prev2\.md$' }
    )
    foreach ($d in $defs) {
        $all = @(N $s @('$defs', $d.Name, 'allOf'))
        Eq 3 $all.Count "$($d.Name) must keep base + role/path + shared parse-status rules."
        Eq '#/$defs/contextFileBase' (P $all[0] '$ref') "$($d.Name) must reuse the base schema."
        Eq $d.Role (N $all[1] @('properties', 'role', 'const')) "$($d.Name) role binding changed."
        Eq $d.Path (N $all[1] @('properties', 'path', 'pattern')) "$($d.Name) path binding changed."
        Eq '#/$defs/contextFileParseStatusRules' (P $all[2] '$ref') "$($d.Name) must reuse the shared parse-status fragment."
    }
}

function Check-StateSchema {
    $s = Json $schemaPaths.State
    Eq '0.12.9' (N $s @('properties', 'schemaVersion', 'const')) 'global-workflow-state version changed.'
    SeqEq @('schemaVersion', 'layers') @($s.required) 'global-workflow-state top-level required set changed.'
    Eq $false (P $s 'additionalProperties') 'global-workflow-state must reject unknown top-level fields.'
    Eq $false (N $s @('properties', 'layers', 'additionalProperties')) 'global-workflow-state must reject unknown layers.'
    SeqEq @('taskBinding', 'contextChain', 'mcpRegistration', 'mcpInventory', 'preflight', 'coordinator', 'workflow', 'worker', 'result', 'acceptance', 'nextGate') @($s.properties.layers.required) 'global-workflow-state layer set changed.'
    SeqEq @('pending', 'ready', 'blocked', 'complete', 'unknown') @(N $s @('$defs', 'layerState', 'properties', 'status', 'enum')) 'global-workflow-state status enum changed.'
    Eq $false (N $s @('$defs', 'layerState', 'additionalProperties')) 'layerState must reject unknown nested fields.'
}

function Check-EnvelopeSchema {
    $s = Json $schemaPaths.Evidence
    Eq '0.12.9' (N $s @('properties', 'schemaVersion', 'const')) 'evidence-envelope version changed.'
    SeqEq @('schemaVersion', 'source', 'observedAt', 'redaction', 'advisoryOnly', 'authority') @($s.required) 'evidence-envelope required set changed.'
    Eq $false (P $s 'additionalProperties') 'evidence-envelope must reject unknown top-level fields.'
    Eq 'boolean' (N $s @('properties', 'advisoryOnly', 'type')) 'advisoryOnly must remain boolean.'
    SeqEq @('canonical', 'observed', 'advisory', 'historical', 'unverified') @(N $s @('properties', 'authority', 'enum')) 'authority layers changed.'
    SeqEq @('kind', 'identifier') @(N $s @('$defs', 'source', 'required')) 'evidence source required set changed.'
    Eq $false (N $s @('$defs', 'source', 'additionalProperties')) 'evidence source must reject unknown nested fields.'
    SeqEq @('level') @(N $s @('$defs', 'redaction', 'required')) 'redaction required set changed.'
    Eq $false (N $s @('$defs', 'redaction', 'additionalProperties')) 'redaction must reject unknown nested fields.'
}

function Check-SchemaFiles {
    foreach ($p in @($schemaPaths.Context, $schemaPaths.State, $schemaPaths.Evidence)) {
        Eq $true (Test-Path -LiteralPath $p -PathType Leaf) "Missing schema file: $p"
        $null = Json $p
    }
}

Invoke-TestCase 'schema files exist and parse as JSON' { Check-SchemaFiles }
Invoke-TestCase 'schema documents lock position-specific role/path rules and advisoryOnly shape' { Check-ContextSchema; Check-StateSchema; Check-EnvelopeSchema }
Invoke-TestCase 'context chain valid fixture keeps three ordered roles and paths' {
    $f = New-ContextChainFixture
    FailIfErrors (Validate-ContextChain $f) 'context-chain valid fixture'
    SeqEq @('current', 'previous', 'previous2') @($f.files.role) 'context-chain role order changed.'
    SeqEq @('docs/context.md', 'docs/context.prev.md', 'docs/context.prev2.md') @($f.files.path) 'context-chain path order changed.'
    Eq 'invalid' $f.files[1].parseStatus 'context-chain invalid status must remain explicit.'
}
Invoke-TestCase 'context chain rejects role/path misordering' {
    $f = New-ContextChainFixture
    $f.files[0].role = 'previous'; $f.files[0].path = 'docs/context.prev.md'
    $f.files[1].role = 'current';  $f.files[1].path = 'docs/context.md'
    Missing-Message (Validate-ContextChain $f) 'context-chain role/path misordering' 'role must be|path must match'
}
Invoke-TestCase 'context chain rejects missing parseStatus with exists and sha256 conflicts' {
    $f = New-ContextChainFixture
    $f.files[2].exists = $true
    $f.files[2].sha256 = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
    Missing-Message (Validate-ContextChain $f) 'context-chain missing conflict' 'parseStatus=missing requires exists=false|parseStatus=missing requires sha256=null'
}
Invoke-TestCase 'context chain rejects nested unknown property' {
    $f = New-ContextChainFixture
    $f.files[1] | Add-Member -NotePropertyName unexpectedNested -NotePropertyValue 'boom'
    Missing-Message (Validate-ContextChain $f) 'context-chain nested unknown property' 'contains unknown property'
}
Invoke-TestCase 'context chain accepts parseStatus=invalid with consistent exists and sha256' {
    FailIfErrors (Validate-ContextChain (New-ContextChainFixture)) 'context-chain invalid parseStatus fixture'
}
Invoke-TestCase 'context chain rejects invalid observedAt format' {
    $f = New-ContextChainFixture
    $f.files[0].observedAt = '2026-09-02 00:00:00'
    Missing-Message (Validate-ContextChain $f) 'context-chain invalid observedAt' 'observedAt must be an RFC 3339 date-time'
}
Invoke-TestCase 'context chain rejects invalid taskBinding observedAt format' {
    $f = New-ContextChainFixture
    $f.taskBinding.observedAt = '2026-09-02 00:00:00'
    Missing-Message (Validate-ContextChain $f) 'context-chain invalid taskBinding observedAt' 'observedAt must be an RFC 3339 date-time'
}
Invoke-TestCase 'context chain rejects nested unknown properties in scope and gates' {
    foreach ($spec in @(
        @{ Path = 'taskScope'; Name = 'unexpectedTaskScope' },
        @{ Path = 'taskBinding'; Name = 'unexpectedTaskBinding' },
        @{ Path = 'worktree'; Name = 'unexpectedWorktree' },
        @{ Path = 'auditDir'; Name = 'unexpectedAuditDir' },
        @{ Path = 'nextGate'; Name = 'unexpectedNextGate' }
    )) {
        $f = New-ContextChainFixture
        $target = P $f $spec.Path
        $target | Add-Member -NotePropertyName $spec.Name -NotePropertyValue 'boom'
        Missing-Message (Validate-ContextChain $f) "context-chain nested unknown property in $($spec.Path)" 'contains unknown property'
    }
}
Invoke-TestCase 'global workflow valid fixture keeps taskBinding ready without promoting acceptance or workflow' {
    $f = New-StateFixture
    FailIfErrors (Validate-State $f) 'global-workflow-state valid fixture'
    Eq 'ready' $f.layers.taskBinding.status 'taskBinding READY changed.'
    Eq 'pending' $f.layers.workflow.status 'workflow must stay pending unless explicitly set.'
    Eq 'pending' $f.layers.acceptance.status 'acceptance must stay pending unless explicitly set.'
}
Invoke-TestCase 'evidence envelope valid fixture accepts all authority layers and boolean advisoryOnly' {
    foreach ($a in @('canonical', 'observed', 'advisory', 'historical', 'unverified')) {
        $f = New-EnvelopeFixture -Authority $a -AdvisoryOnly $true
        FailIfErrors (Validate-Envelope $f) "evidence-envelope valid fixture $a"
        Eq $true ($f.advisoryOnly -is [bool]) "advisoryOnly must remain boolean for authority '$a'."
        Eq $true $f.advisoryOnly "advisoryOnly must remain true for authority '$a'."
    }
}
Invoke-TestCase 'evidence envelope rejects non-boolean advisoryOnly and missing redaction' {
    $f = New-EnvelopeFixture -Authority 'advisory' -AdvisoryOnly $true
    $f.advisoryOnly = 'true'
    $f.PSObject.Properties.Remove('redaction')
    Missing-Message (Validate-Envelope $f) 'evidence-envelope invalid fixture' 'advisoryOnly must be a boolean|missing required property ''redaction'''
}

if ($script:Failures.Count -gt 0) {
    Write-Host ''
    Write-Host "Global workflow tests failed: $($script:Failures.Count) failure(s), $script:Passes pass(es)." -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor DarkRed }
    exit 1
}

Write-Host ''
Write-Host "Global workflow tests passed: $script:Passes test(s)." -ForegroundColor Green
exit 0
