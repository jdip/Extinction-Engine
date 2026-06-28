param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("pr-to-test", "promote-to-main", "validation", "incident")]
    [string] $Kind,

    [Parameter(Mandatory = $true)]
    [string] $SourceBranch,

    [Parameter(Mandatory = $true)]
    [string] $Title,

    [Parameter(Mandatory = $true)]
    [string] $Outcome,

    [Parameter(Mandatory = $true)]
    [string] $ValidationReviewed,

    [Parameter(Mandatory = $true)]
    [string] $AcceptedRisks,

    [Parameter(Mandatory = $true)]
    [string] $Event,
    [string] $FrictionNotes = "",
    [string] $AutomationNotes = "",
    [string] $RemediationNotes = "",
    [string] $Slug = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
$retrospectiveDir = Join-Path $repoRoot "docs/retrospectives"
Ensure-Directory $retrospectiveDir

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

$hasMaterial =
    (Test-MaterialRetrospectiveNote -Value $FrictionNotes) -or
    (Test-MaterialRetrospectiveNote -Value $AutomationNotes) -or
    (Test-MaterialRetrospectiveNote -Value $RemediationNotes)

if (-not $hasMaterial) {
    throw "Refusing to create a no-op retrospective. Durable retrospectives are only for material friction, automation, or remediation findings."
}

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

$eventLine = "PR or event: $Event"
$frictionBody = if ([string]::IsNullOrWhiteSpace($FrictionNotes)) {
    "- No material friction requiring AGENTS.md changes."
}
else {
    $FrictionNotes.Trim()
}
$automationBody = if ([string]::IsNullOrWhiteSpace($AutomationNotes)) {
    "- No material workflow automation follow-up identified."
}
else {
    $AutomationNotes.Trim()
}
$remediationBody = if ([string]::IsNullOrWhiteSpace($RemediationNotes)) {
    "No material remediation."
}
else {
    $RemediationNotes.Trim()
}
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

$frictionBody

## Common Workflows That Should Be Automated With Scripts

$automationBody

## Gaps Discovered That Deserve Remediation

$remediationBody
"@

Write-Utf8LfFile -Path $path -Value $content
Write-Host "Created retrospective: $path"
