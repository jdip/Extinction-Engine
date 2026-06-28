param(
    [string] $Base = "test",
    [switch] $Local,
    [switch] $Remote,
    [switch] $ConfirmDeleteMergedBranches
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

Assert-GitHeadExists
Assert-CleanWorkingTree -Reason "Merged branch cleanup requires a clean working tree."

if (-not $Local -and -not $Remote) {
    $Local = $true
}

Invoke-GitProcess @("fetch", "origin", $Base) | Write-Host
$currentBranch = Get-CurrentBranch
$protectedBranches = @("main", "test", $currentBranch)

if ($Local) {
    $mergedOutput = Invoke-GitProcess @("branch", "--merged", $Base)
    $localBranches = @($mergedOutput -split "`r?`n" |
        ForEach-Object { ($_ -replace "^\*\s*", "").Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $protectedBranches -notcontains $_ -and $_.StartsWith("codex/") })

    if ($localBranches.Count -eq 0) {
        Write-Host "No merged local codex branches found."
    }
    else {
        Write-Host "Merged local codex branches:"
        $localBranches | ForEach-Object { Write-Host "- $_" }
        if ($ConfirmDeleteMergedBranches) {
            foreach ($branch in $localBranches) {
                Invoke-GitProcess @("branch", "-d", $branch) | Write-Host
            }
        }
        else {
            Write-Host "Dry run only. Rerun with -ConfirmDeleteMergedBranches to delete local merged branches."
        }
    }
}

if ($Remote) {
    $remoteOutput = Invoke-GitProcess @("branch", "-r", "--merged", "origin/$Base")
    $remoteBranches = @($remoteOutput -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -like "origin/codex/*" } |
        ForEach-Object { $_ -replace "^origin/", "" })

    if ($remoteBranches.Count -eq 0) {
        Write-Host "No merged remote codex branches found."
    }
    else {
        Write-Host "Merged remote codex branches:"
        $remoteBranches | ForEach-Object { Write-Host "- $_" }
        if ($ConfirmDeleteMergedBranches) {
            foreach ($branch in $remoteBranches) {
                Invoke-GitProcess @("push", "origin", "--delete", $branch) | Write-Host
            }
        }
        else {
            Write-Host "Dry run only. Rerun with -Remote -ConfirmDeleteMergedBranches to delete remote merged branches."
        }
    }
}
