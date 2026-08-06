$script:TestPasses = 0
$script:TestFailures = [System.Collections.Generic.List[string]]::new()

function Invoke-TestCase {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Body
    )

    try {
        & $Body
        $script:TestPasses++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    catch {
        $message = "$Name :: $($_.Exception.Message)"
        $script:TestFailures.Add($message)
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

function Assert-False {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [string]$Message = 'Expected false.'
    )

    if ($Condition) {
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

function Assert-Contains {
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        [Parameter(Mandatory)]
        [string]$Expected,
        [string]$Message = 'Text does not contain expected value.'
    )

    if (-not $Text.Contains($Expected)) {
        throw "$Message Expected fragment='$Expected'"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Body,
        [string]$Pattern
    )

    $thrown = $false
    try {
        & $Body
    }
    catch {
        $thrown = $true
        if ($Pattern -and $_.Exception.Message -notmatch $Pattern) {
            throw "Exception did not match '$Pattern': $($_.Exception.Message)"
        }
    }

    if (-not $thrown) {
        throw 'Expected an exception.'
    }
}

function Assert-JsonValueMatchesSchema {
    param(
        [Parameter(Mandatory)]
        $Value,
        [Parameter(Mandatory)]
        [string]$SchemaPath
    )

    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "Schema file does not exist: $SchemaPath"
    }

    $json = $Value | ConvertTo-Json -Depth 100 -Compress
    $validationErrors = @()
    $valid = Test-Json `
        -Json $json `
        -SchemaFile $SchemaPath `
        -ErrorAction SilentlyContinue `
        -ErrorVariable validationErrors
    if (-not $valid) {
        $details = @($validationErrors | ForEach-Object { $_.ToString() }) -join ' | '
        throw "JSON value failed schema '$SchemaPath'. $details"
    }
}

function Get-TestTempRoot {
    $testsRoot = Split-Path -Parent $PSScriptRoot
    return [System.IO.Path]::GetFullPath((Join-Path $testsRoot '.tmp'))
}

function New-AdapterTestProject {
    param(
        [Parameter(Mandatory)]
        [string]$TaskFixture
    )

    $tempRoot = Get-TestTempRoot
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $projectPath = Join-Path $tempRoot ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $projectPath -Force | Out-Null

    try {
        & git -C $projectPath init -b main *> $null
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to initialize fixture Git repository.'
        }

        Set-Content -LiteralPath (Join-Path $projectPath 'AGENTS.md') -Value '# Fixture rules' -Encoding utf8NoBOM
        $inputDir = Join-Path $projectPath 'input'
        New-Item -ItemType Directory -Path $inputDir -Force | Out-Null

        $task = Get-Content -Raw -LiteralPath $TaskFixture | ConvertFrom-Json
        $task.authorization.allowedPaths = @($projectPath)
        $task.baseline.projectPath = $projectPath
        $task.baseline.repoRoot = $projectPath
        $task.baseline.git.branch = 'main'
        $task.baseline.git.head = 'unborn'
        $task.baseline.git.status.state = 'untracked'
        $task.baseline.git.status.summary = 'Fixture repository contains untracked task inputs.'

        $taskPath = Join-Path $inputDir 'task.json'
        $task | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $taskPath -Encoding utf8NoBOM

        return [pscustomobject]@{
            ProjectPath = $projectPath
            TaskPath = $taskPath
            ArtifactRoot = Join-Path $projectPath '.ccpanes-method/v0.1'
        }
    }
    catch {
        if (Test-Path -LiteralPath $projectPath) {
            Remove-Item -LiteralPath $projectPath -Recurse -Force
        }
        throw
    }
}

function Remove-AdapterTestProject {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    $tempRoot = (Get-TestTempRoot).TrimEnd('\', '/')
    $resolved = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/')
    $prefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing fixture cleanup outside tests temp root: $resolved"
    }
    if (Test-Path -LiteralPath $resolved) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

function Invoke-AdapterScript {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    $output = & $ScriptPath @Parameters
    $json = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "Adapter script returned no JSON: $ScriptPath"
    }
    return $json | ConvertFrom-Json
}

function Set-FixtureProjectPath {
    param(
        [Parameter(Mandatory)]
        [string]$FixturePath,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    $value = Get-Content -Raw -LiteralPath $FixturePath | ConvertFrom-Json
    if ($value.PSObject.Properties.Name -contains 'projectPath') {
        $value.projectPath = $ProjectPath
    }
    $value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
}

function Complete-TestRun {
    param([string]$Label = 'Adapter')

    if ($script:TestFailures.Count -gt 0) {
        Write-Host ""
        Write-Host "$Label tests failed: $($script:TestFailures.Count) failure(s), $script:TestPasses pass(es)." -ForegroundColor Red
        foreach ($failure in $script:TestFailures) {
            Write-Host "  - $failure" -ForegroundColor DarkRed
        }
        exit 1
    }

    Write-Host ""
    Write-Host "$Label tests passed: $script:TestPasses test(s)." -ForegroundColor Green
    exit 0
}
