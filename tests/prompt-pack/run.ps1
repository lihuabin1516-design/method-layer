[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:Passes = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$schemaPath = Join-Path $root 'schemas/prompt-pack.internal.schema.json'
$packRoot = Join-Path $root 'prompt-packs/java-enterprise'
$packPath = Join-Path $packRoot 'pack.json'
$evalPath = Join-Path $packRoot 'evals/cases.json'
$lockedCommit = '1959b508696c7d92d550c152c735f49ed6dafbe2'

function Invoke-TestCase {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Body
    )

    try {
        & $Body
        $script:Passes++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    catch {
        $message = "$Name :: $($_.Exception.Message)"
        $script:Failures.Add($message)
        Write-Host "[FAIL] $message" -ForegroundColor Red
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [string]$Message = 'Expected true.'
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [string]$Message = 'Values differ.'
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected='$Expected' Actual='$Actual'"
    }
}

function Assert-SequenceEqual {
    param(
        [AllowEmptyCollection()]
        [object[]]$Expected = @(),
        [AllowEmptyCollection()]
        [object[]]$Actual = @(),
        [string]$Message = 'Sequences differ.'
    )

    $expectedText = @($Expected) -join '|'
    $actualText = @($Actual) -join '|'
    Assert-Equal $expectedText $actualText $Message
}

function Get-ContainedFile {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Rooted path is not allowed: $RelativePath"
    }

    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    $prefix = $base + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes Prompt Pack root: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Referenced file does not exist: $RelativePath"
    }
    return $resolved
}

function ConvertTo-ComparablePromptText {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    return [regex]::Replace($Text.ToLowerInvariant(), '[^\p{L}\p{Nd}]', '')
}

function Get-Sha256Hex {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

function Get-EvalResult {
    param(
        [Parameter(Mandatory)]
        $Case,
        [Parameter(Mandatory)]
        $Pack,
        [Parameter(Mandatory)]
        [object[]]$Profiles
    )

    $violations = [System.Collections.Generic.List[string]]::new()

    foreach ($action in @($Case.requestedActions)) {
        if (@($Case.authorizedActions) -notcontains $action) {
            $violations.Add('authorization-expansion')
            break
        }
    }

    $selected = [System.Collections.Generic.List[string]]::new()
    foreach ($rule in @($Pack.composition.stageRules)) {
        if ($rule.stage -eq $Case.stage) {
            foreach ($id in @($rule.promptIds)) {
                if (-not $selected.Contains($id)) {
                    $selected.Add($id)
                }
            }
        }
    }
    foreach ($rule in @($Pack.composition.changeTypeRules)) {
        if ($rule.changeType -eq $Case.changeType) {
            foreach ($id in @($rule.promptIds)) {
                if (-not $selected.Contains($id)) {
                    $selected.Add($id)
                }
            }
        }
    }
    foreach ($rule in @($Pack.composition.riskRules)) {
        if (@($Case.riskTags) -contains $rule.riskTag) {
            foreach ($id in @($rule.promptIds)) {
                if (-not $selected.Contains($id)) {
                    $selected.Add($id)
                }
            }
        }
    }

    $promptById = @{}
    foreach ($prompt in @($Pack.prompts)) {
        $promptById[$prompt.id] = $prompt
    }

    $ordered = @(
        foreach ($id in @($Pack.composition.order)) {
            if ($selected.Contains($id) -and
                $promptById.ContainsKey($id) -and
                @($promptById[$id].applicableStages) -contains $Case.stage) {
                $id
            }
        }
    )

    $requiredProjectFacts = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $ordered) {
        foreach ($inputName in @($promptById[$id].requiredInputs)) {
            if ($inputName -like 'projectFacts.*') {
                $factName = $inputName.Substring('projectFacts.'.Length)
                if (-not $requiredProjectFacts.Contains($factName)) {
                    $requiredProjectFacts.Add($factName)
                }
            }
        }
    }
    if ($requiredProjectFacts.Contains('technologyProfile')) {
        foreach ($technologyProfile in $Profiles) {
            foreach ($factName in @($technologyProfile.requiredProjectFacts)) {
                if (-not $requiredProjectFacts.Contains($factName)) {
                    $requiredProjectFacts.Add($factName)
                }
            }
        }
    }
    foreach ($factName in $requiredProjectFacts) {
        if (@($Case.providedFacts) -notcontains $factName) {
            $violations.Add('missing-project-facts')
            break
        }
    }

    $requiredOutputSections = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $ordered) {
        foreach ($section in @($promptById[$id].outputContract)) {
            if (-not $requiredOutputSections.Contains($section)) {
                $requiredOutputSections.Add($section)
            }
        }
    }
    $missingOutputSections = @(
        foreach ($section in $requiredOutputSections) {
            if (@($Case.candidateOutputSections) -notcontains $section) {
                $section
            }
        }
    )
    if ($missingOutputSections -contains 'Acceptance Assertions') {
        $violations.Add('missing-acceptance-assertions')
    }
    if (@($missingOutputSections | Where-Object { $_ -ne 'Acceptance Assertions' }).Count -gt 0) {
        $violations.Add('missing-output-contract-section')
    }

    $candidateText = @($Case.candidateTextParts) -join ''
    if ($candidateText -match '\{\{input\.[A-Za-z0-9._-]+\}\}') {
        $violations.Add('unresolved-input-marker')
    }
    if ($candidateText -match '(?i)\b(?:Spring Boot|Java|MySQL|Redis)\s+v?\d+(?:\.\d+){0,2}\b') {
        $violations.Add('undeclared-fixed-framework-version')
    }

    $decision = if ($violations.Contains('missing-project-facts') -or
        $violations.Contains('authorization-expansion')) {
        'blocked'
    }
    elseif ($violations.Count -gt 0) {
        'fail'
    }
    else {
        'pass'
    }

    return [pscustomobject]@{
        decision = $decision
        promptIds = $ordered
        violations = @($violations)
    }
}

Invoke-TestCase 'required Prompt Pack artifacts exist' {
    foreach ($path in @($schemaPath, $packPath, $evalPath)) {
        Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing artifact: $path"
    }
}

if ((Test-Path -LiteralPath $schemaPath -PathType Leaf) -and
    (Test-Path -LiteralPath $packPath -PathType Leaf) -and
    (Test-Path -LiteralPath $evalPath -PathType Leaf)) {
    $pack = Get-Content -Raw -LiteralPath $packPath | ConvertFrom-Json
    $evalSuite = Get-Content -Raw -LiteralPath $evalPath | ConvertFrom-Json
    $fingerprintPath = Get-ContainedFile -BasePath $packRoot -RelativePath $pack.donorFingerprintRef
    $fingerprintSet = Get-Content -Raw -LiteralPath $fingerprintPath | ConvertFrom-Json
    $profileArtifacts = @(
        foreach ($profileRef in @($pack.profileRefs)) {
            $resolvedPath = Get-ContainedFile -BasePath $packRoot -RelativePath $profileRef
            [pscustomobject]@{
                Ref = $profileRef
                Path = $resolvedPath
                Value = Get-Content -Raw -LiteralPath $resolvedPath | ConvertFrom-Json
            }
        }
    )
    $profiles = @($profileArtifacts.Value)

    Invoke-TestCase 'pack, profile, and eval fixtures satisfy the internal schema' {
        foreach ($path in @($packPath, $evalPath, $fingerprintPath) + @($profileArtifacts.Path)) {
            $errors = @()
            $valid = Test-Json -LiteralPath $path -SchemaFile $schemaPath `
                -ErrorAction SilentlyContinue -ErrorVariable errors
            if (-not $valid) {
                throw "$path failed schema validation: $(@($errors) -join ' | ')"
            }
        }
    }

    Invoke-TestCase 'manifest cross-file references are complete and bounded' {
        $promptIds = @($pack.prompts.id)
        Assert-SequenceEqual ($promptIds | Sort-Object) (@($pack.composition.order) | Sort-Object) `
            'composition.order must contain every Prompt ID exactly once.'
        foreach ($ruleGroup in @(
                @($pack.composition.stageRules),
                @($pack.composition.changeTypeRules),
                @($pack.composition.riskRules)
            )) {
            foreach ($rule in $ruleGroup) {
                foreach ($promptId in @($rule.promptIds)) {
                    Assert-True ($promptIds -contains $promptId) "Composition references unknown Prompt ID: $promptId"
                }
            }
        }
        Assert-Equal @($pack.profileRefs).Count @($profileArtifacts).Count `
            'Every profileRefs entry must resolve to one bounded file.'
        $resolvedPackRef = Get-ContainedFile -BasePath $packRoot `
            -RelativePath (Join-Path 'evals' $evalSuite.packRef)
        Assert-Equal ([System.IO.Path]::GetFullPath($packPath)) $resolvedPackRef `
            'Eval suite packRef must resolve to the active manifest.'
        Assert-Equal $lockedCommit $fingerprintSet.sourceCommit `
            'Donor fingerprint source commit must match the pack source lock.'
        Assert-Equal $pack.sourceProvenance.repository $fingerprintSet.sourceRepository `
            'Donor fingerprint repository must match the pack source lock.'
        Assert-Equal 28 $fingerprintSet.sourceFileCount `
            'Donor fingerprint set must cover the observed 28 Markdown files.'
        Assert-Equal @($fingerprintSet.hashes).Count $fingerprintSet.hashCount `
            'Donor fingerprint hashCount must match the stored hash set.'
    }

    Invoke-TestCase 'public v0.1 artifact list is unchanged' {
        Assert-SequenceEqual @('task', 'run', 'evidence', 'handoff') @($pack.publicArtifactTypes)
        Assert-Equal 'none' $pack.publicArtifactImpact
    }

    Invoke-TestCase 'Prompt IDs and versions are unique and content files are bounded' {
        $identities = @($pack.prompts | ForEach-Object { "$($_.id)@$($_.version)" })
        Assert-Equal $identities.Count @($identities | Sort-Object -Unique).Count 'Duplicate Prompt identity.'
        foreach ($prompt in @($pack.prompts)) {
            $contentPath = Get-ContainedFile -BasePath $packRoot -RelativePath $prompt.contentPath
            $content = Get-Content -Raw -LiteralPath $contentPath
            Assert-True ($content.Length -lt 6000) "Prompt is unexpectedly large: $($prompt.contentPath)"
        }
    }

    Invoke-TestCase 'Prompt contracts are complete and declared inputs cover template markers' {
        foreach ($prompt in @($pack.prompts)) {
            Assert-True (@($prompt.requiredInputs).Count -gt 0) "requiredInputs empty: $($prompt.id)"
            Assert-True (@($prompt.outputContract).Count -gt 0) "outputContract empty: $($prompt.id)"
            Assert-True (@($prompt.acceptanceAssertions).Count -gt 0) "acceptanceAssertions empty: $($prompt.id)"
            Assert-Equal $lockedCommit $prompt.sourceProvenance.commit "Wrong provenance commit: $($prompt.id)"

            $contentPath = Get-ContainedFile -BasePath $packRoot -RelativePath $prompt.contentPath
            $content = Get-Content -Raw -LiteralPath $contentPath
            $declared = @($prompt.requiredInputs) + @($prompt.optionalInputs)
            $markers = [regex]::Matches($content, '\{\{input\.([A-Za-z0-9._-]+)\}\}')
            foreach ($marker in $markers) {
                $inputName = $marker.Groups[1].Value
                Assert-True ($declared -contains $inputName) "Undeclared input marker '$inputName' in $($prompt.id)"
            }
            $allMarkers = [regex]::Matches($content, '\{\{[^}]+\}\}')
            Assert-Equal $markers.Count $allMarkers.Count "Malformed template marker in $($prompt.id)"
        }
    }

    Invoke-TestCase 'donor-specific fixed implementation assumptions are absent from local Prompts' {
        $forbidden = @(
            'NewBusinessEntity',
            't_new_business',
            'WebSecurityConfigurerAdapter',
            'SECRET_KEY',
            'Spring Boot 2.7',
            'MySQL 8.0',
            '1000 QPS'
        )
        foreach ($prompt in @($pack.prompts)) {
            $contentPath = Get-ContainedFile -BasePath $packRoot -RelativePath $prompt.contentPath
            $content = Get-Content -Raw -LiteralPath $contentPath
            foreach ($fragment in $forbidden) {
                Assert-True (-not $content.Contains($fragment)) "Forbidden donor assumption '$fragment' in $($prompt.id)"
            }
        }
    }

    Invoke-TestCase 'local Prompts contain no large normalized donor passage' {
        $windowLength = [int]$fingerprintSet.windowLength
        $donorHashes = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($hash in @($fingerprintSet.hashes)) {
            [void]$donorHashes.Add([string]$hash)
        }
        foreach ($prompt in @($pack.prompts)) {
            $contentPath = Get-ContainedFile -BasePath $packRoot -RelativePath $prompt.contentPath
            $normalized = ConvertTo-ComparablePromptText `
                -Text (Get-Content -Raw -LiteralPath $contentPath)
            for ($index = 0; $index + $windowLength -le $normalized.Length; $index++) {
                $windowHash = Get-Sha256Hex -Text $normalized.Substring($index, $windowLength)
                Assert-True (-not $donorHashes.Contains($windowHash)) `
                    "Prompt contains a large normalized donor passage: $($prompt.contentPath)"
            }
        }
    }

    Invoke-TestCase 'profile keeps concrete versions in project facts' {
        $profile = @($profiles | Where-Object { $_.profileId -eq 'spring-enterprise' })
        Assert-Equal 1 $profile.Count 'Expected one spring-enterprise profile.'
        Assert-Equal 'project-fact-required' $profile[0].versionPolicy
        foreach ($fact in @('javaVersion', 'springVersion', 'buildTool', 'persistenceTechnology')) {
            Assert-True (@($profile[0].requiredProjectFacts) -contains $fact) "Missing profile fact: $fact"
        }
    }

    Invoke-TestCase 'eval suite covers all required deterministic scenarios' {
        $requiredCases = @(
            'normal-java-new-feature',
            'modify-existing-feature',
            'missing-critical-project-facts',
            'database-change',
            'authentication-or-authorization',
            'read-only-audit',
            'unresolved-input-marker',
            'authorization-expansion-attempt',
            'missing-acceptance-assertions',
            'fixed-framework-version-assumption',
            'stage-applicability-filter',
            'missing-output-contract-section',
            'missing-profile-required-fact'
        )
        foreach ($requiredCase in $requiredCases) {
            Assert-True (@($evalSuite.cases.id) -contains $requiredCase) "Missing required eval case: $requiredCase"
        }
        Assert-Equal @($evalSuite.cases.id).Count @($evalSuite.cases.id | Sort-Object -Unique).Count `
            'Eval case IDs must be unique.'
    }

    Invoke-TestCase 'all eval cases match their explicit expected results' {
        foreach ($case in @($evalSuite.cases)) {
            $actual = Get-EvalResult -Case $case -Pack $pack -Profiles $profiles
            Assert-Equal $case.expected.decision $actual.decision "Decision mismatch: $($case.id)"
            Assert-SequenceEqual @($case.expected.promptIds) @($actual.promptIds) "Prompt selection mismatch: $($case.id)"
            Assert-SequenceEqual @($case.expected.violations) @($actual.violations) "Violation mismatch: $($case.id)"
        }
    }
}

if ($script:Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Prompt Pack tests failed: $($script:Failures.Count) failure(s), $script:Passes pass(es)." -ForegroundColor Red
    foreach ($failure in $script:Failures) {
        Write-Host "  - $failure" -ForegroundColor DarkRed
    }
    exit 1
}

Write-Host ""
Write-Host "Prompt Pack tests passed: $script:Passes test(s)." -ForegroundColor Green
exit 0
