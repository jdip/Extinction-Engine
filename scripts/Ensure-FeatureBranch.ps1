param(
    [switch] $RequireCodexPrefix,
    [switch] $AllowUnborn
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$branch = Assert-FeatureBranch -RequireCodexPrefix:$RequireCodexPrefix -AllowUnborn:$AllowUnborn
Write-Host "Feature branch check passed: $branch"
