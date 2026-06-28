param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("pr-to-test", "promote-to-main")]
    [string] $Kind,

    [Parameter(Mandatory = $true)]
    [string] $TargetBranch,

    [string] $HeadSha = "",
    [switch] $RequireSignature,
    [string] $TrustedSignersPath = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
Assert-GitHeadExists

$currentHead = Get-HeadCommit
if (-not [string]::IsNullOrWhiteSpace($HeadSha) -and $currentHead -ne $HeadSha) {
    throw "Verification checkout is not at the expected head. Current: $currentHead Expected: $HeadSha"
}

$currentDigest = Get-RepositoryContentDigest
$trustedFingerprints = @(Get-TrustedProofSignerFingerprints -TrustedSignersPath $TrustedSignersPath)
if ($RequireSignature -and $trustedFingerprints.Count -eq 0) {
    $configuredPath = Get-TrustedProofSignersPath -TrustedSignersPath $TrustedSignersPath
    throw "Proof signatures are required, but no trusted proof signer fingerprints are configured. Add full fingerprints to $configuredPath before enabling mandatory signatures."
}

$safeTarget = Get-ProofSafeName $TargetBranch
$proofDir = Join-Path $repoRoot "docs/proofs/$Kind/$safeTarget"
if (-not (Test-Path -LiteralPath $proofDir -PathType Container)) {
    throw "No proof directory found for $Kind -> ${TargetBranch}: $proofDir"
}

$proofFiles = @(Get-ChildItem -LiteralPath $proofDir -Filter "*.proof.json" -File)
if ($proofFiles.Count -eq 0) {
    throw "No proof files found in $proofDir"
}

$validProofs = New-Object System.Collections.Generic.List[object]
$failureSummaries = New-Object System.Collections.Generic.List[string]

foreach ($proofFile in $proofFiles) {
    $errors = New-Object System.Collections.Generic.List[string]
    $proof = $null

    try {
        $proof = Get-Content -Raw -LiteralPath $proofFile.FullName | ConvertFrom-Json
    }
    catch {
        $errors.Add("Could not parse JSON: $($_.Exception.Message)")
    }

    if ($null -ne $proof) {
        if ($proof.proof_kind -ne $Kind) {
            $errors.Add("proof_kind is '$($proof.proof_kind)', expected '$Kind'.")
        }

        if ($proof.target_branch -ne $TargetBranch) {
            $errors.Add("target_branch is '$($proof.target_branch)', expected '$TargetBranch'.")
        }

        if ($proof.validation.result -ne "passed") {
            $errors.Add("validation.result is '$($proof.validation.result)', expected 'passed'.")
        }

        if ($proof.subject.content_digest_algorithm -ne $currentDigest.Algorithm) {
            $errors.Add("content digest algorithm is '$($proof.subject.content_digest_algorithm)', expected '$($currentDigest.Algorithm)'.")
        }

        if ($proof.subject.content_digest -ne $currentDigest.Digest) {
            $errors.Add("content digest mismatch. Proof: $($proof.subject.content_digest) Current: $($currentDigest.Digest)")
        }
    }

    $hashPath = "$($proofFile.FullName).sha256"
    if (-not (Test-Path -LiteralPath $hashPath -PathType Leaf)) {
        $errors.Add("Missing proof hash sidecar: $hashPath")
    }
    else {
        $expectedHash = ((Get-Content -Raw -LiteralPath $hashPath).Trim() -split "\s+")[0].ToLowerInvariant()
        $actualHash = (Get-FileHash -LiteralPath $proofFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expectedHash -ne $actualHash) {
            $errors.Add("Proof hash mismatch. Sidecar: $expectedHash Actual: $actualHash")
        }
    }

    $signaturePath = "$($proofFile.FullName).asc"
    if ($RequireSignature -and -not (Test-Path -LiteralPath $signaturePath -PathType Leaf)) {
        $errors.Add("Proof signature is required but missing: $signaturePath")
    }

    if (Test-Path -LiteralPath $signaturePath -PathType Leaf) {
        try {
            $signatureFingerprint = Get-GpgSignatureFingerprint -SignaturePath $signaturePath -SignedPath $proofFile.FullName
            if ($RequireSignature -and $trustedFingerprints -notcontains $signatureFingerprint) {
                $errors.Add("Proof signature fingerprint '$signatureFingerprint' is not in the trusted proof signer allowlist.")
            }
        }
        catch {
            $errors.Add($_.Exception.Message)
        }
    }

    if ($errors.Count -eq 0) {
        $validProofs.Add([pscustomobject]@{
            Path = $proofFile.FullName
            Proof = $proof
        })
    }
    else {
        $failureSummaries.Add("$($proofFile.Name): $($errors -join '; ')")
    }
}

if ($validProofs.Count -eq 0) {
    foreach ($failure in $failureSummaries) {
        Write-Error $failure
    }
    throw "No valid proof found for $Kind -> $TargetBranch."
}

$selected = $validProofs |
    Sort-Object { $_.Proof.created_utc } -Descending |
    Select-Object -First 1

Write-Host "Accepted proof: $($selected.Path)"
Write-Host "Subject commit: $($selected.Proof.subject.git_head)"
Write-Host "Current content digest: $($currentDigest.Digest)"
