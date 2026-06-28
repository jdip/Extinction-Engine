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

function ConvertTo-ProcessArgumentString {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    return (($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_.Replace('\', '\\').Replace('"', '\"')) + '"'
        }
        else {
            $_
        }
    }) -join " ")
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FileName,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,

        [string] $WorkingDirectory = ""
    )

    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $FileName
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.Arguments = ConvertTo-ProcessArgumentString $Arguments
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $processInfo.WorkingDirectory = $WorkingDirectory
    }

    $process = [System.Diagnostics.Process]::Start($processInfo)
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()

    return [pscustomobject]@{
        ExitCode = $exitCode
        StdOut = $standardOutput.TrimEnd()
        StdErr = $standardError.TrimEnd()
        Output = (@($standardOutput.TrimEnd(), $standardError.TrimEnd()) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
    }
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
    $result = Invoke-ExternalCommand -FileName $gh -Arguments $Arguments -WorkingDirectory (Get-RepoRoot)
    if ($result.ExitCode -ne 0) {
        throw "gh $($Arguments -join ' ') failed. $($result.Output)"
    }

    return $result.Output
}

function Invoke-GitHubCliRaw {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $gh = Get-GitHubCliPath
    return Invoke-ExternalCommand -FileName $gh -Arguments $Arguments -WorkingDirectory (Get-RepoRoot)
}

function Invoke-GitProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $result = Invoke-ExternalCommand -FileName "git" -Arguments $Arguments -WorkingDirectory (Get-RepoRoot)
    if ($result.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed. $($result.Output)"
    }

    return $result.Output
}

function Assert-GitHubCliAuthenticated {
    $null = Invoke-GitHubCli @("auth", "status")
}

function Push-CurrentBranch {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Branch
    )

    return Invoke-GitProcess @("push", "-u", "origin", $Branch)
}

function Get-GitHubPullRequestForBranches {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepositoryFullName,

        [Parameter(Mandatory = $true)]
        [string] $HeadBranch,

        [Parameter(Mandatory = $true)]
        [string] $BaseBranch
    )

    $json = Invoke-GitHubCli @(
        "pr", "list",
        "--repo", $RepositoryFullName,
        "--head", $HeadBranch,
        "--base", $BaseBranch,
        "--state", "all",
        "--json", "number,url,state,isDraft"
    )

    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    $pullRequests = @($json | ConvertFrom-Json)
    if ($pullRequests.Count -eq 0) {
        return $null
    }

    return $pullRequests | Select-Object -First 1
}

function Get-GitHubPullRequestView {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepositoryFullName,

        [Parameter(Mandatory = $true)]
        [int] $PullRequestNumber
    )

    $json = Invoke-GitHubCli @(
        "pr", "view", "$PullRequestNumber",
        "--repo", $RepositoryFullName,
        "--json", "number,url,state,isDraft,headRefName,headRefOid,baseRefName,mergeCommit,mergeStateStatus"
    )

    return $json | ConvertFrom-Json
}

function Set-GitHubPullRequestReady {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepositoryFullName,

        [Parameter(Mandatory = $true)]
        [int] $PullRequestNumber
    )

    $view = Get-GitHubPullRequestView -RepositoryFullName $RepositoryFullName -PullRequestNumber $PullRequestNumber
    if ($view.isDraft) {
        Invoke-GitHubCli @("pr", "ready", "$PullRequestNumber", "--repo", $RepositoryFullName) | Write-Host
    }
}

function Wait-GitHubPullRequestCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepositoryFullName,

        [Parameter(Mandatory = $true)]
        [int] $PullRequestNumber,

        [string] $CheckName = "Verify checked-in local proof",
        [int] $TimeoutSeconds = 600,
        [int] $PollSeconds = 10
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $result = Invoke-GitHubCliRaw @(
            "pr", "checks", "$PullRequestNumber",
            "--repo", $RepositoryFullName,
            "--json", "name,bucket,state,link,workflow"
        )

        $json = $result.StdOut
        if (-not [string]::IsNullOrWhiteSpace($json)) {
            $checks = @($json | ConvertFrom-Json)
            $matchingCheck = $checks |
                Where-Object { $_.name -eq $CheckName } |
                Select-Object -First 1

            if ($null -ne $matchingCheck) {
                if ($matchingCheck.bucket -eq "pass") {
                    Write-Host "GitHub proof check passed: $CheckName"
                    return $matchingCheck
                }

                if ($matchingCheck.bucket -in @("fail", "cancel")) {
                    throw "GitHub proof check did not pass. bucket=$($matchingCheck.bucket) state=$($matchingCheck.state) link=$($matchingCheck.link)"
                }

                Write-Host "Waiting for GitHub proof check: bucket=$($matchingCheck.bucket) state=$($matchingCheck.state)"
            }
            else {
                Write-Host "Waiting for GitHub proof check to appear: $CheckName"
            }
        }
        else {
            Write-Host "Waiting for GitHub checks to appear."
        }

        Start-Sleep -Seconds $PollSeconds
    }

    throw "Timed out after $TimeoutSeconds seconds waiting for GitHub proof check '$CheckName'."
}

function Merge-GitHubPullRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepositoryFullName,

        [Parameter(Mandatory = $true)]
        [int] $PullRequestNumber,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedHeadSha
    )

    Invoke-GitHubCli @(
        "pr", "merge", "$PullRequestNumber",
        "--repo", $RepositoryFullName,
        "--merge",
        "--match-head-commit", $ExpectedHeadSha
    ) | Write-Host
}

function Assert-RemoteBranchContainsCommit {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Branch,

        [Parameter(Mandatory = $true)]
        [string] $CommitSha
    )

    Invoke-GitProcess @("fetch", "origin", $Branch) | Write-Host
    $result = Invoke-ExternalCommand -FileName "git" -Arguments @("merge-base", "--is-ancestor", $CommitSha, "origin/$Branch") -WorkingDirectory (Get-RepoRoot)
    if ($result.ExitCode -ne 0) {
        throw "origin/$Branch does not contain expected commit $CommitSha."
    }
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

    $indexOutput = Invoke-GitProcess @("ls-files", "-s")
    $indexEntries = @($indexOutput -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.MemoryStream]::new()
    $trackedCount = 0
    $manifestLines = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $indexEntries) {
        if ($entry -notmatch "^(?<mode>\d+)\s+(?<object>[0-9a-fA-F]+)\s+(?<stage>\d+)\t(?<path>.+)$") {
            throw "Could not parse git index entry: $entry"
        }

        $normalized = ($matches.path -replace "\\", "/")
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

        $manifestLines.Add("$($matches.mode) $($matches.object.ToLowerInvariant()) $($matches.stage) $normalized")
        $trackedCount += 1
    }

    foreach ($line in ($manifestLines | Sort-Object)) {
        $bytes = $encoding.GetBytes("$line`n")
        $stream.Write($bytes, 0, $bytes.Length)
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
        Algorithm = "sha256:git-index-manifest-v1"
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
