param(
    [string] $SpecsRoot
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($SpecsRoot)) {
    $SpecsRoot = Join-Path $repoRoot "docs/specs"
}

$requiredHeadings = @(
    "## Research",
    "## Plan",
    "## Implement",
    "## Test",
    "## Validate"
)
$templateFragments = @(
    "Current behavior, constraints, affected files or systems, risks, unknowns",
    "Ordered steps, boundaries, rollback notes, and test strategy",
    "Concrete changes made and any deviations from the plan",
    "Automated tests to add or update, plus relevant existing tests",
    "Commands run, pass/fail evidence, environment used"
)
$errors = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $SpecsRoot -PathType Container)) {
    $errors.Add("Missing specs directory: $SpecsRoot")
}
else {
    $specFiles = @(Get-ChildItem -LiteralPath $SpecsRoot -Filter "*.md" -File |
        Where-Object { $_.Name -ne "TEMPLATE.md" })

    if ($specFiles.Count -eq 0) {
        $errors.Add("No durable spec files found in $SpecsRoot.")
    }

    foreach ($file in $specFiles) {
        $text = Get-Content -Raw -LiteralPath $file.FullName
        $lastHeadingIndex = -1
        foreach ($heading in $requiredHeadings) {
            $match = [regex]::Match($text, "(?m)^$([regex]::Escape($heading))\s*$")
            if (-not $match.Success) {
                $errors.Add("$($file.FullName) is missing required heading '$heading'.")
                continue
            }

            if ($match.Index -le $lastHeadingIndex) {
                $errors.Add("$($file.FullName) has required heading '$heading' out of order.")
            }
            $lastHeadingIndex = $match.Index
        }

        for ($i = 0; $i -lt $requiredHeadings.Count; $i += 1) {
            $heading = $requiredHeadings[$i]
            $startMatch = [regex]::Match($text, "(?m)^$([regex]::Escape($heading))\s*$")
            if (-not $startMatch.Success) {
                continue
            }

            $sectionStart = $startMatch.Index + $startMatch.Length
            $sectionEnd = $text.Length
            if ($i -lt ($requiredHeadings.Count - 1)) {
                $nextHeading = $requiredHeadings[$i + 1]
                $nextMatch = [regex]::Match($text, "(?m)^$([regex]::Escape($nextHeading))\s*$")
                if ($nextMatch.Success) {
                    $sectionEnd = $nextMatch.Index
                }
            }

            $sectionText = $text.Substring($sectionStart, $sectionEnd - $sectionStart).Trim()
            if ([string]::IsNullOrWhiteSpace($sectionText)) {
                $errors.Add("$($file.FullName) has an empty '$heading' section.")
            }

            if ($sectionText -match "(?im)\b(TODO|TBD|PLACEHOLDER)\b") {
                $errors.Add("$($file.FullName) has unresolved placeholder text in '$heading'.")
            }

            foreach ($fragment in $templateFragments) {
                if ($sectionText.Contains($fragment)) {
                    $errors.Add("$($file.FullName) still contains template guidance in '$heading'.")
                    break
                }
            }
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) {
        Write-Error $errorMessage
    }
    throw "Spec validation failed with $($errors.Count) error(s)."
}

Write-Host "Spec validation passed."
