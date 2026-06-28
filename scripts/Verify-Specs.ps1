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
        foreach ($heading in $requiredHeadings) {
            if ($text -notmatch "(?m)^$([regex]::Escape($heading))\s*$") {
                $errors.Add("$($file.FullName) is missing required heading '$heading'.")
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
