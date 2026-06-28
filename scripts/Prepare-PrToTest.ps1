param(
    [switch] $Sign,
    [switch] $NoPush,
    [switch] $NoPr,
    [switch] $ReadyForReview
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
$branch = Assert-FeatureBranch
if ($branch -eq "test" -or $branch -eq "main") {
    throw "PR-to-test must run from a feature branch."
}

$targetBranch = "test"
$repositoryFullName = Get-OriginRepositoryFullName
$safeBranch = Get-ProofSafeName $branch
$safeTarget = Get-ProofSafeName $targetBranch
$title = "[codex] $($branch -replace '^codex/', '' -replace '[-_]+', ' ')"
$title = $title.Trim()

Assert-CleanWorkingTree -Reason "PR-to-test requires feature work committed before proof generation."

$proofValid = $false
try {
    & (Join-Path $repoRoot "scripts/Verify-Proof.ps1") -Kind "pr-to-test" -TargetBranch $targetBranch
    $proofValid = $true
    Write-Host "Existing PR-to-test proof is valid for the current content digest."
}
catch {
    Write-Host "No valid PR-to-test proof found for the current content digest. Generating a new proof."
}

if (-not $proofValid) {
    $subjectHead = Get-HeadCommit
    $proofId = "pr-to-test-$safeTarget-$safeBranch-$($subjectHead.Substring(0, 12))"
    $proofDir = Join-Path $repoRoot "docs/proofs/pr-to-test/$safeTarget"
    $proofPath = Join-Path $proofDir "$proofId.proof.json"
    $proofHashPath = "$proofPath.sha256"
    $proofSignaturePath = "$proofPath.asc"

    & (Join-Path $PSScriptRoot "New-ValidationProof.ps1") -Kind "pr-to-test" -TargetBranch $targetBranch -Sign:$Sign
    & (Join-Path $repoRoot "scripts/Verify-Proof.ps1") -Kind "pr-to-test" -TargetBranch $targetBranch

    $pathsToStage = @($proofPath, $proofHashPath)
    if ($Sign) {
        $pathsToStage += $proofSignaturePath
    }

    foreach ($path in $pathsToStage) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Expected proof artifact was not created: $path"
        }
    }

    & git add -- $pathsToStage
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to stage generated proof artifacts."
    }

    & git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Generated proof artifacts were already committed."
    }
    else {
        & git commit -m "chore: add pr-to-test validation proof"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to commit generated proof artifacts."
        }
    }

    & (Join-Path $repoRoot "scripts/Verify-Proof.ps1") -Kind "pr-to-test" -TargetBranch $targetBranch
}

if (-not $NoPush) {
    Push-CurrentBranch -Branch $branch | Write-Host
}

if (-not $NoPr) {
    Assert-GitHubCliAuthenticated

    $proofSummary = Invoke-GitHubCli @(
        "pr", "list",
        "--repo", $repositoryFullName,
        "--head", $branch,
        "--base", $targetBranch,
        "--json", "number,url,state,isDraft"
    )
    $existingPrs = @()
    if (-not [string]::IsNullOrWhiteSpace($proofSummary)) {
        $existingPrs = @($proofSummary | ConvertFrom-Json)
    }

    $bodyPath = Join-Path $repoRoot "artifacts/pr-bodies/pr-to-test-$safeTarget-$safeBranch.md"
    Ensure-Directory (Split-Path -Parent $bodyPath)
    $currentHead = Get-HeadCommit
    $body = @"
## Summary

Prepared by the local PR-to-test workflow script.

This branch carries feature work plus a checked-in local validation proof.
GitHub should only verify that the proof matches the current PR content digest.

## Validation

- `./scripts/Prepare-PrToTest.ps1` completed successfully.
- `./scripts/Verify-Proof.ps1 -Kind pr-to-test -TargetBranch test` passed.
- Current PR head: `$currentHead`

Rust checks are skipped until `server-rust/Cargo.toml` exists.
"@
    Set-Content -LiteralPath $bodyPath -Value $body -Encoding UTF8

    if ($existingPrs.Count -gt 0) {
        $pr = $existingPrs | Select-Object -First 1
        Invoke-GitHubCli @(
            "pr", "edit", "$($pr.number)",
            "--repo", $repositoryFullName,
            "--title", $title,
            "--body-file", $bodyPath
        ) | Write-Host

        if ($ReadyForReview -and $pr.isDraft) {
            Invoke-GitHubCli @("pr", "ready", "$($pr.number)", "--repo", $repositoryFullName) | Write-Host
        }

        Write-Host "Updated PR: $($pr.url)"
    }
    else {
        $createArgs = @(
            "pr", "create",
            "--repo", $repositoryFullName,
            "--base", $targetBranch,
            "--head", $branch,
            "--title", $title,
            "--body-file", $bodyPath
        )

        if (-not $ReadyForReview) {
            $createArgs += "--draft"
        }

        $createdUrl = Invoke-GitHubCli $createArgs
        Write-Host "Created PR: $createdUrl"
    }
}

Write-Host "PR-to-test workflow complete for '$branch' -> '$targetBranch'."
