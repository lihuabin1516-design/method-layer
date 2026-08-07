[CmdletBinding()]
param(
    [ValidateSet('Fast', 'Full')]
    [string]$Mode = 'Full'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        Write-Host "[FAIL] Test-Json is unavailable and pwsh was not found." -ForegroundColor Red
        exit 1
    }

    Write-Host "[INFO] Relaunching validation with PowerShell 7: $($pwsh.Source)" -ForegroundColor Cyan
    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Mode $Mode
    exit $LASTEXITCODE
}

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] python is required for JSON syntax validation." -ForegroundColor Red
    exit 1
}

$root = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

$schemaByArtifact = @{
    task     = Join-Path $root 'schemas/task.schema.json'
    run      = Join-Path $root 'schemas/run.schema.json'
    evidence = Join-Path $root 'schemas/evidence.schema.json'
    handoff  = Join-Path $root 'schemas/handoff.schema.json'
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    $script:failures.Add($Message)
}

function Get-TestTempRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $root 'tests/.tmp')).TrimEnd('\', '/')
}

function Assert-TestTempEmpty {
    $tempRoot = Get-TestTempRoot
    $expected = [System.IO.Path]::GetFullPath((Join-Path $root 'tests/.tmp')).TrimEnd('\', '/')
    if (-not $tempRoot.Equals($expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Fail "tests temp root resolved unexpectedly: $tempRoot"
        return
    }
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $items = @(Get-ChildItem -LiteralPath $tempRoot -Force -Recurse)
    if ($items.Count -eq 0) {
        Write-Pass 'tests/.tmp is empty'
    }
    else {
        Write-Fail "tests/.tmp is not empty: $($items.Count) item(s)"
        foreach ($item in $items | Select-Object -First 20) {
            Write-Host "       $($item.FullName)" -ForegroundColor DarkRed
        }
    }
}

function Test-JsonSyntax {
    param([System.IO.FileInfo]$File)

    & python -m json.tool $File.FullName *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Pass "JSON syntax: $($File.FullName.Substring($root.Length + 1))"
    }
    else {
        Write-Fail "JSON syntax: $($File.FullName.Substring($root.Length + 1))"
    }
}

function Test-Example {
    param(
        [System.IO.FileInfo]$File,
        [bool]$ExpectedValid
    )

    $instance = Get-Content -Raw -LiteralPath $File.FullName | ConvertFrom-Json
    $artifactType = [string]$instance.artifactType
    if (-not $schemaByArtifact.ContainsKey($artifactType)) {
        Write-Fail "Unknown artifactType '$artifactType' in $($File.Name)"
        return
    }

    $validationErrors = @()
    $actualValid = Test-Json `
        -LiteralPath $File.FullName `
        -SchemaFile $schemaByArtifact[$artifactType] `
        -ErrorAction SilentlyContinue `
        -ErrorVariable validationErrors

    $relativePath = $File.FullName.Substring($root.Length + 1)
    if ($actualValid -eq $ExpectedValid) {
        $expectation = if ($ExpectedValid) { 'valid' } else { 'invalid' }
        Write-Pass "Schema assertion: $relativePath is $expectation"
    }
    else {
        $expectation = if ($ExpectedValid) { 'pass' } else { 'fail' }
        Write-Fail "Schema assertion: $relativePath expected to $expectation"
        foreach ($validationError in $validationErrors) {
            Write-Host "       $validationError" -ForegroundColor DarkRed
        }
    }
}

function Test-PowerShellSyntax {
    param([System.IO.FileInfo]$File)

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $File.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if (@($parseErrors).Count -eq 0) {
        Write-Pass "PowerShell syntax: $($File.FullName.Substring($root.Length + 1))"
    }
    else {
        Write-Fail "PowerShell syntax: $($File.FullName.Substring($root.Length + 1))"
        foreach ($parseError in $parseErrors) {
            Write-Host "       $($parseError.Message)" -ForegroundColor DarkRed
        }
    }
}

$jsonFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $root 'schemas') -Filter '*.json' -File
    Get-ChildItem -LiteralPath (Join-Path $root 'examples') -Filter '*.json' -File -Recurse
    Get-ChildItem -LiteralPath (Join-Path $root 'templates') -Filter '*.json' -File
    Get-ChildItem -LiteralPath (Join-Path $root 'adapter/schemas') -Filter '*.json' -File
    Get-ChildItem -LiteralPath (Join-Path $root 'tests/adapter/fixtures') -Filter '*.json' -File
    Get-ChildItem -LiteralPath (Join-Path $root 'controller/schemas') -Filter '*.json' -File
    Get-ChildItem -LiteralPath (Join-Path $root 'tests/controller/fixtures') -Filter '*.json' -File
) | Sort-Object FullName

foreach ($jsonFile in $jsonFiles) {
    Test-JsonSyntax -File $jsonFile
}

foreach ($validExample in Get-ChildItem -LiteralPath (Join-Path $root 'examples/valid') -Filter '*.json' -File | Sort-Object Name) {
    Test-Example -File $validExample -ExpectedValid $true
}

foreach ($invalidExample in Get-ChildItem -LiteralPath (Join-Path $root 'examples/invalid') -Filter '*.json' -File | Sort-Object Name) {
    Test-Example -File $invalidExample -ExpectedValid $false
}

foreach ($jsonTemplate in Get-ChildItem -LiteralPath (Join-Path $root 'templates') -Filter '*.json' -File | Sort-Object Name) {
    Test-Example -File $jsonTemplate -ExpectedValid $true
}

$powerShellFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Include '*.ps1', '*.psm1' -File -Recurse
    Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Include '*.ps1', '*.psm1' -File -Recurse
) | Sort-Object FullName -Unique

foreach ($powerShellFile in $powerShellFiles) {
    Test-PowerShellSyntax -File $powerShellFile
}

if ($Mode -eq 'Full') {
    $adapterTests = Join-Path $root 'tests/adapter/run.ps1'
    if (Test-Path -LiteralPath $adapterTests -PathType Leaf) {
        Write-Host ""
        Write-Host "[INFO] Running adapter tests" -ForegroundColor Cyan
        & (Get-Command pwsh).Source -NoProfile -ExecutionPolicy Bypass -File $adapterTests
        if ($LASTEXITCODE -eq 0) {
            Write-Pass 'Adapter test suite'
        }
        else {
            Write-Fail "Adapter test suite exited $LASTEXITCODE"
        }
    }

    $controllerTests = Join-Path $root 'tests/controller/run.ps1'
    if (Test-Path -LiteralPath $controllerTests -PathType Leaf) {
        Write-Host ""
        Write-Host "[INFO] Running controller planner tests" -ForegroundColor Cyan
        & (Get-Command pwsh).Source -NoProfile -ExecutionPolicy Bypass -File $controllerTests
        if ($LASTEXITCODE -eq 0) {
            Write-Pass 'Controller planner test suite'
        }
        else {
            Write-Fail "Controller planner test suite exited $LASTEXITCODE"
        }
    }

    $executorTests = Join-Path $root 'tests/controller-executor/run.ps1'
    if (Test-Path -LiteralPath $executorTests -PathType Leaf) {
        Write-Host ""
        Write-Host "[INFO] Running controller executor tests" -ForegroundColor Cyan
        & (Get-Command pwsh).Source -NoProfile -ExecutionPolicy Bypass -File $executorTests
        if ($LASTEXITCODE -eq 0) {
            Write-Pass 'Controller executor test suite'
        }
        else {
            Write-Fail "Controller executor test suite exited $LASTEXITCODE"
        }
    }
}
else {
    Write-Host ""
    Write-Host "[INFO] Fast mode: skipped adapter/controller/executor test suites." -ForegroundColor Cyan
}

Assert-TestTempEmpty

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Validation failed: $($failures.Count) assertion(s)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Validation passed: $Mode validation assertions satisfied." -ForegroundColor Green
exit 0
