Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:AdapterModule = Join-Path $script:RepositoryRoot 'scripts/adapter/MethodLayer.Adapter.psm1'
$script:RequestSchema = Join-Path $script:RepositoryRoot 'companion/schemas/official-companion-request.internal.schema.json'
$script:GuidanceSchema = Join-Path $script:RepositoryRoot 'companion/schemas/official-companion-guidance.internal.schema.json'
$script:PackPath = Join-Path $script:RepositoryRoot 'prompt-packs/java-enterprise/pack.json'
$script:MethodLayerCommit = '921725ec19930687e247841fdfa90bbbf3bf704b'

Import-Module $script:AdapterModule -Force

function Read-OfficialCompanionRequest {
    param([Parameter(Mandatory)][string]$Path)

    Assert-JsonSchema -Path $Path -SchemaPath $script:RequestSchema | Out-Null
    return Read-JsonFile -Path $Path
}

function Read-OfficialPromptPack {
    Assert-JsonSchema -Path $script:PackPath -SchemaPath (Join-Path $script:RepositoryRoot 'schemas/prompt-pack.internal.schema.json') | Out-Null
    return Read-JsonFile -Path $script:PackPath
}

function Read-OfficialPromptProfiles {
    param([Parameter(Mandatory)]$Pack)

    $profiles = [System.Collections.Generic.List[object]]::new()
    foreach ($profileRef in @($Pack.profileRefs)) {
        if ([System.IO.Path]::IsPathRooted([string]$profileRef)) {
            throw "Prompt profile reference must be relative: $profileRef"
        }
        $profilePath = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $script:PackPath) ([string]$profileRef)))
        $packRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $script:PackPath)).TrimEnd('\', '/')
        $prefix = $packRoot + [System.IO.Path]::DirectorySeparatorChar
        if (-not $profilePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Prompt profile reference escapes pack root: $profileRef"
        }
        Assert-JsonSchema -Path $profilePath -SchemaPath (Join-Path $script:RepositoryRoot 'schemas/prompt-pack.internal.schema.json') | Out-Null
        $profiles.Add((Read-JsonFile -Path $profilePath))
    }
    return @($profiles)
}

function Add-UniqueString {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$List,
        [Parameter(Mandatory)][string]$Value
    )

    if (-not $List.Contains($Value)) {
        $List.Add($Value)
    }
}

function Get-OfficialSelectedPromptIds {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Pack
    )

    $nominated = [System.Collections.Generic.List[string]]::new()
    foreach ($rule in @($Pack.composition.stageRules)) {
        if ([string]$rule.stage -eq [string]$Request.task.stage) {
            foreach ($id in @($rule.promptIds)) {
                Add-UniqueString -List $nominated -Value ([string]$id)
            }
        }
    }
    foreach ($rule in @($Pack.composition.changeTypeRules)) {
        if ([string]$rule.changeType -eq [string]$Request.task.changeType) {
            foreach ($id in @($rule.promptIds)) {
                Add-UniqueString -List $nominated -Value ([string]$id)
            }
        }
    }
    foreach ($rule in @($Pack.composition.riskRules)) {
        if (@($Request.task.riskTags) -contains [string]$rule.riskTag) {
            foreach ($id in @($rule.promptIds)) {
                Add-UniqueString -List $nominated -Value ([string]$id)
            }
        }
    }

    $promptById = @{}
    foreach ($prompt in @($Pack.prompts)) {
        $promptById[[string]$prompt.id] = $prompt
    }

    $selected = [System.Collections.Generic.List[string]]::new()
    foreach ($id in @($Pack.composition.order)) {
        $idText = [string]$id
        if (
            $nominated.Contains($idText) -and
            $promptById.ContainsKey($idText) -and
            @($promptById[$idText].applicableStages) -contains [string]$Request.task.stage
        ) {
            $selected.Add($idText)
        }
    }
    return @($selected)
}

function Get-OfficialMissingProjectFacts {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][object[]]$SelectedPrompts,
        [Parameter(Mandatory)][object[]]$Profiles
    )

    $required = [System.Collections.Generic.List[string]]::new()
    foreach ($prompt in @($SelectedPrompts)) {
        foreach ($inputName in @($prompt.requiredInputs)) {
            $inputText = [string]$inputName
            if ($inputText.StartsWith('projectFacts.', [System.StringComparison]::Ordinal)) {
                Add-UniqueString -List $required -Value $inputText.Substring('projectFacts.'.Length)
            }
        }
    }
    if ($required.Contains('technologyProfile')) {
        foreach ($profile in @($Profiles)) {
            foreach ($factName in @($profile.requiredProjectFacts)) {
                Add-UniqueString -List $required -Value ([string]$factName)
            }
        }
    }

    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($factName in @($required)) {
        if (@($Request.projectFacts.provided) -notcontains $factName) {
            $missing.Add($factName)
        }
    }
    return @($missing)
}

function Get-OfficialAuthorizationViolations {
    param([Parameter(Mandatory)]$Request)

    $violations = [System.Collections.Generic.List[string]]::new()
    foreach ($action in @($Request.task.requestedActions)) {
        $actionText = [string]$action
        if (@($Request.task.authorizedActions) -notcontains $actionText) {
            Add-UniqueString -List $violations -Value $actionText
        }
    }
    return @($violations)
}

function New-OfficialSelectedPromptProjection {
    param([Parameter(Mandatory)]$Prompt)

    return [pscustomobject][ordered]@{
        id = [string]$Prompt.id
        version = [string]$Prompt.version
        title = [string]$Prompt.title
        purpose = [string]$Prompt.purpose
        applicableStages = @($Prompt.applicableStages | ForEach-Object { [string]$_ })
        requiredInputs = @($Prompt.requiredInputs | ForEach-Object { [string]$_ })
        outputContract = @($Prompt.outputContract | ForEach-Object { [string]$_ })
        acceptanceAssertions = @($Prompt.acceptanceAssertions | ForEach-Object { [string]$_ })
        contentPath = [string]$Prompt.contentPath
    }
}

function New-OfficialCopyPlan {
    param(
        [Parameter(Mandatory)][string]$Decision
    )

    $steps = switch ($Decision) {
        'blocked-authorization' {
            @(
                'Reduce requested actions or expand task authorization outside this companion.',
                'Re-run companion guidance before using official CC-Panes.'
            )
        }
        'blocked-input-gap' {
            @(
                'Collect the missing project facts before copying guidance into official CC-Panes.',
                'Re-run companion guidance with the completed facts.'
            )
        }
        default {
            @(
                'Copy selected Prompt identities and output contracts into the official CC-Panes task/session prompt manually.',
                'Keep Prompt execution and any runtime composition inside the active official CC-Panes session under task authorization.',
                'Record selected Prompt ids in method-layer evidence if the target project tracks .ccpanes-method/.'
            )
        }
    }

    return [pscustomobject][ordered]@{
        targetSurface = 'official-ccpanes-manual-session-or-existing-transport'
        containsPromptBodies = $false
        steps = @($steps)
    }
}

function New-OfficialCompanionGuidance {
    param([Parameter(Mandatory)]$Request)

    $pack = Read-OfficialPromptPack
    $profiles = @(Read-OfficialPromptProfiles -Pack $pack)
    $selectedIds = @(Get-OfficialSelectedPromptIds -Request $Request -Pack $pack)
    $promptById = @{}
    foreach ($prompt in @($pack.prompts)) {
        $promptById[[string]$prompt.id] = $prompt
    }
    $selectedPrompts = @(
        foreach ($id in $selectedIds) {
            New-OfficialSelectedPromptProjection -Prompt $promptById[$id]
        }
    )
    $missingFacts = @(Get-OfficialMissingProjectFacts -Request $Request -SelectedPrompts $selectedPrompts -Profiles $profiles)
    $authorizationViolations = @(Get-OfficialAuthorizationViolations -Request $Request)

    $decision = if ($authorizationViolations.Count -gt 0) {
        'blocked-authorization'
    }
    elseif ($missingFacts.Count -gt 0) {
        'blocked-input-gap'
    }
    else {
        'ready-to-copy'
    }

    $guidance = [pscustomobject][ordered]@{
        schemaVersion = '0.1-internal'
        artifactType = 'official-ccpanes-companion-guidance'
        requestId = [string]$Request.requestId
        createdAt = [DateTimeOffset]::UtcNow.ToString('o')
        target = [pscustomobject][ordered]@{
            product = 'official-cc-panes'
            exeName = 'cc-panes.exe'
            integrationMode = 'external-companion'
            launchesOfficialExe = $false
            writesOfficialConfig = $false
            mutatesHost = $false
        }
        pack = [pscustomobject][ordered]@{
            packId = [string]$pack.packId
            version = [string]$pack.version
            owner = [string]$pack.owner
            sourceState = 'remote-commit-reviewed'
            methodLayerCommit = $script:MethodLayerCommit
            publicArtifactImpact = [string]$pack.publicArtifactImpact
        }
        decision = $decision
        selectedPrompts = @($selectedPrompts)
        missingProjectFacts = @($missingFacts)
        authorizationViolations = @($authorizationViolations)
        copyPlan = New-OfficialCopyPlan -Decision $decision
        deniedOperations = @(
            'launchOfficialCcPanesExe',
            'mutateOfficialCcPanesConfig',
            'writeUserGlobalConfig',
            'installPluginOrHook',
            'registerMcpServer',
            'executePrompt',
            'composeRuntimePrompt',
            'mutatePromptPackSource',
            'persistPromptBody'
        )
        notes = @(
            'Official CC-Panes remains the authority for panes, sessions, PTY, and existing runtime surfaces.',
            'This companion only returns metadata guidance derived from ccpanes-method-layer Prompt Pack files.',
            'Task authorization, repository facts, stop conditions, and acceptance evidence stay outside Prompt Pack content.'
        )
    }

    Assert-JsonValueSchema -Value $guidance -SchemaPath $script:GuidanceSchema | Out-Null
    return $guidance
}

function ConvertTo-OfficialCompanionGuidanceJson {
    param([Parameter(Mandatory)][string]$ContextPath)

    $request = Read-OfficialCompanionRequest -Path $ContextPath
    $guidance = New-OfficialCompanionGuidance -Request $request
    return ConvertTo-StableJson -Value $guidance
}
