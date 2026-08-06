Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ProtocolSchemas = @{
    task = Join-Path $script:RepositoryRoot 'schemas/task.schema.json'
    run = Join-Path $script:RepositoryRoot 'schemas/run.schema.json'
    evidence = Join-Path $script:RepositoryRoot 'schemas/evidence.schema.json'
    handoff = Join-Path $script:RepositoryRoot 'schemas/handoff.schema.json'
}
$script:InternalSchemas = @{
    launchAttempt = Join-Path $script:RepositoryRoot 'adapter/schemas/launch-attempt.internal.schema.json'
    launchResponse = Join-Path $script:RepositoryRoot 'adapter/schemas/launch-response.internal.schema.json'
    taskBinding = Join-Path $script:RepositoryRoot 'adapter/schemas/task-binding.internal.schema.json'
    handoffContext = Join-Path $script:RepositoryRoot 'adapter/schemas/handoff-context.internal.schema.json'
    prepareLaunchEnvelope = Join-Path $script:RepositoryRoot 'adapter/schemas/prepare-launch-envelope.internal.schema.json'
    bindLaunchEnvelope = Join-Path $script:RepositoryRoot 'adapter/schemas/bind-launch-envelope.internal.schema.json'
    finishRunEnvelope = Join-Path $script:RepositoryRoot 'adapter/schemas/finish-run-envelope.internal.schema.json'
    handoffEnvelope = Join-Path $script:RepositoryRoot 'adapter/schemas/handoff-envelope.internal.schema.json'
    recoveryEnvelope = Join-Path $script:RepositoryRoot 'adapter/schemas/recovery-envelope.internal.schema.json'
}

function Get-MethodLayerRepositoryRoot {
    return $script:RepositoryRoot
}

function Get-MethodSchemaPath {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('task', 'run', 'evidence', 'handoff')]
        [string]$ArtifactType
    )
    return $script:ProtocolSchemas[$ArtifactType]
}

function Get-InternalSchemaPath {
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'launchAttempt',
            'launchResponse',
            'taskBinding',
            'handoffContext',
            'prepareLaunchEnvelope',
            'bindLaunchEnvelope',
            'finishRunEnvelope',
            'handoffEnvelope',
            'recoveryEnvelope'
        )]
        [string]$Name
    )
    return $script:InternalSchemas[$Name]
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file does not exist: $Path"
    }
    try {
        return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON '$Path': $($_.Exception.Message)"
    }
}

function Assert-JsonSchema {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$SchemaPath
    )

    if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
        throw 'PowerShell Test-Json is required.'
    }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "Schema does not exist: $SchemaPath"
    }

    $validationErrors = @()
    $valid = Test-Json -LiteralPath $Path -SchemaFile $SchemaPath -ErrorAction SilentlyContinue -ErrorVariable validationErrors
    if (-not $valid) {
        $details = ($validationErrors | ForEach-Object { $_.ToString() }) -join '; '
        throw "Schema validation failed for '$Path' against '$SchemaPath'. $details"
    }
    return $true
}

function Assert-JsonValueSchema {
    param(
        [Parameter(Mandatory)]
        $Value,
        [Parameter(Mandatory)]
        [string]$SchemaPath
    )

    if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
        throw 'PowerShell Test-Json is required.'
    }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "Schema does not exist: $SchemaPath"
    }

    $json = ConvertTo-StableJson -Value $Value
    $validationErrors = @()
    $valid = Test-Json `
        -Json $json `
        -SchemaFile $SchemaPath `
        -ErrorAction SilentlyContinue `
        -ErrorVariable validationErrors
    if (-not $valid) {
        $details = ($validationErrors | ForEach-Object { $_.ToString() }) -join '; '
        throw "Schema validation failed for in-memory JSON against '$SchemaPath'. $details"
    }
    return $true
}

function ConvertTo-ValidatedEnvelopeJson {
    param(
        [Parameter(Mandatory)]
        $Value,
        [Parameter(Mandatory)]
        [ValidateSet(
            'prepareLaunchEnvelope',
            'bindLaunchEnvelope',
            'finishRunEnvelope',
            'handoffEnvelope',
            'recoveryEnvelope'
        )]
        [string]$Name
    )

    Assert-JsonValueSchema -Value $Value -SchemaPath (Get-InternalSchemaPath -Name $Name) | Out-Null
    return ConvertTo-StableJson -Value $Value
}

function Assert-ProtocolVersion {
    param(
        [Parameter(Mandatory)]
        $Artifact
    )

    if ([string]$Artifact.protocolVersion -ne '0.1') {
        throw "Unsupported protocol version '$($Artifact.protocolVersion)'; expected 0.1."
    }
}

function Read-MethodArtifact {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [ValidateSet('task', 'run', 'evidence', 'handoff')]
        [string]$ArtifactType
    )

    Assert-JsonSchema -Path $Path -SchemaPath (Get-MethodSchemaPath -ArtifactType $ArtifactType) | Out-Null
    $artifact = Read-JsonFile -Path $Path
    Assert-ProtocolVersion -Artifact $artifact
    if ([string]$artifact.artifactType -ne $ArtifactType) {
        throw "Expected artifactType '$ArtifactType', found '$($artifact.artifactType)'."
    }
    return $artifact
}

function ConvertTo-ArtifactKey {
    param(
        [Parameter(Mandatory)]
        [string]$Identity
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Identity)
    $builder = [System.Text.StringBuilder]::new()
    foreach ($byte in $bytes) {
        $isAlphaNumeric =
            ($byte -ge [byte][char]'A' -and $byte -le [byte][char]'Z') -or
            ($byte -ge [byte][char]'a' -and $byte -le [byte][char]'z') -or
            ($byte -ge [byte][char]'0' -and $byte -le [byte][char]'9')
        if ($isAlphaNumeric -or $byte -in @([byte][char]'.', [byte][char]'_', [byte][char]'-')) {
            [void]$builder.Append([char]$byte)
        }
        else {
            [void]$builder.Append(('%{0:X2}' -f $byte))
        }
    }
    return $builder.ToString()
}

function ConvertFrom-ArtifactKey {
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $bytes = [System.Collections.Generic.List[byte]]::new()
    for ($index = 0; $index -lt $Key.Length; $index++) {
        if ($Key[$index] -eq '%') {
            if ($index + 2 -ge $Key.Length) {
                throw "Invalid percent-encoded artifact key: $Key"
            }
            $hex = $Key.Substring($index + 1, 2)
            try {
                $bytes.Add([Convert]::ToByte($hex, 16))
            }
            catch {
                throw "Invalid percent-encoded artifact key: $Key"
            }
            $index += 2
        }
        else {
            $charBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Key[$index])
            foreach ($byte in $charBytes) {
                $bytes.Add($byte)
            }
        }
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes.ToArray())
}

function Get-NormalizedFullPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    return [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Test-PathContained {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$Candidate
    )

    $normalizedRoot = Get-NormalizedFullPath -Path $Root
    $normalizedCandidate = Get-NormalizedFullPath -Path $Candidate
    if ($normalizedCandidate.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    return $normalizedCandidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePointEscape {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$Candidate
    )

    $normalizedRoot = Get-NormalizedFullPath -Path $Root
    $normalizedCandidate = Get-NormalizedFullPath -Path $Candidate
    if (-not (Test-PathContained -Root $normalizedRoot -Candidate $normalizedCandidate)) {
        throw "Candidate path escapes the contained root: $normalizedCandidate"
    }

    $current = $normalizedRoot
    if (Test-Path -LiteralPath $current) {
        $rootItem = Get-Item -LiteralPath $current -Force
        if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Artifact root is a reparse point: $current"
        }
    }

    $relative = [System.IO.Path]::GetRelativePath($normalizedRoot, $normalizedCandidate)
    foreach ($part in ($relative -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($part) -or $part -eq '.') {
            continue
        }
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse point or junction detected in contained path: $current"
            }
        }
    }
}

function Resolve-ContainedPath {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$ChildPath
    )

    if ([System.IO.Path]::IsPathRooted($ChildPath)) {
        throw "Rooted or absolute child path is not accepted: $ChildPath"
    }
    $normalizedRoot = Get-NormalizedFullPath -Path $Root
    $candidate = Get-NormalizedFullPath -Path (Join-Path $normalizedRoot $ChildPath)
    if (-not (Test-PathContained -Root $normalizedRoot -Candidate $candidate)) {
        throw "Child path escapes the contained root: $ChildPath"
    }
    Assert-NoReparsePointEscape -Root $normalizedRoot -Candidate $candidate
    return $candidate
}

function Resolve-ArtifactRoot {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [string]$ArtifactRoot,
        [switch]$Create
    )

    $project = Get-NormalizedFullPath -Path $ProjectPath
    $candidate = if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
        Join-Path $project '.ccpanes-method/v0.1'
    }
    elseif ([System.IO.Path]::IsPathRooted($ArtifactRoot)) {
        Get-NormalizedFullPath -Path $ArtifactRoot
    }
    else {
        Get-NormalizedFullPath -Path (Join-Path $project $ArtifactRoot)
    }

    if (-not (Test-PathContained -Root $project -Candidate $candidate)) {
        throw "Artifact root must remain within projectPath: $candidate"
    }
    Assert-NoReparsePointEscape -Root $project -Candidate $candidate
    if ($Create) {
        New-Item -ItemType Directory -Path $candidate -Force | Out-Null
    }
    return $candidate
}

function ConvertTo-ProjectRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $project = Get-NormalizedFullPath -Path $ProjectPath
    $candidate = Get-NormalizedFullPath -Path $Path
    if (-not (Test-PathContained -Root $project -Candidate $candidate)) {
        throw "Path is outside projectPath: $candidate"
    }
    return ([System.IO.Path]::GetRelativePath($project, $candidate) -replace '\\', '/')
}

function Get-ArtifactRootReferenceFromTaskPath {
    param(
        [Parameter(Mandatory)]
        [string]$TaskArtifactPath
    )

    $normalized = $TaskArtifactPath -replace '\\', '/'
    if ([System.IO.Path]::IsPathRooted($normalized)) {
        throw "Task artifact reference must be project-relative: $TaskArtifactPath"
    }
    $marker = '/tasks/'
    $index = $normalized.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -le 0) {
        throw "Task artifact reference does not contain an artifact-root tasks segment: $TaskArtifactPath"
    }
    return $normalized.Substring(0, $index)
}

function ConvertTo-CanonicalNode {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string] -or $Value -is [ValueType]) {
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
            $ordered[$key] = ConvertTo-CanonicalNode -Value $Value[$key]
        }
        return $ordered
    }
    if ($Value -is [pscustomobject]) {
        $ordered = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties.Name | Sort-Object)) {
            $ordered[$property] = ConvertTo-CanonicalNode -Value $Value.$property
        }
        return $ordered
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value | ForEach-Object { ConvertTo-CanonicalNode -Value $_ })
        return ,$items
    }
    return $Value
}

function ConvertTo-StableJson {
    param(
        [Parameter(Mandatory)]
        $Value,
        [switch]$Compress
    )

    $canonical = ConvertTo-CanonicalNode -Value $Value
    return $canonical | ConvertTo-Json -Depth 100 -Compress:$Compress
}

function Get-FileSha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function New-ValidatedTempJson {
    param(
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [Parameter(Mandatory)]
        $Value,
        [Parameter(Mandatory)]
        [string]$SchemaPath
    )

    $directory = Split-Path -Parent $TargetPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $tempPath = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($TargetPath) + '.tmp.' + [guid]::NewGuid().ToString('N'))
    try {
        $json = ConvertTo-StableJson -Value $Value
        Set-Content -LiteralPath $tempPath -Value $json -Encoding utf8NoBOM
        Assert-JsonSchema -Path $tempPath -SchemaPath $SchemaPath | Out-Null
        return [pscustomobject]@{
            Path = $tempPath
            Sha256 = Get-FileSha256 -Path $tempPath
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
        throw
    }
}

function Write-CreateOnceJson {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        $Value,
        [Parameter(Mandatory)]
        [string]$SchemaPath
    )

    $target = Get-NormalizedFullPath -Path $Path
    $temp = New-ValidatedTempJson -TargetPath $target -Value $Value -SchemaPath $SchemaPath
    try {
        if (Test-Path -LiteralPath $target) {
            $existingHash = Get-FileSha256 -Path $target
            if ($existingHash -eq $temp.Sha256) {
                return [pscustomobject]@{ Path = $target; Sha256 = $existingHash; Idempotent = $true }
            }
            throw "create-once conflict at '$target': existing and candidate SHA-256 differ."
        }
        try {
            [System.IO.File]::Move($temp.Path, $target)
        }
        catch [System.IO.IOException] {
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                $racedHash = Get-FileSha256 -Path $target
                if ($racedHash -eq $temp.Sha256) {
                    return [pscustomobject]@{ Path = $target; Sha256 = $racedHash; Idempotent = $true }
                }
                throw "create-once conflict at '$target': another writer published different content."
            }
            throw
        }
        $publishedHash = Get-FileSha256 -Path $target
        if ($publishedHash -ne $temp.Sha256) {
            throw "Published SHA-256 mismatch at '$target'."
        }
        return [pscustomobject]@{ Path = $target; Sha256 = $publishedHash; Idempotent = $false }
    }
    finally {
        if (Test-Path -LiteralPath $temp.Path) {
            Remove-Item -LiteralPath $temp.Path -Force
        }
    }
}

function Write-CompareAndSwapJson {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        $Value,
        [Parameter(Mandatory)]
        [string]$SchemaPath,
        [string]$ExpectedSha256
    )

    $target = Get-NormalizedFullPath -Path $Path
    if ($ExpectedSha256) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "compare-and-swap conflict: target does not exist: $target"
        }
        $actual = Get-FileSha256 -Path $target
        if ($actual -ne $ExpectedSha256.ToUpperInvariant()) {
            throw "compare-and-swap conflict at '$target': expected $ExpectedSha256, found $actual."
        }
    }

    $temp = New-ValidatedTempJson -TargetPath $target -Value $Value -SchemaPath $SchemaPath
    try {
        [System.IO.File]::Move($temp.Path, $target, $true)
        $publishedHash = Get-FileSha256 -Path $target
        if ($publishedHash -ne $temp.Sha256) {
            throw "Published SHA-256 mismatch at '$target'."
        }
        return [pscustomobject]@{ Path = $target; Sha256 = $publishedHash }
    }
    finally {
        if (Test-Path -LiteralPath $temp.Path) {
            Remove-Item -LiteralPath $temp.Path -Force
        }
    }
}

function Enter-TaskLock {
    param(
        [Parameter(Mandatory)]
        [string]$TaskDirectory,
        [Parameter(Mandatory)]
        [string]$Operation,
        [string]$Owner = 'local-adapter'
    )

    New-Item -ItemType Directory -Path $TaskDirectory -Force | Out-Null
    $lockPath = Join-Path $TaskDirectory '.adapter.lock.json'
    $record = [ordered]@{
        operationId = 'op-' + [guid]::NewGuid().ToString('N')
        pid = $PID
        owner = $Owner
        createdAt = [DateTimeOffset]::UtcNow.ToString('o')
        operation = $Operation
    }
    $json = $record | ConvertTo-Json -Compress
    try {
        $stream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        throw "Task lock conflict at '$lockPath'."
    }
    return [pscustomobject]@{ Path = $lockPath; Record = [pscustomobject]$record }
}

function Exit-TaskLock {
    param(
        [Parameter(Mandatory)]
        $Lock
    )
    if ($Lock.Path -and (Test-Path -LiteralPath $Lock.Path)) {
        Remove-Item -LiteralPath $Lock.Path -Force
    }
}

function Get-GitBaseline {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    $project = Get-NormalizedFullPath -Path $ProjectPath
    $repoRootOutput = @(& git -C $project rev-parse --show-toplevel 2>$null)
    $repoRootExit = $LASTEXITCODE
    $repoRoot = $repoRootOutput | Select-Object -First 1
    if ($repoRootExit -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
        throw "Project is not a Git worktree: $project"
    }
    $repoRoot = Get-NormalizedFullPath -Path $repoRoot
    $branchOutput = @(& git -C $project branch --show-current 2>$null)
    $branch = $branchOutput | Select-Object -First 1
    $headOutput = @(& git -C $project rev-parse --verify HEAD 2>$null)
    $headExit = $LASTEXITCODE
    $head = $headOutput | Select-Object -First 1
    if ($headExit -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
        $head = 'unborn'
    }
    $statusLines = @(& git -C $project status --porcelain=v1 --untracked-files=normal)
    $state = if ($statusLines.Count -eq 0) {
        'clean'
    }
    elseif (@($statusLines | Where-Object { $_ -notmatch '^\?\?' }).Count -eq 0) {
        'untracked'
    }
    elseif (@($statusLines | Where-Object { $_ -match '^\?\?' }).Count -eq 0) {
        'dirty'
    }
    else {
        'mixed'
    }
    $summary = if ($statusLines.Count -eq 0) {
        'Git status is clean.'
    }
    else {
        ($statusLines | Select-Object -First 20) -join '; '
    }
    return [pscustomobject]@{
        projectPath = $project
        repoRoot = $repoRoot
        branch = [string]$branch
        head = [string]$head
        state = $state
        summary = $summary
    }
}

function Compare-TaskBaseline {
    param(
        [Parameter(Mandatory)]
        $Task,
        [Parameter(Mandatory)]
        $Actual
    )

    foreach ($pair in @(
        @{ Name = 'projectPath'; Expected = (Get-NormalizedFullPath $Task.baseline.projectPath); Actual = $Actual.projectPath },
        @{ Name = 'repoRoot'; Expected = (Get-NormalizedFullPath $Task.baseline.repoRoot); Actual = $Actual.repoRoot },
        @{ Name = 'branch'; Expected = [string]$Task.baseline.git.branch; Actual = [string]$Actual.branch },
        @{ Name = 'head'; Expected = [string]$Task.baseline.git.head; Actual = [string]$Actual.head },
        @{ Name = 'status.state'; Expected = [string]$Task.baseline.git.status.state; Actual = [string]$Actual.state }
    )) {
        if ($pair.Expected -ne $pair.Actual) {
            throw "Task baseline mismatch for $($pair.Name): expected '$($pair.Expected)', actual '$($pair.Actual)'."
        }
    }
    return $true
}

function Assert-LaunchAuthorization {
    param(
        [Parameter(Mandatory)]
        $Task,
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [string[]]$ConditionalApproval
    )

    $project = Get-NormalizedFullPath -Path $ProjectPath
    $allowed = $false
    foreach ($allowedPath in @($Task.authorization.allowedPaths)) {
        $candidate = Get-NormalizedFullPath -Path ([string]$allowedPath)
        if (Test-PathContained -Root $candidate -Candidate $project) {
            $allowed = $true
            break
        }
    }
    if (-not $allowed) {
        throw "Project path is outside task authorization.allowedPaths: $project"
    }

    $conditionalActions = @()
    if ($Task.authorization.PSObject.Properties.Name -contains 'conditionalActions') {
        $conditionalActions = @($Task.authorization.conditionalActions)
    }
    $approvalCount = if ($null -eq $ConditionalApproval) {
        0
    }
    else {
        @($ConditionalApproval | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
    }
    if ($conditionalActions.Count -gt 0 -and $approvalCount -eq 0) {
        throw 'Task declares conditional actions; explicit conditional approval evidence is required.'
    }
    return $true
}

function New-AdapterId {
    param(
        [Parameter(Mandatory)]
        [string]$Prefix
    )
    return '{0}-{1}-{2}' -f $Prefix, ([DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
}

function New-LaunchPrompt {
    param(
        [Parameter(Mandatory)]
        $Task,
        [Parameter(Mandatory)]
        [string]$TaskPath,
        [Parameter(Mandatory)]
        [string]$RunId,
        [string[]]$ConditionalApproval
    )

    $conditional = if ($Task.authorization.PSObject.Properties.Name -contains 'conditionalActions') {
        @($Task.authorization.conditionalActions) -join "`n- "
    }
    else {
        'None declared.'
    }
    $approvalEvidence = if ($null -ne $ConditionalApproval -and @($ConditionalApproval).Count -gt 0) {
        @($ConditionalApproval) -join "`n- "
    }
    else {
        'None supplied.'
    }
    $lines = @(
        '# Method Layer Run',
        '',
        "Task ID: $($Task.taskId)",
        "Run ID: $RunId",
        "Task Artifact: $TaskPath",
        '',
        '## Objective',
        [string]$Task.objective,
        '',
        '## Authorization',
        'Allowed paths:',
        '- ' + (@($Task.authorization.allowedPaths) -join "`n- "),
        'Forbidden actions:',
        '- ' + (@($Task.authorization.forbiddenActions) -join "`n- "),
        'Conditional actions:',
        '- ' + $conditional,
        'Conditional approval evidence:',
        '- ' + $approvalEvidence,
        '',
        '## Baseline and Rules',
        "Project: $($Task.baseline.projectPath)",
        "Repository: $($Task.baseline.repoRoot)",
        "Branch: $($Task.baseline.git.branch)",
        "HEAD: $($Task.baseline.git.head)",
        'Rules:',
        '- ' + (@($Task.baseline.relevantRules) -join "`n- "),
        '',
        '## Acceptance',
        '- ' + (@($Task.acceptance) -join "`n- "),
        '',
        '## Required Evidence',
        '- ' + (@($Task.requiredEvidence) -join "`n- "),
        '',
        '## Stop Conditions',
        '- ' + (@($Task.stopConditions) -join "`n- "),
        '',
        '## Artifact Output Contract',
        'Publish evidence before emitting TaskBinding or leader-report envelopes.',
        'Keep full artifacts in files and place only references in TaskBinding metadata.',
        '',
        '## Completion Reporting Order',
        '1. Publish evidence.',
        '2. Call update_task_binding with the returned patch.',
        '3. Call report_to_leader with the returned report.',
        '4. Use reconcile_plan_collaboration when leader notification state is uncertain.'
    )
    return $lines -join "`n"
}

function New-RunContract {
    param(
        [Parameter(Mandatory)]
        $Task,
        [Parameter(Mandatory)]
        [string]$CapturedAt
    )

    $contract = [ordered]@{
        capturedAt = $CapturedAt
        objective = [string]$Task.objective
        allowedPaths = @($Task.authorization.allowedPaths)
        forbiddenActions = @($Task.authorization.forbiddenActions)
    }
    if ($Task.authorization.PSObject.Properties.Name -contains 'conditionalActions') {
        $contract.conditionalActions = @($Task.authorization.conditionalActions)
    }
    $contract.acceptance = @($Task.acceptance)
    $contract.requiredEvidence = @($Task.requiredEvidence)
    $contract.stopConditions = @($Task.stopConditions)
    return [pscustomobject]$contract
}

function New-MethodLayerMetadataPatch {
    param(
        [Parameter(Mandatory)]
        [string]$TaskId,
        [Parameter(Mandatory)]
        [string]$RunId,
        [Parameter(Mandatory)]
        [string]$ArtifactRoot,
        [Parameter(Mandatory)]
        [string]$TaskPath,
        [Parameter(Mandatory)]
        [string]$RunPath,
        [string]$LatestEvidencePath,
        [string]$LatestHandoffPath
    )

    $method = [ordered]@{
        protocolVersion = '0.1'
        taskId = $TaskId
        runId = $RunId
        artifactRoot = ($ArtifactRoot -replace '\\', '/')
        taskPath = ($TaskPath -replace '\\', '/')
        runPath = ($RunPath -replace '\\', '/')
    }
    if ($LatestEvidencePath) {
        $method.latestEvidencePath = ($LatestEvidencePath -replace '\\', '/')
    }
    if ($LatestHandoffPath) {
        $method.latestHandoffPath = ($LatestHandoffPath -replace '\\', '/')
    }
    $patch = [pscustomobject]@{
        metadata = [pscustomobject]@{
            methodLayer = [pscustomobject]$method
        }
    }
    $size = [System.Text.Encoding]::UTF8.GetByteCount(($patch | ConvertTo-Json -Depth 20 -Compress))
    if ($size -ge 8192) {
        throw "TaskBinding metadata patch is $size bytes; expected less than 8192."
    }
    return $patch
}

function Test-EvidenceFinishGate {
    param(
        [Parameter(Mandatory)]
        $Task,
        [Parameter(Mandatory)]
        $Run,
        [Parameter(Mandatory)]
        $Evidence,
        $GitBaseline
    )

    if ($Evidence.taskId -ne $Task.taskId -or $Evidence.runId -ne $Run.runId) {
        return $false
    }
    $expectedContract = New-RunContract -Task $Task -CapturedAt ([string]$Run.contract.capturedAt)
    if (
        (ConvertTo-StableJson -Value $expectedContract -Compress) -ne
        (ConvertTo-StableJson -Value $Run.contract -Compress)
    ) {
        return $false
    }
    $requiredFailures = @($Evidence.checks | Where-Object { $_.required -and $_.status -ne 'pass' })
    if ($requiredFailures.Count -gt 0) {
        return $false
    }
    $coveredRequiredEvidence = @(
        $Evidence.checks |
            Where-Object { $_.required -and $_.status -eq 'pass' } |
            ForEach-Object { [string]$_.name }
    )
    foreach ($requirement in @($Task.requiredEvidence)) {
        if ($coveredRequiredEvidence -notcontains [string]$requirement) {
            return $false
        }
    }
    if (
        $Evidence.driftCheck.scope -ne 'aligned' -or
        $Evidence.driftCheck.files -ne 'aligned' -or
        $Evidence.driftCheck.acceptance -ne 'aligned'
    ) {
        return $false
    }
    if ($null -ne $GitBaseline) {
        if (
            [string]$Evidence.gitStatus.branch -ne [string]$GitBaseline.branch -or
            [string]$Evidence.gitStatus.head -ne [string]$GitBaseline.head -or
            [string]$Evidence.gitStatus.state -ne [string]$GitBaseline.state
        ) {
            return $false
        }
    }
    return $Evidence.outcome -eq 'completed'
}

function New-SummaryOnlyEvidence {
    param(
        [Parameter(Mandatory)]
        $Run,
        [Parameter(Mandatory)]
        $TaskBinding,
        [Parameter(Mandatory)]
        $GitBaseline,
        [Parameter(Mandatory)]
        [string]$RunReferencePath
    )

    $outcome = if ($TaskBinding.status -eq 'failed') { 'failed' } else { 'blocked' }
    $summary = if ($TaskBinding.PSObject.Properties.Name -contains 'completionSummary') {
        [string]$TaskBinding.completionSummary
    }
    else {
        'Worker finished without a completion summary or proof bundle.'
    }
    return [pscustomobject][ordered]@{
        protocolVersion = '0.1'
        artifactType = 'evidence'
        evidenceId = New-AdapterId -Prefix 'evidence'
        runId = [string]$Run.runId
        taskId = [string]$Run.taskRef.taskId
        completedAt = [DateTimeOffset]::UtcNow.ToString('o')
        outcome = $outcome
        summary = $summary
        touchedFiles = @(
            [pscustomobject][ordered]@{
                path = $RunReferencePath
                action = 'inspected'
                notes = 'The adapter inspected the run artifact while recording missing proof.'
            }
        )
        checks = @(
            [pscustomobject][ordered]@{
                name = 'Worker proof bundle'
                command = 'evidence-not-provided'
                required = $true
                status = 'blocked'
                notes = 'completionSummary was available without fresh required-check evidence.'
            }
        )
        driftCheck = [pscustomobject][ordered]@{
            scope = 'needs-review'
            files = 'needs-review'
            acceptance = 'needs-review'
            notes = 'Drift was not established by a complete proof bundle.'
        }
        gitStatus = [pscustomobject][ordered]@{
            branch = [string]$GitBaseline.branch
            head = [string]$GitBaseline.head
            state = [string]$GitBaseline.state
            summary = [string]$GitBaseline.summary
        }
        residualRisk = [pscustomobject][ordered]@{
            level = 'high'
            summary = 'Method completion remains unverified because required evidence is incomplete.'
            items = @('Collect fresh checks and a complete touched-file/drift assessment.')
        }
        recommendedNextAction = 'Complete or review the evidence bundle before method completion.'
    }
}

Export-ModuleMember -Function @(
    'Get-MethodLayerRepositoryRoot',
    'Get-MethodSchemaPath',
    'Get-InternalSchemaPath',
    'Read-JsonFile',
    'Assert-JsonSchema',
    'Assert-JsonValueSchema',
    'ConvertTo-ValidatedEnvelopeJson',
    'Assert-ProtocolVersion',
    'Read-MethodArtifact',
    'ConvertTo-ArtifactKey',
    'ConvertFrom-ArtifactKey',
    'Test-PathContained',
    'Assert-NoReparsePointEscape',
    'Resolve-ContainedPath',
    'Resolve-ArtifactRoot',
    'ConvertTo-ProjectRelativePath',
    'Get-ArtifactRootReferenceFromTaskPath',
    'ConvertTo-StableJson',
    'Get-FileSha256',
    'Write-CreateOnceJson',
    'Write-CompareAndSwapJson',
    'Enter-TaskLock',
    'Exit-TaskLock',
    'Get-GitBaseline',
    'Compare-TaskBaseline',
    'Assert-LaunchAuthorization',
    'New-AdapterId',
    'New-LaunchPrompt',
    'New-RunContract',
    'New-MethodLayerMetadataPatch',
    'Test-EvidenceFinishGate',
    'New-SummaryOnlyEvidence'
)
