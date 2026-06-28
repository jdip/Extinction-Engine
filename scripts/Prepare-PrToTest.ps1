param(
    [switch] $Sign
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$branch = Assert-FeatureBranch
if ($branch -eq "test" -or $branch -eq "main") {
    throw "PR-to-test must run from a feature branch."
}

& (Join-Path $PSScriptRoot "New-ValidationProof.ps1") -Kind "pr-to-test" -TargetBranch "test" -Sign:$Sign

Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Review the proof files under docs/proofs/pr-to-test/test/."
Write-Host "2. Commit the proof files."
Write-Host "3. Open a PR from '$branch' to 'test'. GitHub should only run proof verification."
