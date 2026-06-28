param(
    [switch] $Sign
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$branch = Get-CurrentBranch
if ($branch -ne "test") {
    throw "Promotion proof must be generated from the 'test' branch. Current branch: '$branch'."
}

& (Join-Path $PSScriptRoot "New-ValidationProof.ps1") -Kind "promote-to-main" -TargetBranch "main" -Sign:$Sign

Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Review the proof files under docs/proofs/promote-to-main/main/."
Write-Host "2. Commit the proof files to 'test'."
Write-Host "3. Open a PR from 'test' to 'main'. GitHub should only run proof verification."
