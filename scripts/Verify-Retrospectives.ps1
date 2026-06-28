param(
    [string] $RetrospectivesRoot,
    [string] $ProofsRoot
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($RetrospectivesRoot)) {
    $RetrospectivesRoot = Join-Path $repoRoot "docs/retrospectives"
}
if ([string]::IsNullOrWhiteSpace($ProofsRoot)) {
    $ProofsRoot = Join-Path $repoRoot "docs/proofs"
}

$requiredFields = @("kind", "source_branch", "created", "outcome", "validation_reviewed", "accepted_risks")
$requiredHeadings = @(
    "## Friction Points That Need To Be Addressed In AGENTS.md",
    "## Common Workflows That Should Be Automated With Scripts",
    "## Gaps Discovered That Deserve Remediation"
)

$errors = New-Object System.Collections.Generic.List[string]
$recordsByProofKey = @{}

if (-not (Test-Path -LiteralPath $RetrospectivesRoot -PathType Container)) {
    $errors.Add("Missing retrospectives directory: $RetrospectivesRoot")
}
else {
    $files = @(Get-ChildItem -LiteralPath $RetrospectivesRoot -Filter "*.md" -File |
        Where-Object { $_.Name -ne "TEMPLATE.md" })

    if ($files.Count -eq 0) {
        $errors.Add("No retrospective records found in $RetrospectivesRoot.")
    }

    foreach ($file in $files) {
        $text = Get-Content -Raw -LiteralPath $file.FullName
        if ($text -notmatch "(?s)^---\s*(?<frontmatter>.*?)\s*---") {
            $errors.Add("$($file.FullName) is missing required front matter.")
            continue
        }

        $fields = @{}
        foreach ($line in ($matches.frontmatter -split "`r?`n")) {
            if ($line -match "^([A-Za-z_]+):\s*(.*)$") {
                $fields[$matches[1].ToLowerInvariant()] = $matches[2].Trim()
            }
        }

        foreach ($field in $requiredFields) {
            if (-not $fields.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($fields[$field])) {
                $errors.Add("$($file.FullName) is missing required field '$field'.")
            }
        }

        foreach ($heading in $requiredHeadings) {
            if ($text -notmatch "(?m)^$([regex]::Escape($heading))\s*$") {
                $errors.Add("$($file.FullName) is missing required heading '$heading'.")
            }
        }

        if ($fields.ContainsKey("kind") -and $fields.ContainsKey("source_branch")) {
            $key = "$($fields.kind)|$($fields.source_branch)"
            if ($recordsByProofKey.ContainsKey($key)) {
                $errors.Add("Duplicate retrospective for '$key' in $($file.FullName) and $($recordsByProofKey[$key]).")
            }
            else {
                $recordsByProofKey[$key] = $file.FullName
            }
        }
    }
}

$prProofRoot = Join-Path $ProofsRoot "pr-to-test"
if (Test-Path -LiteralPath $prProofRoot -PathType Container) {
    foreach ($proofFile in @(Get-ChildItem -LiteralPath $prProofRoot -Filter "*.proof.json" -File -Recurse)) {
        try {
            $proof = Get-Content -Raw -LiteralPath $proofFile.FullName | ConvertFrom-Json
        }
        catch {
            $errors.Add("Could not parse proof while validating retrospectives: $($proofFile.FullName)")
            continue
        }

        if ($proof.proof_kind -ne "pr-to-test" -or [string]::IsNullOrWhiteSpace($proof.source_branch)) {
            continue
        }

        $key = "pr-to-test|$($proof.source_branch)"
        if (-not $recordsByProofKey.ContainsKey($key)) {
            $errors.Add("Missing retrospective for pr-to-test proof source branch '$($proof.source_branch)' from $($proofFile.FullName).")
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) {
        Write-Error $errorMessage
    }
    throw "Retrospective validation failed with $($errors.Count) error(s)."
}

Write-Host "Retrospective validation passed."
