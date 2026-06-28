param(
    [Parameter(Mandatory = $true)]
    [string] $Id,

    [ValidateSet("done", "cancelled", "transferred")]
    [string] $Status = "done",

    [Parameter(Mandatory = $true)]
    [string] $Resolution,

    [string] $Validation = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
$openDir = Join-Path $repoRoot "docs/remediation/open"
$doneDir = Join-Path $repoRoot "docs/remediation/done"
Ensure-Directory $doneDir

$sourcePath = Join-Path $openDir "$Id.md"
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Open remediation record not found: $sourcePath"
}

$closed = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$text = Get-Content -Raw -LiteralPath $sourcePath
$text = $text -replace "(?m)^status:\s*.*$", "status: $Status"
$text = $text -replace "(?m)^closed:\s*.*$", "closed: $closed"
$append = @"

## Closure

$Resolution

## Closure Validation

$Validation
"@

$destinationPath = Join-Path $doneDir "$Id.md"
Set-Content -LiteralPath $sourcePath -Value ($text.TrimEnd() + $append) -Encoding UTF8
Move-Item -LiteralPath $sourcePath -Destination $destinationPath
Write-Host "Closed remediation record: $destinationPath"
