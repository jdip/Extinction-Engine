param(
    [Parameter(Mandatory = $true)]
    [string] $Title,

    [Parameter(Mandatory = $true)]
    [string] $Owner,

    [Parameter(Mandatory = $true)]
    [string] $Source,

    [string] $Description = "",
    [string] $Slug = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
$openDir = Join-Path $repoRoot "docs/remediation/open"
Ensure-Directory $openDir

if ([string]::IsNullOrWhiteSpace($Slug)) {
    $Slug = Get-ProofSafeName $Title.ToLowerInvariant()
}
else {
    $Slug = Get-ProofSafeName $Slug.ToLowerInvariant()
}

$date = (Get-Date).ToUniversalTime().ToString("yyyyMMdd")
$created = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$baseId = "REM-$date-$Slug"
$id = $baseId
$index = 2
while (Test-Path -LiteralPath (Join-Path $openDir "$id.md")) {
    $id = "$baseId-$index"
    $index += 1
}

$path = Join-Path $openDir "$id.md"
$content = @"
---
id: $id
status: open
owner: $Owner
created: $created
source: $Source
closed:
---

# $Title

## Context

$Description

## Remediation

Describe the concrete change that will close this record.

## Validation

List the command or review evidence that will prove this is closed.
"@

Set-Content -LiteralPath $path -Value $content -Encoding UTF8
Write-Host "Created remediation record: $path"
