param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("pr-to-test", "promote-to-main", "validation", "incident")]
    [string] $Kind,

    [Parameter(Mandatory = $true)]
    [string] $SourceBranch,

    [Parameter(Mandatory = $true)]
    [string] $Title,

    [string] $Outcome = "Pending lifecycle completion.",
    [string] $ValidationReviewed = "Pending validation review.",
    [string] $AcceptedRisks = "Pending risk review.",
    [string] $Event = "",
    [string] $Slug = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
$retrospectiveDir = Join-Path $repoRoot "docs/retrospectives"
Ensure-Directory $retrospectiveDir

if ([string]::IsNullOrWhiteSpace($Slug)) {
    $Slug = Get-ProofSafeName $Title.ToLowerInvariant()
}
else {
    $Slug = Get-ProofSafeName $Slug.ToLowerInvariant()
}

$created = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$baseName = "$created-$Slug"
$path = Join-Path $retrospectiveDir "$baseName.md"
$index = 2
while (Test-Path -LiteralPath $path) {
    $path = Join-Path $retrospectiveDir "$baseName-$index.md"
    $index += 1
}

$eventLine = if ([string]::IsNullOrWhiteSpace($Event)) { "PR or event: pending" } else { "PR or event: $Event" }
$content = @"
---
kind: $Kind
source_branch: $SourceBranch
created: $created
outcome: $Outcome
validation_reviewed: $ValidationReviewed
accepted_risks: $AcceptedRisks
---

# $Title

$eventLine

## Friction Points That Need To Be Addressed In AGENTS.md

- None recorded yet.

## Common Workflows That Should Be Automated With Scripts

- None recorded yet.

## Gaps Discovered That Deserve Remediation

No new material remediation recorded yet.
"@

Write-Utf8LfFile -Path $path -Value $content
Write-Host "Created retrospective: $path"
