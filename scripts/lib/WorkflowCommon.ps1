Set-StrictMode -Version Latest

function Get-UtcIsoTimestamp {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
}

function ConvertTo-HexString {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]] $Bytes
    )

    return ([System.BitConverter]::ToString($Bytes) -replace "-", "").ToLowerInvariant()
}

function Get-RepoRoot {
    $output = & git rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Out-String))) {
        throw "This script must be run from inside a Git repository."
    }

    return (Resolve-Path (($output | Select-Object -First 1).ToString().Trim())).Path
}

function Get-GitText {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $output = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | Out-String).Trim()
        throw "git $($Arguments -join ' ') failed. $message"
    }

    return ($output | Out-String).Trim()
}

function Test-GitHeadExists {
    $null = & git rev-parse --verify --quiet HEAD
    return ($LASTEXITCODE -eq 0)
}

function Assert-GitHeadExists {
    if (-not (Test-GitHeadExists)) {
        throw "This repository has no commits yet. Create the initial commit before creating branches or commit-bound proofs."
    }
}

function Get-CurrentBranch {
    $branch = Get-GitText @("branch", "--show-current")
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "Detached HEAD is not supported by these workflow scripts."
    }

    return $branch
}

function Get-HeadCommit {
    Assert-GitHeadExists
    return Get-GitText @("rev-parse", "HEAD")
}

function Get-HeadTree {
    Assert-GitHeadExists
    return Get-GitText @("rev-parse", "HEAD^{tree}")
}

function Assert-CleanWorkingTree {
    param(
        [string] $Reason = "This workflow requires a clean working tree."
    )

    $status = @(& git status --porcelain=v1 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed. $(($status | Out-String).Trim())"
    }

    if ($status.Count -gt 0) {
        throw "$Reason Commit or stash changes first. Current changes:`n$(($status | Out-String).Trim())"
    }
}

function Get-WorkingTreeStatus {
    $status = @(& git status --porcelain=v1 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed. $(($status | Out-String).Trim())"
    }

    return $status
}

function Assert-FeatureBranch {
    param(
        [switch] $RequireCodexPrefix,
        [switch] $AllowUnborn
    )

    if (-not $AllowUnborn) {
        Assert-GitHeadExists
    }

    $branch = Get-CurrentBranch
    $protectedBranches = @("main", "test")
    if ($protectedBranches -contains $branch) {
        throw "Work must happen on a feature branch, not '$branch'. Create a branch such as 'codex/<task-name>'."
    }

    if ($RequireCodexPrefix -and -not $branch.StartsWith("codex/")) {
        throw "This workflow expects a Codex feature branch named 'codex/<task-name>'. Current branch: '$branch'."
    }

    return $branch
}

function Get-ProofSafeName {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $safe = $Name -replace "[^A-Za-z0-9._-]+", "-"
    $safe = $safe.Trim("-")
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "unnamed"
    }

    return $safe
}

function Get-GitHubCliPath {
    $command = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $programFiles = [Environment]::GetFolderPath("ProgramFiles")
    $localAppData = [Environment]::GetFolderPath("LocalApplicationData")
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        $candidates += (Join-Path $programFiles "GitHub CLI/gh.exe")
    }
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $candidates += (Join-Path $localAppData "GitHub CLI/gh.exe")
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw "GitHub CLI was not found on PATH or in the standard install locations. Install gh or add it to PATH."
}

function Get-OriginRepositoryFullName {
    $remoteUrl = Get-GitText @("remote", "get-url", "origin")
    if ($remoteUrl -match "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(?:\.git)?$") {
        return "$($matches.owner)/$($matches.repo)"
    }

    throw "Could not infer GitHub repository owner/name from origin URL: $remoteUrl"
}

function Invoke-GitHubCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $gh = Get-GitHubCliPath
    $output = & $gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | Out-String).Trim()
        throw "gh $($Arguments -join ' ') failed. $message"
    }

    return ($output | Out-String).Trim()
}

function Assert-GitHubCliAuthenticated {
    $null = Invoke-GitHubCli @("auth", "status")
}

function Push-CurrentBranch {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Branch
    )

    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& git push -u origin $Branch 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    if ($exitCode -ne 0) {
        throw "git push -u origin $Branch failed. $(($output | Out-String).Trim())"
    }

    return ($output | Out-String).Trim()
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path
    }
}

function Get-RepositoryContentDigest {
    param(
        [string[]] $ExcludedPrefixes = @("docs/proofs/")
    )

    $repoRoot = Get-RepoRoot
    $files = & git -C $repoRoot ls-files 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed. $(($files | Out-String).Trim())"
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.MemoryStream]::new()
    $trackedCount = 0

    foreach ($file in ($files | Sort-Object)) {
        $normalized = ($file.ToString() -replace "\\", "/")
        $excluded = $false
        foreach ($prefix in $ExcludedPrefixes) {
            if ($normalized.StartsWith($prefix)) {
                $excluded = $true
                break
            }
        }

        if ($excluded) {
            continue
        }

        $absolutePath = Join-Path $repoRoot $normalized
        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            continue
        }

        $bytes = [System.IO.File]::ReadAllBytes($absolutePath)
        $header = $encoding.GetBytes("path:$normalized`nlength:$($bytes.Length)`n")
        $stream.Write($header, 0, $header.Length)
        $stream.Write($bytes, 0, $bytes.Length)
        $separator = $encoding.GetBytes("`n")
        $stream.Write($separator, 0, $separator.Length)
        $trackedCount += 1
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = ConvertTo-HexString ($sha.ComputeHash($stream.ToArray()))
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }

    return [pscustomobject]@{
        Algorithm = "sha256:repo-tracked-files-v1"
        Digest = $digest
        TrackedFileCount = $trackedCount
        ExcludedPrefixes = $ExcludedPrefixes
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [object] $InputObject,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $directory = Split-Path -Parent $Path
    Ensure-Directory $directory
    $json = $InputObject | ConvertTo-Json -Depth 32
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function New-SkippedValidationStep {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Reason
    )

    $now = Get-UtcIsoTimestamp
    return [pscustomobject]@{
        name = $Name
        command = ""
        status = "skipped"
        exit_code = $null
        started_utc = $now
        completed_utc = $now
        summary = $Reason
        output = @()
    }
}

function Invoke-ValidationCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Command,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Script
    )

    $started = Get-UtcIsoTimestamp
    $output = @()
    $exitCode = 0

    try {
        $global:LASTEXITCODE = 0
        $output = & $Script 2>&1
        if ($LASTEXITCODE -is [int]) {
            $exitCode = $LASTEXITCODE
        }
        else {
            $exitCode = 0
        }
    }
    catch {
        $exitCode = 1
        $output = @($_.Exception.Message)
    }

    $completed = Get-UtcIsoTimestamp
    $status = if ($exitCode -eq 0) { "passed" } else { "failed" }
    $summary = if ($exitCode -eq 0) { "Passed" } else { "Failed with exit code $exitCode" }

    return [pscustomobject]@{
        name = $Name
        command = $Command
        status = $status
        exit_code = $exitCode
        started_utc = $started
        completed_utc = $completed
        summary = $summary
        output = @($output | ForEach-Object { $_.ToString() })
    }
}
