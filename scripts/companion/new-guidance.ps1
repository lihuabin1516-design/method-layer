[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ContextPath
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'MethodLayer.Companion.psm1'
Import-Module $modulePath -Force

ConvertTo-OfficialCompanionGuidanceJson -ContextPath $ContextPath
