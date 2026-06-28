param(
    [string] $RetrospectivesRoot,
    [string] $ProofsRoot,
    [switch] $RequireProofCoverage
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

function Get-RetrospectiveSectionBody {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [string] $Heading
    )

    $escapedHeading = [regex]::Escape($Heading)
    $match = [regex]::Match($Text, "(?ms)^$escapedHeading\s*(?<body>.*?)(?=^## |\z)")
    if (-not $match.Success) {
        return ""
    }

    return $match.Groups["body"].Value.Trim()
}

function Test-RetrospectiveSectionHasMaterial {
    param(
        [string] $Body
    )

    $materialLines = @($Body -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            $_ -notmatch "(?i)^(-\s*)?(no\b|none\b|n/a\b|no new material\b|no material\b|everything (good|fixed)\b)"
        })

    return ($materialLines.Count -gt 0)
}

$errors = New-Object System.Collections.Generic.List[string]
$recordsByProofKey = @{}

if (-not (Test-Path -LiteralPath $RetrospectivesRoot -PathType Container)) {
    $errors.Add("Missing retrospectives directory: $RetrospectivesRoot")
}
else {
    $files = @(Get-ChildItem -LiteralPath $RetrospectivesRoot -Filter "*.md" -File |
        Where-Object { $_.Name -ne "TEMPLATE.md" })

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
            elseif ($fields[$field] -match "(?i)^pending\b") {
                $errors.Add("$($file.FullName) has draft field '$field': $($fields[$field])")
            }
        }

        foreach ($heading in $requiredHeadings) {
            if ($text -notmatch "(?m)^$([regex]::Escape($heading))\s*$") {
                $errors.Add("$($file.FullName) is missing required heading '$heading'.")
            }
        }

        $hasMaterial = $false
        foreach ($heading in $requiredHeadings) {
            $body = Get-RetrospectiveSectionBody -Text $text -Heading $heading
            if (Test-RetrospectiveSectionHasMaterial -Body $body) {
                $hasMaterial = $true
            }
        }
        if (-not $hasMaterial) {
            $errors.Add("$($file.FullName) contains no material retrospective content. Do not commit durable retrospectives just to record an all-good result.")
        }

        if ($text -match "(?im)PR or event:\s*pending") {
            $errors.Add("$($file.FullName) still contains a pending PR/event marker.")
        }

        if ($text -match "(?i)\brecorded yet\b") {
            $errors.Add("$($file.FullName) still contains draft retrospective text.")
        }

        if ($text -match "`t") {
            $errors.Add("$($file.FullName) contains a tab character. Retrospective records should not contain PowerShell escape artifacts.")
        }

        if ($text -match "\`$mergedHead") {
            $errors.Add("$($file.FullName) contains an unresolved merged-head placeholder.")
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
if ($RequireProofCoverage -and (Test-Path -LiteralPath $prProofRoot -PathType Container)) {
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
