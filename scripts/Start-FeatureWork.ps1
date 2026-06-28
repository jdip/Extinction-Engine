param(
    [Parameter(Mandatory = $true)]
    [string] $Name,

    [string] $Base = "test"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

Assert-GitHeadExists
Assert-CleanWorkingTree -Reason "Starting feature work requires a clean working tree."

$safeName = Get-ProofSafeName $Name.ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($safeName) -or $safeName -eq "unnamed") {
    throw "Name must produce a non-empty branch slug."
}

$branch = "codex/$safeName"
Sync-LocalBranchToOrigin -Branch $Base

$existing = Invoke-ExternalCommand -FileName "git" -Arguments @("show-ref", "--verify", "--quiet", "refs/heads/$branch") -WorkingDirectory (Get-RepoRoot)
if ($existing.ExitCode -eq 0) {
    Invoke-GitProcess @("switch", $branch) | Write-Host
    Assert-BranchContainsRemoteBranch -RemoteBranch $Base
    Write-Host "Switched to existing feature branch: $branch"
}
else {
    Invoke-GitProcess @("switch", "-c", $branch) | Write-Host
    Write-Host "Created feature branch from synced ${Base}: $branch"
}
