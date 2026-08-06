[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$ProjectPath,
    [ValidateSet('dry-run', 'live')][string]$Mode = 'dry-run',
    [string]$ArtifactRoot,
    [switch]$AllowNonAtomicTaskBindingUpdate
)

$ErrorActionPreference = 'Stop'
$executor = Join-Path $PSScriptRoot 'MethodLayer.Executor.psm1'
$transport = Join-Path $PSScriptRoot 'CcPanesMcp.Transport.psm1'
$adapter = Join-Path (Split-Path -Parent $PSScriptRoot) 'adapter/MethodLayer.Adapter.psm1'
Import-Module $executor -Force
Import-Module $adapter -Force

if ($Mode -eq 'live') {
    Import-Module $transport -Force
    $invoker = { param($Tool, $Request) Invoke-CcPanesMcpTool -Tool $Tool -Request $Request }
    try {
        $result = Invoke-ControllerExecution -PlanPath $PlanPath -ProjectPath $ProjectPath -Mode live -ArtifactRoot $ArtifactRoot -TransportTargetProjectPath $ProjectPath -AllowNonAtomicTaskBindingUpdate:$AllowNonAtomicTaskBindingUpdate -TransportInvoker $invoker
    }
    finally {
        Disconnect-CcPanesMcp
    }
}
else {
    $result = Invoke-ControllerExecution -PlanPath $PlanPath -ProjectPath $ProjectPath -Mode dry-run -ArtifactRoot $ArtifactRoot
}

ConvertTo-StableJson -Value $result
if ($result.status -eq 'failed') { exit 1 }
if ($result.status -eq 'manual-review') { exit 2 }
exit 0
