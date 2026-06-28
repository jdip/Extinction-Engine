param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("pr-to-test", "promote-to-main")]
    [string] $Kind,

    [Parameter(Mandatory = $true)]
    [string] $TargetBranch,

    [switch] $Sign,
    [string] $TrustedSignersPath = "",

    [ValidateSet("full", "docs-only")]
    [string] $ValidationProfile = "full",

    [string] $ValidationSkipReason = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
Assert-GitHeadExists
Assert-CleanWorkingTree -Reason "Proof generation must start from a clean commit so the proof binds to reviewed content."

$branch = Get-CurrentBranch
$head = Get-HeadCommit
$tree = Get-HeadTree
$contentDigest = Get-RepositoryContentDigest

$artifactDir = Join-Path $repoRoot "artifacts/validation"
Ensure-Directory $artifactDir
$validationResultPath = Join-Path $artifactDir "$Kind-$($head.Substring(0, 12)).validation.json"

try {
    $validationArgs = @(
        "-ResultPath", $validationResultPath,
        "-Profile", $ValidationProfile
    )
    if ($ValidationProfile -eq "docs-only") {
        $validationArgs += @(
            "-SkipFullValidationReason", $ValidationSkipReason,
            "-DocsOnlyBaseBranch", $TargetBranch
        )
    }

    & (Join-Path $repoRoot "scripts/Invoke-LocalValidation.ps1") @validationArgs
}
catch {
    throw "Local validation failed. See $validationResultPath for captured evidence. $($_.Exception.Message)"
}

$validation = Get-Content -Raw -LiteralPath $validationResultPath | ConvertFrom-Json
if ($validation.result -ne "passed") {
    throw "Validation result was '$($validation.result)'; refusing to create passing proof."
}

$safeBranch = Get-ProofSafeName $branch
$safeTarget = Get-ProofSafeName $TargetBranch
$proofId = "$Kind-$safeTarget-$safeBranch-$($head.Substring(0, 12))"
$proofDir = Join-Path $repoRoot "docs/proofs/$Kind/$safeTarget"
Ensure-Directory $proofDir
$proofPath = Join-Path $proofDir "$proofId.proof.json"

$proof = [ordered]@{
    schema_version = 1
    proof_id = $proofId
    proof_kind = $Kind
    target_branch = $TargetBranch
    source_branch = $branch
    created_utc = Get-UtcIsoTimestamp
    subject = [ordered]@{
        git_head = $head
        git_tree = $tree
        content_digest_algorithm = $contentDigest.Algorithm
        content_digest = $contentDigest.Digest
        tracked_file_count = $contentDigest.TrackedFileCount
        excluded_prefixes = $contentDigest.ExcludedPrefixes
    }
    validation = $validation
}

Write-JsonFile -InputObject $proof -Path $proofPath

$proofHash = (Get-FileHash -LiteralPath $proofPath -Algorithm SHA256).Hash.ToLowerInvariant()
$hashPath = "$proofPath.sha256"
Write-Utf8LfFile -Path $hashPath -Value "$proofHash  $(Split-Path -Leaf $proofPath)"

$shouldSign = $Sign -or (Test-TrustedProofSignerSecretAvailable -TrustedSignersPath $TrustedSignersPath)
if ($shouldSign) {
    $signaturePath = "$proofPath.asc"
    $gpg = Get-GpgPath
    & $gpg --armor --detach-sign --output $signaturePath $proofPath
    if ($LASTEXITCODE -ne 0) {
        throw "gpg failed to sign proof file."
    }
}

Write-Host "Created proof: $proofPath"
Write-Host "Created proof hash: $hashPath"
if ($shouldSign) {
    Write-Host "Created proof signature: $signaturePath"
}
