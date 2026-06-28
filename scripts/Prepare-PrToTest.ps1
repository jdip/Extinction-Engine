param(
    [switch] $Sign,
    [switch] $NoPush,
    [switch] $NoPr,
    [switch] $NoMerge,
    [int] $CheckTimeoutSeconds = 600,
    [int] $CheckPollSeconds = 10
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

if (($NoPush -or $NoPr) -and -not $NoMerge) {
    throw "Use -NoMerge when using -NoPush or -NoPr."
}

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
    $proofPrefix = "pr-to-test-$safeTarget-$safeBranch-"

    & (Join-Path $PSScriptRoot "New-ValidationProof.ps1") -Kind "pr-to-test" -TargetBranch $targetBranch -Sign:$Sign
    $keepProofPaths = @($proofPath, $proofHashPath)
    if ($Sign) {
        $keepProofPaths += $proofSignaturePath
    }
    Remove-StaleProofArtifacts -ProofDirectory $proofDir -ProofPrefix $proofPrefix -KeepPaths $keepProofPaths
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

    & git add -- $proofDir
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

    $existingPr = Get-GitHubPullRequestForBranches `
        -RepositoryFullName $repositoryFullName `
        -HeadBranch $branch `
        -BaseBranch $targetBranch
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

    if ($null -ne $existingPr -and $existingPr.state -eq "MERGED") {
        Assert-RemoteBranchContainsCommit -Branch $targetBranch -CommitSha $currentHead
        Write-Host "PR already merged and origin/$targetBranch contains ${currentHead}: $($existingPr.url)"
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
        $createArgs = @(
            "pr", "create",
            "--repo", $repositoryFullName,
            "--base", $targetBranch,
            "--head", $branch,
            "--title", $title,
            "--body-file", $bodyPath
        )

        $createdUrl = Invoke-GitHubCli $createArgs
        Write-Host "Created PR: $createdUrl"
        $pr = Get-GitHubPullRequestForBranches `
            -RepositoryFullName $repositoryFullName `
            -HeadBranch $branch `
            -BaseBranch $targetBranch
    }

    if ($null -eq $pr) {
        throw "Could not find or create PR for '$branch' -> '$targetBranch'."
    }

    Set-GitHubPullRequestReady -RepositoryFullName $repositoryFullName -PullRequestNumber $pr.number

    if (-not $NoMerge) {
        if ($NoPush -or $NoPr) {
            throw "Cannot merge when -NoPush or -NoPr is set."
        }

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
}

Write-Host "PR-to-test workflow complete for '$branch' -> '$targetBranch'."
