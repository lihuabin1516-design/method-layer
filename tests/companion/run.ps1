[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'adapter/TestHarness.ps1')

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$guidanceScript = Join-Path $root 'scripts/companion/new-guidance.ps1'
$requestSchema = Join-Path $root 'companion/schemas/official-companion-request.internal.schema.json'
$guidanceSchema = Join-Path $root 'companion/schemas/official-companion-guidance.internal.schema.json'

function Invoke-CompanionGuidance {
    param([Parameter(Mandatory)][string]$FixtureName)

    return Invoke-AdapterScript -ScriptPath $guidanceScript -Parameters @{
        ContextPath = Join-Path $fixtures $FixtureName
    }
}

function Assert-CompanionSchema {
    param([Parameter(Mandatory)]$Guidance)

    Assert-JsonValueMatchesSchema -Value $Guidance -SchemaPath $guidanceSchema
}

Invoke-TestCase 'request and guidance schemas are present' {
    Assert-True (Test-Path -LiteralPath $requestSchema -PathType Leaf) 'Missing official companion request schema.'
    Assert-True (Test-Path -LiteralPath $guidanceSchema -PathType Leaf) 'Missing official companion guidance schema.'
}

Invoke-TestCase 'official CC-Panes companion selects design prompts without runtime mutation' {
    $guidance = Invoke-CompanionGuidance -FixtureName 'design-request.json'
    Assert-CompanionSchema -Guidance $guidance

    Assert-Equal 'official-ccpanes-companion-guidance' $guidance.artifactType
    Assert-Equal 'fixture-java-design' $guidance.requestId
    Assert-Equal 'official-cc-panes' $guidance.target.product
    Assert-Equal 'cc-panes.exe' $guidance.target.exeName
    Assert-Equal 'external-companion' $guidance.target.integrationMode
    Assert-False ([bool]$guidance.target.launchesOfficialExe)
    Assert-False ([bool]$guidance.target.writesOfficialConfig)
    Assert-False ([bool]$guidance.target.mutatesHost)
    Assert-Equal 'remote-commit-reviewed' $guidance.pack.sourceState
    Assert-Equal '921725ec19930687e247841fdfa90bbbf3bf704b' $guidance.pack.methodLayerCommit
    Assert-Equal 'ready-to-copy' $guidance.decision
    Assert-Equal 'requirement-review|solution-design' (@($guidance.selectedPrompts.id) -join '|')
    Assert-Equal 0 @($guidance.missingProjectFacts).Count
    Assert-Equal 0 @($guidance.authorizationViolations).Count
    Assert-False ([bool]$guidance.copyPlan.containsPromptBodies)
    Assert-Contains (@($guidance.deniedOperations) -join '|') 'mutateOfficialCcPanesConfig'
}

Invoke-TestCase 'missing technology facts block guidance before copy' {
    $guidance = Invoke-CompanionGuidance -FixtureName 'missing-facts-request.json'
    Assert-CompanionSchema -Guidance $guidance

    Assert-Equal 'blocked-input-gap' $guidance.decision
    Assert-Equal 'requirement-review|solution-design|persistence-design' (@($guidance.selectedPrompts.id) -join '|')
    Assert-Contains (@($guidance.missingProjectFacts) -join '|') 'javaVersion'
    Assert-Contains (@($guidance.missingProjectFacts) -join '|') 'springVersion'
    Assert-Contains (@($guidance.copyPlan.steps) -join '|') 'Collect the missing project facts before copying guidance into official CC-Panes.'
}

Invoke-TestCase 'requested actions outside authorization block companion guidance' {
    $guidance = Invoke-CompanionGuidance -FixtureName 'authorization-expansion-request.json'
    Assert-CompanionSchema -Guidance $guidance

    Assert-Equal 'blocked-authorization' $guidance.decision
    Assert-Equal 'implement' (@($guidance.authorizationViolations) -join '|')
    Assert-Contains (@($guidance.copyPlan.steps) -join '|') 'Reduce requested actions or expand task authorization outside this companion.'
}

Invoke-TestCase 'official host mutation fields are rejected by schema' {
    Assert-Throws {
        Invoke-CompanionGuidance -FixtureName 'invalid-host-mutation-request.json'
    } 'schema|valid|writeUserConfig'
}

Invoke-TestCase 'guidance output stays metadata-only and contains no prompt body or host token' {
    $guidance = Invoke-CompanionGuidance -FixtureName 'design-request.json'
    $json = $guidance | ConvertTo-Json -Depth 100 -Compress

    Assert-False $json.Contains('{{input.') 'Prompt body marker leaked into guidance output.'
    Assert-False $json.Contains('CC_PANES_API_TOKEN') 'Runtime token name leaked into guidance output.'
    Assert-False $json.Contains('C:\\Users\\') 'Host absolute path leaked into guidance output.'
    Assert-False $json.Contains('D:\\cc-pane') 'PaneForge or host checkout path leaked into guidance output.'
}

Complete-TestRun -Label 'Official companion'
