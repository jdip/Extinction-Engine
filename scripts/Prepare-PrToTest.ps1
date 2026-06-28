param(
    [switch] $Sign,
    [switch] $NoPush,
    [switch] $NoPr,
    [switch] $NoMerge,
    [string] $SpecPath = "",
    [string] $Summary = "",
    [string] $RiskNotes = "",
    [string] $RollbackNotes = "",
    [string] $TrustedSignersPath = "",
    [ValidateSet("full", "docs-only")]
    [string] $ValidationProfile = "full",
    [string] $ValidationSkipReason = "",
    [string] $RetrospectiveFrictionNotes = "",
    [string] $RetrospectiveAutomationNotes = "",
    [string] $RetrospectiveRemediationNotes = "",
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

function Test-MaterialRetrospectiveNote {
    param(
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $materialLines = @($Value -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            $_ -notmatch "(?i)^(-\s*)?(no\b|none\b|n/a\b|no new material\b|no material\b|everything (good|fixed)\b)"
        })

    return ($materialLines.Count -gt 0)
}

if (($NoPush -or $NoPr) -and -not $NoMerge) {
    throw "Use -NoMerge when using -NoPush or -NoPr."
}

Assert-CleanWorkingTree -Reason "PR-to-test requires feature work committed before proof generation."
Assert-BranchContainsRemoteBranch -RemoteBranch $targetBranch
$relativeSpecPath = ""
if (-not $NoPr) {
    $relativeSpecPath = Assert-PrMetadata -SpecPath $SpecPath -Summary $Summary -RiskNotes $RiskNotes -RollbackNotes $RollbackNotes
}

$proofValid = $false
try {
    & (Join-Path $repoRoot "scripts/Verify-Proof.ps1") -Kind "pr-to-test" -TargetBranch $targetBranch -TrustedSignersPath $TrustedSignersPath
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

    & (Join-Path $PSScriptRoot "New-ValidationProof.ps1") `
        -Kind "pr-to-test" `
        -TargetBranch $targetBranch `
        -Sign:$Sign `
        -TrustedSignersPath $TrustedSignersPath `
        -ValidationProfile $ValidationProfile `
        -ValidationSkipReason $ValidationSkipReason
    $keepProofPaths = @($proofPath, $proofHashPath)
    if (Test-Path -LiteralPath $proofSignaturePath -PathType Leaf) {
        $keepProofPaths += $proofSignaturePath
    }
    Remove-StaleProofArtifacts -ProofDirectory $proofDir -ProofPrefix $proofPrefix -KeepPaths $keepProofPaths
    & (Join-Path $repoRoot "scripts/Verify-Proof.ps1") -Kind "pr-to-test" -TargetBranch $targetBranch -TrustedSignersPath $TrustedSignersPath

    $pathsToStage = @($proofPath, $proofHashPath)
    if (Test-Path -LiteralPath $proofSignaturePath -PathType Leaf) {
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

    & (Join-Path $repoRoot "scripts/Verify-Proof.ps1") -Kind "pr-to-test" -TargetBranch $targetBranch -TrustedSignersPath $TrustedSignersPath
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
    $selectedProof = Get-LatestMatchingProof -Kind "pr-to-test" -TargetBranch $targetBranch
    if ($null -eq $selectedProof) {
        throw "Could not find a valid PR-to-test proof for the current content digest."
    }

    $validationSummary = Convert-ValidationStepsToMarkdown -Validation $selectedProof.Proof.validation
    $body = @"
## Summary

$Summary

Prepared by the local PR-to-test workflow script. This branch carries feature
work plus a checked-in local validation proof. GitHub should only verify that
the proof matches the current PR content digest.

## Lifecycle Records

- Spec: `$relativeSpecPath`
- Retrospective: finalized after successful PR-to-test merge
- Proof: `$($selectedProof.RelativePath)`
- Proof id: `$($selectedProof.Proof.proof_id)`

## Validation

- `./scripts/Prepare-PrToTest.ps1` completed successfully.
- `./scripts/Verify-Proof.ps1 -Kind pr-to-test -TargetBranch test` passed.
- Validation profile: `$ValidationProfile`
- Current PR head: `$currentHead`

$validationSummary

## Risks

$RiskNotes

## Rollback

$RollbackNotes
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
            -PollSeconds $CheckPollSeconds |
            Out-Null

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
        Sync-LocalBranchToOrigin -Branch $targetBranch

        $mergedHead = Get-HeadCommit
        $created = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
        $retrospectiveHasMaterial =
            (Test-MaterialRetrospectiveNote -Value $RetrospectiveFrictionNotes) -or
            (Test-MaterialRetrospectiveNote -Value $RetrospectiveAutomationNotes) -or
            (Test-MaterialRetrospectiveNote -Value $RetrospectiveRemediationNotes)
        $frictionNotes = if ([string]::IsNullOrWhiteSpace($RetrospectiveFrictionNotes)) {
            "- No material friction requiring AGENTS.md changes."
        }
        else {
            $RetrospectiveFrictionNotes.Trim()
        }
        $automationNotes = if ([string]::IsNullOrWhiteSpace($RetrospectiveAutomationNotes)) {
            "- No material workflow automation follow-up identified."
        }
        else {
            $RetrospectiveAutomationNotes.Trim()
        }
        $remediationNotes = if ([string]::IsNullOrWhiteSpace($RetrospectiveRemediationNotes)) {
            "No material remediation."
        }
        else {
            $RetrospectiveRemediationNotes.Trim()
        }

        if ($retrospectiveHasMaterial) {
            $retrospectivePath = Join-Path $repoRoot "docs/retrospectives/$created-pr-$($pr.number)-$safeBranch.md"
            $retrospectiveRelativePath = ConvertTo-RepositoryRelativePath $retrospectivePath
            $retrospectiveContent = @"
---
kind: pr-to-test
source_branch: $branch
created: $created
outcome: PR #$($pr.number) merged to test on $created.
validation_reviewed: local validation proof, GitHub proof check, merge result, and local test sync
accepted_risks: $RiskNotes
---

# PR $($pr.number) $($branch -replace '^codex/', '' -replace '[-_]+', ' ') Retrospective

PR: $($pr.url)
Outcome: Merged to test on $created.
Validation reviewed: local validation proof, GitHub proof check, merge result,
and local test sync to $mergedHead.
Accepted risks: $RiskNotes

## Friction Points That Need To Be Addressed In AGENTS.md

$frictionNotes

## Common Workflows That Should Be Automated With Scripts

$automationNotes

## Gaps Discovered That Deserve Remediation

$remediationNotes
"@
            Write-Utf8LfFile -Path $retrospectivePath -Value $retrospectiveContent
            & (Join-Path $repoRoot "scripts/Invoke-LocalValidation.ps1") `
                -Profile "docs-only" `
                -SkipFullValidationReason "Post-merge retrospective documentation only; feature validation was captured by proof $($selectedProof.Proof.proof_id)."
            if ($LASTEXITCODE -ne 0) {
                throw "Docs-only validation failed after writing post-merge retrospective."
            }

            Invoke-GitProcess @("add", "--", $retrospectiveRelativePath) | Write-Host
            $diffResult = Invoke-ExternalCommand -FileName "git" -Arguments @("diff", "--cached", "--quiet") -WorkingDirectory $repoRoot
            if ($diffResult.ExitCode -ne 0) {
                Invoke-GitProcess @("commit", "-m", "docs: add pr-to-test retrospective for PR #$($pr.number)") | Write-Host
                Invoke-GitProcess @("push", "origin", $targetBranch) | Write-Host
            }

            Write-Host ""
            Write-Host "Post-PR retrospective: $retrospectiveRelativePath"
        }
        else {
            Write-Host ""
            Write-Host "Post-PR retrospective: no durable record written; no material findings were supplied."
        }

        Write-Host "## Friction Points That Need To Be Addressed In AGENTS.md"
        Write-Host $frictionNotes
        Write-Host "## Common Workflows That Should Be Automated With Scripts"
        Write-Host $automationNotes
        Write-Host "## Gaps Discovered That Deserve Remediation"
        Write-Host $remediationNotes
    }
}

Write-Host "PR-to-test workflow complete for '$branch' -> '$targetBranch'."
