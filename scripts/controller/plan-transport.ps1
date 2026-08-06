[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EnvelopePath,
    [string]$TaskBindingPath,
    [string]$PrepareEnvelopePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MethodLayer.Controller.psm1') -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'adapter/MethodLayer.Adapter.psm1') -Force

$envelope = Read-ControllerEnvelope -Path $EnvelopePath
$binding = if ($TaskBindingPath) {
    Read-ControllerTaskBinding -Path $TaskBindingPath
}
else {
    $null
}
$prepareEnvelope = if ($PrepareEnvelopePath) {
    $value = Read-ControllerEnvelope -Path $PrepareEnvelopePath
    if ([string]$value.envelopeType -ne 'prepare-launch-envelope') {
        throw 'PrepareEnvelopePath must contain a prepare-launch-envelope.'
    }
    $value
}
else {
    $null
}

$plan = New-ControllerTransportPlan `
    -Envelope $envelope `
    -TaskBinding $binding `
    -PrepareEnvelope $prepareEnvelope
Assert-ControllerTransportPlan -Plan $plan | Out-Null
ConvertTo-StableJson -Value $plan
