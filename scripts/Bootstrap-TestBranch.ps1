param(
    [string] $SourceBranch = "main",
    [string] $TestBranch = "test",
    [switch] $Checkout,
    [switch] $FromCurrentHead
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

Assert-GitHeadExists

$existing = & git show-ref --verify --quiet "refs/heads/$TestBranch"
if ($LASTEXITCODE -eq 0) {
    Write-Host "Branch '$TestBranch' already exists."
    if ($Checkout) {
        & git switch $TestBranch
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to switch to '$TestBranch'."
        }
    }
    return
}

if ($FromCurrentHead) {
    & git branch $TestBranch HEAD
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create '$TestBranch' from HEAD."
    }
    Write-Host "Created '$TestBranch' from current HEAD."
}
else {
    $sourceExists = & git show-ref --verify --quiet "refs/heads/$SourceBranch"
    if ($LASTEXITCODE -ne 0) {
        throw "Source branch '$SourceBranch' does not exist. Create the initial commit on '$SourceBranch', or rerun with -FromCurrentHead intentionally."
    }

    & git branch $TestBranch $SourceBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create '$TestBranch' from '$SourceBranch'."
    }
    Write-Host "Created '$TestBranch' from '$SourceBranch'."
}

if ($Checkout) {
    & git switch $TestBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to switch to '$TestBranch'."
    }
}
