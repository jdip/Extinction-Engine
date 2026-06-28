param(
    [string] $ResultPath
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
$started = Get-UtcIsoTimestamp
$steps = @()

$steps += Invoke-ValidationCommand `
    -Name "git diff whitespace check" `
    -Command "git diff --check" `
    -Script { & git -C $repoRoot diff --check }

$steps += Invoke-ValidationCommand `
    -Name "git staged diff whitespace check" `
    -Command "git diff --cached --check" `
    -Script { & git -C $repoRoot diff --cached --check }

$steps += Invoke-ValidationCommand `
    -Name "remediation record validation" `
    -Command "./scripts/Verify-RemediationRecords.ps1" `
    -Script { & (Join-Path $repoRoot "scripts/Verify-RemediationRecords.ps1") }

$serverCargo = Join-Path $repoRoot "server-rust/Cargo.toml"
if (Test-Path -LiteralPath $serverCargo -PathType Leaf) {
    $serverRoot = Join-Path $repoRoot "server-rust"

    $steps += Invoke-ValidationCommand `
        -Name "rust format check" `
        -Command "cargo fmt --all --check" `
        -Script {
            Push-Location $serverRoot
            try { & cargo fmt --all --check }
            finally { Pop-Location }
        }

    $steps += Invoke-ValidationCommand `
        -Name "rust clippy" `
        -Command "cargo clippy --workspace --all-targets -- -D warnings" `
        -Script {
            Push-Location $serverRoot
            try { & cargo clippy --workspace --all-targets -- -D warnings }
            finally { Pop-Location }
        }

    $steps += Invoke-ValidationCommand `
        -Name "rust tests" `
        -Command "cargo test --workspace" `
        -Script {
            Push-Location $serverRoot
            try { & cargo test --workspace }
            finally { Pop-Location }
        }
}
else {
    $steps += New-SkippedValidationStep -Name "rust format check" -Reason "server-rust/Cargo.toml does not exist yet."
    $steps += New-SkippedValidationStep -Name "rust clippy" -Reason "server-rust/Cargo.toml does not exist yet."
    $steps += New-SkippedValidationStep -Name "rust tests" -Reason "server-rust/Cargo.toml does not exist yet."
}

$failedSteps = @($steps | Where-Object { $_.status -eq "failed" })
$resultStatus = if ($failedSteps.Count -eq 0) { "passed" } else { "failed" }

$result = [pscustomobject]@{
    schema_version = 1
    result = $resultStatus
    started_utc = $started
    completed_utc = Get-UtcIsoTimestamp
    repository = $repoRoot
    steps = $steps
}

if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
    Write-JsonFile -InputObject $result -Path $ResultPath
}

foreach ($step in $steps) {
    Write-Host "[$($step.status)] $($step.name)"
}

if ($resultStatus -ne "passed") {
    throw "Local validation failed."
}
