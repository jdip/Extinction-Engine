param(
    [string] $ResultPath,

    [ValidateSet("full", "docs-only")]
    [string] $Profile = "full",

    [string] $SkipFullValidationReason = "",
    [string] $DocsOnlyBaseBranch = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/WorkflowCommon.ps1"

$repoRoot = Get-RepoRoot
$started = Get-UtcIsoTimestamp
$steps = @()

if ($Profile -eq "docs-only") {
    Assert-RequiredText -Name "SkipFullValidationReason" -Value $SkipFullValidationReason
}

$steps += Invoke-ValidationCommand `
    -Name "git diff whitespace check" `
    -Command "git diff --check" `
    -Script { & git -C $repoRoot diff --check }

$steps += Invoke-ValidationCommand `
    -Name "git staged diff whitespace check" `
    -Command "git diff --cached --check" `
    -Script { & git -C $repoRoot diff --cached --check }

if ($Profile -eq "docs-only") {
    $steps += Invoke-ValidationCommand `
        -Name "docs-only scope guard" `
        -Command "git diff/status path check for AGENTS.md and docs/" `
        -Script {
            $paths = New-Object System.Collections.Generic.List[string]

            if (-not [string]::IsNullOrWhiteSpace($DocsOnlyBaseBranch)) {
                $baseRef = if ($DocsOnlyBaseBranch -match "^origin/") {
                    $DocsOnlyBaseBranch
                }
                else {
                    "origin/$DocsOnlyBaseBranch"
                }

                $baseDiff = & git -C $repoRoot diff --name-only "${baseRef}...HEAD"
                if ($LASTEXITCODE -ne 0) {
                    throw "Could not compare docs-only scope against $baseRef."
                }
                foreach ($path in @($baseDiff)) {
                    if (-not [string]::IsNullOrWhiteSpace($path)) {
                        $paths.Add($path)
                    }
                }
            }

            $unstaged = & git -C $repoRoot diff --name-only
            if ($LASTEXITCODE -ne 0) {
                throw "Could not inspect unstaged docs-only paths."
            }
            foreach ($path in @($unstaged)) {
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    $paths.Add($path)
                }
            }

            $staged = & git -C $repoRoot diff --cached --name-only
            if ($LASTEXITCODE -ne 0) {
                throw "Could not inspect staged docs-only paths."
            }
            foreach ($path in @($staged)) {
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    $paths.Add($path)
                }
            }

            $untracked = & git -C $repoRoot ls-files --others --exclude-standard
            if ($LASTEXITCODE -ne 0) {
                throw "Could not inspect untracked docs-only paths."
            }
            foreach ($path in @($untracked)) {
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    $paths.Add($path)
                }
            }

            $uniquePaths = @($paths | Sort-Object -Unique)
            $invalidPaths = @($uniquePaths | Where-Object {
                    $normalized = ($_ -replace "\\", "/")
                    $normalized -ne "AGENTS.md" -and -not $normalized.StartsWith("docs/")
                })

            if ($invalidPaths.Count -gt 0) {
                throw "Docs-only validation profile cannot be used because non-documentation paths changed: $($invalidPaths -join ', ')"
            }

            if ($uniquePaths.Count -eq 0) {
                Write-Host "No changed paths found for docs-only scope guard."
            }
            else {
                Write-Host "Docs-only paths: $($uniquePaths -join ', ')"
            }
        }
}

$steps += Invoke-ValidationCommand `
    -Name "remediation record validation" `
    -Command "./scripts/Verify-RemediationRecords.ps1" `
    -Script { & (Join-Path $repoRoot "scripts/Verify-RemediationRecords.ps1") }

$steps += Invoke-ValidationCommand `
    -Name "durable spec validation" `
    -Command "./scripts/Verify-Specs.ps1" `
    -Script { & (Join-Path $repoRoot "scripts/Verify-Specs.ps1") }

$steps += Invoke-ValidationCommand `
    -Name "retrospective validation" `
    -Command "./scripts/Verify-Retrospectives.ps1" `
    -Script { & (Join-Path $repoRoot "scripts/Verify-Retrospectives.ps1") }

$serverCargo = Join-Path $repoRoot "server-rust/Cargo.toml"
if ($Profile -eq "docs-only") {
    $skipReason = "Docs-only validation profile: $SkipFullValidationReason"
    $steps += New-SkippedValidationStep -Name "rust format check" -Reason $skipReason
    $steps += New-SkippedValidationStep -Name "rust clippy" -Reason $skipReason
    $steps += New-SkippedValidationStep -Name "rust tests" -Reason $skipReason
}
elseif (Test-Path -LiteralPath $serverCargo -PathType Leaf) {
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
    validation_profile = $Profile
    full_validation_skip_reason = if ($Profile -eq "docs-only") { $SkipFullValidationReason } else { "" }
    started_utc = $started
    completed_utc = Get-UtcIsoTimestamp
    environment = [ordered]@{
        repository_root = "."
        repository_root_kind = "current-checkout"
        shell = "powershell"
        powershell_version = $PSVersionTable.PSVersion.ToString()
        os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    }
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
