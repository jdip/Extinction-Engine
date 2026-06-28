param(
    [switch] $Sign,
    [switch] $NoPush,
    [switch] $NoPr,
    [switch] $NoMerge,
    [string] $ConfirmPromotion = "",
    [int] $CheckTimeoutSeconds = 600,
    [int] $CheckPollSeconds = 10
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
$branch = Get-CurrentBranch
if ($branch -ne "test") {
    throw "Promotion proof must be generated from the 'test' branch. Current branch: '$branch'."
}

$targetBranch = "main"
$repositoryFullName = Get-OriginRepositoryFullName
$safeBranch = Get-ProofSafeName $branch
$safeTarget = Get-ProofSafeName $targetBranch
$title = "[codex] promote test to main"
$requiredPromotionPhrase = "promote test to main"
$mergeRequested = -not $NoMerge -and $ConfirmPromotion -eq $requiredPromotionPhrase

if (($NoPush -or $NoPr) -and $mergeRequested) {
    throw "Cannot merge when -NoPush or -NoPr is set."
}

if (-not [string]::IsNullOrWhiteSpace($ConfirmPromotion) -and $ConfirmPromotion -ne $requiredPromotionPhrase) {
    throw "Promotion confirmation must exactly match '$requiredPromotionPhrase'."
}

Assert-CleanWorkingTree -Reason "Promotion requires test branch work committed before proof generation."

$proofValid = $false
try {
    & (Join-Path $repoRoot "scripts/Verify-Proof.ps1") -Kind "promote-to-main" -TargetBranch $targetBranch
    $proofValid = $true
    Write-Host "Existing promote-to-main proof is valid for the current content digest."
}
catch {
    Write-Host "No valid promote-to-main proof found for the current content digest. Generating a new proof."
}

if (-not $proofValid) {
    $subjectHead = Get-HeadCommit
    $proofId = "promote-to-main-$safeTarget-$safeBranch-$($subjectHead.Substring(0, 12))"
    $proofDir = Join-Path $repoRoot "docs/proofs/promote-to-main/$safeTarget"
    $proofPath = Join-Path $proofDir "$proofId.proof.json"
    $proofHashPath = "$proofPath.sha256"
    $proofSignaturePath = "$proofPath.asc"

    & (Join-Path $PSScriptRoot "New-ValidationProof.ps1") -Kind "promote-to-main" -TargetBranch $targetBranch -Sign:$Sign
    & (Join-Path $repoRoot "scripts/Verify-Proof.ps1") -Kind "promote-to-main" -TargetBranch $targetBranch

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
    if ($LASTEXITCODE -ne 0) {
        & git commit -m "chore: add promote-to-main validation proof"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to commit generated proof artifacts."
        }
    }

    & (Join-Path $repoRoot "scripts/Verify-Proof.ps1") -Kind "promote-to-main" -TargetBranch $targetBranch
}

if (-not $NoPush) {
    Push-CurrentBranch -Branch $branch | Write-Host
}

if (-not $NoPr) {
    Assert-GitHubCliAuthenticated

    $existingPr = Get-GitHubPullRequestForBranches `
        -RepositoryFullName $repositoryFullName `
        -HeadBranch $branch `
        -BaseBranch $targetBranch

    $bodyPath = Join-Path $repoRoot "artifacts/pr-bodies/promote-to-main-$safeTarget-$safeBranch.md"
    Ensure-Directory (Split-Path -Parent $bodyPath)
    $currentHead = Get-HeadCommit
    $body = @"
## Summary

Prepared by the local promote-to-main workflow script.

This PR promotes `test` to `main` with a checked-in local validation proof.
GitHub should only verify that the proof matches the current PR content digest.

## Validation

- `./scripts/Prepare-PromoteToMain.ps1` completed successfully.
- `./scripts/Verify-Proof.ps1 -Kind promote-to-main -TargetBranch main` passed.
- Current PR head: `$currentHead`

Rust checks are skipped until `server-rust/Cargo.toml` exists.
"@
    Set-Content -LiteralPath $bodyPath -Value $body -Encoding UTF8

    if ($null -ne $existingPr -and $existingPr.state -eq "MERGED") {
        Assert-RemoteBranchContainsCommit -Branch $targetBranch -CommitSha $currentHead
        Write-Host "Promotion PR already merged and origin/$targetBranch contains $currentHead: $($existingPr.url)"
        return
    }

    if ($null -ne $existingPr -and $existingPr.state -ne "CLOSED") {
        $pr = $existingPr
        Invoke-GitHubCli @(
            "pr", "edit", "$($pr.number)",
            "--repo", $repositoryFullName,
            "--title", $title,
            "--body-file", $bodyPath
        ) | Write-Host
        Write-Host "Updated PR: $($pr.url)"
    }
    else {
        $createdUrl = Invoke-GitHubCli @(
            "pr", "create",
            "--repo", $repositoryFullName,
            "--base", $targetBranch,
            "--head", $branch,
            "--title", $title,
            "--body-file", $bodyPath,
            "--draft"
        )
        Write-Host "Created PR: $createdUrl"
        $pr = Get-GitHubPullRequestForBranches `
            -RepositoryFullName $repositoryFullName `
            -HeadBranch $branch `
            -BaseBranch $targetBranch
    }

    if ($null -eq $pr) {
        throw "Could not find or create PR for '$branch' -> '$targetBranch'."
    }

    if ($mergeRequested) {
        Set-GitHubPullRequestReady -RepositoryFullName $repositoryFullName -PullRequestNumber $pr.number
        $view = Get-GitHubPullRequestView -RepositoryFullName $repositoryFullName -PullRequestNumber $pr.number
        if ($view.headRefOid -ne $currentHead) {
            throw "Refusing to merge PR #$($pr.number): head moved. PR head=$($view.headRefOid) local head=$currentHead"
        }

        Wait-GitHubPullRequestCheck `
            -RepositoryFullName $repositoryFullName `
            -PullRequestNumber $pr.number `
            -TimeoutSeconds $CheckTimeoutSeconds `
            -PollSeconds $CheckPollSeconds

        Merge-GitHubPullRequest `
            -RepositoryFullName $repositoryFullName `
            -PullRequestNumber $pr.number `
            -ExpectedHeadSha $currentHead

        $mergedView = Get-GitHubPullRequestView -RepositoryFullName $repositoryFullName -PullRequestNumber $pr.number
        if ($mergedView.state -ne "MERGED") {
            throw "PR #$($pr.number) did not end in MERGED state. Current state: $($mergedView.state)"
        }

        Assert-RemoteBranchContainsCommit -Branch $targetBranch -CommitSha $currentHead
        Write-Host "Merged PR #$($pr.number) into origin/$targetBranch."
    }
    else {
        Write-Host "Promotion PR is prepared but not merged. To merge, rerun with -ConfirmPromotion '$requiredPromotionPhrase'."
    }
}

Write-Host "Promote-to-main workflow complete for '$branch' -> '$targetBranch'."
